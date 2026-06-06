#!/usr/bin/env bash
#
# build-projectm.sh — Phase 0 spike: build libprojectM v4 as a dynamic/shared
# library for the MilkDrop visualizer, wired to MetalANGLE's GLES3.
# See docs/projectm-integration-plan.md.
#
# HISTORY: the pinned RELEASE tag v4.1.6 hard-gates ENABLE_GLES to Linux/Android
# and FATAL_ERRORs on Apple (CMakeLists.txt:169). The investigation found that
# projectM `master` removed that guard: `if(ENABLE_GLES) set(USE_GLES ON)` with
# no system-GLES `find_package` (so it links against whatever GLES provider you
# supply — i.e. MetalANGLE), plus new macOS-framework support. We therefore pin
# the specific master commit below (NOT the moving branch).
#
# GLES wiring on Apple: master's projectM still `#include <GLES3/gl3.h>`, which
# is not a system header on macOS/iOS — we add MetalANGLE's framework Headers to
# the compile include path so it resolves, and build the shared lib with
# `-undefined dynamic_lookup` so the GL entry points resolve at the consuming
# app's final link against MetalANGLE (standard for an ANGLE-backed dylib).
#
#   $ scripts/build-projectm.sh mac    # macOS slice (fastest signal)
#   $ scripts/build-projectm.sh ios    # iOS device + simulator
#   $ scripts/build-projectm.sh xcframework
#   $ scripts/build-projectm.sh all
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export PATH="/opt/homebrew/bin:$PATH"

# --- Pin (specific master commit, Apple-GLES support; do NOT use branch name) ---
REPO="https://github.com/projectM-visualizer/projectm.git"
PIN_SHA="4d2849333b63235a6af4d1f02508a97529d96dc7"   # master @ 2026-05-08

SRC="$ROOT/spike/.build/projectm"
LOG="$ROOT/spike/.build/logs"
OUT="$ROOT/Vendor/projectM"
XCF="$ROOT/Vendor/MetalANGLE/MetalANGLE.xcframework"
mkdir -p "$LOG" "$OUT" "$(dirname "$SRC")"

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
command -v cmake >/dev/null || fail "cmake not found (brew install cmake)"
[ -d "$XCF" ] || fail "MetalANGLE.xcframework not found — run scripts/build-metalangle.sh first"

angle_headers() { echo "$XCF/$1/MetalANGLE.framework/$2Headers"; }  # $1 slice, $2 'Versions/A/' for mac

# CMake flags (plan §2): shared (LGPL), GLES (match ANGLE), playlist OFF (v1),
# bundled projectm-eval + GLM, no SDL UI, no tests.
CMAKE_COMMON=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=ON
  -DENABLE_GLES=ON
  -DENABLE_PLAYLIST=OFF
  -DENABLE_SYSTEM_PROJECTM_EVAL=OFF
  -DENABLE_SYSTEM_GLM=OFF
  -DENABLE_SDL_UI=OFF
  -DBUILD_TESTING=OFF
)

fetch_src() {
  if [ ! -d "$SRC/.git" ]; then
    log "Cloning projectM"
    git clone "$REPO" "$SRC"
  fi
  ( cd "$SRC" && git fetch --force origin && git checkout --force "$PIN_SHA" \
      && git submodule update --init --recursive )
  local have; have="$(cd "$SRC" && git rev-parse HEAD)"
  [ "$have" = "$PIN_SHA" ] || fail "pin mismatch: HEAD=$have expected=$PIN_SHA"
  log "Source at $PIN_SHA (+ submodules)"
}

# $1 build-tag  $2 install-dir  $3 angle-headers  rest: extra cmake args
build_one() {
  local tag="$1" dest="$2" inc="$3"; shift 3
  local bdir="$SRC/build-$tag"
  log "Configure projectM ($tag)"
  rm -rf "$bdir" "$dest"
  cmake -S "$SRC" -B "$bdir" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$dest" \
    -DCMAKE_C_FLAGS="-I$inc" \
    -DCMAKE_CXX_FLAGS="-I$inc" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-undefined,dynamic_lookup" \
    "$@" 2>&1 | tee "$LOG/projectm-configure-$tag.log"
  log "Build + install projectM ($tag)"
  cmake --build "$bdir" --config Release -j 2>&1 | tee "$LOG/projectm-build-$tag.log"
  cmake --install "$bdir" 2>&1 | tee -a "$LOG/projectm-build-$tag.log"
  log "Installed to $dest"
  find "$dest" -name "libprojectM*" 2>/dev/null
}

build_mac() {
  build_one mac "$SRC/install-mac" "$(angle_headers macos-arm64_x86_64 Versions/A/)" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
}

build_ios() {
  # iOS device (arm64) + simulator (arm64;x86_64) via the SDK; no external toolchain.
  build_one ios-dev "$SRC/install-ios" "$(angle_headers ios-arm64 '')" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphoneos
  build_one ios-sim "$SRC/install-ios-sim" "$(angle_headers ios-arm64_x86_64-simulator '')" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_SYSROOT=iphonesimulator
}

make_xcframework() {
  local hdrs="$SRC/xcf-headers"
  rm -rf "$hdrs"; mkdir -p "$hdrs"
  cp -R "$SRC/install-mac/include/projectM-4" "$hdrs/"
  printf 'module projectM {\n    header "projectM-4/projectM.h"\n    export *\n}\n' > "$hdrs/module.modulemap"
  local mac ios sim
  mac=$(echo "$SRC"/install-mac/lib/libprojectM-4.*.*.dylib)
  ios=$(echo "$SRC"/install-ios/lib/libprojectM-4.*.*.dylib)
  sim=$(echo "$SRC"/install-ios-sim/lib/libprojectM-4.*.*.dylib)
  # The dylib's install name is @rpath/libprojectM-4.4.dylib but only the fully
  # versioned file (libprojectM-4.4.1.0.dylib) gets embedded by -create-xcframework
  # (no symlinks), so dyld can't find it at runtime. Re-id each to its real
  # filename so the embedded file and the load command match.
  for L in "$ios" "$sim" "$mac"; do
    install_name_tool -id "@rpath/$(basename "$L")" "$L"
  done
  rm -rf "$OUT/projectM.xcframework"
  log "Creating projectM.xcframework"
  xcodebuild -create-xcframework \
    -library "$ios" -headers "$hdrs" \
    -library "$sim" -headers "$hdrs" \
    -library "$mac" -headers "$hdrs" \
    -output "$OUT/projectM.xcframework"
  /usr/bin/du -sh "$OUT/projectM.xcframework" 2>/dev/null || true
}

case "${1:-mac}" in
  mac) fetch_src; build_mac ;;
  ios) fetch_src; build_ios ;;
  xcframework) make_xcframework ;;
  all) fetch_src; build_mac; build_ios; make_xcframework ;;
  *)   fail "unknown subcommand: $1" ;;
esac
