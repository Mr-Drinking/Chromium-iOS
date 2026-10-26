#!/usr/bin/env bash
# Wraps the unsigned device build into an IPA for SideStore / AltStore /
# Sideloadly, which sign it with your Apple ID when installing.
#
# usage: scripts/05-package-ipa.sh [--with-app-groups]
#   -> dist/Chromium-<version>-sideload.ipa
#
# --with-app-groups  ad-hoc sign the app with an entitlements file that asks
#                    for Chrome's two app groups. Sideloading tools read the
#                    requested entitlements from the binary when they set up
#                    capabilities, and an unsigned build requests none. Try this
#                    if Chrome fails because its app group container is missing.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=config.sh
source "$(dirname "$0")/config.sh"

with_app_groups=0
for arg in "$@"; do
  case "$arg" in
    --with-app-groups) with_app_groups=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

app="$CHROMIUM_DIR/src/$OUT_DEVICE/Chromium.app"
[ -d "$app" ] || die "$app is not built; run: scripts/03-build.sh device"

dist="$REPO_ROOT/dist"
mkdir -p "$dist"
ipa="$dist/Chromium-$CHROMIUM_VERSION-sideload.ipa"

work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$work/Payload"
ditto "$app" "$work/Payload/Chromium.app"
bundle="$work/Payload/Chromium.app"

# App extensions: args/device.gn disables Chrome's own extensions, and the
# Chrome app target does not bundle BrowserEngineKit extension processes (they
# would never launch in single-process mode anyway). Drop any that appear so
# each sideload doesn't burn extra App IDs.
for d in PlugIns Extensions; do
  if [ -d "$bundle/$d" ]; then
    note "removing $d/: $(find "$bundle/$d" -mindepth 1 -maxdepth 1 -exec basename {} \; | tr '\n' ' ')"
    rm -rf "${bundle:?}/${d:?}"
  fi
done

# The build is unsigned (ios_enable_code_signing = false); remove any stray
# signature directories so the sideloading tool signs from scratch.
find "$bundle" -type d -name _CodeSignature -prune -exec rm -rf {} +

if [ "$with_app_groups" = 1 ]; then
  # Same groups as ios/chrome/app/resources/Chrome.entitlements; the
  # BrowserEngineKit and credential-provider entitlements are left out because
  # a sideloaded app cannot be granted them.
  cat > "$work/requested.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.$BUNDLE_ID_PREFIX.chrome</string>
    <string>group.$BUNDLE_ID_PREFIX.common</string>
  </array>
</dict>
</plist>
EOF
  note "ad-hoc signing with requested app groups (group.$BUNDLE_ID_PREFIX.chrome/.common)"
  codesign --force --deep --sign - --timestamp=none \
    --entitlements "$work/requested.entitlements" "$bundle"
fi

exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist")
note "executable: $(lipo -archs "$bundle/$exe" 2>/dev/null || echo '?')"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "$bundle/$exe" 2>/dev/null | grep -E 'platform|minos|sdk' | sed 's/^/    /' || true
fi
note "bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")"
note "bundle size: $(du -sh "$bundle" | cut -f1)"

rm -f "${ipa:?}"
(cd "$work" && zip -qry "$ipa" Payload)
note "wrote $ipa"
echo "Install it with Sideloadly, AltStore or SideStore (see docs/build-guide.md)."
