#!/usr/bin/env bash
# Runs every RUIN DIGGER test suite headlessly and reports a combined result.
#
#   ./tools/run_tests.sh            # run all suites
#   GODOT=/path/to/godot ./tools/run_tests.sh
#
# Each suite is a scene; Godot is asked to quit with a non-zero code on failure,
# and a timeout guards against a hung suite.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
TIMEOUT="${TEST_TIMEOUT:-600}"

SUITES=(
	"src/tests/test_runner.tscn"
	"src/tests/sweep.tscn"
	"src/tests/objective.tscn"
	"src/tests/playthrough.tscn"
	"src/tests/scenes.tscn"
)

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "godot not found; set GODOT=/path/to/godot" >&2
	exit 127
fi

cd "$ROOT" || exit 1

failed=0
passed=0
for suite in "${SUITES[@]}"; do
	echo "----------------------------------------------------------------"
	echo ">>> $suite"
	echo "----------------------------------------------------------------"
	if timeout "$TIMEOUT" "$GODOT" --headless --quit-after 20000 "res://$suite"; then
		passed=$((passed + 1))
	else
		code=$?
		if [ "$code" -eq 124 ]; then
			echo "!!! TIMEOUT after ${TIMEOUT}s"
		fi
		failed=$((failed + 1))
	fi
done

echo "================================================================"
echo "suites: $passed passed, $failed failed"
echo "================================================================"
[ "$failed" -eq 0 ]
