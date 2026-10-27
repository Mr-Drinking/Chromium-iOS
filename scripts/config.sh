# Shared settings for the scripts in this directory. Sourced, not executed.
# shellcheck disable=SC2034  # variables are used by the sourcing scripts
# Every value can be overridden from the environment, e.g.
#   CHROMIUM_DIR=/Volumes/Build/chromium scripts/01-fetch-chromium.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Per-machine settings (paths, Xcode) go in the untracked
# scripts/config.local.sh, sourced before the defaults below. Write them as
# ': "${VAR:=value}"' so the environment still wins, e.g.
#   : "${CHROMIUM_DIR:=/Volumes/Build/chromium}"
#   : "${DEVELOPER_DIR:=/Volumes/Build/Xcode.app/Contents/Developer}"; export DEVELOPER_DIR
if [ -f "$REPO_ROOT/scripts/config.local.sh" ]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/config.local.sh"
fi

# Pinned Chromium main revision: green on the official iOS Blink CI builder
# (ios-blink-rel-fyi, build 8666871797155972657, 2026-10-26), which compiles
# "all" with use_blink=true and runs tests on an iPhone 16 / iOS 27.0
# simulator with Xcode 27 (27a266a). DEPS pins V8 f7be3c62, ANGLE ab90d2a9.
CHROMIUM_REV="${CHROMIUM_REV:-4558926cce232609ce125114e633e0b3a67b793d}"
CHROMIUM_VERSION="${CHROMIUM_VERSION:-158.0.8127.0}"

# gclient root; the Chromium checkout ends up in "$CHROMIUM_DIR/src".
# Needs roughly 150-200 GB free.
CHROMIUM_DIR="${CHROMIUM_DIR:-$HOME/chromium}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$HOME/depot_tools}"

# Prefix for the app's bundle identifier (ios_app_bundle_id_prefix). Use your
# own reverse-DNS name; sideloading tools may rewrite it anyway.
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.example.iosblink}"

OUT_SIM="${OUT_SIM:-out/Release-iphonesimulator-blink}"
OUT_DEVICE="${OUT_DEVICE:-out/Release-iphoneos-blink}"

# Parallel build jobs; empty lets autoninja decide (one per CPU core). A heavy
# compile can take 1-2 GB and siso itself a few GB, so lower this on a 16 GB
# Mac or the build ends up swapping.
BUILD_JOBS="${BUILD_JOBS:-}"

# Local branch (in src/, and in src/v8 etc. if a patch targets them) holding
# the applied patch series.
PATCH_BRANCH="${PATCH_BRANCH:-ios-blink-sideload}"

export PATH="$DEPOT_TOOLS_DIR:$PATH"

# Check out Git LFS files as pointers, as Chromium's builders do. A global
# "git lfs install" marks the lfs filter as required, and without git-lfs on
# PATH that breaks deps using LFS (third_party/litert/src: prebuilt binaries
# the build never uses). Appends to any GIT_CONFIG_COUNT already set.
_n="${GIT_CONFIG_COUNT:-0}"
for _kv in filter.lfs.process= filter.lfs.smudge= filter.lfs.clean= filter.lfs.required=false; do
  export "GIT_CONFIG_KEY_$_n=${_kv%%=*}" "GIT_CONFIG_VALUE_$_n=${_kv#*=}"
  _n=$((_n + 1))
done
export GIT_CONFIG_COUNT="$_n"
unset _n _kv

die() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "==> $*"
}
