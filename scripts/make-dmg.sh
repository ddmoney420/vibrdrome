#!/usr/bin/env bash
#
# make-dmg.sh — build a signed + notarized macOS .dmg of Vibrdrome for direct
# (non-App-Store) distribution, and optionally attach it to a GitHub release.
#
# Pipeline:
#   regenerate project -> archive (Release) -> Developer ID export ->
#   notarize app -> staple -> build DMG -> sign + notarize DMG -> staple ->
#   verify -> (optional) upload to a GitHub release.
#
# DRAFT: not yet test-run. Requires the prerequisites below to be in place.
# See docs/MACOS-RELEASE.md for full setup.
#
# Prerequisites (the script checks for these and fails early if missing):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Hardened Runtime enabled on the VibrdromeMac target
#      (ENABLE_HARDENED_RUNTIME = YES in project.yml). Required for notarization.
#   3. A notarytool credential profile (default name below), created once via
#      `xcrun notarytool store-credentials`.
#
# Usage:
#   scripts/make-dmg.sh                 # build + notarize the DMG locally
#   scripts/make-dmg.sh --upload TAG    # also upload to GitHub release TAG
#                                       #   (creates a pre-release if TAG has none)
#
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Config ---------------------------------------------------------------
PROJECT="Vibrdrome.xcodeproj"
SCHEME="VibrdromeMac"
APP_NAME="Vibrdrome"
TEAM_ID="85JD2B827Q"
NOTARY_PROFILE="vibrdrome-notary"          # `xcrun notarytool store-credentials vibrdrome-notary ...`
EXPORT_OPTS="scripts/ExportOptions-DeveloperID.plist"
BUILD_DIR="build-dmg"
ARCHIVE="$BUILD_DIR/Vibrdrome.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

UPLOAD_TAG=""
if [ "${1:-}" = "--upload" ]; then UPLOAD_TAG="${2:-}"; [ -n "$UPLOAD_TAG" ] || { echo "--upload needs a TAG"; exit 2; }; fi

log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# --- Single-instance lock -------------------------------------------------
# Two concurrent runs both `rm -rf` the build dir and submit duplicate
# notarizations that clobber each other. `mkdir` is atomic, so it's a reliable
# mutex. The lock lives outside BUILD_DIR (which gets wiped below) and is
# released on any exit.
LOCKDIR=".make-dmg.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  other=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "?")
  if [ "$other" != "?" ] && kill -0 "$other" 2>/dev/null; then
    fail "make-dmg.sh is already running (pid $other). Only one notarization run at a time."
  fi
  echo "Removing stale lock from dead pid $other." >&2
  rm -rf "$LOCKDIR"
  mkdir "$LOCKDIR" 2>/dev/null || fail "Could not acquire lock $LOCKDIR."
fi
echo "$$" > "$LOCKDIR/pid"
cleanup() { [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCKDIR"; }
trap cleanup EXIT INT TERM

# --- Prerequisite checks --------------------------------------------------
log "Checking prerequisites"
command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"
command -v gh >/dev/null || [ -z "$UPLOAD_TAG" ] || fail "gh not found but --upload requested"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || fail "No 'Developer ID Application' certificate in your keychain.
       Create one at developer.apple.com -> Certificates -> Developer ID Application,
       download and double-click it. See docs/MACOS-RELEASE.md."

[ -f "$EXPORT_OPTS" ] || fail "Missing $EXPORT_OPTS"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "Notary credential profile '$NOTARY_PROFILE' not found. Set it up once:
       xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
         --key <path/to/AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_UUID>
       (or use --apple-id/--team-id/--password). See docs/MACOS-RELEASE.md."

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

# --- Generate project (xcodegen clears entitlements; restore from git) ----
log "Regenerating Xcode project"
xcodegen generate >/dev/null
git checkout -- Vibrdrome/Vibrdrome.entitlements VibrdromeWidget/VibrdromeWidget.entitlements 2>/dev/null || true

# --- Archive (Release) ----------------------------------------------------
log "Archiving $SCHEME (Release)"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'generic/platform=macOS' \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:" || true
[ -d "$ARCHIVE" ] || fail "Archive failed (see output above)"

# --- Export Developer ID app ----------------------------------------------
log "Exporting Developer ID-signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP" ] || fail "Export did not produce $APP"

SHORT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DMG_NAME="$APP_NAME-macOS-v${SHORT_VER}-build${BUILD_NUM}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
log "Version $SHORT_VER (build $BUILD_NUM) -> $DMG_NAME"

# --- Notarize the app, then staple ----------------------------------------
log "Submitting app for notarization (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# --- Build the DMG --------------------------------------------------------
log "Building DMG"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

# --- Sign + notarize + staple the DMG -------------------------------------
log "Signing, notarizing, and stapling the DMG"
codesign --force --timestamp --sign "Developer ID Application" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

# --- Verify ---------------------------------------------------------------
log "Verifying notarization"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 || true

log "DONE: $DMG_PATH"

# --- Optional upload ------------------------------------------------------
if [ -n "$UPLOAD_TAG" ]; then
  log "Uploading to GitHub release $UPLOAD_TAG"
  gh release view "$UPLOAD_TAG" >/dev/null 2>&1 \
    || gh release create "$UPLOAD_TAG" --prerelease \
         --title "v${SHORT_VER} Beta (Build ${BUILD_NUM}) - macOS" \
         --notes "macOS build ${BUILD_NUM}. See CHANGELOG.md for details."
  gh release upload "$UPLOAD_TAG" "$DMG_PATH" --clobber
  log "Uploaded $DMG_NAME to release $UPLOAD_TAG"
fi
