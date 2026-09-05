# Mission input — Java word-count CLI

The immutable input of the smoke scenario. The kanban workers must satisfy
exactly this and nothing more; save any change to this file as a new mission.

## Specification (the contract)

Invocation, from the repo root:

```
java -cp build WordCount <file>
```

- Reads a UTF-8 text file, prints **one line** to stdout: the number of words
  (whitespace-separated tokens). Exit 0.
- Empty file → prints `0`, exit 0.
- Whitespace-only file → prints `0`, exit 0.
- Missing file → message on **stderr**, exit **2**.

## Test harness (black-box, owned by the tester card)

`tests/run_count_words.sh` — plain bash, no pytest/JUnit needed. One
PASS/FAIL line per acceptance criterion, final line `N passed, M failed`,
non-zero exit if any check failed. Invokes only
`java -cp build WordCount <fixture>` and inspects stdout / stderr / exit
code. Fixtures in `tests/fixtures/` (empty, whitespace-only, three words,
multi-line).

RED phase: with no `build/` directory every check fails with
`ClassNotFoundException: WordCount` — that is the required RED evidence.

## Environment facts the cards may rely on

- JDK 17 (`javac`, `java`) on PATH. Plain `javac -d build` only; no
  Maven/Gradle.
- JUnit console jar (optional, coder's unit tests only):
  `/tmp/junit/junit-platform-console-standalone-1.10.2.jar`
  (re-download from Maven Central if missing).
- pytest was deliberately avoided: the acceptance harness is bash so the
  scenario has no Python dependency at all.

## Mission shape

Small lane (`--small` in the kanban doc): `TW → C1 → RVa → G2`.
Full lane (`R1 → P1 → RV1 → G1 → TW → C1 → RVa → TI → RV2 → G2`) is overkill
for this input; the small lane already exercises every role (tester, coder,
reviewer, human gate) and the reviewer/verdict mechanics.

Stage-only: workers `git add` their own files and attach a per-card
`git diff --cached` patch as the completion artifact; nothing commits until
the human gate.
