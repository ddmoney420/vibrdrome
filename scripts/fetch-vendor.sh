#!/usr/bin/env bash
#
# fetch-vendor.sh — download the pinned, prebuilt Vendor xcframeworks (MetalANGLE
# + projectM) from a public GitHub Release asset via curl, verify each against a
# hard-coded SHA-256, then extract into the gitignored Vendor/ directory.
# No gh CLI or token required (fetches the public release download URL directly),
# so it works the same for dev setup and CI.
#
# This is Vendor strategy B: the binaries are NOT committed to git; they are
# fetched on demand (dev setup + CI) from a pinned Release asset, with the
# SHA-256 baked in here as the integrity anchor. Produced by package-vendor.sh.
#
# Usage:
#   scripts/fetch-vendor.sh            # fetch+verify+extract any missing frameworks
#   scripts/fetch-vendor.sh --force    # re-fetch even if already present
#   scripts/fetch-vendor.sh verify     # verify already-extracted Vendor/ (re-zip+compare)
#   scripts/fetch-vendor.sh selftest <dir>  # run verify+extract against local zips in <dir>
#                                           # (proves the pipeline without a published Release)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# --- Pin -------------------------------------------------------------------
# Bump TAG + the SHA-256s together whenever the xcframeworks are rebuilt and
# re-published via `scripts/package-vendor.sh upload <tag>`.
REPO="ddmoney420/vibrdrome"
TAG="vendor-frameworks-v1"

# name | dest dir under Vendor/ | release asset | sha256 of the asset zip
ASSETS=(
  "MetalANGLE|Vendor/MetalANGLE|MetalANGLE.xcframework.zip|cfebe63237fb5122af73b7a4fcb611a622e4eec3704b1bcab6f3ec698984ffcb"
  "projectM|Vendor/projectM|projectM.xcframework.zip|bb8bb31ae12297f708f6ebe163737d74cdb8d829e64e2ea85a113fd937afe4fd"
)

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

# Verify a zip against an expected sha256, then extract it into a dest dir
# (ditto preserves the macOS framework version symlinks). $1 zip $2 dest $3 sum
verify_and_extract() {
  local zip="$1" dest="$2" want="$3" got
  got="$(sha256 "$zip")"
  [ "$got" = "$want" ] || fail "SHA-256 mismatch for $(basename "$zip")\n  expected $want\n  got      $got"
  log "SHA-256 OK: $(basename "$zip")"
  mkdir -p "$dest"
  find "$dest" -maxdepth 1 -name '*.xcframework' -exec rm -rf {} +
  ditto -x -k "$zip" "$dest"
}

fetch() {
  local force="${1:-}"
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name destrel asset want <<<"$entry"
    local dest="$ROOT/$destrel"
    if [ -z "$force" ] && find "$dest" -maxdepth 1 -name '*.xcframework' -print -quit 2>/dev/null | grep -q .; then
      log "$name already present — skipping (use --force to re-fetch)"
      continue
    fi
    local url="https://github.com/${REPO}/releases/download/${TAG}/${asset}"
    log "Downloading $asset from $url"
    curl -fL --retry 3 -o "$tmp/$asset" "$url" \
      || fail "download failed — has the Release '$TAG' been published? (scripts/package-vendor.sh upload $TAG)"
    verify_and_extract "$tmp/$asset" "$dest" "$want"
  done
  log "Vendor frameworks ready."
}

# Re-zip the currently-extracted Vendor/ and compare to the pinned sums. Note:
# ditto zips are not always byte-identical run-to-run, so a mismatch here is a
# weak signal, not proof of tampering; the authoritative check is on the
# downloaded asset in fetch(). Provided mainly for a quick local sanity pass.
verify_local() {
  command -v "$ROOT/scripts/package-vendor.sh" >/dev/null 2>&1 || true
  bash "$ROOT/scripts/package-vendor.sh" >/dev/null
  local ok=1
  for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name destrel asset want <<<"$entry"
    local got; got="$(sha256 "$ROOT/dist/vendor/$asset")"
    if [ "$got" = "$want" ]; then printf '  OK   %s\n' "$asset"
    else printf '  DIFF %s\n    pinned %s\n    local  %s\n' "$asset" "$want" "$got"; ok=0; fi
  done
  [ "$ok" = 1 ] && log "local Vendor matches pinned sums" || log "local Vendor differs (see above)"
}

# Prove verify+extract end-to-end against local zips (no Release needed).
selftest() {
  local dir="${1:-$ROOT/dist/vendor}"
  [ -d "$dir" ] || fail "no zip dir at $dir (run scripts/package-vendor.sh first)"
  for entry in "${ASSETS[@]}"; do
    IFS='|' read -r name destrel asset want <<<"$entry"
    [ -f "$dir/$asset" ] || fail "missing $dir/$asset"
    verify_and_extract "$dir/$asset" "$ROOT/$destrel" "$want"
  done
  log "selftest OK — verify+extract pipeline works against $dir"
}

case "${1:-fetch}" in
  fetch)    fetch ;;
  --force)  fetch force ;;
  verify)   verify_local ;;
  selftest) selftest "${2:-}" ;;
  *)        fail "unknown subcommand: $1" ;;
esac
