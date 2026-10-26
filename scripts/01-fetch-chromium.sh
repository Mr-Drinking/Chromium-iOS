#!/usr/bin/env bash
# Checks out Chromium (with iOS deps) at the pinned revision into
# $CHROMIUM_DIR/src. Safe to re-run: it re-syncs to $CHROMIUM_REV.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

if [ ! -x "$DEPOT_TOOLS_DIR/gclient" ]; then
  note "Cloning depot_tools into $DEPOT_TOOLS_DIR"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
fi

mkdir -p "$CHROMIUM_DIR"
cd "$CHROMIUM_DIR"

if [ ! -f .gclient ]; then
  note "Writing $CHROMIUM_DIR/.gclient (target_os = ios)"
  cat > .gclient <<'EOF'
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["ios"]
target_os_only = True
EOF
fi

if [ -d src/.git ] && [ -n "$(git -C src status --porcelain --untracked-files=no)" ]; then
  die "src/ has local changes; commit or stash them (scripts/02-apply-patches.sh re-applies the series on a fresh branch)"
fi

# Shallow by default: googlesource serves a pinned commit at depth 1. Full
# history (FULL_HISTORY=1) is a much larger download, so it is never an
# automatic fallback; most sync failures (network, one broken dep) have
# nothing to do with history, and re-running resumes the sync.
if [ "${FULL_HISTORY:-0}" = 1 ]; then
  note "Syncing src@$CHROMIUM_REV with full history"
  gclient sync --nohooks --revision "src@$CHROMIUM_REV"
else
  note "Syncing src@$CHROMIUM_REV (shallow; the first sync downloads tens of GB)"
  gclient sync --nohooks --no-history --revision "src@$CHROMIUM_REV" ||
    die "gclient sync failed (see above). Re-run to resume; FULL_HISTORY=1 fetches full history instead (much larger)"
fi

note "Running hooks (toolchains, SDK checks)"
gclient runhooks

head=$(git -C src rev-parse HEAD)
[ "$head" = "$CHROMIUM_REV" ] || die "src is at $head, expected $CHROMIUM_REV"
note "Checkout ready: $CHROMIUM_DIR/src at $head ($CHROMIUM_VERSION)"
echo "Next: scripts/03-build.sh sim content_shell   (unpatched baseline), then scripts/02-apply-patches.sh"
