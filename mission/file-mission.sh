#!/usr/bin/env bash
# File and drive the plan-first, stage-only smoke missions on ONE board.
#
# Layout (input-spec.md is authoritative):
#   T1: P1 -> RVp1 -> Gp1 -> TW1 -> C1 -> RVa1 -> Gc1
#   T2: P2 -> RVp2 -> Gp2 -> TW2 -> C2 -> RVa2 -> TI2 -> RVc2 -> Gc2   (root at Gc1)
#
# Auto-chain: worker cards are PRE-ASSIGNED to their profile and created
# blocked; completing a parent auto-promotes the child to ready and the
# dispatcher claims it. Only P1/P2 (manager = console) and the four gates
# (Gp1 Gc1 Gp2 Gc2) are handled from here.
#
# Phases: file | gate <sha> | status
# Keys are run-stamped: export RUN_STAMP or each replay is key-distinct.
set -euo pipefail
BOARD=${BOARD:-smoke-test}
REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID=${RUN_STAMP:-$(date +%Y%m%d-%H%M)}
K="smoke2-$RUN_ID"
HERE="$REPO/mission"

PHASE=${1:?phase: file | gate <sha> | status}
SHA=${2:-}

kb() { hermes kanban --board "$BOARD" "$@"; }
body() { sed "s|<REPO>|$REPO|g" "$HERE/card-bodies/$1"; }

status_of() { kb show "$1" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["status"])' 2>/dev/null || echo gone; }
id_by_title() {
  kb list --json | python3 -c "
import json,sys
t='$1'
for x in json.load(sys.stdin):
    if x['title'] == t: print(x['id']); break"
}

# create_card <title> <bodyfile> <assignee> <parent-id|-> [skill]
create_card() {
  local title=$1 bf=$2 asg=$3 parent=$4 skill=${5:-} id
  id=$(id_by_title "$title")
  [ -n "$id" ] && { echo "$id"; return; }
  local -a a=(create "$title" --body "$(body "$bf")" --assignee "$asg" \
              --workspace "dir:$REPO" --max-runtime 45m --max-retries 1 \
              --idempotency-key "$K-$title" --created-by manager --json)
  [ "$parent" != - ] && a+=(--parent "$parent")
  [ -n "$skill" ] && a+=(--skill "$skill")
  id=$(kb "${a[@]}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  # todo cards cannot be blocked; ready ones must be parked for auto-chain
  kb block --kind needs_input "$id" "auto-chain: parked until parent completes" >/dev/null 2>&1 || true
  echo "$id"
}

file_all() {
  echo "== filing run $RUN_ID =="
  P1=$(id_by_title "P1: implementation plan - wordcount CLI")
  [ -n "$P1" ] || {
    P1=$(kb create "P1: implementation plan - wordcount CLI" \
      --body "$(body p-body.txt)" --assignee manager --workspace "dir:$REPO" \
      --max-runtime 60m --max-retries 1 --idempotency-key "$K-P1" --created-by manager --json |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  }
  RVP1=$(create_card "RVp1: plan review - wordcount CLI" rvp-body.txt reviewer "$P1")
  GP1=$(create_card "Gp1: plan gate - wordcount CLI" gp-body.txt human-gate "$RVP1")
  TW1=$(create_card "TW1: unit tests (RED-first, JUnit) - wordcount CLI" tw1-body.txt tester "$GP1" test-driven-development)
  C11=$(create_card "C1: implement - wordcount CLI" c1-cli-body.txt coder "$TW1")
  RVA1=$(create_card "RVa1: reviewer verdict - wordcount CLI" rva-body.txt reviewer "$C11")
  GC1=$(create_card "Gc1: code gate - wordcount CLI" gc-body.txt human-gate "$RVA1")
  P2=$(create_card "P2: implementation plan - wordcount service" p-body.txt manager "$GC1")
  RVP2=$(create_card "RVp2: plan review - wordcount service" rvp-body.txt reviewer "$P2")
  GP2=$(create_card "Gp2: plan gate - wordcount service" gp-body.txt human-gate "$RVP2")
  TW2=$(create_card "TW2: contract acceptance tests (RED-first) - wordcount service" tw2-body.txt tester "$GP2" test-driven-development)
  C21=$(create_card "C2: implement - wordcount service" c2-body.txt coder "$TW2")
  RVA2=$(create_card "RVa2: reviewer verdict - wordcount service" rva-body.txt reviewer "$C21")
  TI2=$(create_card "TI2: failsafe integration tests - wordcount service" ti2-body.txt tester "$RVA2")
  RVC2=$(create_card "RVc2: final review - wordcount service" rvc-body.txt reviewer "$TI2")
  GC2=$(create_card "Gc2: code gate - wordcount service" gc-body.txt human-gate "$RVC2")
  cat <<EOF
filed ($RUN_ID):
P1=$P1 RVp1=$RVP1 Gp1=$GP1 TW1=$TW1 C1=$C11 RVa1=$RVA1 Gc1=$GC1
P2=$P2 RVp2=$RVP2 Gp2=$GP2 TW2=$TW2 C2=$C21 RVa2=$RVA2 TI2=$TI2 RVc2=$RVC2 Gc2=$GC2
EOF
  # P1 is manager's own work (console). Park nothing: P1 starts as todo.
  kb unblock "$P1" >/dev/null 2>&1 || true
}

case "$PHASE" in
file) file_all ;;
status) kb list ;;
gate)
  [ -n "$SHA" ] || { echo "gate <sha> required"; exit 2; }
  gate_title() {
    case $1 in
      Gp1) echo "Gp1: plan gate - wordcount CLI" ;;
      Gc1) echo "Gc1: code gate - wordcount CLI" ;;
      Gp2) echo "Gp2: plan gate - wordcount service" ;;
      Gc2) echo "Gc2: code gate - wordcount service" ;;
    esac
  }
  for g in Gp1 Gc1 Gp2 Gc2; do
    ID=$(id_by_title "$(gate_title "$g")")
    [ -n "$ID" ] || { echo "no card titled $(gate_title "$g")"; exit 1; }
    ST=$(status_of "$ID"); [ "$ST" = done ] && continue
    [ "$ST" = ready ] || { echo "$g is $ST (want ready)"; exit 1; }
    kb complete "$ID" --result "Gate pushed in auto-gates mode. Commit/plan recorded: $SHA." --summary "auto-gates: $g @ $SHA"
    echo "$g completed ($SHA)"
    exit 0
  done
  echo "no pending gate"; exit 1
  ;;
*) echo "unknown phase"; exit 2 ;;
esac