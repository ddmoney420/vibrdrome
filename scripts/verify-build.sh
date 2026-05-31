#!/usr/bin/env bash
#
# verify-build.sh — single source of truth for "is this build green?".
#
# Runs SwiftLint, the three platform builds, and the unit + UI rotation tests,
# writing every log to build-logs/ and printing ONE pass/fail summary. Exits
# non-zero if ANY check fails OR if any build emits a *source* warning.
#
# Why this exists: scrolled xcodebuild output is unreliable to eyeball (and in
# some terminals renders truncated/garbled). Never report a build or test as
# passing from scrolled output — run this script and report its exit code and
# the "RESULT:" line.
#
# Usage:
#   scripts/verify-build.sh            # full suite
#   scripts/verify-build.sh --quick    # SwiftLint + iOS build + unit tests only
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT="Vibrdrome.xcodeproj"
IOS_DEST='platform=iOS Simulator,name=iPhone 17 Pro'
WATCH_DEST='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
LOGDIR="build-logs"
rm -rf "$LOGDIR"        # start clean so stale logs never leak into a summary
mkdir -p "$LOGDIR"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# Each check writes exactly one line "STATUS\tNAME\tDETAIL" to this file.
# A flat append-once file (not a bash array) makes duplication impossible and
# keeps the summary trustworthy even if a helper is called oddly.
SUMMARY="$LOGDIR/_summary.tsv"
: > "$SUMMARY"
emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SUMMARY"; }

require() {
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { echo "MISSING TOOL: $t (install via brew)"; exit 2; }
  done
}
require swiftlint xcodebuild

# --- SwiftLint ---
swiftlint lint --quiet > "$LOGDIR/lint.log" 2>&1
v=$(grep -cE ': (warning|error):' "$LOGDIR/lint.log")
if [ "$v" -eq 0 ]; then emit PASS "SwiftLint" "0 violations"; else emit FAIL "SwiftLint" "$v violations"; fi

# build NAME SCHEME DEST
build() {
  local name="$1" scheme="$2" dest="$3" log="$LOGDIR/build-$1.log"
  xcodebuild -project "$PROJECT" -scheme "$scheme" -destination "$dest" build > "$log" 2>&1
  local ok warn err
  ok=$(grep -Fc 'BUILD SUCCEEDED' "$log")
  warn=$(grep -Ec '\.swift:[0-9]+:[0-9]+: warning:' "$log")
  err=$(grep -Ec '\.swift:[0-9]+:[0-9]+: error:' "$log")
  if [ "$ok" -ge 1 ] && [ "$warn" -eq 0 ] && [ "$err" -eq 0 ]; then
    emit PASS "$name build" "0 warnings, 0 errors"
  else
    emit FAIL "$name build" "succeeded=$ok warnings=$warn errors=$err (see $log)"
  fi
}

# runtest NAME ONLY
runtest() {
  local name="$1" only="$2" log="$LOGDIR/test-$1.log"
  xcodebuild -project "$PROJECT" -scheme Vibrdrome -destination "$IOS_DEST" \
    -only-testing:"$only" test > "$log" 2>&1
  local ok bad
  ok=$(grep -Fc 'TEST SUCCEEDED' "$log")
  bad=$(grep -Fc 'TEST FAILED' "$log")
  if [ "$ok" -ge 1 ] && [ "$bad" -eq 0 ]; then
    emit PASS "$name" "passed"
  else
    emit FAIL "$name" "succeeded=$ok failed=$bad (see $log)"
  fi
}

build iOS Vibrdrome "$IOS_DEST"
runtest unit-tests "VibrdromeTests"

if [ "$QUICK" -eq 0 ]; then
  build macOS VibrdromeMac "platform=macOS"
  build watchOS VibrdromeWatch "$WATCH_DEST"
  runtest ui-rotation-tests "VibrdromeUITests/RotationTests"
fi

# --- Single summary, printed once from the flat file ---
echo ""
echo "================ VERIFY SUMMARY ================"
while IFS=$'\t' read -r status name detail; do
  printf "  %-4s  %-20s  %s\n" "$status" "$name" "$detail"
done < "$SUMMARY"
echo "==============================================="
if grep -q '^FAIL' "$SUMMARY"; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
