#!/bin/bash
# Genuine one-hour gapless playback gate.
#
# The bounded soak runs inside `verify-build.sh`. This runs the FULL-volume branch, and its whole
# job is to make that provable: a bounded run reported as a full one is the exact false-green that
# has already happened in this work, when `GAPLESS_HOUR=1` was not forwarded to the test runner
# and the identical runtime was the only clue.
#
#   ./scripts/verify-gapless-full-soak.sh
#
set -uo pipefail

PROJECT="Vibrdrome.xcodeproj"
SCHEME="Vibrdrome"
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
LOG_DIR="build-logs"
LOG="$LOG_DIR/gapless-one-hour.log"
REQUIRED_SUITES=("GaplessOneHourPlaybackTests")
EXPECTED_MINIMUM=1
# The hour test must actually play for an hour. A millisecond result is a skip, and a few-minute
# result is the bounded 180 s path — both have been mistaken for a pass before.
MINIMUM_RUNTIME_SECONDS=3600
MINIMUM_MEASURED_SECONDS=3500

mkdir -p "$LOG_DIR"
: > "$LOG"

ONLY_TESTING=()
for suite in "${REQUIRED_SUITES[@]}"; do
  ONLY_TESTING+=("-only-testing:VibrdromeTests/$suite")
done

# TEST_RUNNER_ prefix is mandatory: xcodebuild does not forward a bare variable to the runner.
CMD=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION"
     "${ONLY_TESTING[@]}" -parallel-testing-enabled NO test)

echo "=== Genuine one-hour gapless playback ==="
echo "command: TEST_RUNNER_GAPLESS_HOUR=1 ${CMD[*]}"
echo

START=$(date +%s)
TEST_RUNNER_GAPLESS_HOUR=1 "${CMD[@]}" > "$LOG" 2>&1
XCODE_STATUS=$?
RUNTIME=$(( $(date +%s) - START ))

ACTUAL=$(grep -aoE "Test run with [0-9]+ tests?" "$LOG" | tail -1 | grep -oE "[0-9]+" | head -1)
ACTUAL=${ACTUAL:-0}
SKIPPED=$(grep -acE "Test .* skipped" "$LOG" || true); SKIPPED=${SKIPPED:-0}
FAILURES=$(grep -acE "recorded an issue|Expectation failed" "$LOG" || true); FAILURES=${FAILURES:-0}
RESTARTS=$(grep -ac "Restarting after unexpected exit, crash, or test timeout" "$LOG" || true)
RESTARTS=${RESTARTS:-0}
ENABLED=$(grep -ac "GAPLESS_HOUR_ENABLED=1" "$LOG" || true); ENABLED=${ENABLED:-0}
STARTED=$(grep -ac "GAPLESS_HOUR_STARTED" "$LOG" || true); STARTED=${STARTED:-0}
COMPLETED=$(grep -ac "GAPLESS_HOUR_COMPLETED" "$LOG" || true); COMPLETED=${COMPLETED:-0}
# The duration the test itself measured, not the duration xcodebuild took.
MEASURED=$(grep -aoE "GAPLESS_HOUR_COMPLETED measuredSeconds=[0-9.]+" "$LOG" | tail -1 \
  | grep -oE "[0-9.]+" | tail -1)
MEASURED=${MEASURED:-0}

FAIL_REASONS=()
[ "$XCODE_STATUS" -ne 0 ] && FAIL_REASONS+=("xcodebuild exited $XCODE_STATUS")
[ "$ACTUAL" -eq 0 ] && FAIL_REASONS+=("no soak test executed")
[ "$ACTUAL" -lt "$EXPECTED_MINIMUM" ] && FAIL_REASONS+=("executed $ACTUAL tests, expected >= $EXPECTED_MINIMUM")
[ "$SKIPPED" -ne 0 ] && FAIL_REASONS+=("$SKIPPED skipped; a skipped soak test is not a pass")
[ "$FAILURES" -ne 0 ] && FAIL_REASONS+=("$FAILURES recorded issue(s)")
[ "$RESTARTS" -ne 0 ] && FAIL_REASONS+=("test process restarted $RESTARTS time(s)")
[ "$ENABLED" -eq 0 ] && FAIL_REASONS+=("no GAPLESS_HOUR_ENABLED=1 marker — the hour path did not run")
[ "$STARTED" -eq 0 ] && FAIL_REASONS+=("no GAPLESS_HOUR_STARTED marker")
[ "$COMPLETED" -eq 0 ] && FAIL_REASONS+=("no GAPLESS_HOUR_COMPLETED marker — the run exited early")
awk -v m="$MEASURED" -v n="$MINIMUM_MEASURED_SECONDS" 'BEGIN{exit !(m+0 < n+0)}' && \
  FAIL_REASONS+=("measured playback ${MEASURED}s is below the required ${MINIMUM_MEASURED_SECONDS}s")
[ "$RUNTIME" -lt "$MINIMUM_RUNTIME_SECONDS" ] && \
  FAIL_REASONS+=("runtime ${RUNTIME}s is implausibly short for an hour run")
for suite in "${REQUIRED_SUITES[@]}"; do
  grep -aq "Suite $suite started" "$LOG" || FAIL_REASONS+=("required suite did not run: $suite")
done

echo "--- Gate evidence"
echo "  tests executed    : $ACTUAL (minimum $EXPECTED_MINIMUM)"
echo "  skipped           : $SKIPPED"
echo "  failures          : $FAILURES"
echo "  restarts          : $RESTARTS"
echo "  hour enabled      : $ENABLED"
echo "  started / done    : $STARTED / $COMPLETED"
echo "  measured playback : ${MEASURED}s (minimum ${MINIMUM_MEASURED_SECONDS}s)"
echo "  runtime           : ${RUNTIME}s (minimum ${MINIMUM_RUNTIME_SECONDS}s)"
echo "  log               : $LOG"
echo

if [ ${#FAIL_REASONS[@]} -ne 0 ]; then
  echo "--- Why this gate failed"
  for reason in "${FAIL_REASONS[@]}"; do echo "  - $reason"; done
  echo
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
