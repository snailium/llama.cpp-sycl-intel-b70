#!/usr/bin/env bash
# Promote a B70-tested candidate image to its channel tag, and advance :latest.
#
# Rationale (r5 audit §7#3): CI only ever emits per-version-candidate tags
# like `server-c<CR>-v<v>-<timestamp>` / `server-dev-b<n>-c<CR>-<timestamp>`.
# The `:stable` / `:server-dev` / `:latest` tags are NOT produced by any workflow —
# they live purely as manual promote points. Without a recorded procedure, an anchor
# can silently drift from what is actually validated. This script makes the promote
# step explicit and auditable.
#
# When to run: after a candidate image has passed a full B70 test suite
# (T1-T5 + V1-V3, 0 crashes), promote its exact digest so production and docs
# point at a known-good image.
#
# Usage:
#   ./scripts/promote-b70-image.sh <candidate-digest> [semver] [repo] [channel]
#
#   channel: "stable" (default) -> moves :stable  (+ :$SEMVER when given)
#            "dev"              -> moves :server-dev
#
# Examples:
#   ./scripts/promote-b70-image.sh sha256:4b7923e9... v0.5.0
#     -> :stable and :v0.5.0
#   ./scripts/promote-b70-image.sh sha256:a7106ff2... "" ghcr.io/OWNER/IMG dev
#     -> :server-dev only  (:stable is NOT touched)
#
# :latest — "last known-good image", whichever channel
#   :latest always tracks the most recently built image that we tested AND promoted,
#   on either channel. It is MONOTONIC by image build date: it only ever moves to a
#   NEWER build, never backwards. Promoting an older digest (e.g. a re-promote of a
#   stable release after a dev build) leaves :latest where it is and says so.
#   Rationale: `docker pull repo:latest` should never hand someone bits older than
#   what they already got. Set LATEST=0 to skip :latest entirely.
#
# Note: tagging is a manifest-only operation (~0.7s). After promoting:
#   1. close the candidate's issue ("promoted to :stable = :vX.Y")
#   2. optionally GC the duplicate per-version tags left behind by redundant
#      builds (see r5 §7#4) so tags/list stays small
set -euo pipefail

REPO=${3:-ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70}
DIGEST=${1:?usage: promote-b70-image.sh <digest> [semver] [repo] [channel]}
SEMVER=${2:-}
CHANNEL=${4:-stable}
LATEST=${LATEST:-1}

if ! [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ERR: digest must look like sha256:<64 hex>, got '$DIGEST'" >&2
  exit 1
fi

case "$CHANNEL" in
  stable) CHANNEL_TAG="stable" ;;
  dev)    CHANNEL_TAG="server-dev" ;;
  *) echo "ERR: channel must be 'stable' or 'dev', got '$CHANNEL'" >&2; exit 1 ;;
esac

# Build timestamp of a remote tag/digest. We use the image's build time (the leading
# field of `imagetools inspect --format '{{.Image}}'`), NOT the manifest push time:
# re-pushing a tag must not make old bits look new. Falls back to empty if unreadable.
#
# NOTE: `{{.Image}}` prints a Go struct, not JSON — its first line starts with
# `{YYYY-MM-DD HH:MM:SS.<ns> +0000 UTC ...`. Match that prefix only, and take the
# first line, so the rest of the (very long, multi-line) struct cannot bleed in.
img_created() {
  local ref="$1" raw
  raw=$(docker buildx imagetools inspect "$ref" --format '{{.Image}}' 2>/dev/null | head -1) || true
  printf '%s' "$raw" \
    | sed -nE 's/^\{([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+ \+0000 UTC.*/\1 +0000/p'
}

created_epoch() {
  local ts="$1"
  [ -n "$ts" ] || return 1
  date -u -d "$ts" +%s 2>/dev/null
}

# Warn (r7 N1): a release tag already pointing to a *different* digest means we're
# silently repointing a known-good anchor to new bits — cached consumers won't pick
# the change up, so surface it explicitly. Normalize the sha256: prefix for compare.
warn_if_repoint() {
  local tag="$1" cur new
  cur=$(docker buildx imagetools inspect "$REPO:$tag" --format '{{.Manifest.Digest}}' 2>/dev/null || true)
  new="${DIGEST#sha256:}"
  if [ -n "$cur" ]; then
    cur="${cur#sha256:}"
    if [ "$cur" != "$new" ]; then
      echo "  ⚠️ :$tag already → sha256:$cur; repointing to sha256:$new" >&2
    fi
  fi
}

echo "Promoting $DIGEST -> $REPO  (channel: $CHANNEL)"

# --- channel tag -------------------------------------------------------------
warn_if_repoint "$CHANNEL_TAG"
docker buildx imagetools create --tag "$REPO:$CHANNEL_TAG" "$REPO@$DIGEST"
echo "  ✓ :$CHANNEL_TAG"

if [ "$CHANNEL" = "stable" ] && [ -n "$SEMVER" ]; then
  warn_if_repoint "$SEMVER"
  docker buildx imagetools create --tag "$REPO:$SEMVER" "$REPO@$DIGEST"
  echo "  ✓ :$SEMVER"
elif [ "$CHANNEL" = "dev" ] && [ -n "$SEMVER" ]; then
  echo "  note: semver '$SEMVER' ignored on the dev channel (dev tags are :server-dev)" >&2
fi

# --- :latest (monotonic: newest build only) ----------------------------------
if [ "$LATEST" = "1" ]; then
  echo ""
  echo ":latest"
  NEW_TS=$(img_created "$REPO@$DIGEST")
  CUR_TS=$(img_created "$REPO:latest" 2>/dev/null || true)
  NEW_E=$(created_epoch "$NEW_TS" || true)
  CUR_E=$(created_epoch "$CUR_TS" || true)

  if [ -z "$CUR_E" ]; then
    # No :latest yet, or unreadable created time -> safe to create it here.
    if docker buildx imagetools inspect "$REPO:latest" >/dev/null 2>&1; then
      echo "  ! :latest exists but its build time is unreadable; not moving it" >&2
      echo "    (resolve manually: docker buildx imagetools inspect $REPO:latest)" >&2
    else
      docker buildx imagetools create --tag "$REPO:latest" "$REPO@$DIGEST"
      echo "  ✓ :latest created (${NEW_TS:-unknown time})"
    fi
  elif [ -z "$NEW_E" ]; then
    echo "  ! cannot read this image's build time; leaving :latest untouched" >&2
  elif [ "$NEW_E" -gt "$CUR_E" ]; then
    docker buildx imagetools create --tag "$REPO:latest" "$REPO@$DIGEST"
    echo "  ✓ :latest advanced: $CUR_TS -> $NEW_TS"
  elif [ "$NEW_E" -eq "$CUR_E" ]; then
    echo "  = :latest already at this build ($NEW_TS); no change"
  else
    echo "  ⊘ :latest NOT moved — this image ($NEW_TS) is OLDER than :latest ($CUR_TS)"
    echo "    :latest is monotonic by build date; promoting older bits never pulls it back."
  fi
fi

echo ""
echo "Verify:"
echo "  docker buildx imagetools inspect $REPO:$CHANNEL_TAG"
echo "  docker buildx imagetools inspect $REPO:latest"
echo ""
echo "Then: close the candidate's issue and (optionally) delete stale duplicate"
echo "tags: docker buildx imagetools create --tag <reclaim> / gh api or crane delete"
