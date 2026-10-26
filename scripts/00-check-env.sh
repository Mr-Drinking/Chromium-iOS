#!/usr/bin/env bash
# Checks that this Mac can build the project. Read-only; changes nothing.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

fail=0
warn() { echo "  WARN: $*"; }
bad() { echo "  FAIL: $*"; fail=1; }
ok() { echo "  ok:   $*"; }

note "Host"
[ "$(uname -s)" = "Darwin" ] || bad "not macOS"
ok "macOS $(sw_vers -productVersion) on $(uname -m)"
[ "$(uname -m)" = "arm64" ] || warn "Apple silicon strongly recommended (CI builds on arm64)"
ram_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
if [ "$ram_gb" -lt 16 ]; then warn "${ram_gb} GB RAM; 16 GB is the practical minimum, 32 GB+ is comfortable"; else ok "${ram_gb} GB RAM"; fi
ok "$(sysctl -n hw.ncpu) CPU cores"

note "Disk ($(dirname "$CHROMIUM_DIR"))"
mkdir -p "$(dirname "$CHROMIUM_DIR")"
free_gb=$(df -g "$(dirname "$CHROMIUM_DIR")" | awk 'NR==2 {print $4}')
if [ "$free_gb" -lt 150 ]; then bad "${free_gb} GB free; need ~150-200 GB for checkout + builds"; else ok "${free_gb} GB free"; fi

note "Xcode"
dev_dir=$(xcode-select -p 2>/dev/null || true)
case "$dev_dir" in
  *CommandLineTools*|"") bad "xcode-select points at '$dev_dir'; run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer (or, to leave the system setting alone: export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer)" ;;
  *) ok "developer dir $dev_dir${DEVELOPER_DIR:+ (from DEVELOPER_DIR)}" ;;
esac
if xcode_ver=$(xcodebuild -version 2>/dev/null); then
  xcode_major=$(echo "$xcode_ver" | awk 'NR==1 {split($2, v, "."); print v[1]}')
  ok "$(echo "$xcode_ver" | tr '\n' ' ')"
  if [ "${xcode_major:-0}" -lt 26 ]; then bad "Chromium at this revision requires Xcode 26 or newer"; fi
  if [ "${xcode_major:-0}" -lt 27 ]; then warn "the pinned revision's CI uses Xcode 27 (27a266a); Xcode 27 matches your iOS 27 phone best"; fi
else
  bad "xcodebuild not usable (Xcode installed? license accepted? try: sudo xcodebuild -license accept)"
fi
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || warn "Xcode first-launch tasks pending; run: sudo xcodebuild -runFirstLaunch"
ok "iphoneos SDK $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo '?')"
ok "iphonesimulator SDK $(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo '?')"
runtimes=$(xcrun simctl list runtimes 2>/dev/null | grep -E '^iOS' || true)
if [ -n "$runtimes" ]; then ok "simulator runtimes: $(echo "$runtimes" | awk '{print $2}' | tr '\n' ' ')"; else warn "no iOS simulator runtime installed (Xcode > Settings > Components)"; fi

note "Tools"
for t in git python3 curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t $("$t" --version 2>&1 | head -1)"; else bad "$t missing"; fi
done
if [ -x "$DEPOT_TOOLS_DIR/gclient" ]; then ok "depot_tools at $DEPOT_TOOLS_DIR"; else warn "depot_tools not found at $DEPOT_TOOLS_DIR (01-fetch-chromium.sh will clone it)"; fi

note "Checkout"
if [ -d "$CHROMIUM_DIR/src/.git" ]; then
  head=$(git -C "$CHROMIUM_DIR/src" rev-parse HEAD 2>/dev/null || echo '?')
  ok "src at $head (pinned: $CHROMIUM_REV)"
else
  ok "no checkout yet at $CHROMIUM_DIR/src"
fi

echo
if [ "$fail" -ne 0 ]; then echo "Fix the FAIL items above first."; exit 1; fi
echo "Environment looks usable."
