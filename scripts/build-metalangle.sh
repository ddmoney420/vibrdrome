#!/usr/bin/env bash
#
# build-metalangle.sh — Phase 0 spike: build MetalANGLE as an .xcframework
# (iOS device + iOS simulator + macOS) from a PINNED commit, for the
# projectM/MilkDrop visualizer spike. See docs/projectm-integration-plan.md.
#
# MetalANGLE (kakashidinho/metalangle) is BSD-licensed (ANGLE), so static or
# dynamic linkage are both license-OK; we build the dynamic framework targets so
# the result is a normal embeddable xcframework. The repo is UNMAINTAINED
# (last release Jul 2022) — this script exists to find out, in a timeboxed way,
# whether it still builds on the current Xcode. Output is NOT committed (Vendor/
# is gitignored); the script is the reproducible source of truth.
#
# Build recipe is adapted from the upstream CI script
# ios/xcode/travis_build_ios.sh: run ios/xcode/fetchDependencies.sh, then
# xcodebuild the MetalANGLE framework scheme per SDK, then -create-xcframework.
#
# Usage:
#   scripts/build-metalangle.sh            # full: clone (pinned) + deps + build + xcframework
#   scripts/build-metalangle.sh deps       # just clone + fetchDependencies (fail-fast on network)
#   scripts/build-metalangle.sh ios|sim|mac# build a single slice (for debugging)
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# --- Pin -------------------------------------------------------------------
REPO="https://github.com/kakashidinho/metalangle.git"
TAG="gles3-0.0.8"
PIN_SHA="850c87ba5b744c7c39f30c66bacdc9648d15067a"   # == tag gles3-0.0.8

# --- Paths (all gitignored) -----------------------------------------------
SRC="$ROOT/spike/.build/metalangle"
DD="$ROOT/spike/.build/metalangle-dd"        # xcodebuild DerivedData
LOG="$ROOT/spike/.build/logs"
OUT="$ROOT/Vendor/MetalANGLE"
PROJ="$SRC/ios/xcode/MGLKitSamples.xcodeproj"
mkdir -p "$LOG" "$OUT" "$(dirname "$SRC")"

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
XCPRETTY=cat; command -v xcpretty >/dev/null && XCPRETTY="xcpretty"

# --- 1. Clone at the pinned SHA -------------------------------------------
fetch_src() {
  if [ ! -d "$SRC/.git" ]; then
    log "Cloning MetalANGLE @ $TAG"
    git clone "$REPO" "$SRC"
  fi
  ( cd "$SRC" && git fetch --tags --force origin && git checkout --force "$PIN_SHA" )
  local have; have="$(cd "$SRC" && git rev-parse HEAD)"
  [ "$have" = "$PIN_SHA" ] || fail "pin mismatch: HEAD=$have expected=$PIN_SHA"
  log "Source at $PIN_SHA"
}

# --- 2. Fetch upstream deps (glslang / SPIRV-Cross / jsoncpp) --------------
fetch_deps() {
  log "fetchDependencies.sh (glslang, SPIRV-Cross, jsoncpp from chromium.googlesource.com)"
  ( cd "$SRC/ios/xcode" && ./fetchDependencies.sh ) 2>&1 | tee "$LOG/00-fetchdeps.log"
}

# --- 3. Build one framework slice -----------------------------------------
# $1 scheme  $2 sdk  $3 tag-for-logfile
build_slice() {
  local scheme="$1" sdk="$2" tag="$3"
  log "xcodebuild $scheme ($sdk)"
  set -o pipefail
  xcodebuild build \
    -project "$PROJ" \
    -scheme "$scheme" \
    -sdk "$sdk" \
    -configuration Release \
    -derivedDataPath "$DD" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | tee "$LOG/build-$tag.log" | $XCPRETTY
  set +o pipefail
}

locate_fw() { # find the built MetalANGLE.framework in an EXACT build-products subdir
  find "$DD/Build/Products/$1" -maxdepth 1 -name "MetalANGLE*.framework" -type d 2>/dev/null | head -1
}

# --- 4. Assemble xcframework ----------------------------------------------
make_xcframework() {
  local ios sim mac args=()
  ios="$(locate_fw 'Release-iphoneos')"
  sim="$(locate_fw 'Release-iphonesimulator')"
  # The MetalANGLE_mac scheme (-sdk macosx) emits to plain Release/, not Release-macosx.
  mac="$(locate_fw 'Release-macosx')"; [ -z "$mac" ] && mac="$(locate_fw 'Release')"
  for f in "$ios" "$sim" "$mac"; do [ -n "$f" ] && args+=(-framework "$f"); done
  [ ${#args[@]} -gt 0 ] || fail "no framework slices found under $DD/Build/Products"
  rm -rf "$OUT/MetalANGLE.xcframework"
  log "Creating xcframework from: $ios $sim $mac"
  xcodebuild -create-xcframework "${args[@]}" -output "$OUT/MetalANGLE.xcframework"
  log "DONE: $OUT/MetalANGLE.xcframework"
  /usr/bin/du -sh "$OUT/MetalANGLE.xcframework" 2>/dev/null || true
}

case "${1:-all}" in
  deps) fetch_src; fetch_deps ;;
  ios)  build_slice MetalANGLE iphoneos ios ;;
  sim)  build_slice MetalANGLE iphonesimulator sim ;;
  mac)  build_slice MetalANGLE_mac macosx mac ;;
  xcframework) make_xcframework ;;
  all)
    fetch_src; fetch_deps
    build_slice MetalANGLE iphoneos ios
    build_slice MetalANGLE iphonesimulator sim
    build_slice MetalANGLE_mac macosx mac
    make_xcframework
    ;;
  *) fail "unknown subcommand: $1" ;;
esac
