#!/usr/bin/env bash
#
# build-projectm.sh — Phase 0 spike: build libprojectM v4 as a dynamic/shared
# .xcframework (iOS device + simulator + macOS) for the MilkDrop visualizer.
# See docs/projectm-integration-plan.md.
#
# STATUS: BLOCKED at configure (documented below). projectM v4.1.6's GLES path
# is hard-gated to Linux/Android and FATAL_ERRORs on Apple platforms. This
# script clones+pins+configures to REPRODUCE that blocker; the Apple-GLES patch
# is described but intentionally NOT applied pending a go/no-go decision (it
# means patching upstream's deliberate platform support — surfaced before doing).
#
#   $ scripts/build-projectm.sh configure   # reproduce the blocker (mac)
#
# ---------------------------------------------------------------------------
# THE BLOCKER (verified 2026-06-05, cmake 4.3.3):
#   CMake Error at CMakeLists.txt:169 (message):
#     OpenGL ES 3 support is currently only available for Linux platforms.
#
#   CMakeLists.txt ~165-178:
#     if(ENABLE_GLES)
#       if(NOT CMAKE_SYSTEM_NAME STREQUAL Linux AND NOT ... STREQUAL Android)
#         message(FATAL_ERROR "OpenGL ES 3 support is currently only available
#                              for Linux platforms. ...")
#       find_package(OpenGL REQUIRED COMPONENTS GLES3)   # OpenGL::GLES3
#
# Two patches would be required to build Apple GLES against MetalANGLE:
#   (1) Allow Darwin in the line-169 guard.
#   (2) Provide the OpenGL::GLES3 target: cmake/gles/FindOpenGL.cmake only
#       resolves GLES3 on its Linux branch (OPENGL_GLES3_INCLUDE_DIR via
#       find_path GLES3/gl3.h; OPENGL_gles3_LIBRARY via find_library). On Apple
#       it must instead point at MetalANGLE:
#         OPENGL_GLES3_INCLUDE_DIR = Vendor/MetalANGLE/.../Headers
#         OPENGL_gles3_LIBRARY     = the MetalANGLE framework binary
#       and create the OpenGL::GLES3 IMPORTED target from those.
# Both are NON-TRIVIAL (forcing an upstream-unsupported config) → decision first.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export PATH="/opt/homebrew/bin:$PATH"

# --- Pin ---
REPO="https://github.com/projectM-visualizer/projectm.git"
TAG="v4.1.6"
PIN_SHA="3158ee615eaafd93a8912b5f6dd84a9c47b2e00a"   # == tag v4.1.6

SRC="$ROOT/spike/.build/projectm"
LOG="$ROOT/spike/.build/logs"
OUT="$ROOT/Vendor/projectM"
ANGLE_HEADERS="$ROOT/Vendor/MetalANGLE/MetalANGLE.xcframework/macos-arm64_x86_64/MetalANGLE.framework/Headers"
ANGLE_LIB="$ROOT/Vendor/MetalANGLE/MetalANGLE.xcframework/macos-arm64_x86_64/MetalANGLE.framework/MetalANGLE"
mkdir -p "$LOG" "$OUT" "$(dirname "$SRC")"

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
command -v cmake >/dev/null || fail "cmake not found (brew install cmake)"

# CMake flags decided from the v4.1.6 option set (see plan doc §2):
#   shared (LGPL dynamic), GLES (match ANGLE), playlist OFF (v1), bundled
#   projectm-eval + GLM (no system deps), no SDL UI, no tests.
CMAKE_FLAGS=(
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
    log "Cloning projectM @ $TAG"
    git clone "$REPO" "$SRC"
  fi
  ( cd "$SRC" && git fetch --tags --force origin && git checkout --force "$PIN_SHA" \
      && git submodule update --init --recursive )   # vendor/projectm-eval
  log "Source at $PIN_SHA (+ submodules)"
}

configure_mac() {
  log "Configuring (macOS native) — reproduces the Apple-GLES blocker"
  rm -rf "$SRC/build-mac"
  cmake -S "$SRC" -B "$SRC/build-mac" "${CMAKE_FLAGS[@]}" 2>&1 | tee "$LOG/projectm-configure-mac.log"
}

case "${1:-configure}" in
  configure) fetch_src; configure_mac ;;
  *) fail "BLOCKED — see header. Only 'configure' is wired (reproduces the blocker)." ;;
esac
