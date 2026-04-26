#!/usr/bin/env bash
# Basic smoke tests for quietshrink

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/../bin/quietshrink"
PASS=0
FAIL=0

assert_equal() {
  if [ "$1" = "$2" ]; then
    echo "  ✓ $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $3"
    echo "    expected: $2"
    echo "    actual:   $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if echo "$1" | grep -q "$2"; then
    echo "  ✓ $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $3"
    echo "    expected to contain: $2"
    echo "    actual:              $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== quietshrink smoke tests ==="

# Test 1: help works
echo "test: --help"
HELP_OUT=$("$BIN" --help 2>&1)
assert_contains "$HELP_OUT" "USAGE" "help shows USAGE section"
assert_contains "$HELP_OUT" "tiny" "help mentions tiny preset"
assert_contains "$HELP_OUT" "transparent" "help mentions transparent preset"

# Test 2: version
echo "test: --version"
VERSION_OUT=$("$BIN" --version 2>&1)
assert_contains "$VERSION_OUT" "quietshrink" "version output mentions quietshrink"

# Test 3: missing file errors
echo "test: missing input file"
if "$BIN" /nonexistent/file.mov 2>/dev/null; then
  echo "  ✗ should fail on missing file"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ correctly errors on missing file"
  PASS=$((PASS + 1))
fi

# Test 4: invalid quality preset
echo "test: invalid quality preset"
if "$BIN" -q invalid /tmp/dummy.mov 2>/dev/null; then
  echo "  ✗ should fail on invalid preset"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ correctly errors on invalid preset"
  PASS=$((PASS + 1))
fi

# Test 5: real compression (if test fixture exists)
if [ -f "$SCRIPT_DIR/fixtures/sample.mov" ]; then
  echo "test: real compression"
  TMP_OUT="/tmp/quietshrink_test_$$.mov"
  RESULT=$("$BIN" --json "$SCRIPT_DIR/fixtures/sample.mov" "$TMP_OUT" 2>/dev/null)

  if [ -f "$TMP_OUT" ]; then
    echo "  ✓ output file created"
    PASS=$((PASS + 1))

    SAVED_PCT=$(echo "$RESULT" | grep saved_percent | grep -oE '[0-9]+\.[0-9]+')
    if [ -n "$SAVED_PCT" ]; then
      echo "  ✓ JSON output has saved_percent: $SAVED_PCT%"
      PASS=$((PASS + 1))
    fi
    rm -f "$TMP_OUT"
  else
    echo "  ✗ output file not created"
    FAIL=$((FAIL + 1))
  fi
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
