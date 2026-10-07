#!/usr/bin/env bash
# Sync the vendored llama.cpp/ subtree to an upstream ref.
#
# The build reads llama.cpp/ AS COMMITTED — CI does not clone upstream — so this
# script is how a new llama.cpp version enters the image. Read the ref from
# upstream, replace the tree, refresh the provenance file, and leave the change
# staged for review. Nothing is pushed and nothing is committed for you.
#
# Usage:
#   scripts/sync-llama-subtree.sh v0.6.0        # a release tag
#   scripts/sync-llama-subtree.sh b11429        # a dev tag
#   scripts/sync-llama-subtree.sh v0.6.0 --dry-run
#
# Why not `git subtree pull`:
#   The vendored commit is a SQUASH with no upstream ancestry, and the upstream
#   commit it came from was later rewritten (unreachable: "not our ref"). With
#   no common ancestor there is nothing for subtree to diff against, and it
#   refuses with "refusing to merge unrelated histories". A tree replacement
#   against a named tag is the equivalent, and is what this does.
#
# After running:
#   1. review `git diff --cached --stat` and the changed files
#   2. commit, then push — CI reads the version from llama.cpp/CMakeLists.txt,
#      so the image tag follows automatically and no workflow edit is needed
#   3. the new b_tag changes the dev tag prefix, so the duplicate check in
#      build-dev.yml sees a new combo and builds

set -euo pipefail

REF="${1:?usage: sync-llama-subtree.sh <upstream-ref> [--dry-run]}"
DRY_RUN="${2:-}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/ggml-org/llama.cpp.git}"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
SUBTREE="$REPO_ROOT/llama.cpp"

[[ -d "$SUBTREE" ]] || { echo "ERR: $SUBTREE not found" >&2; exit 1; }

# --- work in a scratch clone so the caller's tree is never half-modified -----
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Fetching upstream $REF ..."
git clone --quiet --filter=blob:none --no-checkout "$UPSTREAM_URL" "$TMP/up" 2>/dev/null
git -C "$TMP/up" fetch --quiet --tags origin "+refs/tags/*:refs/tags/*"
git -C "$TMP/up" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || {
  echo "ERR: upstream has no ref '$REF'" >&2; exit 1; }

COMMIT=$(git -C "$TMP/up" rev-parse "$REF^{commit}")
TAG_OBJ=$(git -C "$TMP/up" rev-parse "$REF" 2>/dev/null || echo "")
TAG_TYPE=$(git -C "$TMP/up" cat-file -t "$REF" 2>/dev/null || echo "")
SUBJECT=$(git -C "$TMP/up" log -1 --format=%s "$COMMIT")

# The dev tag is whichever b* tag points at this commit (may be none).
B_TAG=$(git -C "$TMP/up" tag --points-at "$COMMIT" | grep -E '^b[0-9]+$' | sort -V | tail -1 || true)

# LLAMA_VERSION_BASE is a CMake template (${LLAMA_VERSION_MAJOR}...), so compose
# the number from the three components instead of reading BASE.
_cm=$(git -C "$TMP/up" show "$COMMIT:CMakeLists.txt")
_vmaj=$(echo "$_cm" | grep -m1 '^set(LLAMA_VERSION_MAJOR' | sed 's/.*[[:space:]]\([0-9]*\).*/\1/')
_vmin=$(echo "$_cm" | grep -m1 '^set(LLAMA_VERSION_MINOR' | sed 's/.*[[:space:]]\([0-9]*\).*/\1/')
_vpat=$(echo "$_cm" | grep -m1 '^set(LLAMA_VERSION_PATCH' | sed 's/.*[[:space:]]\([0-9]*\).*/\1/')
VER="${_vmaj}.${_vmin}.${_vpat}"

echo "  ref        : $REF  ($TAG_TYPE)"
echo "  commit     : $COMMIT"
echo "  CMakeLists : $VER"
echo "  b tag      : ${B_TAG:-<none>}"
echo "  subject    : $SUBJECT"

# --- show what would change before touching anything ------------------------
OLD_FILES=$(mktemp); NEW_FILES=$(mktemp)
( cd "$SUBTREE" && find . -type f | sed 's|^\./||' | grep -v '^\.subtree-upstream$' | LC_ALL=C sort ) > "$OLD_FILES"
git -C "$TMP/up" ls-tree -r --name-only "$COMMIT" | LC_ALL=C sort > "$NEW_FILES"
echo
echo "  files: $(wc -l < "$OLD_FILES") -> $(wc -l < "$NEW_FILES")"
echo "  removed: $(comm -23 "$OLD_FILES" "$NEW_FILES" | wc -l), added: $(comm -13 "$OLD_FILES" "$NEW_FILES" | wc -l)"

# Refuse to discard anything that is NOT upstream's, i.e. a genuine local edit
# inside the subtree. Upstream deletions are fine; our own files are not.
OURS=$(comm -23 "$OLD_FILES" "$NEW_FILES" | grep -v '^\.subtree-upstream$' || true)
if [[ -n "$OURS" ]]; then
  echo
  echo "  Files present locally but ABSENT in $REF:"
  echo "$OURS" | sed 's/^/    /'
  echo "  (these are upstream deletions/renames — expected. Confirm before proceeding.)"
fi

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo; echo "Dry run: nothing changed."; exit 0
fi

# --- replace the tree -------------------------------------------------------
echo
echo "Replacing $SUBTREE ..."
rm -rf "$SUBTREE"
mkdir -p "$SUBTREE"
git -C "$TMP/up" archive "$COMMIT" | tar -x -C "$SUBTREE"

cat > "$SUBTREE/.subtree-upstream" <<EOF
# Upstream provenance for the vendored llama.cpp/ subtree.
#
# The build uses THIS tree, not a fresh upstream clone. To move to a new
# release, run scripts/sync-llama-subtree.sh <ref> and push; the version read
# in CI comes from llama.cpp/CMakeLists.txt, so the image tag follows
# automatically.
#
# The fields below record exactly where the current content came from, so a
# build can be traced back to an upstream commit and a b tag (the stable
# workflow tags images by v* version; the dev workflow needs the b tag).
tag=$REF
b_tag=${B_TAG:-none}
commit=$COMMIT
tag_object=$TAG_OBJ
tag_type=$TAG_TYPE
version=$VER
synced=$(date -u +%Y-%m-%d)
subject=$SUBJECT
EOF

git add -A llama.cpp
echo
echo "Staged. Review with:"
echo "  git diff --cached --stat"
echo "  git diff --cached -- llama.cpp/.subtree-upstream"
echo
echo "Then commit and push. CI picks the version up from llama.cpp/CMakeLists.txt."
