#!/usr/bin/env bash
# Applies patches/series (git am --3way) onto a fresh local branch at the
# pinned revision. Re-running resets the branch and re-applies everything.
#
# Series lines are "<patch>" (applied in src/) or "<repo>:<patch>" with <repo>
# relative to $CHROMIUM_DIR, e.g. "src/v8:v8/0201-foo.patch".
#
# usage: scripts/02-apply-patches.sh [--with-optional]
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

with_optional=0
for arg in "$@"; do
  case "$arg" in
    --with-optional) with_optional=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

SRC="$CHROMIUM_DIR/src"
[ -d "$SRC/.git" ] || die "no checkout at $SRC; run scripts/01-fetch-chromium.sh first"

entries=$(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/patches/series" || true)
if [ "$with_optional" = 1 ]; then
  for p in "$REPO_ROOT"/patches/optional/*.patch; do
    [ -e "$p" ] && entries="$entries
optional/$(basename "$p")"
  done
fi

deps_rev() {
  sed -nE "s/^[[:space:]]*'$1_revision':[[:space:]]*'([0-9a-f]{40})'.*/\\1/p" "$SRC/DEPS" | head -1
}

base_rev_for() {
  case "$1" in
    src) echo "$CHROMIUM_REV" ;;
    src/v8) deps_rev v8 ;;
    src/third_party/angle) deps_rev angle ;;
    *) die "no base revision known for '$1'; extend base_rev_for() in $0" ;;
  esac
}

prepared=" "
prepare_repo() {
  local repo="$1" dir="$CHROMIUM_DIR/$1" rev
  case "$prepared" in *" $repo "*) return 0 ;; esac
  [ -e "$dir/.git" ] || die "$dir is not a git checkout"
  [ ! -d "$dir/.git/rebase-apply" ] || die "git am in progress in $dir; finish it or run: git -C $dir am --abort"
  # Dependencies such as src/v8 are gitlinks in src; a patched one shows up as
  # modified there, and gets its own check when the series reaches it.
  [ -z "$(git -C "$dir" status --porcelain --untracked-files=no --ignore-submodules=all)" ] || die "$dir has uncommitted changes"
  rev=$(base_rev_for "$repo")
  [ -n "$rev" ] || die "could not determine the base revision for $repo"
  git -C "$dir" config user.name >/dev/null || git -C "$dir" config user.name "ios-blink-sideload"
  git -C "$dir" config user.email >/dev/null || git -C "$dir" config user.email "ios-blink-sideload@localhost"
  note "$repo: fresh branch '$PATCH_BRANCH' at $rev"
  git -C "$dir" checkout -q -B "$PATCH_BRANCH" "$rev"
  prepared="$prepared$repo "
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *:*) repo="${line%%:*}"; patch="${line#*:}" ;;
    *) repo="src"; patch="$line" ;;
  esac
  file="$REPO_ROOT/patches/$patch"
  [ -f "$file" ] || die "missing patch file $file"
  prepare_repo "$repo"
  note "applying $patch"
  if ! git -C "$CHROMIUM_DIR/$repo" am -q --3way "$file"; then
    echo
    echo "Patch $patch did not apply cleanly in $CHROMIUM_DIR/$repo."
    echo "  inspect: git -C $CHROMIUM_DIR/$repo am --show-current-patch=diff"
    echo "  resolve the conflicts, git add the files, then: git -C $CHROMIUM_DIR/$repo am --continue"
    echo "  or give up: git -C $CHROMIUM_DIR/$repo am --abort"
    echo "Once fixed, regenerate the patch (git format-patch) and update patches/."
    exit 1
  fi
done <<< "$entries"

note "applied series:"
for repo in $prepared; do
  echo "$repo:"
  git -C "$CHROMIUM_DIR/$repo" log --oneline "$(base_rev_for "$repo")..HEAD"
done
