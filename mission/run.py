#!/usr/bin/env python3
"""Unattended driver for the scenario-v2 kanban smoke missions.

--auto-gates : driver plays gate-holder (commits staged plan/code at Gp/Gc,
               files plan-revision rounds on REJECT, unblocks on handoff).
default      : normal run — promotes handoffs, WAITS at gates for a human.

Usage: mission/run.py [--auto-gates] [--once] [--timeout-min 120]
"""
import json, subprocess, sys, time, os, re, datetime

BOARD = os.environ.get("BOARD", "smoke-test")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMING_PATH = os.path.join(REPO, "mission", "timing.jsonl")
AUTO = "--auto-gates" in sys.argv
ONCE = "--once" in sys.argv
POLL = 20

# ordered card graph: title -> (parents by title prefix, kind, task)
CARDS = [
    ("P1: implementation plan - wordcount CLI", [], "plan", 1),
    ("RVp1: plan review - wordcount CLI", ["P1"], "rvp", 1),
    ("Gp1: plan gate - wordcount CLI", ["RVp1", "P1-rev", "RVp1-r"], "gp", 1),
    ("TW1: unit tests (RED-first, JUnit) - wordcount CLI", ["Gp1"], "tw", 1),
    ("C1: implement - wordcount CLI", ["TW1"], "c", 1),
    ("RVa1: reviewer verdict - wordcount CLI", ["C1"], "rva", 1),
    ("Gc1: code gate - wordcount CLI", ["RVa1"], "gc", 1),
    ("P2: implementation plan - wordcount service", ["Gc1"], "plan", 2),
    ("RVp2: plan review - wordcount service", ["P2", "P2-rev", "RVp2-r"], "rvp", 2),
    ("Gp2: plan gate - wordcount service", ["RVp2", "P2-rev", "RVp2-r"], "gp", 2),
    ("TW2: contract acceptance tests (RED-first) - wordcount service", ["Gp2"], "tw", 2),
    ("C2: implement - wordcount service", ["TW2"], "c", 2),
    ("RVa2: reviewer verdict - wordcount service", ["C2"], "rva", 2),
    ("TI2: failsafe integration tests - wordcount service", ["RVa2"], "ti", 2),
    ("RVc2: final review - wordcount service", ["TI2"], "rvc", 2),
    ("Gc2: code gate - wordcount service", ["RVc2"], "gc", 2),
]

def kb(*args, capture=True):
    r = subprocess.run(["hermes", "kanban", "--board", BOARD, *args],
                       capture_output=capture, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"kb {args[:2]}: {r.stderr.strip()[:200]}")
    return r.stdout

def board():
    out = json.loads(kb("list", "--json"))
    return {t["title"]: t for t in out}

def log(msg):
    print(f"[{datetime.datetime.now():%H:%M:%S}] {msg}", flush=True)

def title_of_prefix(state, prefix):
    for t, card in state.items():
        if t.startswith(prefix):
            return t, card
    return None, None

def parents_done(state, prefixes):
    for p in prefixes:
        t, card = title_of_prefix(state, p)
        if card is None or card["status"] != "done":
            return False
    return True

def result_of(state, prefix):
    t, card = title_of_prefix(state, prefix)
    return (card or {}).get("result") or ""

def git(*args):
    r = subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git {args}: {r.stderr.strip()[:200]}")
    return r.stdout.strip()

def commit_push(msg, paths):
    for p in paths:
        git("add", "--", p)
    if not git("status", "--porcelain"):
        # everything already committed (e.g. gate re-entry) — idempotent exit
        return git("rev-parse", "--short", "HEAD")
    git("commit", "-m", msg)
    sha = git("rev-parse", "--short", "HEAD")
    git("push", "origin", "main")
    return sha

def recorded_sha(card):
    """A commit sha already recorded on the gate card (result or summary)."""
    for src in (card.get("result"), card.get("summary")):
        if src:
            m = re.search(r"\b[0-9a-f]{7,40}\b", src)
            if m:
                return m.group(0)
    return ""

def complete_gate(title, sha="", what=""):
    st = board()
    cid = card_id(st, title)
    if st[title]["status"] == "blocked":
        kb("unblock", cid)  # ready cards must NOT be unblocked (raises)
    res = f"Auto-gates: {what}" + (f" recorded at {sha}." if sha else " — HUMAN COMMIT+PUSH REQUIRED at the gate.")
    kb("complete", cid,
       "--result", res,
       "--summary", f"auto-gates {title.split(':')[0]}" + (f" @ {sha}" if sha else " (human commit pending)"))
    log(f"GATE {title.split(':')[0]} completed" + (f" @ {sha}" if sha else " — HUMAN COMMIT REQUIRED"))

def card_id(state, title):
    c = state.get(title)
    if not c:
        raise RuntimeError(f"card missing: {title}")
    return c["id"]

def plan_review_pass(state, task):
    # latest of RVp / RVp-r2 / RVp-r3 with a verdict
    best = None
    for pref in (f"RVp{'2' if task==2 else '1'}", f"RVp{'2' if task==2 else '1'}-r2",
                 f"RVp{'2' if task==2 else '1'}-r3"):
        t, c = title_of_prefix(state, pref)
        if c and c["status"] == "done" and c.get("result"):
            best = c["result"]
    return best or ""

def file_revision(state, task, round_no, findings):
    n = f"{'2' if task==2 else '1'}"
    prod = f"P{n}"
    rev_title = f"{prod}-rev-{round_no}: plan revision round {round_no} - wordcount {'CLI' if task==1 else 'service'}"
    rvp_title = f"RVp{n}-r{round_no+1}: plan review round {round_no+1} - wordcount {'CLI' if task==1 else 'service'}"
    if title_of_prefix(state, rev_title)[0]:
        return  # already filed
    pbody = open(f"{REPO}/mission/card-bodies/p-body.txt").read()
    pbody += f"\nREVISION ROUND {round_no} of 3 (max 3, then human escalation).\n\nYour plan was REJECTED. Findings to fix EXACTLY:\n{findings}\nFix ONLY these, re-verify every numeric expectation by computation, re-stage, re-attach, complete with a change summary.\n"
    out = kb("create", rev_title, "--body", pbody, "--assignee", "manager",
             "--workspace", f"dir:{REPO}", "--max-runtime", "60m", "--max-retries", "1",
             "--idempotency-key", f"smoke2-rev-{prod}-{round_no}", "--created-by", "manager", "--json")
    rev_id = json.loads(out)["id"]
    rvbody = open(f"{REPO}/mission/card-bodies/rvp-body.txt").read()
    rvbody += f"\nREVIEW ROUND {round_no+1} of 3. Plan revised after REJECT. Re-verify the findings are fixed AND re-check (a)-(d). Verdict in result field.\n"
    out = kb("create", rvp_title, "--body", rvbody, "--assignee", "reviewer",
             "--parent", rev_id, "--workspace", f"dir:{REPO}", "--max-runtime", "45m",
             "--max-retries", "1", "--idempotency-key", f"smoke2-rvp-{prod}-r{round_no+1}",
             "--created-by", "manager", "--json")
    rvp_id = json.loads(out)["id"]
    kb("link", rvp_id, card_id(state, [t for t in state if t.startswith(f"Gp{n}:")][0]))
    log(f"filed revision round {round_no}: {rev_title} + {rvp_title}")

def run_suite(task):
    if task == 1:
        r = subprocess.run(["mvn", "-q", "test"], cwd=f"{REPO}/wordcount-cli",
                           capture_output=True, text=True)
    else:
        r = subprocess.run(["mvn", "-q", "verify"], cwd=f"{REPO}/wordcount-service",
                           capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"task {task} suite failed:\n{r.stdout[-1500:]}")
    return True

def runs_result(card_id):
    """Last completed run's summary/result for this card (fallback when the
    card's result field is empty)."""
    out = kb("runs", card_id)
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("→"):
            return s[1:].strip()
    return ""

def verdict(state, prefix):
    t, c = title_of_prefix(state, prefix)
    if not c or c["status"] != "done":
        return ""
    return c.get("result") or c.get("summary") or (runs_result(c["id"]) if c.get("id") else "")

def gate_action(state, title, kind, task):
    n = "1" if task == 1 else "2"
    if kind == "gp":
        verdict_txt = plan_review_pass(state, task)
        if not verdict_txt.startswith("PASS"):
            return f"waiting: plan review verdict = {verdict_txt[:40]!r}"
        if AUTO:
            # stage-only: the DRIVER never commits — record the verdict and
            # leave the actual commit+push to the human gate executor.
            kb("complete", card_id(state, title),
               f"Auto-gates: plan task-{n} ready for human commit (verdict PASS, staged).")
            log(f"GATE {title.split(':')[0]}: verdict PASS — HUMAN COMMIT REQUIRED")
        else:
            log(f"HUMAN GATE READY: {title} (plan staged, verdict PASS) — waiting for human")
        return "gate-held"
    if kind == "gc":
        verdict_txt = verdict(state, f"RV{'c' if task==2 else 'a'}{n}")
        if not verdict_txt.startswith("PASS"):
            return f"waiting: final review verdict = {verdict_txt[:40]!r}"
        if AUTO:
            # stage-only: no suite-run/commit here — human gate does that.
            complete_gate(title, "", f"code task-{n} staged — human commit required")
            log(f"GATE {title.split(':')[0]}: ready — HUMAN COMMIT REQUIRED")
        else:
            log(f"HUMAN GATE READY: {title} ({len(git('status','--porcelain').splitlines())} files staged) — waiting for human")
        return "gate-held"
    return "skip"

def record_timing(state):
    """Append one JSONL line: per-card status snapshots for timing analysis."""
    snap = {t: {"status": c["status"], "id": c["id"]} for t, c in state.items()}
    entry = {"ts": datetime.datetime.now().isoformat(timespec="seconds"),
             "epoch": time.time(), "cards": snap}
    with open(TIMING_PATH, "a") as f:
        f.write(json.dumps(entry) + "\n")

def tick():
    st = state = board()
    record_timing(st)
    # 1. handoff promotion: blocked card with all parents done -> unblock
    for title, parents, kind, task in CARDS:
        card = st.get(title)
        if not card or card["status"] != "blocked" or not parents:
            continue
        if parents_done(st, parents):
            kb("unblock", card["id"])
            log(f"unblocked {title.split(':')[0]} (parents done)")
    st = state = board()
    # 2. rework loop on plan REJECT (gates go ready via unblock, so accept
    #    both blocked and ready — the REJECT verdict itself is the trigger)
    for task in (1, 2):
        n = "2" if task == 2 else "1"
        t, c = title_of_prefix(st, f"Gp{n}:")
        if c and c["status"] in ("blocked", "ready", "todo"):
            verdict = plan_review_pass(st, task)
            if verdict.startswith("REJECT"):
                # only file the NEXT round if the previous one finished:
                # any live (non-done) P{n}-rev or RVp{n}-r card = rework in flight
                live = [t for t in st
                        if t.startswith(f"P{n}-rev") and st[t]["status"] not in ("done",)
                        or t.startswith(f"RVp{n}-r") and st[t]["status"] not in ("done",)]
                if live:
                    continue
                m = verdict.split("REJECT:")[1][:1200]
                rounds = len([t for t in st if t.startswith(f"P{n}-rev")])
                if rounds < 3:
                    file_revision(st, task, rounds + 1, m)
                else:
                    kb("block", "--kind", "needs_input", c["id"],
                       "3 revision rounds exhausted — human escalation required")
                    log(f"ESCALATED: {c['title']} (3 REJECT rounds)")
    # 3. gates
    for title, parents, kind, task in CARDS:
        if kind not in ("gp", "gc"):
            continue
        card = st.get(title)
        if not card or card["status"] in ("done", "blocked") and False:
            continue
        if card["status"] == "done":
            continue
        if not parents_done(st, parents):
            continue
        msg = gate_action(st, title, kind, task)
        if msg and msg not in ("gate-held", "skip"):
            log(f"{title.split(':')[0]}: {msg}")
    # done?
    _, gc2 = title_of_prefix(st, "Gc2:")
    return gc2 and gc2["status"] == "done"

def main():
    t0 = time.time()
    timeout = 120 * 60
    for a in sys.argv:
        if a.startswith("--timeout-min"):
            timeout = float(sys.argv[sys.argv.index(a) + 1]) * 60
    while True:
        try:
            if tick():
                log("ALL GATES COMPLETE — scenario finished")
                return 0
        except Exception as e:
            import traceback
            log(f"ERROR: {e}\n{traceback.format_exc()}")
            if AUTO:
                pass  # keep driving; transient errors are expected during runs
            else:
                raise
        if ONCE:
            return 0
        if time.time() - t0 > timeout:
            log("timeout — stopping driver")
            return 1
        time.sleep(POLL)

if __name__ == "__main__":
    sys.exit(main())
