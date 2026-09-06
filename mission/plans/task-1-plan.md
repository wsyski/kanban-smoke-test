# P1 Implementation Plan — word-count CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Spring Boot fat-jar CLI (`wordcount-cli/`) that reads all of stdin and prints the word count — words are maximal runs of non-whitespace — plus a newline, exit 0.

**Architecture:** One small Maven project, Spring Boot 3 parent, Java 17. Word counting is a pure static method in a `WordCounter` class; the entry point is a `CommandLineRunner` that slurps stdin (UTF-8), calls `WordCounter.count`, and prints the integer. No HTTP; a two-line `application.properties` turns off the Spring banner and root logging so that at runtime stdout carries exactly the count line. Unit tests exercise the runner through captured System streams; the packaged fat jar is smoke-run end-to-end in the packaging task.

**Tech Stack:** Java 17, Spring Boot 3.3.x (Maven parent + spring-boot-maven-plugin repackage → executable fat jar), JUnit 5 (JUnitPlatformEngine, Spring Boot starter-test), Maven.

**Spec:** `mission/input-spec.md` — Task 1 section (`### Task 1 — word-count CLI`).

**Card mapping (execution model):** the plan is executed 1:1 by the mission's TW1/C1 cards. TW1 owns the RED side: plan Task 1 (pom + `CliApplication` skeleton — scaffolding done by the TW card because this plan assigns it there), Task 2 Steps 1–2, Task 3 Steps 1–2. C1 owns the GREEN side: Task 2 Steps 3–5, Task 3 Steps 3–5, Task 4 (packaging smoke). C1 must not modify TW1's test files; nobody commits.

## Global Constraints

- Target directory: everything lives under `wordcount-cli/`. Do not create `wordcount-service/` (that is task 2).
- Spring Boot Maven app packaged as an executable fat jar, run with `java -jar`.
- Behavior: reads **all of stdin**, writes **one integer + `\n`** to stdout, exit 0.
- Words = maximal runs of non-whitespace (`\S+` counting semantics, 1:1 with `wc -w`).
- Entry point: `CommandLineRunner`. **No HTTP** in this task (no `spring-boot-starter-web`, no Tomcat).
- Stdout purity: at runtime stdout carries **exactly** the integer line — Spring banner off and root logging off via `src/main/resources/application.properties` (Boot's default console logging would otherwise pollute stdout; verified in Task 4).
- Tests: JUnit **unit** tests only — counting logic + stdin/stdout entry point via captured System streams. No integration tests (`*IT`), no failsafe, no TestRestTemplate.
- RED-first: tests are written and verified RED before the implementation exists; one verification run per phase.
- No commits — stage only: `git add -- <own paths>`. No branches, no stash/reset/clean, no installs.
- Hard rules repeat `mission/input-spec.md` §Hard rules for all workers: tests RED before implementation (TW cards) and GREEN after (C cards); evidence in the card result.

---

### Task 1: Bare Spring Boot Maven skeleton — pom + main class, no logic

**Files:**
- Create: `wordcount-cli/pom.xml`
- Create: `wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: Maven coordinates `com.example.wordcount:wordcount-cli:1.0.0` with `spring-boot-maven-plugin` repackage, main class `com.example.wordcount.cli.CliApplication` (all later tasks import under this package). Build command `mvn -q -f wordcount-cli/pom.xml test|package` is the contract every task uses.

- [ ] **Step 1: Verify the RED premise — no Maven project exists yet (RED evidence)**

The RED step for the skeleton is: the Maven project does not exist, so no build can pass. Verify before creating files:

```bash
mvn -q -f wordcount-cli/pom.xml test; echo "exit=$?"
```

Expected: BUILD FAILURE — `no POM in this directory` (or equivalent), exit 1.

- [ ] **Step 2: Write the pom**

`wordcount-cli/pom.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
    <relativePath/>
  </parent>
  <groupId>com.example.wordcount</groupId>
  <artifactId>wordcount-cli</artifactId>
  <version>1.0.0</version>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

- [ ] **Step 3: Write the main class**

`wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java`:

```java
package com.example.wordcount.cli;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class CliApplication {

    public static void main(String[] args) {
        SpringApplication.run(CliApplication.class, args);
    }

    static CommandLineRunner runner() {
        return args -> { /* implemented in plan Task 3 */ };
    }
}
```

- [ ] **Step 4: Verify the skeleton builds (GREEN for Task 1)**

Run: `mvn -q -f wordcount-cli/pom.xml test`
Expected: BUILD SUCCESS, 0 tests.

- [ ] **Step 5: Stage Task 1 files**

```bash
git add -- wordcount-cli/pom.xml wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java
```

---

### Task 2: `WordCounter` counting logic (RED → GREEN)

**Files:**
- Create: `wordcount-cli/src/main/java/com/example/wordcount/cli/WordCounter.java`
- Test: `wordcount-cli/src/test/java/com/example/wordcount/cli/WordCounterTest.java`

**Interfaces:**
- Consumes: Maven project from Task 1 (`com.example.wordcount.cli` package).
- Produces: `static int WordCounter.count(String text)` — returns the number of maximal non-whitespace runs in `text`; returns 0 for null or empty input. Later tasks (Task 3 here, and task 2 of the mission in `wordcount-service/`) call exactly this signature on the CLI side.

- [ ] **Step 1: Write the failing test (RED)**

`wordcount-cli/src/test/java/com/example/wordcount/cli/WordCounterTest.java`:

```java
package com.example.wordcount.cli;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class WordCounterTest {

    @Test
    void countsWordsSeparatedBySpaces() {
        assertEquals(3, WordCounter.count("hello world again"));
    }

    @Test
    void countsWordsSeparatedByNewlinesTabsAndMixedWhitespace() {
        assertEquals(5, WordCounter.count("one\ntwo\tthree  four\n\n five"));
    }

    @Test
    void emptyStringCountsZero() {
        assertEquals(0, WordCounter.count(""));
    }

    @Test
    void nullCountsZero() {
        assertEquals(0, WordCounter.count(null));
    }

    @Test
    void whitespaceOnlyCountsZero() {
        assertEquals(0, WordCounter.count("  \n\t  \n"));
    }

    @Test
    void utf8SafeWordIsOneWord() {
        assertEquals(2, WordCounter.count("smörgås 世界"));
    }

    @Test
    void singleWordNoWhitespace() {
        assertEquals(1, WordCounter.count("hello"));
    }

    @Test
    void leadingAndTrailingWhitespaceIgnored() {
        assertEquals(2, WordCounter.count("  hello world  "));
    }

    @Test
    void largeInputCountsExactly() {
        assertEquals(500, WordCounter.count(String.join(" ", java.util.Collections.nCopies(500, "word"))));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (RED evidence)**

Run: `mvn -q -f wordcount-cli/pom.xml -Dtest=WordCounterTest test`
Expected: BUILD FAILURE — compilation error `cannot find symbol`, `symbol: variable WordCounter` (test source references the not-yet-existing class).

- [ ] **Step 3: Write the minimal implementation**

`wordcount-cli/src/main/java/com/example/wordcount/cli/WordCounter.java`:

```java
package com.example.wordcount.cli;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class WordCounter {

    private static final Pattern NON_WHITESPACE = Pattern.compile("\\S+");

    private WordCounter() {
    }

    public static int count(String text) {
        if (text == null || text.isEmpty()) {
            return 0;
        }
        Matcher m = NON_WHITESPACE.matcher(text);

        int count = 0;
        while (m.find()) {
            count++;
        }
        return count;
    }
}
```

- [ ] **Step 4: Run the test to verify it passes (GREEN evidence)**

Run: `mvn -q -f wordcount-cli/pom.xml -Dtest=WordCounterTest test`
Expected: PASS — 9 tests, 0 failures.

- [ ] **Step 5: Stage Task 2 files**

```bash
git add -- wordcount-cli/src/main/java/com/example/wordcount/cli/WordCounter.java wordcount-cli/src/test/java/com/example/wordcount/cli/WordCounterTest.java
```

---

### Task 3: stdin/stdout entry point via CommandLineRunner (RED → GREEN)

**Files:**
- Create: `wordcount-cli/src/test/java/com/example/wordcount/cli/RunnerStreamTest.java`
- Create: `wordcount-cli/src/main/resources/application.properties`
- Modify: `wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java` — replace the empty runner with the real one, registered as a static `@Bean`.

**Interfaces:**
- Consumes: `static int WordCounter.count(String text)` from Task 2; `CliApplication.runner()` from Task 1.
- Produces: `static CommandLineRunner CliApplication.runner()` — registered as a static `@Bean` so `SpringApplication` executes it on startup. Reads all of stdin as UTF-8, prints `count + System.lineSeparator()` to stdout, appends nothing else. `application.properties` (`spring.main.banner-mode=off`, `logging.level.root=OFF`) guarantees runtime stdout carries only that line. The fat jar's smoke run in Task 4 exercises this bean through the real Spring context and asserts stdout purity.

- [ ] **Step 1: Write the failing test (RED)**

`wordcount-cli/src/test/java/com/example/wordcount/cli/RunnerStreamTest.java`:

```java
package com.example.wordcount.cli;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;

class RunnerStreamTest {

    @Test
    void runnerPrintsCountAndNewlineToStdout() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("hello world\nworld again".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("4" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerHandlesEmptyStdin() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream(new byte[0]));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("0" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerReadsAllOfStdinNotJustFirstLine() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("a\nb\nc\nd\n".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("4" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerIsUtf8Safe() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("smörgås 世界 world".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("3" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (RED evidence)**

Run: `mvn -q -f wordcount-cli/pom.xml -Dtest=RunnerStreamTest test`
Expected: FAIL — the tests compile against the Task 1 skeleton (`runner()` returns a no-op lambda; each test declares `throws Exception`, required because `CommandLineRunner.run` declares it) and the first assertion fails with expected `4\n` got `` — empty stdout.

- [ ] **Step 3: Write the minimal implementation**

Replace the runner body in `wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java` — register it as a static `@Bean` (canonical Boot wiring; `main` stays `SpringApplication.run(CliApplication.class, args)`).

Add `wordcount-cli/src/main/resources/application.properties` — without this, Boot's banner and startup logs go to stdout and pollute the count line (verified defect during plan authoring):

```properties
spring.main.banner-mode=off
logging.level.root=OFF
```

`wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java`:

```java
package com.example.wordcount.cli;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class CliApplication {

    public static void main(String[] args) {
        SpringApplication.run(CliApplication.class, args);
    }

    @Bean
    static CommandLineRunner runner() {
        return args -> {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = System.in.read(chunk)) != -1) {
                buffer.write(chunk, 0, n);
            }
            String text = new String(buffer.toByteArray(), StandardCharsets.UTF_8);
            System.out.print(WordCounter.count(text) + System.lineSeparator());
        };
    }
}
```

- [ ] **Step 4: Run both test classes to verify green (GREEN evidence)**

Run: `mvn -q -f wordcount-cli/pom.xml test`
Expected: PASS — WordCounterTest (9) + RunnerStreamTest (4), 0 failures.

- [ ] **Step 5: Stage Task 3 files**

```bash
git add -- wordcount-cli/src/main/java/com/example/wordcount/cli/CliApplication.java wordcount-cli/src/test/java/com/example/wordcount/cli/RunnerStreamTest.java wordcount-cli/src/main/resources/application.properties
```

---

### Task 4: Packaging check — executable fat jar end-to-end smoke

**Files:**
- Modify: none (verification-only task against what exists).
- Test: none required — real subprocess run is the evidence.

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: `wordcount-cli/target/wordcount-cli-1.0.0.jar` executable via `java -jar` (artifact the gate card demonstrates).

- [ ] **Step 1: Package the fat jar**

Run: `mvn -q -f wordcount-cli/pom.xml package -DskipTests`
Expected: BUILD SUCCESS; `wordcount-cli/target/wordcount-cli-1.0.0.jar` exists.

- [ ] **Step 2: Smoke-run the fat jar with piped stdin**

Run:

```bash
printf 'hello world\nworld again' | java -jar wordcount-cli/target/wordcount-cli-1.0.0.jar; echo "exit=$?"
printf 'one\ntwo\nthree' | java -jar wordcount-cli/target/wordcount-cli-1.0.0.jar; echo "exit=$?"
printf '' | java -jar wordcount-cli/target/wordcount-cli-1.0.0.jar; echo "exit=$?"
out=$(printf 'pipe test' | java -jar wordcount-cli/target/wordcount-cli-1.0.0.jar 2>/dev/null); [ "$out" = "2" ] && echo "stdout-pure" || echo "STDOUT-DIRTY: $out"
```

Expected stdout lines, in order: `4`, exit 0; `3`, exit 0; `0`, exit 0; then `stdout-pure`. Each count is followed by a newline; the last check proves stdout carries exactly the integer line (no banner, no logs).

- [ ] **Step 3: Confirm no HTTP listener starts**

Run: `java -jar wordcount-cli/target/wordcount-cli-1.0.0.jar` with stdin from `/dev/null`, verify it terminates immediately (no Tomcat/spring-web on the classpath at all):

```bash
if unzip -l wordcount-cli/target/wordcount-cli-1.0.0.jar | grep -qE 'tomcat|spring-web'; then echo "WEB-FOUND"; else echo "no-web"; fi
```

Expected: `no-web` — the boot jar contains only `spring-boot-starter` dependencies (no servlet container, no web stack).

- [ ] **Step 4: Stage nothing new (verification-only) and record evidence**

No staging step — Task 4 produces only `target/` output which is not staged.
