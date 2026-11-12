#!/usr/bin/env bash
# Runs every automated suite headless. Non-zero exit on any failure,
# script error, or hang. Honours GODOT=/path/to/godot and TEST_TIMEOUT.
set -u
GODOT="${GODOT:-godot}"
TIMEOUT="${TEST_TIMEOUT:-600}"
cd "$(dirname "$0")/.."
LOG_DIR="${LOG_DIR:-build/test-logs}"
mkdir -p "$LOG_DIR"

echo "== import"
timeout "$TIMEOUT" "$GODOT" --headless --import > "$LOG_DIR/import.log" 2>&1
if grep -E "SCRIPT ERROR|Parse Error" "$LOG_DIR/import.log"; then
  echo "import reported script errors"; exit 1
fi

status=0
for suite in terrain physics save ui gen game deep; do
  log="$LOG_DIR/$suite.log"
  timeout "$TIMEOUT" "$GODOT" --headless res://tests/test_runner.tscn -- suite="$suite" seeds="${SEEDS:-60}" > "$log" 2>&1
  code=$?
  grep -E "^== |FAIL|RESULT" "$log"
  if [ $code -eq 124 ]; then
    echo "!! suite $suite timed out"; status=1
  elif [ $code -ne 0 ]; then
    echo "!! suite $suite exited $code"; status=1
  fi
  if grep -E "SCRIPT ERROR|Parse Error" "$log"; then
    echo "!! suite $suite logged script errors"; status=1
  fi
  if ! grep -q "RESULT:" "$log"; then
    echo "!! suite $suite produced no result line"; status=1
  fi
done
[ $status -eq 0 ] && echo "ALL SUITES PASSED" || echo "TESTS FAILED"
exit $status
