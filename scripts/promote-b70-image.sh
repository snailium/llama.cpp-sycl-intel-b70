#!/usr/bin/env bash
# Promote a B70-tested candidate image to a clean release tag (stable + semver).
#
# Rationale (r5 audit §7#3): CI only ever emits per-version-candidate tags
# like `server-c<CR>-v<v>-<timestamp>`. The `:stable` / `:vX.Y` release tags
# are NOT produced by any workflow — they live purely as manual promote points.
# Without a recorded procedure, `:stable` can silently drift from what is
# actually validated. This script makes the promote step explicit and auditable.
#
# When to run: after a candidate image has passed a full B70 test suite
# (T1-T5 + V1-V3, 0 crashes), promote its exact digest to `:stable` and a
# semver tag so production and docs point at a known-good image.
#
# Usage:
#   ./scripts/promote-b70-image.sh <candidate-digest> [semver] [repo]
#
# Examples:
#   ./scripts/promote-b70-image.sh sha256:4b7923e9... v0.2.1
#     -> tags the digest as both :stable and :v0.2.1 (same image)
#
# Note: tagging is a manifest-only operation (~0.7s). After promoting:
#   1. close the candidate's issue ("promoted to :stable = :vX.Y")
#   2. optionally GC the duplicate per-version tags left behind by redundant
#      builds (see r5 §7#4) so tags/list stays small
set -euo pipefail

REPO=${3:-ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70}
DIGEST=${1:?usage: promote-b70-image.sh <digest> [semver] [repo]}
SEMVER=${2:-}

if ! [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ERR: digest must look like sha256:<64 hex>, got '$DIGEST'" >&2
  exit 1
fi

echo "Promoting $DIGEST -> $REPO"
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

warn_if_repoint stable
docker buildx imagetools create --tag "$REPO:stable" "$REPO@$DIGEST"
echo "  ✓ :stable"

if [ -n "$SEMVER" ]; then
  warn_if_repoint "$SEMVER"
  docker buildx imagetools create --tag "$REPO:$SEMVER" "$REPO@$DIGEST"
  echo "  ✓ :$SEMVER"
fi

echo ""
echo "Verify:"
echo "  docker buildx imagetools inspect $REPO:stable"
echo ""
echo "Then: close the candidate's issue and (optionally) delete stale duplicate"
echo "tags: docker buildx imagetools create --tag <reclaim> / gh api or crane delete"
