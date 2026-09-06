# kanban-smoke-test

Smoke-test repo for the **coding-team kanban** solution: multi-profile agents
(manager plans, tester tests RED-first, coder implements, reviewer gates the
verdict, human gate commits) building real Maven projects on a kanban board.

Two deliverables per replay: the **products** built by the lane itself, and
the **recipe** that makes the run re-executable.

> Run 1 (2026-09-05, 3 missions): provenance below.
> Run 2 (2026-09-06, scenario v2 — full timing + instrumentation): §4–§8.

- Products: `wordcount-cli/` (fat-jar stdin→count CLI), `wordcount-service/`
  (spec-first Spring Boot REST API).
- Recipe: everything under `mission/` — input spec, card bodies, board
  declaration (`scenario.json`), driver (`run.py`), timing
  (`timing.jsonl` + `timing-report.py`), replay one-liner (`replay.sh`).

```
mission/replay.sh                  # ONE command: board → cards → launch → drive
```

---

## 1. What the board enforces (design)

**Plan-first, stage-only, 2 sequential tasks, both gated by a human.**

| rule | where it lives |
|---|---|
| Workers STAGE only (`git add -- own paths`), never commit/push | card bodies hard-rules block (first section); reviewed by reviewers |
| Nobody commits before the human gate — not even the driver | run.py `--auto-gates` completes gate cards with "HUMAN COMMIT REQUIRED" |
| `git add`/`git diff` always allowed (provenance patches) | card bodies |
| Task N+1 chain-root parented to task N's gate card | scenario.json — the board itself is the sequencer |
| Every card's evidence | `git diff --cached` patch attached to the card |
| Verdicts in the result field | reviewer card bodies mandate it |

Lane shape task 1: `P → RVp → Gp → TW → C → RVa → Gc`.
Task 2 adds `TI` (failsafe ITs) and a final `RVc` before the gate.

---

## 2. Prerequisites

```
hermes profile list        # manager/coder/tester/reviewer gateways running
hermes --profile <P> gateway install && hermes --profile <P> gateway start   # per profile
javac -version && mvn -version    # JDK 17 + Maven 3.9
# ~/.m2 pre-warmed (offline builds — workers have iteration budgets):
mvn -q dependency:get -Dartifact=org.springframework.boot:spring-boot-starter-web:3.3.4
mvn -q dependency:get -Dartifact=org.openapitools:openapi-generator-maven-plugin:7.8.0
mvn -q dependency:get -Dartifact=org.apache.maven.plugins:maven-failsafe-plugin:3.5.4
```

## 3. Replay — one command

```
cd /opt/projects/kanban-smoke-test/main/kanban-smoke-test
mission/replay.sh
```

What it does (no repo reset needed — workers are stage-only):

1. Pre-flight: profiles up, assets present
2. Creates-or-reuses the board (`scenario.json` → slug + workdir)
3. Reclaims + archives ALL leftover cards on that board — never re-file
   over live cards (orphans burn budget on archived cards and re-stage stale
   files)
4. Deletes generated source (`git clean` `wordcount-*/`, `target/`) —
   committed history and `mission/` untouched
5. Files every card from `mission/scenario.json` (title-deduped, idempotent)
6. Launches task 1's root; starts `run.py --auto-gates` in the background
   — from its first tick it appends status snapshots to
   `mission/timing.jsonl`
7. Prints watch commands

Your role (the human gate — the point of the scenario): when the driver log
prints `GATE Gxx: ... HUMAN COMMIT REQUIRED`:

```
hermes kanban --board smoke-test show <gate-id>     # read verdict evidence
(cd wordcount-cli && mvn -q test) | (cd wordcount-service && mvn -q verify)   # suite GREEN?
git add <staged files> && git commit -m "<gate commit msg>" -- <pathspec> && git push origin main
```

The chain continues by itself after each gate commit.

Watch:

```
hermes kanban --board smoke-test list
tail -f /tmp/run-replay.log
python3 mission/timing-report.py            # after Gc2
hermes kanban --board smoke-test runs <id>  # per-card attempts
~/.hermes/kanban/boards/smoke-test/logs/<card-id>.log   # worker transcripts
```

## 4. Timing statistics (final run 2026-09-06)

**Totals: 175 min agent work / 213 min wall clock = 18% overhead.**

Per-card (agent time from board run records; wall from 609-tick driver log):

| card | profile | work | note |
|---|---|---|---|
| P1 plan | manager | 16m | verified plan, executed RED/GREEN preview |
| RVp1 review | reviewer | 14m | PASS, re-derived every number |
| TW1 unit tests RED | tester | 9m | 12 tests staged |
| C1 implement | coder | 3m | 12/12 GREEN |
| RVa1 review | reviewer | 12m | PASS |
| P2 plan | manager | 1m | completed from staged reuse (same file fresh: 16–23m) |
| RVp2 review | reviewer | 14m | REJECT: 3 pom errors (reproduced) |
| revision round 1 | manager | 11m | fixes staged, verifier caught unstaged state |
| RVp2-r2 review | reviewer | 11m | REJECT: XML corrupt + dependency contradiction |
| revision round 2 | manager | 23m | 4 findings, parse-verified |
| RVp2-r3 review | reviewer | 10m | PASS |
| TW2 contract tests | tester | 5m | 7 tests RED-first |
| C2 implement | coder | 24m | openapi + service + controller + tests |
| RVa2 review | reviewer | 15m | PASS |
| TI2 failsafe ITs | tester | 2m | 6/6 IT, `mvn verify` |
| RVc2 final review | reviewer | 5m | PASS |
| **agent work total** | | **175 min** | |

### Where the 38 min of wall-vs-work overhead goes (estimates)

| component | est. | why |
|---|---|---|
| Dispatcher gaps + worker spin-up | ~15 min | fresh agent session per card; ~1 min
floor × 20 cards + hand-off wait between
parent-done and child-spawn |
| Human gate latency (4 gates) | ~3 min | verify staged diff + run suite +
commit + push at each gate |
| Budget-exhaustion churn | ~20 min | one P-card hit the per-session turn
cap mid-run and requeued; policy since removed |
| Remaining bookkeeping | ~0 min | driver tick is 20s, idempotent |

Notes on the work vs wall split:
- Review work is ~45% of all agent time (85 of 175 min) — by design: reviews
  reproduce the producer's claims instead of trusting them; that is where the
  2 REJECT rework rounds came from, and both REJECTs found real pom bugs.
- The rework loop (2 REJECTs + 2 revisions) is ~59 min of the agent total —
  quality filter, not overhead.
- Small cards (TI2 2 min, C1 3 min) are near the spin-up floor: most work
  cards pay ~1 min dispatch overhead regardless of content, which is why
  batching many tiny cards is worse than fewer bigger ones.

### Timing instrumentation (on the board itself)

- Driver tick every 20 s appends a status snapshot to
  `mission/timing.jsonl` (one JSON line per tick: card → status + id).
- After the run: `python3 mission/timing-report.py` — merges per-tick
  transitions with per-card run records (ELAPSED from
  `hermes kanban runs <id>`) into the per-card table + totals above.
- Gate cards are the chain checkpoints: gate completion timestamps delimit
  planning vs build vs review phases per task.

---

## 5. Operational rules that made the run clean

- **Single driver discipline:** exactly one `run.py` at a time; duplicates
  idle silently and interleave log output. Kill all, start one.
- **Re-filing mid-run is forbidden:** first archive + reclaim every card.
  Orphaned workers burn full budgets on archived cards and can re-stage
  stale file content into the index.
- **Turn budgets are global, not per-profile:** `agent.max_turns` (80) in
  `~/.hermes/config.yaml` governs every kanban worker. A profile-level
  shadow value caused two run-killing exhaustions — never set
  `agent.max_turns` on a worker profile.
- **Plan/revision cards need turn-diet guidance in their bodies:** targeted
  patches to the existing file, re-verify ONLY the fixed lines, never
  re-read/re-verify the whole plan. A complete plan-fix fit in 18 tool
  calls when framed this way (vs budget death when framed as
  "re-verify everything").
- **Rework loop live-guard:** run.py files a revision round only when the
  previous round's cards are all done — REJECT as latest verdict alone
  does NOT trigger another filing (that would file all 3 rounds instantly).
- **Idempotent gates:** run.py gate actions use explicit pathspecs (never
  `git status` parsing), skip when the gate card already records a SHA,
  and treat "already terminal" as success. A stalled run recovers with a
  single driver restart.
- **Reviewers must reproduce, not skim:** every REJECT in this run listed
  concrete reproduction steps; every PASS was earned by re-derivation.

## 6. Gate discipline (stage-only flow)

The full authorization chain per task:

```
workers stage (git add own paths) + attach per-card patch
        ↓
reviewer verifies the STAGED diff (not the worktree)
        ↓
driver completes the gate card: "HUMAN COMMIT REQUIRED"
        ↓
human runs the suite, commits with explicit pathspec, pushes
        ↓
board sees gate done → next task's root unblocks
```

Nothing under `wordcount-*/` enters history except through a gate commit;
`mission/` assets are committed freely by the operator between runs.

## 7. Making a NEW scenario (genericity)

1. Write `mission/scenario.json` (template: this repo) — board slug, task
   sequence, cards[] `{title, body-file, assignee, parent, skill}`.
2. Write the card bodies in `mission/card-bodies/` (hard rules FIRST).
3. Write the task contract in `mission/input-spec.md` — that file is the
   immutable source; card bodies point workers at it.
4. If the driver's card graph differs from the shipped one, extend
   `CARDS` in `mission/run.py` to match the new titles/parents.
5. `mission/replay.sh <your-scenario>.json` — board, cards, launch, drive.
   Timing collection is automatic.

## 8. Provenance — run 1 (2026-09-05, three missions)

Original verbatim run, 3 missions on one board: word-count CLI (simple lane),
WordCountService Spring Boot (TW2→C12→RVa2→TI→G2b), mavenize CLI
(C13→RVa3→G3). Commits `74274bb`, `6780be3`, `9ed3c83`. Board sequencing
proved the core mechanism (mission roots parented to previous gates).
Details: `mission/env-first-run.txt`, `mission/REPLAY.md` (v1 section).
