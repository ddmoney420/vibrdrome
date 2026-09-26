#!/usr/bin/env bash
#
# verify-entitlements.sh — fail if a required entitlement has gone missing.
#
# Why this exists: `targets.<name>.entitlements` in project.yml is a file *generation* directive,
# not a reference to a hand-maintained file. For a long time it carried a `path` with no
# `properties`, so every `xcodegen generate` wrote an empty <dict/> over the real entitlements and
# silently dropped CarPlay audio and the App Group. The symptom appears much later — CarPlay stops
# offering the app, or the widget can no longer read the shared container — and neither shows up as
# a build failure.
#
# project.yml now lists the required keys, so generation reproduces them. This script is the
# backstop that makes a regression loud: it reads the *tracked entitlement files on disk* (the
# artifacts that actually get code-signed into the app), not a build log message.
#
# Usage:
#   scripts/verify-entitlements.sh          # exits 0 if every requirement is present
#
# Exit codes: 0 = all present, 1 = at least one missing, 2 = tooling/file problem.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

PB=/usr/libexec/PlistBuddy
[ -x "$PB" ] || { echo "MISSING TOOL: $PB"; exit 2; }

fail=0

# require_true <file> <key>
require_true() {
  local file="$1" key="$2" value
  if [ ! -f "$file" ]; then
    echo "  MISSING FILE  $file"
    fail=1
    return
  fi
  value=$("$PB" -c "Print :$key" "$file" 2>/dev/null)
  if [ "$value" = "true" ]; then
    echo "  ok            $file :: $key = true"
  else
    echo "  MISSING       $file :: $key (expected true, got '${value:-<absent>}')"
    fail=1
  fi
}

# require_array_member <file> <key> <expected member>
require_array_member() {
  local file="$1" key="$2" want="$3" members
  if [ ! -f "$file" ]; then
    echo "  MISSING FILE  $file"
    fail=1
    return
  fi
  # PlistBuddy prints an array as one indented entry per line between Array { }.
  members=$("$PB" -c "Print :$key" "$file" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e '/^Array {$/d' -e '/^}$/d')
  if printf '%s\n' "$members" | grep -qx "$want"; then
    echo "  ok            $file :: $key contains $want"
  else
    echo "  MISSING       $file :: $key does not contain $want (found: ${members:-<absent>})"
    fail=1
  fi
}

APP_GROUP="group.com.vibrdrome.app"
APP_ENT="Vibrdrome/Vibrdrome.entitlements"
WIDGET_ENT="VibrdromeWidget/VibrdromeWidget.entitlements"

echo "Verifying required entitlements..."

# CarPlay audio: without this the app does not appear in CarPlay at all.
require_true          "$APP_ENT"    "com.apple.developer.carplay-audio"
# App Group: the widget and the app share state through this container.
require_array_member  "$APP_ENT"    "com.apple.security.application-groups" "$APP_GROUP"
require_array_member  "$WIDGET_ENT" "com.apple.security.application-groups" "$APP_GROUP"

if [ "$fail" -ne 0 ]; then
  echo "ENTITLEMENTS: FAIL"
  echo "Re-add the missing key(s) to project.yml under the target's 'entitlements.properties',"
  echo "then run 'xcodegen generate' and re-run this script."
  exit 1
fi

echo "ENTITLEMENTS: PASS"
exit 0
