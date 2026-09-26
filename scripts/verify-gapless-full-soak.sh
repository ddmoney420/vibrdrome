#!/bin/bash
# Genuine full-volume gapless soak gate.
#
# The bounded soak runs inside `verify-build.sh`. This runs the FULL-volume branch, and its whole
# job is to make that provable: a bounded run reported as a full one is the exact false-green that
# has already happened in this work, when `GAPLESS_SOAK=full` was not forwarded to the test runner
# and the identical runtime was the only clue.
#
#   ./scripts/verify-gapless-full-soak.sh
#
set -uo pipefail

PROJECT="Vibrdrome.xcodeproj"
SCHEME="Vibrdrome"
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
LOG_DIR="build-logs"
LOG="$LOG_DIR/gapless-full-soak.log"
REQUIRED_SUITES=("GaplessFailureAndSoakTests")
EXPECTED_MINIMUM=4
# A full-volume soak cannot plausibly finish in seconds. Anything faster means the bounded counts
# ran, whatever the marker claims.
MINIMUM_RUNTIME_SECONDS=120

mkdir -p "$LOG_DIR"
: > "$LOG"

ONLY_TESTING=()
for suite in "${REQUIRED_SUITES[@]}"; do
  ONLY_TESTING+=("-only-testing:VibrdromeTests/$suite")
done

# TEST_RUNNER_ prefix is mandatory: xcodebuild does not forward a bare variable to the runner.
CMD=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION"
     "${ONLY_TESTING[@]}" -parallel-testing-enabled NO test)

echo "=== Genuine full gapless soak ==="
echo "command: TEST_RUNNER_GAPLESS_SOAK=full ${CMD[*]}"
echo

START=$(date +%s)
TEST_RUNNER_GAPLESS_SOAK=full "${CMD[@]}" > "$LOG" 2>&1
XCODE_STATUS=$?
RUNTIME=$(( $(date +%s) - START ))

ACTUAL=$(grep -aoE "Test run with [0-9]+ tests?" "$LOG" | tail -1 | grep -oE "[0-9]+" | head -1)
ACTUAL=${ACTUAL:-0}
SKIPPED=$(grep -acE "Test .* skipped" "$LOG" || true); SKIPPED=${SKIPPED:-0}
FAILURES=$(grep -acE "recorded an issue|Expectation failed" "$LOG" || true); FAILURES=${FAILURES:-0}
RESTARTS=$(grep -ac "Restarting after unexpected exit, crash, or test timeout" "$LOG" || true)
RESTARTS=${RESTARTS:-0}
FULL_MARKERS=$(grep -ac "GAPLESS_SOAK_MODE=full" "$LOG" || true); FULL_MARKERS=${FULL_MARKERS:-0}
BOUNDED_MARKERS=$(grep -ac "GAPLESS_SOAK_MODE=bounded" "$LOG" || true); BOUNDED_MARKERS=${BOUNDED_MARKERS:-0}

FAIL_REASONS=()
[ "$XCODE_STATUS" -ne 0 ] && FAIL_REASONS+=("xcodebuild exited $XCODE_STATUS")
[ "$ACTUAL" -eq 0 ] && FAIL_REASONS+=("no soak test executed")
[ "$ACTUAL" -lt "$EXPECTED_MINIMUM" ] && FAIL_REASONS+=("executed $ACTUAL tests, expected >= $EXPECTED_MINIMUM")
[ "$SKIPPED" -ne 0 ] && FAIL_REASONS+=("$SKIPPED skipped; a skipped soak test is not a pass")
[ "$FAILURES" -ne 0 ] && FAIL_REASONS+=("$FAILURES recorded issue(s)")
[ "$RESTARTS" -ne 0 ] && FAIL_REASONS+=("test process restarted $RESTARTS time(s)")
[ "$FULL_MARKERS" -eq 0 ] && FAIL_REASONS+=("no GAPLESS_SOAK_MODE=full marker — the full branch did not run")
[ "$BOUNDED_MARKERS" -ne 0 ] && FAIL_REASONS+=("$BOUNDED_MARKERS bounded marker(s) — the bounded counts executed")
[ "$RUNTIME" -lt "$MINIMUM_RUNTIME_SECONDS" ] && \
  FAIL_REASONS+=("runtime ${RUNTIME}s is implausibly short for a full soak (< ${MINIMUM_RUNTIME_SECONDS}s)")
for suite in "${REQUIRED_SUITES[@]}"; do
  grep -aq "Suite $suite started" "$LOG" || FAIL_REASONS+=("required suite did not run: $suite")
done

echo "--- Gate evidence"
echo "  tests executed    : $ACTUAL (minimum $EXPECTED_MINIMUM)"
echo "  skipped           : $SKIPPED"
echo "  failures          : $FAILURES"
echo "  restarts          : $RESTARTS"
echo "  full markers      : $FULL_MARKERS"
echo "  bounded markers   : $BOUNDED_MARKERS"
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
