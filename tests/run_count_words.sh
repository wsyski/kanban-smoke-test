#!/usr/bin/env bash
# Black-box acceptance tests for the 'WordCount' console program.
#
# Contract under test (invocation from repo root):
#   mvn -q -DskipTests compile   (build)
#   java -cp target/classes WordCount <file>
#   - reads a UTF-8 text file, prints ONE line to stdout: the number of
#     words (whitespace-separated tokens), exits 0
#   - empty file / whitespace-only file: prints 0, exit 0
#   - missing file: message on stderr, exit 2
#
# Asserts observable behavior only (stdout / stderr / exit code).
# Plain bash, no pytest. Build: mvn -q -DskipTests compile. Exit 0 iff every check passes.

set -u
cd "$(dirname "$0")/.." || exit 1

FX=tests/fixtures
PASS=0
FAIL=0
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

run_wc() {
  java -cp target/classes WordCount "$1" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

pass() {
  PASS=$((PASS + 1))
  echo "PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1"
  if [ -n "${2:-}" ]; then
    echo "      $2"
  fi
  return 0
}

# check_count <name> <fixture path> <expected count>
# Expects exactly one newline-terminated stdout line containing the count.
check_count() {
  local name="$1" file="$2" expected="$3"
  local rc nl out
  run_wc "$file"
  rc=$?
  nl=$(wc -l <"$STDOUT_FILE")
  out=$(cat "$STDOUT_FILE")
  if [ "$rc" -ne 0 ]; then
    fail "$name" "exit code $rc (expected 0); stderr: $(cat "$STDERR_FILE")"
  elif [ "$nl" -ne 1 ]; then
    fail "$name" "stdout was not exactly one line (got $nl newline-terminated): '$out'"
  elif [ "$out" != "$expected" ]; then
    fail "$name" "stdout was '$out' (expected '$expected')"
  else
    pass "$name"
  fi
}

echo "WordCount acceptance tests (java -cp target/classes WordCount <file>)"

check_count "three-words.txt prints 3, exit 0" \
  "$FX/three-words.txt" 3

check_count "multi-line.txt prints 9 (multiple lines, UTF-8 words), exit 0" \
  "$FX/multi-line.txt" 9

check_count "empty.txt prints 0, exit 0" \
  "$FX/empty.txt" 0

check_count "whitespace.txt prints 0, exit 0" \
  "$FX/whitespace.txt" 0

# Missing file: message on stderr AND exit code 2 (one acceptance criterion).
run_wc "$FX/does-not-exist.txt"
rc=$?
err=$(cat "$STDERR_FILE")
if [ "$rc" -ne 2 ]; then
  fail "missing file: stderr message, exit 2" "exit code $rc (expected 2); stderr: '$err'"
elif [ -z "$err" ]; then
  fail "missing file: stderr message, exit 2" "exit code was 2 but stderr empty (expected a message)"
else
  pass "missing file: stderr message, exit 2"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
