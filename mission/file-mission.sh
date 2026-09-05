#!/usr/bin/env bash
# File the Java smoke missions on ONE kanban board (smoke-test), sequentially.
#
#   mission 1 (-m 1): word-count CLI        TW  -> C1  -> RVa  -> G2
#   mission 2 (-m 2): Spring Boot service   TW2 -> C12 -> RVa2 -> TI -> G2b
#
# One board, two tasks, strict sequence: mission 2's root TW2 is PARENTED to
# mission 1's gate (G2), so the board itself enforces "task 2 only after
# task 1 is committed". Mission 2 additionally carries TI (end-to-end
# integration tests) between review and gate.
#
# Phases (mode-aware; default -m all files BOTH missions):
#   file    create cards, parked on the human-gate lane (nothing dispatches)
#   launch  unblock + assign the FIRST task's root TW only (sequence!)
#   drive   assign the next card whenever its parents are done
#   gate    complete the next non-done gate with the commit SHA
#
# Usage:
#   mission/file-mission.sh [-b BOARD] [-r REPO_DIR] [-k KEY_PREFIX] [-m 1|2|all] file
#   mission/file-mission.sh [-m 1|2|all] launch
#   mission/file-mission.sh [-m 1|2|all] drive
#   mission/file-mission.sh [-m 1|2|all] gate "SHA"
#
# Idempotent: title-deduped (idempotency keys alone are NOT a dedupe).
set -euo pipefail

BOARD=smoke-test
REPO=/opt/projects/kanban-smoke-test/main/kanban-smoke-test
KEY=smokejava
MISSION=all                                   # 1 | 2 | all
HERE="$(cd "$(dirname "$0")" && pwd)"

while getopts "b:r:k:m:" opt; do
  case $opt in
    b) BOARD=$OPTARG ;;
    r) REPO=$OPTARG ;;
    k) KEY=$OPTARG ;;
    m) MISSION=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
PHASE=${1:?phase: file | launch | drive | gate}
GATE_SHA=${2:-}
case "$MISSION" in 1|2|3|all) ;; *) echo "-m must be 1, 2, 3 or all"; exit 2 ;; esac

kb() { hermes kanban --board "$BOARD" "$@"; }

# Card id lookup by exact title prefix; `list --json` is a bare JSON array.
id_by_title() {
  kb list --json | python3 -c '
import json, sys
prefix = sys.argv[1]
for t in json.load(sys.stdin):
    if t["title"].startswith(prefix) and t.get("status") != "archived":
        print(t["id"]); break
' "$1"
}
status_of() { kb show "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["status"])'; }

# Titles — unique prefixes across the whole board.
M1_TW="TW: acceptance tests (black-box) - Java word-count"
M1_C1="C1: implement - Java word-count"
M1_RVA="RVa: reviewer verdict on implementation + acceptance tests"
M1_G2="Gate: approve and commit - Java word-count smoke"
M2_TW="TW2: acceptance tests (black-box) - WordCountService"
M2_C1="C12: implement - WordCountService"
M2_RVA="RVa2: reviewer verdict - WordCountService"
M2_TI="TI: end-to-end integration tests - WordCountService"
M2_G2="Gate: approve and commit - WordCountService"
M3_C1="C13: mavenize word-count CLI"
M3_RVA="RVa3: reviewer verdict - mavenized word-count CLI"
M3_G2="Gate: approve and commit - Maven word-count CLI"

subst() { sed "s|<REPO>|$REPO|g" "$1"; }

# create_if_missing TITLE BODY KEY [--parent PARENT_ID] [--extra flags...]
create_if_missing() {
  local title=$1 body=$2 key=$3; shift 3
  local id
  id=$(id_by_title "$title")
  if [ -n "$id" ]; then echo "$id"; return; fi
  local parent=""
  local -a extra=()
  while [ $# -gt 0 ]; do
    case $1 in
      --parent) parent=$2; shift 2 ;;
      --extra) shift ;;                      # separator: the rest are kb flags
      *) extra+=("$1"); shift ;;
    esac
  done
  if [ -n "$parent" ]; then
    kb create "$title" --body "$body" --assignee human-gate --parent "$parent" \
      "${extra[@]}" --idempotency-key "$key" --created-by manager --json >/dev/null
  else
    # Root card: --initial-status blocked parks it atomically (no dispatch race).
    kb create "$title" --body "$body" --assignee human-gate --initial-status blocked \
      "${extra[@]}" --idempotency-key "$key" --created-by manager --json >/dev/null
  fi
  id_by_title "$title"
}

# assign_if_ready CARD_ID PROFILE PARENT_STATUS... : assign when all parents done
# and the card itself is ready (parents completed -> status auto-promotes).
assign_when_ready() {
  local card=$1 profile=$2; shift 2
  local st
  st=$(status_of "$card")
  if [ "$st" = ready ]; then
    kb assign "$card" "$profile"; echo "  $card -> $profile"
  fi
}

file_m1() {
  M1_TW_ID=$(create_if_missing "$M1_TW" "$(cat "$HERE/card-bodies/tw-body.txt")" "$KEY-m1-tw" \
    --extra --workspace "dir:$REPO" --skill test-driven-development \
    --max-retries 1 --max-runtime 30m)
  M1_C1_ID=$(create_if_missing "$M1_C1" "$(subst "$HERE/card-bodies/c1-body.txt")" "$KEY-m1-c1" \
    --parent "$M1_TW_ID" --extra --workspace "dir:$REPO" \
    --skill subagent-driven-development --max-retries 1 --max-runtime 30m)
  M1_RVA_ID=$(create_if_missing "$M1_RVA" "$(subst "$HERE/card-bodies/rva-body.txt")" "$KEY-m1-rva" \
    --parent "$M1_C1_ID" --extra --workspace "dir:$REPO" \
    --max-retries 1 --max-runtime 30m)   # NO --goal: judge could open the gate
  M1_G2_ID=$(create_if_missing "$M1_G2" "$(subst "$HERE/card-bodies/g2-body.txt")" "$KEY-m1-g2" \
    --parent "$M1_RVA_ID" --max-retries 1)
  echo "M1 filed: TW=$M1_TW_ID C1=$M1_C1_ID RVa=$M1_RVA_ID G2=$M1_G2_ID"
}

file_m2() {
  # Root TW2's parent = mission 1's gate -> board enforces the sequence.
  local g2
  g2=$(id_by_title "$M1_G2")
  [ -n "$g2" ] || { echo "mission 1 gate not on board — file mission 1 first (-m 1 or all)"; exit 1; }
  M2_TW_ID=$(create_if_missing "$M2_TW" "$(subst "$HERE/card-bodies/tw-spring-body.txt")" "$KEY-m2-tw" \
    --parent "$g2" --extra --workspace "dir:$REPO" --skill test-driven-development \
    --max-retries 1 --max-runtime 45m)
  M2_C1_ID=$(create_if_missing "$M2_C1" "$(subst "$HERE/card-bodies/c1-spring-body.txt")" "$KEY-m2-c1" \
    --parent "$M2_TW_ID" --extra --workspace "dir:$REPO" \
    --skill subagent-driven-development --max-retries 1 --max-runtime 45m)
  M2_RVA_ID=$(create_if_missing "$M2_RVA" "$(subst "$HERE/card-bodies/rva-body.txt")" "$KEY-m2-rva" \
    --parent "$M2_C1_ID" --extra --workspace "dir:$REPO" \
    --max-retries 1 --max-runtime 30m)   # NO --goal
  M2_TI_ID=$(create_if_missing "$M2_TI" "$(subst "$HERE/card-bodies/ti-spring-body.txt")" "$KEY-m2-ti" \
    --parent "$M2_RVA_ID" --extra --workspace "dir:$REPO" --skill test-driven-development \
    --max-retries 1 --max-runtime 45m)
  M2_G2_ID=$(create_if_missing "$M2_G2" "$(subst "$HERE/card-bodies/g2-body.txt")" "$KEY-m2-g2" \
    --parent "$M2_TI_ID" --max-retries 1)
  echo "M2 filed: TW2=$M2_TW_ID C12=$M2_C1_ID RVa2=$M2_RVA_ID TI=$M2_TI_ID G2b=$M2_G2_ID (root parented to M1 gate $g2)"
}

file_m3() {
  # M3 = Maven conversion of the word-count CLI. No TW card: the acceptance
  # suite exists (task 1) and is frozen — it IS the spec. Root parented to
  # M2's gate.
  local g2b
  g2b=$(id_by_title "$M2_G2")
  [ -n "$g2b" ] || { echo "mission 2 gate not on board — file mission 2 first"; exit 1; }
  M3_C1_ID=$(create_if_missing "$M3_C1" "$(subst "$HERE/card-bodies/c1-maven-body.txt")" "$KEY-m3-c1" \
    --parent "$g2b" --extra --workspace "dir:$REPO" \
    --skill subagent-driven-development --max-retries 1 --max-runtime 30m)
  M3_RVA_ID=$(create_if_missing "$M3_RVA" "$(subst "$HERE/card-bodies/rva-body.txt")" "$KEY-m3-rva" \
    --parent "$M3_C1_ID" --extra --workspace "dir:$REPO" \
    --max-retries 1 --max-runtime 30m)   # NO --goal
  M3_G2_ID=$(create_if_missing "$M3_G2" "$(subst "$HERE/card-bodies/g2-body.txt")" "$KEY-m3-g2" \
    --parent "$M3_RVA_ID" --max-retries 1)
  echo "M3 filed: C13=$M3_C1_ID RVa3=$M3_RVA_ID G3=$M3_G2_ID (root parented to M2 gate $g2b)"
}

case "$PHASE" in
file)
  if [ "$MISSION" = 1 ] || [ "$MISSION" = all ]; then file_m1; fi
  if [ "$MISSION" = 2 ] || [ "$MISSION" = all ]; then file_m2; fi
  if [ "$MISSION" = 3 ] || [ "$MISSION" = all ]; then file_m3; fi
  ;;

launch)
  # Only mission 1's TW launches now — mission 2's root is parented to M1's
  # gate and must wait for the human commit. drive handles the rest.
  TW1=$(id_by_title "$M1_TW")
  [ -n "$TW1" ] || { echo "no TW on board — run 'file' first"; exit 1; }
  TW1_ST=$(status_of "$TW1")
  if [ "$TW1_ST" = done ]; then
    echo "M1 TW already done — nothing to launch."
  else
    kb unblock "$TW1"
    kb assign "$TW1" tester
    echo "Launched: TW1=$TW1 -> tester. M2 root stays parked until M1's gate completes."
  fi
  ;;

drive)
  # Assign the next card whenever its parents are all done (status auto-promotes
  # to ready; only the human-gate -> profile assignment needs a hand).
  if [ "$MISSION" = 1 ] || [ "$MISSION" = all ]; then
    TW1=$(id_by_title "$M1_TW"); C1=$(id_by_title "$M1_C1"); RVA=$(id_by_title "$M1_RVA")
    if [ "$(status_of "$TW1")" = done ] && [ "$(status_of "$C1")" = ready ]; then
      kb assign "$C1" coder; echo "M1: C1 -> coder"
    fi
    if [ "$(status_of "$C1")" = done ] && [ "$(status_of "$RVA")" = ready ]; then
      kb assign "$RVA" reviewer; echo "M1: RVa -> reviewer"
    fi
  fi
  if [ "$MISSION" = 2 ] || [ "$MISSION" = all ]; then
    TW2=$(id_by_title "$M2_TW"); C12=$(id_by_title "$M2_C1")
    RVA2=$(id_by_title "$M2_RVA"); TI=$(id_by_title "$M2_TI")
    if [ -n "$TW2" ] && [ "$(status_of "$TW2")" = ready ]; then
      kb assign "$TW2" tester; echo "M2: TW2 -> tester (M1 gate done — sequence honored)"
    fi
    if [ -n "$C12" ] && [ "$(status_of "$TW2")" = done ] && [ "$(status_of "$C12")" = ready ]; then
      kb assign "$C12" coder; echo "M2: C12 -> coder"
    fi
    if [ -n "$RVA2" ] && [ "$(status_of "$C12")" = done ] && [ "$(status_of "$RVA2")" = ready ]; then
      kb assign "$RVA2" reviewer; echo "M2: RVa2 -> reviewer"
    fi
    if [ -n "$TI" ] && [ "$(status_of "$RVA2")" = done ] && [ "$(status_of "$TI")" = ready ]; then
      kb assign "$TI" tester; echo "M2: TI -> tester (e2e + full suite)"
    fi
  fi
  if [ "$MISSION" = 3 ] || [ "$MISSION" = all ]; then
    C13=$(id_by_title "$M3_C1"); RVA3=$(id_by_title "$M3_RVA")
    if [ -n "$C13" ] && [ "$(status_of "$C13")" = ready ]; then
      kb assign "$C13" coder; echo "M3: C13 -> coder (M2 gate done — sequence honored)"
    fi
    if [ -n "$RVA3" ] && [ "$(status_of "$C13")" = done ] && [ "$(status_of "$RVA3")" = ready ]; then
      kb assign "$RVA3" reviewer; echo "M3: RVa3 -> reviewer"
    fi
  fi
  kb list
  ;;

gate)
  [ -n "$GATE_SHA" ] || { echo "usage: $0 [-m MODE] gate <commit-sha>"; exit 1; }
  # Complete the first non-done gate in mission order.
  G_DONE=""
  if [ "$MISSION" = 1 ] || [ "$MISSION" = all ]; then
    G=$(id_by_title "$M1_G2")
    if [ -n "$G" ] && [ "$(status_of "$G")" != done ]; then
      kb complete "$G" \
        --result "Committed $GATE_SHA and pushed to origin main. Evidence: RVa PASS verdict; stage-only invariant held until this commit." \
        --summary "Human gate executed (mission 1): commit $GATE_SHA pushed."
      echo "M1 gate $G completed with $GATE_SHA"; G_DONE=1
    fi
  fi
  if [ -z "$G_DONE" ] && { [ "$MISSION" = 2 ] || [ "$MISSION" = all ]; }; then
    G=$(id_by_title "$M2_G2")
    if [ -n "$G" ] && [ "$(status_of "$G")" != done ]; then
      kb complete "$G" \
        --result "Committed $GATE_SHA and pushed to origin main. Evidence: RVa2 PASS + TI e2e suite GREEN; stage-only invariant held until this commit." \
        --summary "Human gate executed (mission 2): commit $GATE_SHA pushed."
      echo "M2 gate $G completed with $GATE_SHA"; G_DONE=1
    fi
  fi
  if [ -z "$G_DONE" ] && { [ "$MISSION" = 3 ] || [ "$MISSION" = all ]; }; then
    G=$(id_by_title "$M3_G2")
    if [ -n "$G" ] && [ "$(status_of "$G")" != done ]; then
      kb complete "$G" \
        --result "Committed $GATE_SHA and pushed to origin main. Evidence: RVa3 PASS, run_count_words.sh GREEN via Maven build; stage-only invariant held until this commit." \
        --summary "Human gate executed (mission 3): commit $GATE_SHA pushed."
      echo "M3 gate $G completed with $GATE_SHA"; G_DONE=1
    fi
  fi
  [ -n "$G_DONE" ] || { echo "no pending gate found for mode $MISSION"; exit 1; }
  ;;

*) echo "unknown phase: $PHASE"; exit 2 ;;
esac
