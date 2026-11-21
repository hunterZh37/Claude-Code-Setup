#!/usr/bin/env bash
# End-to-end tests: run setup.sh and uninstall.sh against throwaway HOMEs.
# Never touches your real ~/.claude. Usage: tests/run-tests.sh [core|migrate|stress ...]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$REPO/tests"
# shellcheck source=tests/lib.sh
source "$TESTS/lib.sh"

parts=("$@")
[[ ${#parts[@]} -gt 0 ]] || parts=(core migrate stress bench web plugin)
for part in "${parts[@]}"; do
  echo "=== $part"
  # shellcheck source=/dev/null
  source "$TESTS/$part.sh"
done

echo "=== lint"
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck clean" shellcheck "$REPO/setup.sh" "$REPO/uninstall.sh" "$REPO"/tests/*.sh
else
  echo "○ shellcheck not installed, skipped (brew install shellcheck)"
fi
check "python compiles" python3 -m py_compile "$REPO/lib/settings.py" "$REPO/lib/helpers.py" "$REPO/lib/migrate.py" "$REPO/templates/scripts/workday-hours.py"
find "$REPO" -name __pycache__ -type d -prune -exec rm -rf {} +

echo
echo "Passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
