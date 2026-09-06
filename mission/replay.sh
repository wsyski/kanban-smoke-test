#!/usr/bin/env bash
# One-command scenario replay — generic, board-creating, no repo reset.
#
#   mission/replay.sh [scenario.json]     # default: mission/scenario.json
#
# Scenario contract (mission/scenario.json):
#   board        board slug to create-or-reuse
#   tasks[]      sequential tasks; each has cards[] (id/title/body-file/
#                assignee/parent/skill) and a root_parent cross-task link
#
# Behavior:
#   1. Creates the board if missing (slug from scenario; workdir = this repo)
#   2. Archives leftover live cards ON THAT BOARD (reclaim first)
#   3. Deletes generated source (wordcount-*/) but keeps mission/ + committed
#      history — stage-only workers never had commits, so this is safe
#   4. Files every card from the scenario JSON (title-deduped, idempotent)
#   5. Launches task 1's root; run.py drives with timing collection
#
# Human gate: when the log prints "GATE ... HUMAN COMMIT REQUIRED", commit
# with an explicit pathspec (plan or product dir). Chain continues itself.
#
# Genericity: pointing BOARDSLUG/replay at another repo only needs that repo
# to have its own mission/scenario.json + card-bodies/ — card text is data,
# not code. The file/launch/drive/gate machinery is repo-agnostic.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO=${1:-mission/scenario.json}
BOARD=$(python3 -c "import json;print(json.load(open('mission/scenario.json'))['board'])")
RUNLOG=${RUNLOG:-/tmp/run-replay.log}

cd "$REPO"

echo "== pre-flight =="
for p in manager coder tester reviewer; do
  hermes profile list | grep -q " $p " || { echo "profile $p not available"; exit 1; }
done
[ -f mission/run.py ] && [ -f mission/scenario.json ] || { echo "mission assets missing"; exit 1; }
echo "ok: profiles + assets"

echo "== create-or-reuse board '$BOARD' =="
BOARD_PATH=$(hermes kanban boards set-default-workdir "$BOARD" "$REPO" 2>/dev/null && echo exists || true)
if ! hermes kanban --board "$BOARD" list >/dev/null 2>&1; then
  hermes kanban boards create "$BOARD" --default-workdir "$REPO"
  echo "board created"
else
  echo "board exists — reusing"
fi

echo "== archiving leftover cards (reclaim first) =="
ids=$(hermes kanban --board "$BOARD" list --json | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    print(t['id'])")
if [ -n "$ids" ]; then
  # shellcheck disable=SC2086
  hermes kanban --board "$BOARD" reclaim $ids 2>/dev/null | grep -v "not running" || true
  # shellcheck disable=SC2086
  hermes kanban --board "$BOARD" archive $ids >/dev/null
fi
echo "board cleared"

echo "== cleaning generated source (workers stage-only; committed state untouched) =="
git clean -fdx -q -e .idea -e .classpath -e .project -e .settings -e mission 2>/dev/null || true
git status --short | head -3

echo "== filing cards from scenario.json =="
python3 - "$BOARD" "$REPO" <<'EOF'
import json, subprocess, sys, datetime

board, repo = sys.argv[1], sys.argv[2]
scen = json.load(open(f"{repo}/mission/scenario.json"))
run_id = datetime.datetime.now().strftime("%Y%m%d-%H%M")
k = f"replay-{run_id}"

def kb(*a):
    r = subprocess.run(["hermes","kanban","--board",board,*a],capture_output=True,text=True)
    if r.returncode: raise RuntimeError(a[:2], a, r.stderr[:300])
    return r.stdout

def body(bf): return open(f"{repo}/mission/card-bodies/{bf}").read()

def id_by_title(title):
    for t in json.loads(kb("list","--json")):
        if t["title"] == title: return t["id"]
    return None

made = {}
for task in scen["tasks"]:
    for c in task["cards"]:
        if id_by_title(c["title"]):
            continue
        parent = made.get(c["parent"]) if c["parent"] else None
        args = ["create", c["title"], "--body", body(c["body"]),
                "--assignee", c["assignee"], "--workspace", f"dir:{repo}",
                "--max-runtime","60m","--max-retries","1",
                "--idempotency-key", f"{k}-{c['id']}",
                "--created-by","manager","--json"]
        if parent: args += ["--parent", parent]
        if c["skill"]: args += ["--skill", c["skill"]]
        cid = json.loads(kb(*args))["id"]
        made[c["id"]] = cid
        if c["assignee"] != "human-gate":
            kb("block","--kind","needs_input",cid,"auto-chain: parked until parent completes") if c["id"] != "P1" else None
    root = task["cards"][0]["id"]
    if task.get("root_parent"):
        # cross-task link handled naturally via parent chain already in cards[]
        pass

# unblock+assign P1 (the launch)
p1 = id_by_title(scen["tasks"][0]["cards"][0]["title"])
kb("unblock", p1)
kb("assign", p1, "manager")
print("filed+launched:", len(made), "cards created")
EOF

echo "== starting driver (auto-gates + timing) =="
: > "${RUNLOG}"
nohup python3 mission/run.py --auto-gates --timeout-min 240 >> "${RUNLOG}" 2>&1 &
echo "driver started; log: ${RUNLOG}"

cat <<'EOF'

Replay in flight.
  watch board:   hermes kanban --board <board> list
  watch driver:  tail -f /tmp/run-replay.log
  gate actions:  commit staged plan/product when log says HUMAN COMMIT REQUIRED
  timing:        python3 mission/timing-report.py   (after Gc2)
EOF
