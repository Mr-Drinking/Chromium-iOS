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

udid=$(xcrun simctl list devices available | sed -nE "s/^[[:space:]]+$device \\(([0-9A-F-]{36})\\).*/\\1/p" | head -1)
if [ -z "$udid" ]; then
  runtime=$(xcrun simctl list runtimes | sed -nE 's/^iOS .* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+)$/\1/p' | tail -1)
  [ -n "$runtime" ] || die "no iOS simulator runtime installed (Xcode > Settings > Components)"
  note "creating simulator '$device' on $runtime"
  udid=$(xcrun simctl create "ios-blink $device" "$device" "$runtime")
fi

note "booting $device ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$udid"

note "installing $app"
xcrun simctl install "$udid" "$app"

note "launching $bundle_id; app output follows (Ctrl-C to stop)"
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id"
