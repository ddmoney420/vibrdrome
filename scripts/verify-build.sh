#!/usr/bin/env bash
#
# verify-build.sh — single source of truth for "is this build green?".
#
# Runs SwiftLint, all three platform builds, and the unit + UI rotation tests,
# writing every log to build-logs/ and printing ONE pass/fail summary. Exits
# non-zero if ANY check fails OR if any build emits a source warning.
#
# Why this exists: scrolled xcodebuild output is unreliable to eyeball (and in
# some terminals renders truncated/garbled). Never report a build or test as
# passing from scrolled output — run this script and report its exit code.
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
mkdir -p "$LOGDIR"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

fail=0
declare -a RESULTS

# record NAME PASS|FAIL DETAIL
record() { RESULTS+=("$1|$2|$3"); [ "$2" = "FAIL" ] && fail=1; }

require() {
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { echo "MISSING TOOL: $t (install via brew)"; exit 2; }
  done
}
require swiftlint xcodebuild

# --- SwiftLint ---
swiftlint lint --quiet > "$LOGDIR/lint.log" 2>&1
v=$(grep -cE ': (warning|error):' "$LOGDIR/lint.log")
[ "$v" -eq 0 ] && record "SwiftLint" PASS "0 violations" || record "SwiftLint" FAIL "$v violations"

# build SCHEME DEST LOGNAME
build() {
  local scheme="$1" dest="$2" name="$3"
  xcodebuild -project "$PROJECT" -scheme "$scheme" -destination "$dest" build \
    > "$LOGDIR/$name.log" 2>&1
  local ok warn err
  ok=$(grep -c 'BUILD SUCCEEDED' "$LOGDIR/$name.log")
  warn=$(grep -cE '\.swift:[0-9]+:[0-9]+: warning:' "$LOGDIR/$name.log")
  err=$(grep -cE '\.swift:[0-9]+:[0-9]+: error:' "$LOGDIR/$name.log")
  if [ "$ok" -ge 1 ] && [ "$warn" -eq 0 ] && [ "$err" -eq 0 ]; then
    record "$name build" PASS "0 warnings, 0 errors"
  else
    record "$name build" FAIL "succeeded=$ok warnings=$warn errors=$err (see $LOGDIR/$name.log)"
  fi
}

# test SCHEME ONLY LOGNAME
runtest() {
  local scheme="$1" only="$2" name="$3"
  xcodebuild -project "$PROJECT" -scheme "$scheme" -destination "$IOS_DEST" \
    -only-testing:"$only" test > "$LOGDIR/$name.log" 2>&1
  local ok bad
  ok=$(grep -c 'TEST SUCCEEDED' "$LOGDIR/$name.log")
  bad=$(grep -c 'TEST FAILED' "$LOGDIR/$name.log")
  if [ "$ok" -ge 1 ] && [ "$bad" -eq 0 ]; then
    record "$name" PASS "passed"
  else
    record "$name" FAIL "succeeded=$ok failed=$bad (see $LOGDIR/$name.log)"
  fi
}

build Vibrdrome "$IOS_DEST" "iOS"
runtest Vibrdrome "VibrdromeTests" "unit-tests"

if [ "$QUICK" -eq 0 ]; then
  build VibrdromeMac "platform=macOS" "macOS"
  build VibrdromeWatch "$WATCH_DEST" "watchOS"
  runtest Vibrdrome "VibrdromeUITests/RotationTests" "ui-rotation-tests"
fi

echo ""
echo "================ VERIFY SUMMARY ================"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r name status detail <<< "$r"
  printf "  %-4s  %-22s  %s\n" "$status" "$name" "$detail"
done
echo "==============================================="
if [ "$fail" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi
exit "$fail"
