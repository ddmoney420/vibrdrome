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
# This is the STANDARD (bounded, parallel) suite. It deliberately does NOT include the serialized
# gapless buffer gate: those are minutes-long real-time audio runs that destabilise the test process
# when run alongside other audio suites. Run them separately with
# ./scripts/verify-gapless-buffer-gate.sh -- a PASS here alone is not "full verification".
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

# --- Single-instance lock -------------------------------------------------
# Two concurrent runs share build-logs/ and each wipes it at startup, so they
# clobber each other's logs and produce a partial/garbled summary (this bit us
# for real). `mkdir` is atomic, so it's a reliable mutex. Acquire BEFORE the
# rm -rf below, and only ever remove a lock this process owns.
LOCKDIR="$LOGDIR/.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  other=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "?")
  if [ "$other" != "?" ] && kill -0 "$other" 2>/dev/null; then
    echo "verify-build.sh is already running (pid $other). Aborting to avoid clobbering build-logs/." >&2
    echo "If that pid is dead, remove $LOCKDIR and re-run." >&2
    exit 3
  fi
  # Stale lock (owner gone): reclaim it.
  echo "Removing stale lock from dead pid $other." >&2
  rm -rf "$LOCKDIR"
  mkdir "$LOCKDIR" 2>/dev/null || { echo "Could not acquire lock $LOCKDIR." >&2; exit 3; }
fi
echo "$$" > "$LOCKDIR/pid"
# Release the lock on any exit, but only the dir we own (guard against the
# rm -rf "$LOGDIR" below having already removed it).
cleanup() { [ -f "$LOCKDIR/pid" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCKDIR"; }
trap cleanup EXIT INT TERM

# Preserve our lock across the clean-slate wipe of the log dir.
_lockbak=$(mktemp -d)
mv "$LOCKDIR" "$_lockbak/.lock"
rm -rf "$LOGDIR"        # start clean so stale logs never leak into a summary
mkdir -p "$LOGDIR"
mv "$_lockbak/.lock" "$LOCKDIR"
rmdir "$_lockbak" 2>/dev/null || true

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
# Same binary + same config + same strictness as CI (.github/workflows/ci.yml): the version is
# pinned in .swiftlint-version, and we lint with --config .swiftlint.yml --strict. A green run
# here therefore means a green CI SwiftLint job. Version drift is a hard FAIL, not a silent pass;
# --quiet only trims progress/summary lines and does not change violations or the exit code.
SL_EXPECTED="$(cat .swiftlint-version)"
SL_ACTUAL="$(swiftlint version 2>/dev/null)"
if [ "$SL_ACTUAL" != "$SL_EXPECTED" ]; then
  emit FAIL "SwiftLint" "version mismatch: expected $SL_EXPECTED, got ${SL_ACTUAL:-none} (see .swiftlint-version)"
elif swiftlint lint --config .swiftlint.yml --strict --quiet > "$LOGDIR/lint.log" 2>&1; then
  emit PASS "SwiftLint" "0 violations (strict, $SL_EXPECTED)"
else
  v=$(grep -cE ': (warning|error):' "$LOGDIR/lint.log")
  emit FAIL "SwiftLint" "$v violations (strict, $SL_EXPECTED)"
fi

# --- Entitlements ---
# project.yml GENERATES the entitlement files rather than referencing them, so a spec regression
# silently drops CarPlay audio and the App Group. Nothing else in this suite would notice: the
# builds still succeed, and the damage only shows up as the app vanishing from CarPlay or the
# widget losing the shared container. Checked against the tracked files, not a log message.
if ./scripts/verify-entitlements.sh > "$LOGDIR/entitlements.log" 2>&1; then
  emit PASS "entitlements" "CarPlay + App Group present"
else
  emit FAIL "entitlements" "required entitlement missing (see $LOGDIR/entitlements.log)"
fi

# --- Serialized-suite partition ---
# A suite skipped here but absent from the gate would run nowhere, and the gate's minimum-count
# check only asserts a floor, so it would not notice. This proves the two paths cover everything.
if ./scripts/verify-suite-partition.sh > "$LOGDIR/suite-partition.log" 2>&1; then
  emit PASS "suite partition" "serialized suites covered by the gate"
else
  emit FAIL "suite partition" "a suite runs in neither path (see $LOGDIR/suite-partition.log)"
fi

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

# Suites that must run serialized, read from the shared manifest so this list and the gate's cannot
# drift apart. scripts/verify-suite-partition.sh proves the two paths together cover everything.
SERIALIZED_ONLY_SUITES=()
while IFS= read -r _suite; do
  [ -n "$_suite" ] && SERIALIZED_ONLY_SUITES+=("VibrdromeTests/$_suite")
done < <(grep -vE '^\s*(#|$)' scripts/serialized-suites.txt)

# runtest NAME ONLY
runtest() {
  local name="$1" only="$2" log="$LOGDIR/test-$1.log"
  local skips=()
  if [ "$only" = "VibrdromeTests" ]; then
    for suite in "${SERIALIZED_ONLY_SUITES[@]}"; do skips+=("-skip-testing:$suite"); done
  fi
  xcodebuild -project "$PROJECT" -scheme Vibrdrome -destination "$IOS_DEST" \
    -only-testing:"$only" "${skips[@]}" test > "$log" 2>&1
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
  echo "Standard verification: FAIL"
  echo "Serialized gapless buffer gate: NOT RUN (./scripts/verify-gapless-buffer-gate.sh)"
  echo "RESULT: FAIL"
  exit 1
fi
echo "Standard verification: PASS"
echo "Serialized gapless buffer gate: NOT RUN (./scripts/verify-gapless-buffer-gate.sh)"
echo "RESULT: PASS"
exit 0
