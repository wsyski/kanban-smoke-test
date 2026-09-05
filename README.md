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

Board: `smoke-test` (small lane `TW → C1 → RVa → G2`, stage-only — workers
stage, never commit; the human commits at the gate).
