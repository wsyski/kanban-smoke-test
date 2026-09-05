# kanban-smoke-test

Scratch repo for smoke-testing the **coding-team kanban** solution
(KnowledgeBase → `docs/agents-skills/coding-team-kanban`).

Two things live here:

1. **A tiny Java program** produced *by the kanban lane itself* — the mission
   artifact. `WordCount` reads a text file and prints the number of
   whitespace-separated words.

   ```
   mvn -q -DskipTests compile
   java -cp target/classes WordCount tests/fixtures/three-words.txt   # -> 3
   bash tests/run_count_words.sh                                      # 5 acceptance checks
   ```

   Contract: `java -cp target/classes WordCount <file>` → count on stdout, exit 0;
   empty / whitespace-only file → `0`; missing file → stderr message, exit 2.

2. **The mission recipe** (under `mission/`) — everything needed to re-execute
   the smoke test from the clean project: the input specification, a filing
   script that recreates the kanban card tree, and a replay manual.

   → Start at `mission/REPLAY.md`.

Mission provenance (first full run, 2026-09-05):

| card | id | profile | outcome |
|---|---|---|---|
| TW acceptance tests (RED first) | `t_11606aba` | tester | done, `t_11606aba.patch` |
| C1 implement | `t_6e737860` | coder | done, `t_6e737860.patch` |
| RVa review verdict | `t_f4d747dd` | reviewer | PASS |
| G2 human gate | `t_5163381e` | human | commit `74274bb` pushed |

## Mission 2 — WordCountService, Spring Boot (sequential after M1)

Chain `TW2 → C12 → RVa2 → TI → G2b`; TW2's root is **parented to M1's gate**,
so the board itself enforces the sequence. Maven build; e2e integration card
(TI) between review and gate.

| card | id | profile | outcome |
|---|---|---|---|
| TW2 acceptance tests | `t_4116b3ec` | tester | done, RED-first, `run_wordcount_service.sh` |
| C12 implement Boot 3.x service | `t_9fa12be9` | coder | done, starter-web only |
| RVa2 review verdict | `t_00e4ce90` | reviewer | PASS, 12/12 incl. task-1 regression |
| TI e2e integration + full suite | `t_6e1fc5ec` | tester | done, e2e 8/8, full 5/7/8 GREEN |
| G2b human gate | `t_04c50bc8` | human | commit `6780be3` pushed |

## Mission 3 — Mavenize word-count CLI (sequential after M2)

Chain `C13 → RVa3 → G3` (no TW: the task-1 suite is frozen and IS the spec);
root parented to M2's gate.

| card | id | profile | outcome |
|---|---|---|---|
| C13 mavenize CLI | `t_099e0d31` | coder | done, source → src/main/java, suite byte-identical |
| RVa3 review verdict | `t_a754a95f` | reviewer | PASS, fresh rebuild + regression |
| G3 human gate | `t_86985026` | human | commit `9ed3c83` pushed |

Board: `smoke-test` (small lane `TW → C1 → RVa → G2`, stage-only — workers
stage, never commit; the human commits at the gate).
