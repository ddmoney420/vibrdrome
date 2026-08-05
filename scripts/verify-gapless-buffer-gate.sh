#!/bin/bash
# Serialized gapless buffer gate.
#
# The buffer-substrate acceptance suites are minutes-long real-time audio runs. They are excluded
# from `verify-build.sh` because running them in parallel with every other audio suite restarted the
# test process ("unexpected exit, crash, or test timeout") and took unrelated suites down with it.
# Excluding them is only defensible if they are actually run somewhere, by name, with a result that
# cannot be mistaken for a pass — which is what this script is.
#
# It is built to fail loudly rather than quietly: a skipped test, a test that never executed, an
# environment variable that did not reach the runner, or a crashed test process all fail the gate.
# A millisecond-duration skipped test is NOT a pass; that mistake has been made in this work before.
#
#   ./scripts/verify-gapless-buffer-gate.sh
#
set -uo pipefail

PROJECT="Vibrdrome.xcodeproj"
SCHEME="Vibrdrome"
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
LOG_DIR="build-logs"
LOG="$LOG_DIR/gapless-buffer-gate.log"

# Suites that must run. Swift Testing reports a parameterised @Test as ONE test in its run summary
# however many arguments it has, so the expected minimum is a count of @Test functions, not of cases.
# Set just below the current total so a suite silently dropping out fails the gate while adding a
# test does not.
# Read from the shared manifest (scripts/serialized-suites.txt) so this list and verify-build.sh's
# skip list cannot drift apart — a suite in one but not the other would run nowhere.
REQUIRED_SUITES=()
while IFS= read -r _suite; do
  [ -n "$_suite" ] && REQUIRED_SUITES+=("$_suite")
done < <(grep -vE '^\s*(#|$)' "$(dirname "$0")/serialized-suites.txt")
EXPECTED_MINIMUM=80

mkdir -p "$LOG_DIR"
: > "$LOG"

ONLY_TESTING=()
for suite in "${REQUIRED_SUITES[@]}"; do
  ONLY_TESTING+=("-only-testing:VibrdromeTests/$suite")
done

# TEST_RUNNER_ prefix is mandatory: xcodebuild does NOT forward a bare environment variable to the
# test runner process, and a gate that silently ran the bounded path while reporting the full one
# would be worse than no gate at all.
CMD=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION"
     "${ONLY_TESTING[@]}" -parallel-testing-enabled NO test)

echo "=== Serialized gapless buffer gate ==="
echo "command: TEST_RUNNER_GAPLESS_BUFFER_GATE=1 ${CMD[*]}"
echo

START=$(date +%s)
TEST_RUNNER_GAPLESS_BUFFER_GATE=1 "${CMD[@]}" > "$LOG" 2>&1
XCODE_STATUS=$?
END=$(date +%s)
RUNTIME=$((END - START))

# --- Evidence extracted from the log, not inferred from the exit code ---------------------------

SUMMARY=$(grep -aoE "Test run with [0-9]+ tests?" "$LOG" | tail -1)
ACTUAL=$(printf '%s' "$SUMMARY" | grep -oE "[0-9]+" | head -1)
ACTUAL=${ACTUAL:-0}
SKIPPED=$(grep -acE "^.*Test .* skipped" "$LOG" || true)
SKIPPED=${SKIPPED:-0}
FAILURES=$(grep -acE "recorded an issue|Expectation failed" "$LOG" || true)
FAILURES=${FAILURES:-0}
RESTARTS=$(grep -ac "Restarting after unexpected exit, crash, or test timeout" "$LOG" || true)
RESTARTS=${RESTARTS:-0}

FAIL_REASONS=()

[ "$XCODE_STATUS" -ne 0 ] && FAIL_REASONS+=("xcodebuild exited $XCODE_STATUS")
[ "$ACTUAL" -eq 0 ] && FAIL_REASONS+=("no gated test executed (no test-run summary in the log)")
[ "$ACTUAL" -lt "$EXPECTED_MINIMUM" ] && \
  FAIL_REASONS+=("executed $ACTUAL tests, expected at least $EXPECTED_MINIMUM")
[ "$SKIPPED" -ne 0 ] && FAIL_REASONS+=("$SKIPPED test(s) skipped; a skipped gate test is not a pass")
[ "$FAILURES" -ne 0 ] && FAIL_REASONS+=("$FAILURES recorded issue(s)")
[ "$RESTARTS" -ne 0 ] && FAIL_REASONS+=("test process restarted $RESTARTS time(s) — crash or timeout")

# Every required suite must actually appear as having started.
for suite in "${REQUIRED_SUITES[@]}"; do
  if ! grep -aq "Suite $suite started" "$LOG"; then
    FAIL_REASONS+=("required suite did not run: $suite")
  fi
done

# The gate is meaningless if the flag never reached the test process. The gated tests are
# `.enabled(if:)` on it, so if it were missing they would silently not run — which the count check
# above would catch, but this names the actual cause.
if ! grep -aq "GATEFLAG reached runner" "$LOG"; then
  FAIL_REASONS+=("GAPLESS_BUFFER_GATE did not reach the test runner (no GATEFLAG marker)")
fi

echo "--- Gate evidence"
echo "  expected minimum tests : $EXPECTED_MINIMUM"
echo "  actual tests executed  : $ACTUAL"
echo "  tests skipped          : $SKIPPED"
echo "  recorded failures      : $FAILURES"
echo "  process restarts       : $RESTARTS"
echo "  runtime                : ${RUNTIME}s"
echo "  log                    : $LOG"
echo

if [ ${#FAIL_REASONS[@]} -ne 0 ]; then
  echo "--- Why this gate failed"
  for reason in "${FAIL_REASONS[@]}"; do echo "  - $reason"; done
  echo
  echo "RESULT: FAIL"
  exit 1
fi

echo "RESULT: PASS"
exit 0
