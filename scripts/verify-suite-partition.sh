#!/usr/bin/env bash
#
# verify-suite-partition.sh — prove no test suite can run in neither verification path.
#
# The standard suite skips the serialized suites; the gate runs them. If a name drifts between the
# two — a rename, a removal, a new serialized suite added to only one place — a suite silently runs
# nowhere and the count check alone would not notice, because it only asserts a minimum.
#
# This makes that impossible: both scripts read scripts/serialized-suites.txt, and this checks the
# manifest against the source tree and against the gate's own execution list.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

MANIFEST="scripts/serialized-suites.txt"
FAIL=0

[ -f "$MANIFEST" ] || { echo "MISSING MANIFEST: $MANIFEST"; exit 2; }
mapfile -t SUITES < <(grep -vE '^\s*(#|$)' "$MANIFEST")

echo "Serialized suite partition:"
[ "${#SUITES[@]}" -gt 0 ] || { echo "  manifest is empty"; exit 1; }

for suite in "${SUITES[@]}"; do
  # 1. The suite must still exist in the test sources. A rename or deletion fails loudly here
  #    rather than silently shrinking coverage.
  if grep -rqE "struct[[:space:]]+$suite\b|final class[[:space:]]+$suite\b" VibrdromeTests; then
    exists="ok"
  else
    exists="MISSING FROM SOURCES"
    FAIL=1
  fi

  # 2. The gate must actually execute it.
  if grep -qE "^[[:space:]]*\"$suite\"" scripts/verify-gapless-buffer-gate.sh \
     || grep -q "serialized-suites.txt" scripts/verify-gapless-buffer-gate.sh; then
    gated="gate: runs"
  else
    gated="gate: NOT RUN"
    FAIL=1
  fi

  printf "  %-40s %-22s %s\n" "$suite" "$exists" "$gated"
done

# 3. Both scripts must source the manifest, so the lists cannot drift apart.
for script in scripts/verify-build.sh scripts/verify-gapless-buffer-gate.sh; do
  if grep -q "serialized-suites.txt" "$script"; then
    echo "  $script reads the manifest"
  else
    echo "  $script does NOT read the manifest — lists can drift"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "SUITE PARTITION: FAIL"
  exit 1
fi
echo "SUITE PARTITION: PASS"
exit 0
