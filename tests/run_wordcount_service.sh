#!/usr/bin/env bash
# Black-box acceptance tests for the 'WordCountService' web service.
#
# Contract under test:
#   mvn -q -DskipTests package  -> runnable fat jar under target/
#   java -jar target/<name>.jar -> listens on port 8080
#   POST /count <plain text>    -> 200, body = word count as plain text ('2')
#   POST /count <empty body>    -> 400 (client error, not a crash)
#   POST /count (multi-line)    -> 200, words counted across lines ('4')
#   POST /count ('   \n  ')     -> 200, body '0' (valid text, NOT 400)
#   GET <unknown path>          -> normal 404, service keeps serving
#
# Asserts observable behavior only (HTTP status + response body; for the
# 400 the contract fixes the status only, so the body is reported but not
# asserted). Plain bash + curl, no build tools. Exit 0 iff every check passes.

set -u
cd "$(dirname "$0")/.." || exit 1

PORT=8080
BASE_URL="http://127.0.0.1:$PORT"
PASS=0
FAIL=0
SVC_PID=""
SERVICE_LOG=$(mktemp)
FX=$(mktemp -d)
trap 'rm -f "$SERVICE_LOG"; rm -rf "$FX"; [ -n "$SVC_PID" ] && kill "$SVC_PID" 2>/dev/null' EXIT

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

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }

# http_post <fixture-path> -> sets POST_STATUS and POST_BODY (one request)
http_post() {
  local raw
  raw=$(curl -s -w $'\n%{http_code}' -X POST \
    -H 'Content-Type: text/plain' --data-binary @"$1" "$BASE_URL/count" | tr -d '\r')
  POST_STATUS=${raw##*$'\n'}
  POST_BODY=$(printf '%s' "${raw%$'\n'*}" | tr -d '\n')
}

# check_post <name> <fixture-path> <expected status> <expected body>
check_post() {
  local name="$1" fixture="$2" want_status="$3" want_body="$4"
  http_post "$fixture"
  if [ "$POST_STATUS" != "$want_status" ]; then
    fail "$name" "HTTP status was '$POST_STATUS' (expected '$want_status'); body: '$POST_BODY'"
  elif [ "$POST_BODY" != "$want_body" ]; then
    fail "$name" "body was '$POST_BODY' (expected '$want_body'), status $POST_STATUS"
  else
    pass "$name"
  fi
}

echo "WordCountService acceptance tests (java -jar target/<name>.jar, port $PORT)"

# ---- phase 0: locate the jar (required RED phase when absent) ----------
JAR=""
for f in target/*.jar; do
  [ -e "$f" ] || continue
  case "$f" in *-sources.jar|*original*) continue ;; esac
  JAR="$f"
  break
done

NOT_BUILT="service jar not built — run mvn package"

# ---- phase 1: start the service ----------------------------------------
START_NAME="service fat jar starts and listens on port $PORT"
if [ -z "$JAR" ]; then
  fail "$START_NAME" "$NOT_BUILT"
  fail "POST /count 'one two' -> 200, body '2'" "$NOT_BUILT"
  fail "POST /count empty body -> 400 (client error, not a crash)" "$NOT_BUILT"
  fail "POST /count multi-line 'one two\nthree four' -> 200, body '4'" "$NOT_BUILT"
  fail "POST /count whitespace/newline-only '   \\n  ' -> 200, body '0'" "$NOT_BUILT"
  fail "GET unknown path -> 404" "$NOT_BUILT"
  fail "service still answers after unknown-path GET (no crash)" "$NOT_BUILT"
  echo "$PASS passed, $FAIL failed"
  exit 1
fi

if port_open; then
  echo "FAIL-fast: port $PORT already occupied — stop the process using it and retry" >&2
  exit 1
fi

java -jar "$JAR" >"$SERVICE_LOG" 2>&1 &
SVC_PID=$!

READY=""
for _ in $(seq 1 30); do
  port_open || { sleep 1; continue; }
  # port may bind before the app serves requests — wait for real HTTP
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL/" 2>/dev/null)
  if [ "$code" != "000" ] && [ -n "$code" ]; then READY=1; break; fi
  sleep 1
done

if [ -z "$READY" ]; then
  fail "$START_NAME" "jar '$JAR' did not answer HTTP on port $PORT within 30s; service log:"
  sed 's/^/      /' "$SERVICE_LOG" | tail -20
  echo "$PASS passed, $FAIL failed"
  exit 1
fi
pass "$START_NAME (jar: $JAR)"

# ---- fixtures (inline-created, tmpfiles only) ---------------------------
printf 'one two' > "$FX/two-words.txt"
printf 'one two\nthree four' > "$FX/multi-line.txt"
printf '   \n  ' > "$FX/newline-only.txt"

# ---- acceptance checks ---------------------------------------------------
check_post "POST /count 'one two' -> 200, body '2'" \
  "$FX/two-words.txt" 200 "2"

# Empty body: contract fixes the STATUS (400), not the body shape
# (a default error body is fine) — assert status, report body.
http_post /dev/null
if [ "$POST_STATUS" = "400" ]; then
  pass "POST /count empty body -> 400 (client error, not a crash)"
else
  fail "POST /count empty body -> 400 (client error, not a crash)" \
    "HTTP status was '$POST_STATUS' (expected '400'); body: '$POST_BODY'"
fi

check_post "POST /count multi-line 'one two\nthree four' -> 200, body '4'" \
  "$FX/multi-line.txt" 200 "4"

check_post "POST /count whitespace/newline-only '   \\n  ' -> 200, body '0'" \
  "$FX/newline-only.txt" 200 "0"

CODE_404=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/no-such-path-acceptance-test")
if [ "$CODE_404" = "404" ]; then
  pass "GET unknown path -> 404"
else
  fail "GET unknown path -> 404" "HTTP status was '$CODE_404' (expected '404')"
fi

check_post "service still answers after unknown-path GET (no crash)" \
  "$FX/two-words.txt" 200 "2"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
