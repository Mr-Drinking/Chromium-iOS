#!/usr/bin/env bash
# Generates the build directory from args/<mode>.gn and builds.
#
# usage: scripts/03-build.sh sim|device [ninja targets...]
#   default target: chrome  (the Chrome iOS app -> Chromium.app)
#   e.g.  scripts/03-build.sh sim content_shell   # unpatched baseline
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

mode="${1:-}"
[ -n "$mode" ] || die "usage: $0 sim|device [targets...]"
shift
case "$mode" in
  sim) out="$OUT_SIM"; args_file="$REPO_ROOT/args/simulator.gn" ;;
  device) out="$OUT_DEVICE"; args_file="$REPO_ROOT/args/device.gn" ;;
  *) die "unknown mode '$mode' (expected sim or device)" ;;
esac
targets="${*:-chrome}"

SRC="$CHROMIUM_DIR/src"
[ -d "$SRC/.git" ] || die "no checkout at $SRC; run scripts/01-fetch-chromium.sh first"
cd "$SRC"

mkdir -p "$out"
sed "s|@BUNDLE_ID_PREFIX@|$BUNDLE_ID_PREFIX|g" "$args_file" > "$out/args.gn.new"
if cmp -s "$out/args.gn.new" "$out/args.gn" 2>/dev/null; then
  rm -f "${out:?}/args.gn.new"
else
  mv "$out/args.gn.new" "$out/args.gn"
fi

note "gn gen $out  (args from ${args_file#"$REPO_ROOT"/})"
gn gen "$out"

note "building: $targets"
# shellcheck disable=SC2086  # targets is a word list on purpose
autoninja -C "$out" $targets

for t in $targets; do
  case "$t" in
    chrome) note "app: $SRC/$out/Chromium.app" ;;
    content_shell) note "app: $SRC/$out/content_shell.app" ;;
  esac
done
