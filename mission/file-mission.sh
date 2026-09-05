#!/usr/bin/env bash
# File the Java word-count smoke mission on a kanban board.
#
# Recreates the exact card tree of the first run (small lane, stage-only):
#
#   TW -> C1 -> RVa -> G2
#
# Phases:
#   file    create every card, parked on the human-gate lane (nothing dispatches)
#   launch  unblock TW + assign it to tester — the dispatcher takes over
#   drive   assign the next card once its parent completes (C1->coder, RVa->reviewer)
#   gate    complete G2 with the commit SHA (the authorization record)
#
# Usage:
#   mission/file-mission.sh [-b BOARD] [-r REPO_DIR] [-k KEY_PREFIX] file
#   mission/file-mission.sh [-b BOARD] launch
#   mission/file-mission.sh [-b BOARD] drive
#   mission/file-mission.sh [-b BOARD] gate "SHA"
#
# Idempotent: re-running 'file' with the same -k prefix returns existing ids.
set -euo pipefail

BOARD=smoke-test
REPO=/opt/projects/kanban-smoke-test/main/kanban-smoke-test
KEY=smokejava                                  # idempotency prefix
HERE="$(cd "$(dirname "$0")" && pwd)"

while getopts "b:r:k:" opt; do
  case $opt in
    b) BOARD=$OPTARG ;;
    r) REPO=$OPTARG ;;
    k) KEY=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
PHASE=${1:?phase: file | launch | drive | gate}
GATE_SHA=${2:-}

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

TW_TITLE="TW: acceptance tests (black-box) - Java word-count"
C1_TITLE="C1: implement - Java word-count"
RVA_TITLE="RVa: reviewer verdict on implementation + acceptance tests"
G2_TITLE="Gate: approve and commit - Java word-count smoke"

case "$PHASE" in
file)
  # Dedupe by title first: idempotency keys alone are not enough (a changed
  # -k prefix would silently duplicate the mission).
  TW_ID=$(id_by_title "$TW_TITLE")
  [ -n "$TW_ID" ] || kb create "$TW_TITLE" \
    --body "$(cat "$HERE/card-bodies/tw-body.txt")" \
    --assignee human-gate --workspace "dir:$REPO" \
    --skill test-driven-development --max-retries 1 \
    --idempotency-key "$KEY-tw" --created-by manager --json >/dev/null

  C1_ID=$(id_by_title "$C1_TITLE")
  [ -n "$C1_ID" ] || kb create "$C1_TITLE" \
    --body "$(sed "s|<REPO>|$REPO|g" "$HERE/card-bodies/c1-body.txt")" \
    --assignee human-gate --parent "$(id_by_title "$TW_TITLE")" \
    --workspace "dir:$REPO" \
    --skill subagent-driven-development --max-retries 1 \
    --idempotency-key "$KEY-c1" --created-by manager --json >/dev/null

  # RVa: NO --goal (the judge can push a reviewer to complete and open the gate).
  RVA_ID=$(id_by_title "$RVA_TITLE")
  [ -n "$RVA_ID" ] || kb create "$RVA_TITLE" \
    --body "$(sed "s|<REPO>|$REPO|g" "$HERE/card-bodies/rva-body.txt")" \
    --assignee human-gate --parent "$(id_by_title "$C1_TITLE")" \
    --workspace "dir:$REPO" --max-retries 1 \
    --idempotency-key "$KEY-rva" --created-by manager --json >/dev/null

  # G2: scratch workspace — a gate never spawns.
  G2_ID=$(id_by_title "$G2_TITLE")
  [ -n "$G2_ID" ] || kb create "$G2_TITLE" \
    --body "$(sed "s|<REPO>|$REPO|g" "$HERE/card-bodies/g2-body.txt")" \
    --assignee human-gate --parent "$(id_by_title "$RVA_TITLE")" \
    --max-retries 1 --idempotency-key "$KEY-g2" --created-by manager --json >/dev/null

  echo "Filed (parked): TW=$(id_by_title "$TW_TITLE") C1=$(id_by_title "$C1_TITLE") RVA=$(id_by_title "$RVA_TITLE") G2=$(id_by_title "$G2_TITLE")"
  ;;

launch)
  TW=$(id_by_title "$TW_TITLE")
  [ -n "$TW" ] || { echo "no TW on board — run 'file' first"; exit 1; }
  kb unblock "$TW"
  kb assign "$TW" tester
  echo "Launched: TW=$TW assigned to tester. Downstream cards stay parked on human-gate."
  ;;

drive)
  # Status transitions (todo -> ready) happen automatically when a parent
  # completes; only the human-gate -> profile assignment needs a hand.
  C1=$(id_by_title "$C1_TITLE"); RVA=$(id_by_title "$RVA_TITLE")
  TW_ST=$(id_by_title "$TW_TITLE" >/dev/null; kb show "$(id_by_title "$TW_TITLE")" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["status"])')
  C1_ST=$(kb show "$C1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["status"])')
  RVA_ST=$(kb show "$RVA" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"]["status"])')
  if [ "$TW_ST" = done ] && [ "$C1_ST" = ready ]; then
    kb assign "$C1" coder; echo "C1 -> coder"
  fi
  if [ "$C1_ST" = done ] && [ "$RVA_ST" = ready ]; then
    kb assign "$RVA" reviewer; echo "RVa -> reviewer"
  fi
  kb list
  ;;

gate)
  G2=$(id_by_title "$G2_TITLE")
  [ -n "$GATE_SHA" ] || { echo "usage: $0 [-b BOARD] gate <commit-sha>"; exit 1; }
  kb complete "$G2" \
    --result "Committed $GATE_SHA and pushed to origin main. Evidence: RVa PASS verdict; stage-only invariant held until this commit." \
    --summary "Human gate executed: commit $GATE_SHA pushed."
  echo "Gate $G2 completed with $GATE_SHA"
  ;;

*) echo "unknown phase: $PHASE"; exit 2 ;;
esac
