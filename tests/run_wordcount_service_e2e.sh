#!/usr/bin/env bash
# End-to-end integration tests for the 'WordCountService' web service.
#
# Full lifecycle exercised here (self-contained, bash + curl only):
#   mvn -q -DskipTests package -> locate fat jar under target/
#   -> start it as a real process on port 8080 (clear failure if the port is
#      taken; ~30s startup wait; process ALWAYS killed on exit via trap)
#   -> exercise POST /count over HTTP -> kill -> port-leak check -> report.
#
# Scenarios assert EXACT response bodies (not just status codes):
#   - first POST right after boot (no warmup)
#   - repeated sequential POSTs return consistent counts
#   - tabs / runs of multiple spaces count tokens, not characters
#   - large body (400 generated words) -> exact count
#   - UTF-8 multibyte body counts words correctly (charset=utf-8 AND no header)
#   - ASCII body with no Content-Type header counts correctly
#   - service process is gone after the script exits (port re-checked)
#
# One PASS/FAIL line per scenario; final line 'N passed, M failed';
# exit 0 iff every check passes.

set -u
cd "$(dirname "$0")/.." || exit 1

PORT=8080
BASE_URL="http://127.0.0.1:$PORT"
PASS=0
FAIL=0
SVC_PID=""
SERVICE_LOG=$(mktemp)
BUILD_LOG=$(mktemp)
FX=$(mktemp -d)
trap 'rm -f "$SERVICE_LOG" "$BUILD_LOG"; rm -rf "$FX"; [ -n "$SVC_PID" ] && kill "$SVC_PID" 2>/dev/null' EXIT

pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1"
  if [ -n "${2:-}" ]; then
    echo "      $2"
  fi
  return 0
}

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }

# http_post <fixture-path> <content-type or '' for none>
#   -> sets POST_STATUS and POST_BODY (one request)
http_post() {
  local raw
  local ct_args=()
  if [ -n "${2:-}" ]; then
    ct_args=(-H "Content-Type: $2")
  else
    ct_args=(-H 'Content-Type:')   # remove curl's default Content-Type header
  fi
  raw=$(curl -s --max-time 10 -w $'\n%{http_code}' -X POST \
    "${ct_args[@]}" --data-binary @"$1" "$BASE_URL/count" | tr -d '\r')
  POST_STATUS=${raw##*$'\n'}
  POST_BODY=$(printf '%s' "${raw%$'\n'*}" | tr -d '\n')
}

# check_post <name> <fixture-path> <content-type or ''> <expected status> <expected body>
check_post() {
  local name="$1" fixture="$2" ctype="$3" want_status="$4" want_body="$5"
  http_post "$fixture" "$ctype"
  if [ "$POST_STATUS" != "$want_status" ]; then
    fail "$name" "HTTP status was '$POST_STATUS' (expected '$want_status'); body: '$POST_BODY'"
  elif [ "$POST_BODY" != "$want_body" ]; then
    fail "$name" "body was '$POST_BODY' (expected '$want_body'), status $POST_STATUS"
  else
    pass "$name"
  fi
}

echo "WordCountService end-to-end integration tests (build -> run fat jar -> HTTP, port $PORT)"

# ---- phase 0: port must be free ------------------------------------------
if port_open; then
  echo "FAIL-fast: port $PORT already occupied — stop the process using it and retry" >&2
  exit 1
fi

# ---- phase 1: build the fat jar ------------------------------------------
echo "building: mvn -q -DskipTests package"
if ! mvn -q -DskipTests package >"$BUILD_LOG" 2>&1; then
  echo "FAIL-fast: mvn package failed — build log (tail):" >&2
  tail -30 "$BUILD_LOG" >&2
  exit 1
fi

JAR=""
for f in target/*.jar; do
  [ -e "$f" ] || continue
  case "$f" in *-sources.jar|*original*) continue ;; esac
  JAR="$f"
  break
done
if [ -z "$JAR" ]; then
  echo "FAIL-fast: no runnable fat jar found under target/ after mvn package" >&2
  exit 1
fi

# ---- phase 2: start the service as a real process ------------------------
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
  echo "FAIL-fast: jar '$JAR' did not answer HTTP on port $PORT within 30s; service log (tail):" >&2
  tail -20 "$SERVICE_LOG" >&2
  exit 1
fi

# ---- fixtures (generated inline, tmpfiles only) ---------------------------
printf 'boot one two three' > "$FX/first.txt"           # 4 words
printf 'alpha beta' > "$FX/repeat.txt"                  # 2 words
printf 'one\ttwo   three\t\tfour' > "$FX/tabs.txt"      # 4 tokens
printf 'naïve café 你好 世界 señoriña' > "$FX/utf8.txt"  # 5 words, multibyte
printf 'no content type header ascii' > "$FX/nohdr.txt" # 5 words

# large body: 400 generated words of varying length, single-spaced
LARGE_FILE="$FX/large.txt"
LARGE_WORDS=""
i=1
while [ "$i" -le 400 ]; do
  n=$(( i % 5 + 2 ))
  word="$(printf 'w%.0s' $(seq 1 "$n"))${i}"
  LARGE_WORDS="$LARGE_WORDS $word"
  i=$(( i + 1 ))
done
printf '%s' "${LARGE_WORDS# }" > "$LARGE_FILE"
EXPECTED_LARGE=$(wc -w < "$LARGE_FILE")

# ---- e2e scenarios --------------------------------------------------------
check_post "POST /count right after boot (no warmup) -> 200, body '4'" \
  "$FX/first.txt" "text/plain" 200 "4"

# repeated sequential POSTs, same body three times -> same count every time
CONSISTENT=1
DETAIL=""
for rep in 1 2 3; do
  http_post "$FX/repeat.txt" "text/plain"
  if [ "$POST_STATUS" != "200" ] || [ "$POST_BODY" != "2" ]; then
    CONSISTENT=0
    DETAIL="repeat $rep: status '$POST_STATUS' body '$POST_BODY' (expected 200 / '2')"
    break
  fi
done
if [ "$CONSISTENT" -eq 1 ]; then
  pass "repeated sequential POSTs return consistent counts (same body 3x -> '2' every time)"
else
  fail "repeated sequential POSTs return consistent counts (same body 3x -> '2' every time)" "$DETAIL"
fi

check_post "body with tabs/multiple spaces counts tokens not characters -> 200, body '4'" \
  "$FX/tabs.txt" "text/plain" 200 "4"

if [ "$EXPECTED_LARGE" -eq 400 ]; then
  check_post "large body (400 generated words) -> 200, body '400'" \
    "$FX/large.txt" "text/plain" 200 "400"
else
  fail "large body (400 generated words) -> 200, body '400'" \
    "test generator broken: fixture has $EXPECTED_LARGE words (expected 400)"
fi

check_post "UTF-8 multibyte body, Content-Type text/plain; charset=utf-8 -> 200, body '5'" \
  "$FX/utf8.txt" "text/plain; charset=utf-8" 200 "5"

check_post "UTF-8 multibyte body, no Content-Type header -> 200, body '5'" \
  "$FX/utf8.txt" "" 200 "5"

check_post "ASCII body, no Content-Type header -> 200, body '5'" \
  "$FX/nohdr.txt" "" 200 "5"

# ---- teardown: kill, then verify the port is really released --------------
kill "$SVC_PID" 2>/dev/null
wait "$SVC_PID" 2>/dev/null
SVC_PID=""

PORT_STILL_OPEN=""
for _ in $(seq 1 50); do
  port_open || break
  PORT_STILL_OPEN=1
  sleep 0.1
done
if [ -n "$PORT_STILL_OPEN" ]; then
  fail "service process gone after script (port $PORT free)" \
    "something is STILL listening on port $PORT after kill — leaked service process"
else
  pass "service process gone after script (port $PORT free)"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
