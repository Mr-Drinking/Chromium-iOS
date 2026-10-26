# Shared settings for the scripts in this directory. Sourced, not executed.
# shellcheck disable=SC2034  # variables are used by the sourcing scripts
# Every value can be overridden from the environment, e.g.
#   CHROMIUM_DIR=/Volumes/Build/chromium scripts/01-fetch-chromium.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned Chromium main revision: green on the official iOS Blink CI builder
# (ios-blink-rel-fyi, build 8666930859126518865, 2026-10-25), which compiles
# "all" with use_blink=true and runs tests on an iPhone 16 / iOS 27.0
# simulator with Xcode 27 (27a266a). DEPS pins V8 1be68595, ANGLE 9addc298.
CHROMIUM_REV="${CHROMIUM_REV:-d586be9fa9b8009487056edccf01555bb18dc3b2}"
CHROMIUM_VERSION="${CHROMIUM_VERSION:-158.0.8125.0}"

# gclient root; the Chromium checkout ends up in "$CHROMIUM_DIR/src".
# Needs roughly 150-200 GB free.
CHROMIUM_DIR="${CHROMIUM_DIR:-$HOME/chromium}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$HOME/depot_tools}"

# Prefix for the app's bundle identifier (ios_app_bundle_id_prefix). Use your
# own reverse-DNS name; sideloading tools may rewrite it anyway.
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.example.iosblink}"

OUT_SIM="${OUT_SIM:-out/Release-iphonesimulator-blink}"
OUT_DEVICE="${OUT_DEVICE:-out/Release-iphoneos-blink}"

# Local branch (in src/, and in src/v8 etc. if a patch targets them) holding
# the applied patch series.
PATCH_BRANCH="${PATCH_BRANCH:-ios-blink-sideload}"

export PATH="$DEPOT_TOOLS_DIR:$PATH"

die() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "==> $*"
}
