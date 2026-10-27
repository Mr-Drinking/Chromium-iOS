#!/usr/bin/env bash
# Installs a simulator build and launches it with stdout/stderr attached.
#
# usage: scripts/04-run-simulator.sh [chrome|content_shell] [simulator name]
#   defaults: chrome, "iPhone 16" (the device the official iOS Blink CI uses)
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

which_app="${1:-chrome}"
device="${2:-iPhone 16}"
case "$which_app" in
  chrome) app="$CHROMIUM_DIR/src/$OUT_SIM/Chromium.app" ;;
  content_shell) app="$CHROMIUM_DIR/src/$OUT_SIM/content_shell.app" ;;
  *) die "unknown app '$which_app' (chrome or content_shell)" ;;
esac
[ -d "$app" ] || die "$app is not built; run: scripts/03-build.sh sim $which_app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")

# Prints "<udid> <name>" of the first available simulator whose name matches
# the extended regex $1.
find_sim() {
  xcrun simctl list devices available |
    sed -nE "s/^[[:space:]]+($1) \\(([0-9A-F-]{36})\\).*/\\2 \\1/p" | head -1
}

sim=$(find_sim "$device")
if [ -z "$sim" ]; then
  # Each runtime supports only some device types (Xcode 27.1's iOS 27.1 offers
  # just "iPhone Duo", its iOS 27.0 the usual iPhones), so pick the newest
  # available runtime that supports this one.
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
device = sys.argv[1]
ok = [r for r in json.load(sys.stdin)["runtimes"]
      if r.get("isAvailable") and r.get("platform") == "iOS"
      and device in [t["name"] for t in r.get("supportedDeviceTypes", [])]]
ok.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(ok[-1]["identifier"] if ok else "")' "$device")
  if [ -n "$runtime" ]; then
    note "creating simulator '$device' on $runtime"
    sim="$(xcrun simctl create "ios-blink $device" "$device" "$runtime") ios-blink $device"
  else
    sim=$(find_sim 'iPhone[^(]*')
    [ -n "$sim" ] || die "no runtime supports '$device', and no iPhone simulator is available"
    note "no runtime supports '$device'; using '${sim#* }' instead"
  fi
fi
udid="${sim%% *}"

note "booting ${sim#* } ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
# The simulator window is Simulator.app up to Xcode 26 and DeviceHub.app (in
# Xcode.app/Contents/Applications) from Xcode 27. Open it by path: an Xcode on
# another disk, selected through DEVELOPER_DIR, is unknown to LaunchServices.
dev_dir=$(xcode-select -p)
if [ -d "$dev_dir/Applications/Simulator.app" ]; then
  window_app="$dev_dir/Applications/Simulator.app"
else
  window_app="$(dirname "$dev_dir")/Applications/DeviceHub.app"
fi
open -a "$window_app" --args -CurrentDeviceUDID "$udid" ||
  echo "warning: could not open $window_app; the simulator still runs without a window"

note "installing $app"
xcrun simctl install "$udid" "$app"

note "launching $bundle_id; app output follows (Ctrl-C to stop)"
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id"
