#!/usr/bin/env bash
#
# package-vendor.sh — package the locally-built Vendor xcframeworks into pinned,
# checksummed zips for distribution as GitHub Release assets (Vendor strategy B:
# fetch pinned prebuilts). The xcframeworks themselves are NOT committed to git
# (Vendor/ is gitignored); this script is how the prebuilt artifacts are produced
# and published, and `fetch-vendor.sh` is how they come back down.
#
# zip is done with `ditto -c -k --keepParent` (not plain `zip`) because the macOS
# slice is a versioned framework bundle whose Versions/Current + Modules symlinks
# MUST survive the round-trip; ditto preserves them, plain zip can mangle them.
#
# Usage:
#   scripts/package-vendor.sh                 # zip + sha256 into dist/ (no upload)
#   scripts/package-vendor.sh upload <tag>    # ALSO create/upload a GitHub Release
#                                             # (explicit; never runs by default)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

OUT="$ROOT/dist/vendor"
FRAMEWORKS=(
  "MetalANGLE:Vendor/MetalANGLE/MetalANGLE.xcframework"
  "projectM:Vendor/projectM/projectM.xcframework"
)

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

package() {
  rm -rf "$OUT"; mkdir -p "$OUT"
  : > "$OUT/SHA256SUMS"
  for entry in "${FRAMEWORKS[@]}"; do
    local name="${entry%%:*}" path="${entry#*:}"
    [ -d "$ROOT/$path" ] || fail "missing $path — build it first (scripts/build-$(echo "$name" | tr '[:upper:]' '[:lower:]').sh)"
    local zip="$OUT/$name.xcframework.zip"
    log "Zipping $path"
    ( cd "$ROOT/$(dirname "$path")" && ditto -c -k --keepParent "$(basename "$path")" "$zip" )
    local sum; sum="$(sha256 "$zip")"
    printf '%s  %s\n' "$sum" "$name.xcframework.zip" >> "$OUT/SHA256SUMS"
    printf '  %-26s %s  (%s)\n' "$name.xcframework.zip" "$sum" "$(/usr/bin/du -h "$zip" | awk '{print $1}')"
  done
  log "Wrote $OUT/SHA256SUMS"
  cat "$OUT/SHA256SUMS"
}

upload() {
  local tag="${1:-}"
  [ -n "$tag" ] || fail "usage: package-vendor.sh upload <tag>"
  command -v gh >/dev/null || fail "gh CLI not found"
  [ -f "$OUT/SHA256SUMS" ] || package
  log "Creating/uploading GitHub Release '$tag' (prerelease)"
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$OUT"/*.zip "$OUT/SHA256SUMS" --clobber
  else
    gh release create "$tag" "$OUT"/*.zip "$OUT/SHA256SUMS" \
      --prerelease --title "Vendor frameworks ($tag)" \
      --notes "Prebuilt MetalANGLE + projectM xcframeworks for the projectM/MilkDrop visualizer. Consumed by scripts/fetch-vendor.sh with SHA-256 pinning. LGPL-2.1 (projectM, dynamic) + BSD (ANGLE)."
  fi
  log "Uploaded. Pin these sums in scripts/fetch-vendor.sh:"
  cat "$OUT/SHA256SUMS"
}

case "${1:-package}" in
  package) package ;;
  upload)  upload "${2:-}" ;;
  *)       fail "unknown subcommand: $1" ;;
esac
