# Replay manual — Java word-count smoke mission

Re-executes the complete small-lane kanban run (`TW → C1 → RVa → G2`) that
produced this project. Every step was executed verbatim on 2026-09-05;
per-card provenance is in `env-first-run.txt`.

## 0. Prerequisites

| need | check / fix |
|---|---|
| board exists, workdir pinned | `hermes kanban boards list`; `hermes kanban boards set-default-workdir smoke-test /opt/projects/kanban-smoke-test/main/kanban-smoke-test` |
| dispatcher running | `lsof ~/.hermes/kanban/.dispatcher.lock` → PID exists; owner should be the default-profile gateway (`dispatch_in_gateway: true` in `~/.hermes/config.yaml`) |
| JDK 17 | `javac -version` → 17.x |
| JUnit jar (coder unit tests only) | `mkdir -p /tmp/junit && curl -sSL -o /tmp/junit/junit-platform-console-standalone-1.10.2.jar https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/1.10.2/junit-platform-console-standalone-1.10.2.jar` |
| profiles able to run | `hermes profile list` — tester/coder/reviewer gateways must be up for their cards to dispatch |

## 1. Reset the scratch project (only if re-running from clean)

The repo is disposable; the only thing to reset is its git state:

```bash
cd /opt/projects/kanban-smoke-test/main/kanban-smoke-test
git reset --hard <baseline>        # e.g. origin/main's initial commit
git clean -fd                      # removes build/, stale artifacts (HUMAN step, never workers)
git push --force origin main       # only if the remote must also go back
```

`mission/input-spec.md` and this directory are the durable input — never
delete them; they are what makes the scenario re-executable.

## 2. File the mission (cards created parked on human-gate)

```bash
cd /opt/projects/kanban-smoke-test/main/kanban-smoke-test
mission/file-mission.sh file
# -> Filed (parked): TW=t_xxx C1=t_xxx RVA=t_xxx G2=t_xxx
```

Idempotent: same `-k` prefix returns the existing ids. Nothing dispatches:
every card sits on the `human-gate` lane, blocked or todo-behind-blocked.

## 3. Launch

```bash
mission/file-mission.sh launch
# unblocks TW, assigns tester. Dispatcher claims within one 60s tick.
```

## 4. Monitor

Poll `hermes kanban --board smoke-test list` (60s dispatcher tick). Expected
durations from the first run:

| card | profile | first-run duration | success evidence |
|---|---|---|---|
| TW | tester | ~5 min | comment with RED output ("0 passed, 5 failed", ClassNotFoundException); patch attached; `tests/` staged |
| C1 | coder | ~3.5 min | comment with GREEN summary ("5 passed, 0 failed"); patch attached; `WordCount.java` + `.gitignore` staged |
| RVa | reviewer | ~3 min | PASS verdict listing (a)-(d) checks |
| G2 | human | minutes | commit SHA recorded (step 6) |

Worker transcripts: `~/.hermes/kanban/boards/smoke-test/logs/<card-id>.log`
(the file appends across re-runs — split on `Initializing agent...`).
Attempt history: `hermes kanban --board smoke-test runs <card-id>`.

**Intervention rules** (nothing here should take more than a few minutes):

- worker cards carry `--max-runtime 30m --max-retries 1`: a wedged worker is
  SIGTERMed and re-queued once, then trips into a visible `blocked` — no
  silent looping. Manual version for faster reaction:
  `hermes kanban --board smoke-test reclaim <id>` then
  `block --kind needs_input <id> "stalled"`, examine, fix, `unblock`.
- worker failed N times → card auto-`blocked`; read the log tail, fix the
  environment (not the card body), `unblock <id>`.
- card finished but shows a stale "still running" nudge → known cosmetic
  dispatcher-view lag; check `runs <id>` — if the last run is `completed`,
  move on.
- `launch` is a no-op when TW is already done — a second launch cannot
  double-run the mission; for a fresh replay use a new `-k` prefix (and
  archive or reset the old cards).

## 5. Drive the hand-offs (the only manual step per card)

Parent completion auto-promotes the child to `ready`; its *lane* is still
`human-gate`, so one assign flips it to the real profile:

```bash
mission/file-mission.sh drive    # after TW done: C1 -> coder; after C1 done: RVa -> reviewer
```

Repeat `drive` after each card completes. When RVa finishes with PASS, G2
becomes `ready` and waits for a human.

## 6. Human gate: commit + push

```bash
cd /opt/projects/kanban-smoke-test/main/kanban-smoke-test
git status --short                     # staged mission files only; git log unchanged
bash tests/run_count_words.sh          # 5 passed, 0 failed
git add -- .gitignore WordCount.java tests/
git commit -m "Java word-count CLI: black-box acceptance tests + implementation"
git push origin main
mission/file-mission.sh gate "$(git rev-parse --short HEAD)"
```

## 7. Replay-verification checklist

- `hermes kanban --board smoke-test stats` → done=4 (this mission), blocked=0
- `git log` on the repo: exactly one new commit since baseline, 7 files
- `bash tests/run_count_words.sh` → `5 passed, 0 failed`
- per-card patches exist: `hermes kanban --board smoke-test attachments <id>`

## Failure handling — what happened on the first run

| symptom | cause | fix |
|---|---|---|
| workers see no `kanban_*` tools | tool-catalog gap on worker sessions; the hermes kanban **CLI** is the prescribed fallback and worked every time | none needed; file-mission + card bodies now state the CLI route |
| stale "still running" nudge after completion | dispatcher board-view lag | ignore; verify via `runs <id>` |
| tester briefly flagged a needed `rm -rf /tmp/...` | tooling approval heuristics | worker self-corrected by dropping the unnecessary rm; no action |
| card wedged in `running` | worker died without releasing claim | `reclaim` + `block`, inspect log, `unblock` |

## Full lane variant (not used)

The full lane adds `R1 → P1 → RV1 → G1` before TW and `TI → RV2` after RVa
(integration tests + second review). Use it when the mission has real
interfaces to integration-test. For this input the small lane already
exercises every role and both review/gate mechanics; TI would test nothing
the acceptance suite does not.
