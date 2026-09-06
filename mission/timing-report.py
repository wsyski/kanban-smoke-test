#!/usr/bin/env python3
"""Timing report for the kanban smoke mission.

Reads mission/timing.jsonl (written by run.py's record_timing each tick) and
merges per-card run records from `hermes kanban runs <id>` to produce:

  - per-card: agent elapsed (from runs data), dispatch gap (time triaged->ready
    ->running vs parent-done), first-running and done timestamps
  - phase totals: work time vs overhead (gaps), by task
  - budget-exhaustion events (failed runs)

Usage: mission/timing-report.py [--jsonl mission/timing.jsonl]
"""
import json, subprocess, sys, os, collections, datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD = os.environ.get("BOARD", "smoke-test")
JSONL = os.path.join(REPO, "mission", "timing.jsonl")

def load_snaps():
    snaps = []
    with open(JSONL) as f:
        for line in f:
            line = line.strip()
            if line:
                snaps.append(json.loads(line))
    return snaps

def transitions(snaps):
    """First time each card entered each status."""
    seen = {}
    for s in snaps:
        for title, c in s["cards"].items():
            key = (title, c["status"])
            if key not in seen:
                seen[key] = s["epoch"]
                seen[(title, c["status"], "id")] = c["id"]
    return seen

def runs_elapsed(card_id):
    try:
        out = subprocess.run(["hermes", "kanban", "--board", BOARD, "runs", card_id],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    rows = []
    cur = None
    for line in out.splitlines():
        s = line.strip()
        parts = s.split()
        if parts and parts[0].isdigit() and len(parts) > 3:
            if cur:
                rows.append(cur)
            outcome = parts[1]
            elapsed = parts[-2] if parts[-1].isdigit() == False else parts[-1]
            started = " ".join(parts[-5:])
            cur = {"outcome": outcome, "elapsed_raw": parts[-2] if len(parts) > 4 else "",
                   "started": " ".join(parts[-5:]) if len(parts) > 5 else ""}
        elif s.startswith("→") and cur:
            cur["note"] = s[1:].strip()[:80]
        elif s.startswith("✖") and cur:
            cur["note"] = (cur.get("note", "") + " " + s.strip()[:80]).strip()
    if cur:
        rows.append(cur)
    return rows

def parse_elapsed_minutes(el_raw):
    if not el_raw:
        return None
    el_raw = el_raw.strip()
    if el_raw.endswith("m"):
        try:
            return float(el_raw[:-1])
        except ValueError:
            return None
    if el_raw.endswith("s"):
        try:
            return float(el_raw[:-1]) / 60
        except ValueError:
            return None
    try:
        return float(el_raw)
    except ValueError:
        return None

def main():
    snaps = load_snaps()
    if not snaps:
        print("no timing data — is mission/timing.jsonl empty?")
        return 1
    t0, t1 = snaps[0]["epoch"], snaps[-1]["epoch"]
    tr = transitions(snaps)
    statuses = collections.Counter()
    for (title, status), _ in [(k, v) for k, v in tr.items() if len(k) == 2]:
        statuses[status] += 1
    print(f"== Timing report ==")
    print(f"window: {datetime.datetime.fromtimestamp(t0):%H:%M} → "
          f"{datetime.datetime.fromtimestamp(t1):%H:%M} "
          f"({(t1-t0)/60:.1f} min wall, {len(snaps)} driver ticks)")
    print(f"end status histogram: {dict(statuses)}")
    print()
    print(f"{'card':<50} {'first_running':>13} {'done_at':>13} {'status':>8}")
    print("-" * 90)
    order = sorted({t for (t, s) in tr if len((t, s)) == 2},
                   key=lambda t: tr.get((t, "running"), t1) or t1)
    work_total = 0.0
    for title in order:
        cid = tr.get((title, "done", "id")) or tr.get((title, "running", "id")) or "?"
        # agent elapsed from board runs data
        rows = runs_elapsed(cid)
        agent = sum(parse_elapsed_minutes(r.get("elapsed_raw", "")) or 0
                    for r in rows if r.get("outcome") in ("completed", "gave_up"))
        work_total += agent
        fr = tr.get((title, "running"))
        dn = tr.get((title, "done"))
        last_status = None
        for s in reversed(snaps):
            if title in s["cards"]:
                last_status = s["cards"][title]["status"]
                break
        fmt = lambda e: f"{datetime.datetime.fromtimestamp(e):%H:%M}" if e else "-"
        print(f"{title[:50]:<50} {fmt(fr):>13} {fmt(dn):>13} {last_status:>8}"
              + (f"   agent={agent:.1f}m" if agent else ""))
    print()
    print(f"total agent work time: {work_total:.1f} min")
    print(f"total wall time: {(t1-t0)/60:.1f} min")
    print(f"overhead ratio: {(t1-t0)/60 - work_total:.1f} min non-agent time "
          f"({100*((t1-t0)/60 - work_total)/max((t1-t0)/60,.1):.0f}%)")
    # budget exhaustion flags
    for title in order:
        cid = tr.get((title, "done", "id")) or tr.get((title, "running", "id"))
        if not cid:
            continue
        rows = runs_elapsed(cid)
        for r in rows:
            if r.get("outcome") == "gave_up":
                print(f"⚠ BUDGET: {title.split(':')[0]} gave_up — {r.get('note','')}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
