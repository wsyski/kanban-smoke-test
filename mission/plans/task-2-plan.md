# WordCount REST Service (Task 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone Spring Boot Maven project `wordcount-service/` exposing the word count over HTTP — `POST /count` (JSON `{"text": ...}` → `200 {"count": <int>}`, empty/missing text → `400 {"error": "<message>"}`) and `GET /count/health` (`200 {"service": "wordcount-service", "status": "ok"}`) — per `mission/input-spec.md` task 2.

**Architecture:** Sibling standalone Maven project (no dependency on task 1's code; counting is re-implemented). A hand-written OpenAPI 3.0 spec (`src/main/resources/api/openapi.yaml`) is the reviewed contract; `openapi-generator-maven-plugin` (generator `spring`, `interfaceOnly`) generates the API interface `CountApi` + models into `target/generated-sources` at build time; one `@RestController` implements the generated interface (compile-time conformance); a small `WordCountService` component owns the counting. Tests in three layers: coder-owned JUnit unit tests (surefire), TW2's contract acceptance tests (`@SpringBootTest(RANDOM_PORT)`), TI2's failsafe ITs (`*IT.java`, run by `mvn verify`).

**Tech Stack:** Java 17, Spring Boot 3.5.10 (parent), `spring-boot-starter-web`, `spring-boot-starter-test` (test scope), `openapi-generator-maven-plugin` 7.8.0, JUnit 5 (Boot-managed), `maven-failsafe-plugin` 3.5.4 (Boot-managed). All pre-warmed in `~/.m2` — offline build, no installs.

**Spec:** `mission/input-spec.md` (§Task 2 is the contract source; §Hard rules apply to every card)

## Card mapping (this plan executes on three kanban cards, in board order)

| Plan task | Kanban card | Card ID | Card owner |
|---|---|---|---|
| Task 1 + Task 2 | TW2: contract acceptance tests (RED-first) | t_18850f84 | tester |
| Task 3 + Task 4 + Task 5 | C2: implement - wordcount service | t_2629b86d | coder |
| Task 6 | TI2: failsafe integration tests | t_46ad6f20 | tester |

Task 1 (bootable skeleton) is assigned to card TW2 because TW2's contract tests must
boot a Spring context and fail 404-RED — that requires a pom + application class to
already exist, and TW2 runs before C2 on the board. If the mission is ever re-filed
(driver re-runs `file-mission.sh`), card IDs churn — identify cards by their title
prefix (`TW2:`, `C2:`, `TI2:`); the IDs in this table are the filing of
2026-09-06 13:07+. Consequence: `wordcount-service/pom.xml`
is created minimal by TW2, extended by C2 (openapi-generator), extended by TI2
(failsafe). Each card stages the full file it leaves behind; the later card's staged
version supersedes the earlier one. All three patches remain valid provenance.

## Global Constraints

- Java 17 + Maven 3.9; dependencies pre-warmed in `~/.m2` (openapi-generator 7.8.0, Boot 3.5.10 line). No installs, no new dependencies beyond: starter-web, starter-test (test scope — required by the TW2/TI2 card-specified `@SpringBootTest` + TestRestTemplate harness), the openapi-generator build plugin (with `documentationProvider=none` so no swagger runtime dependency is added), and the failsafe build plugin.
- Everything happens on the current branch of main. No commits, no branches, no stash/reset/restore/clean by any card. Stage-only: `git add -- <own paths>`, never `git add -A`, never `target/` (root `.gitignore` already covers `target/` at any depth — do not touch it).
- Every Maven command targets the sibling project explicitly: `mvn -q -f wordcount-service/pom.xml ...`. Never run task-2 Maven goals from the repo root (the root pom is task 1's CLI project — leave it and all task 1 files untouched: `src/main/java/WordCount.java`, `tests/`, `pom.xml`, `mission/`).
- Word definition (identical to task 1, `src/main/java/WordCount.java:21` `countWords`): maximal runs of non-whitespace characters (`Character.isWhitespace`), UTF-8 safe.
- Response bodies exactly: `200 {"count": <int>}`; `400 {"error": "<message>"}`; health `200 {"service": "wordcount-service", "status": "ok"}`. JSON only, UTF-8.
- Default port 8080 (Boot default; no `application.properties` needed).
- Generated sources land under `target/generated-sources` — never staged.
- Evidence discipline: contract tests verified RED before the controller exists (TW2), counting unit tests RED→GREEN inside C2, everything GREEN after C2, full `mvn verify` GREEN at TI2. Paste command summaries in card results.

---

### Task 1: Bootable skeleton — minimal pom + application class (card TW2)

**Files:**
- Create: `wordcount-service/pom.xml`
- Create: `wordcount-service/src/main/java/dev/kanban/wordcount/WordCountServiceApplication.java`

**Interfaces:**
- Consumes: nothing (project start).
- Produces: a Spring Boot project that `mvn -q -f wordcount-service/pom.xml test` can build and whose context `@SpringBootTest` can boot, with zero tests. Later tasks extend the pom in place; the application class is never modified again.

- [ ] **Step 1: Write `wordcount-service/pom.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.5.10</version>
    <relativePath/>
  </parent>

  <groupId>dev.kanban</groupId>
  <artifactId>wordcount-service</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <name>wordcount-service</name>
  <description>Word-count REST service (POST /count, GET /count/health)</description>

  <properties>
    <java.version>17</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
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

- [ ] **Step 2: Write `wordcount-service/src/main/java/dev/kanban/wordcount/WordCountServiceApplication.java`**

```java
package dev.kanban.wordcount;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class WordCountServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(WordCountServiceApplication.class, args);
    }
}
```

- [ ] **Step 3: Verify the skeleton builds**

Run: `mvn -q -f wordcount-service/pom.xml test`
Expected: BUILD SUCCESS, no tests run (surefire finds none). Do not proceed until this succeeds.

### Task 2: Contract acceptance tests, RED-first (card TW2)

**Files:**
- Create: `wordcount-service/src/test/java/dev/kanban/wordcount/contract/CountContractTest.java`

**Interfaces:**
- Consumes: Task 1's bootable context (HTTP endpoints answer; none exist yet → 404).
- Produces: 7 failing contract tests asserting exactly the input-spec contract. C2's Task 5 makes them GREEN without modifying this file.

- [ ] **Step 1: Write the failing contract tests**

```java
package dev.kanban.wordcount.contract;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CountContractTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Autowired
    private TestRestTemplate rest;

    private ResponseEntity<byte[]> post(String json) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return rest.exchange("/count", HttpMethod.POST,
                new HttpEntity<>(json.getBytes(StandardCharsets.UTF_8), headers), byte[].class);
    }

    private ResponseEntity<byte[]> getHealth() {
        return rest.getForEntity("/count/health", byte[].class);
    }

    private JsonNode json(ResponseEntity<byte[]> response) throws Exception {
        byte[] body = response.getBody() == null ? new byte[0] : response.getBody();
        return MAPPER.readTree(new String(body, StandardCharsets.UTF_8));
    }

    @Test
    void countsTwoWords() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"Hello world\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("2", json(response).path("count").asText());
    }

    @Test
    void countsTokensAcrossTabsAndMultipleSpaces() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"Hello\\tworld   again\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("3", json(response).path("count").asText());
    }

    @Test
    void countsUtf8MultibyteWords() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"héllo wörld — naïve café\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("5", json(response).path("count").asText());
    }

    @Test
    void countsAcrossLines() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"one two\\nthree four\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("4", json(response).path("count").asText());
    }

    @Test
    void rejectsEmptyTextWith400AndErrorBody() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"\"}");
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertFalse(json(response).path("error").asText().isEmpty());
    }

    @Test
    void rejectsMissingTextFieldWith400AndErrorBody() throws Exception {
        ResponseEntity<byte[]> response = post("{ }");
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertFalse(json(response).path("error").asText().isEmpty());
    }

    @Test
    void healthReturnsServiceAndOkStatus() throws Exception {
        ResponseEntity<byte[]> response = getHealth();
        assertEquals(HttpStatus.OK, response.getStatusCode());
        JsonNode body = json(response);
        assertEquals("ok", body.path("status").asText());
        assertFalse(body.path("service").asText().isEmpty());
    }
}
```

- [ ] **Step 2: Verify RED**

Run: `mvn -q -f wordcount-service/pom.xml test`
Expected: BUILD FAILURE — `Tests run: 7, Failures: 7, Errors: 0`. Each test fails at its first assertion with `expected: <200 OK> but was: <404 NOT_FOUND>` (no controller exists). This is the required RED for the right reason: context boots, service endpoints absent. Paste the summary line in the card result.

- [ ] **Step 3: Stage TW2's files and attach the patch**

```bash
git add -- wordcount-service/pom.xml \
  wordcount-service/src/main/java/dev/kanban/wordcount/WordCountServiceApplication.java \
  wordcount-service/src/test/java/dev/kanban/wordcount/contract/CountContractTest.java
git diff --cached -- wordcount-service > /tmp/t_18850f84.patch
hermes kanban --board smoke-test attach t_18850f84 /tmp/t_18850f84.patch
hermes kanban --board smoke-test complete t_18850f84 \
  --result "RED verified: mvn -q -f wordcount-service/pom.xml test -> Tests run: 7, Failures: 7 (404, no controller). Staged: pom.xml (minimal bootable skeleton), WordCountServiceApplication.java, CountContractTest.java (7 contract tests per plan Tasks 1-2). Contract source: mission/input-spec.md task 2." \
  --summary "TW2: 7 contract tests RED (404) against bootable skeleton."
```

Do NOT touch `wordcount-service/src/main/resources/api/openapi.yaml` (belongs to C2) or any `*IT.java` (belongs to TI2). Do not write production code.

### Task 3: OpenAPI spec + generator-enabled pom (card C2)

**Files:**
- Create: `wordcount-service/src/main/resources/api/openapi.yaml`
- Modify: `wordcount-service/pom.xml` (add the openapi-generator plugin to `<build><plugins>`)

**Interfaces:**
- Consumes: Task 1's pom (extends it).
- Produces: generated interface `dev.kanban.wordcount.api.CountApi` with methods `ResponseEntity<CountResponse> count(CountRequest countRequest)` and `ResponseEntity<HealthResponse> health()`; generated models `dev.kanban.wordcount.model.CountRequest` (`getText()`), `CountResponse` (`getCount()/setCount(Integer)`), `HealthResponse` (`getService()/setService(String)`, `getStatus()/setStatus(String)`), `Error` (`getError()/setError(String)`). Task 5's controller implements `CountApi` exactly.

- [ ] **Step 1: Write the OpenAPI spec (hand-written, exactly the input-spec contract)**

```yaml
openapi: 3.0.3
info:
  title: WordCount Service API
  version: 1.0.0
  description: Word counting over HTTP. Contract source mission/input-spec.md (task 2).
paths:
  /count:
    post:
      tags: [count]
      operationId: count
      summary: Count words in text
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CountRequest'
      responses:
        '200':
          description: Word count
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/CountResponse'
        '400':
          description: Empty or missing text
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
  /count/health:
    get:
      tags: [count]
      operationId: health
      summary: Service health
      responses:
        '200':
          description: Health status
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/HealthResponse'
components:
  schemas:
    CountRequest:
      type: object
      properties:
        text:
          type: string
          description: Arbitrary text whose words are counted
    CountResponse:
      type: object
      properties:
        count:
          type: integer
          description: Number of words (maximal runs of non-whitespace)
    HealthResponse:
      type: object
      properties:
        service:
          type: string
        status:
          type: string
    Error:
      type: object
      properties:
        error:
          type: string
```

Note: `text` deliberately carries no `required`/`minLength` constraints — the 400 path is enforced in the controller (Task 5) so the error body shape stays exactly `{"error": ...}` under our advice instead of Boot's default validation body.

- [ ] **Step 2: Add the generator plugin to `wordcount-service/pom.xml`**

Inside the existing `<build><plugins>` section, add:

```xml
      <plugin>
        <groupId>org.openapitools</groupId>
        <artifactId>openapi-generator-maven-plugin</artifactId>
        <version>7.8.0</version>
        <executions>
          <execution>
            <id>generate-api</id>
            <goals>
              <goal>generate</goal>
            </goals>
            <configuration>
              <inputSpec>${project.basedir}/src/main/resources/api/openapi.yaml</inputSpec>
              <generatorName>spring</generatorName>
              <apiPackage>dev.kanban.wordcount.api</apiPackage>
              <modelPackage>dev.kanban.wordcount.model</modelPackage>
              <interfaceOnly>true</interfaceOnly>
              <useTags>true</useTags>
              <skipDefaultInterface>true</skipDefaultInterface>
              <documentationProvider>none</documentationProvider>
              <useSpringBoot3>true</useSpringBoot3>
            </configuration>
          </execution>
        </executions>
      </plugin>
```

(`documentationProvider=none` keeps swagger annotations out of generated code — no runtime dependency beyond starter-web. Generation binds to the `generate-sources` phase, so every `mvn test`/`verify` regenerates into `target/generated-sources`.)

- [ ] **Step 3: Verify generation offline**

Run: `mvn -q -f wordcount-service/pom.xml generate-sources`
Expected: BUILD SUCCESS. Then check:
Run: `ls target/generated-sources/openapi/src/main/java/dev/kanban/wordcount/api target/generated-sources/openapi/src/main/java/dev/kanban/wordcount/model`
Expected: `CountApi.java` and `CountRequest.java CountResponse.java HealthResponse.java Error.java` (plus possibly `ApiUtil.java` — harmless).

### Task 4: Counting component — unit tests first, then code (card C2)

**Files:**
- Create: `wordcount-service/src/test/java/dev/kanban/wordcount/service/WordCountServiceTest.java`
- Create: `wordcount-service/src/main/java/dev/kanban/wordcount/service/WordCountService.java`

**Interfaces:**
- Consumes: nothing.
- Produces: `int WordCountService.count(String text)` — maximal runs of non-whitespace (`Character.isWhitespace`), UTF-8 safe, same definition as task 1. Task 5's controller calls it.

- [ ] **Step 1: Write the failing unit tests (TDD — class does not exist yet)**

```java
package dev.kanban.wordcount.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class WordCountServiceTest {

    private final WordCountService service = new WordCountService();

    @Test
    void countsSimpleSentence() {
        assertEquals(2, service.count("Hello world"));
    }

    @Test
    void tabSeparatedTokensCountAsWords() {
        assertEquals(2, service.count("Hello\tworld"));
    }

    @Test
    void countsAcrossLinesAndMixedWhitespace() {
        assertEquals(5, service.count("one two\nthree\tfour  five"));
    }

    @Test
    void whitespaceOnlyTextCountsZero() {
        assertEquals(0, service.count("   \n  "));
    }

    @Test
    void emptyTextCountsZero() {
        assertEquals(0, service.count(""));
    }

    @Test
    void countsUtf8MultibyteWords() {
        assertEquals(5, service.count("héllo wörld —   naïve\tcafé"));
    }

    @Test
    void singleWordCountsOne() {
        assertEquals(1, service.count("word"));
    }

    @Test
    void noDoubleCountOnAdjacentWords() {
        assertEquals(4, service.count("a b c d"));
    }
}
```

- [ ] **Step 2: Verify RED**

Run: `mvn -q -f wordcount-service/pom.xml test -Dtest=WordCountServiceTest`
Expected: BUILD FAILURE at compile — `cannot find symbol: class WordCountService`. Paste in result.

- [ ] **Step 3: Write the minimal implementation**

```java
package dev.kanban.wordcount.service;

import org.springframework.stereotype.Service;

@Service
public class WordCountService {

    public int count(String text) {
        int count = 0;
        boolean inWord = false;
        for (int i = 0; i < text.length(); i++) {
            if (Character.isWhitespace(text.charAt(i))) {
                inWord = false;
            } else if (!inWord) {
                inWord = true;
                count++;
            }
        }
        return count;
    }
}
```

- [ ] **Step 4: Verify GREEN for the unit layer**

Run: `mvn -q -f wordcount-service/pom.xml test`
Expected: BUILD FAILURE — `Tests run: 15, Failures: 7, Errors: 0`. The 8 unit tests pass; the 7 contract tests still fail 404 (controller comes in Task 5). This is the expected intermediate state.

### Task 5: Controller implementing the generated API (card C2)

**Files:**
- Create: `wordcount-service/src/main/java/dev/kanban/wordcount/web/InvalidTextException.java`
- Create: `wordcount-service/src/main/java/dev/kanban/wordcount/web/GlobalExceptionHandler.java`
- Create: `wordcount-service/src/main/java/dev/kanban/wordcount/web/WordCountController.java`

**Interfaces:**
- Consumes: `CountApi`, models (Task 3), `WordCountService.count(String)` (Task 4).
- Produces: `@RestController WordCountController implements CountApi`; `InvalidTextException(String message)` — makes all 7 contract tests GREEN. Nothing later consumes these beyond the HTTP surface.

- [ ] **Step 1: Write the exception**

```java
package dev.kanban.wordcount.web;

public class InvalidTextException extends RuntimeException {

    public InvalidTextException(String message) {
        super(message);
    }
}
```

- [ ] **Step 2: Write the advice that guarantees the `{"error": ...}` body shape**

```java
package dev.kanban.wordcount.web;

import dev.kanban.wordcount.model.Error;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler({InvalidTextException.class, HttpMessageNotReadableException.class})
    public ResponseEntity<Error> handleBadRequest(Exception e) {
        Error error = new Error();
        error.setError(e instanceof InvalidTextException
                ? e.getMessage()
                : "invalid or missing request body");
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }
}
```

(`import dev.kanban.wordcount.model.Error;` shadows `java.lang.Error` inside this file — intentional, the generated model is what the yaml declares. `HttpMessageNotReadableException` covers a fully absent request body, which the contract treats as missing text.)

- [ ] **Step 3: Write the controller implementing the generated interface**

```java
package dev.kanban.wordcount.web;

import dev.kanban.wordcount.api.CountApi;
import dev.kanban.wordcount.model.CountRequest;
import dev.kanban.wordcount.model.CountResponse;
import dev.kanban.wordcount.model.HealthResponse;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class WordCountController implements CountApi {

    private final WordCountService wordCountService;

    public WordCountController(WordCountService wordCountService) {
        this.wordCountService = wordCountService;
    }

    @Override
    public ResponseEntity<CountResponse> count(CountRequest countRequest) {
        String text = countRequest == null ? null : countRequest.getText();
        if (text == null || text.isEmpty()) {
            throw new InvalidTextException("text must be a non-empty string");
        }
        CountResponse response = new CountResponse();
        response.setCount(wordCountService.count(text));
        return ResponseEntity.ok(response);
    }

    @Override
    public ResponseEntity<HealthResponse> health() {
        HealthResponse health = new HealthResponse();
        health.setService("wordcount-service");
        health.setStatus("ok");
        return ResponseEntity.ok(health);
    }
}
```

(Spring MVC reads the mapping/`@RequestBody` annotations from the generated interface — the implementation declares none. Import `dev.kanban.wordcount.service.WordCountService` as IDE-suggested or fully qualify; it is in a sibling package, so the import is: `import dev.kanban.wordcount.service.WordCountService;` — add it to the imports above.)

- [ ] **Step 4: Verify all unit + contract tests GREEN**

Run: `mvn -q -f wordcount-service/pom.xml test`
Expected: BUILD SUCCESS — `Tests run: 15, Failures: 0, Errors: 0` (8 unit + 7 contract). Paste summary in result.

- [ ] **Step 5: Stage C2's files and attach the patch**

```bash
git add -- wordcount-service/pom.xml \
  wordcount-service/src/main/resources/api/openapi.yaml \
  wordcount-service/src/main/java/dev/kanban/wordcount/service/WordCountService.java \
  wordcount-service/src/main/java/dev/kanban/wordcount/web/InvalidTextException.java \
  wordcount-service/src/main/java/dev/kanban/wordcount/web/GlobalExceptionHandler.java \
  wordcount-service/src/main/java/dev/kanban/wordcount/web/WordCountController.java \
  wordcount-service/src/test/java/dev/kanban/wordcount/service/WordCountServiceTest.java
git diff --cached -- wordcount-service > /tmp/t_2629b86d.patch
hermes kanban --board smoke-test attach t_2629b86d /tmp/t_2629b86d.patch
hermes kanban --board smoke-test complete t_2629b86d \
  --result "GREEN verified: mvn -q -f wordcount-service/pom.xml test -> Tests run: 15, Failures: 0 (8 unit + 7 TW2 contract). Staged: openapi.yaml (hand-written per plan Task 3), pom.xml (added openapi-generator 7.8.0: spring, interfaceOnly, useTags, skipDefaultInterface, documentationProvider=none, useSpringBoot3; no swagger runtime dep), WordCountService + 8 unit tests (TDD RED->GREEN per plan Task 4), controller + advice per plan Task 5. Generated sources stay in target/, never staged. TW2's test files untouched." \
  --summary "C2: service GREEN (15/15) implementing generated CountApi."
```

Do NOT modify TW2's `CountContractTest.java`. Do NOT wire failsafe — that is TI2's pom step.

### Task 6: Failsafe integration tests + full verify (card TI2)

**Files:**
- Modify: `wordcount-service/pom.xml` (add `maven-failsafe-plugin` to `<build><plugins>`)
- Create: `wordcount-service/src/test/java/dev/kanban/wordcount/it/WordCountServiceIT.java`

**Interfaces:**
- Consumes: fully GREEN service from Task 5 (working tree, staged but uncommitted). Version managed by the Boot parent (3.5.10 → failsafe 3.5.4, pre-warmed) — no `<version>` tag.
- Produces: 6 `*IT` tests run by `mvn verify` against the real booted context; `mvn -q test` continues to ignore `*IT` (surefire's default includes never match `*IT.java`).

- [ ] **Step 1: Add the failsafe plugin to `wordcount-service/pom.xml`**

Inside `<build><plugins>`, after the existing plugins, add:

```xml
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-failsafe-plugin</artifactId>
        <executions>
          <execution>
            <goals>
              <goal>integration-test</goal>
              <goal>verify</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
```

- [ ] **Step 2: Write the IT**

```java
package dev.kanban.wordcount.it;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class WordCountServiceIT {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Autowired
    private TestRestTemplate rest;

    private ResponseEntity<byte[]> post(String json) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return rest.exchange("/count", HttpMethod.POST,
                new HttpEntity<>(json.getBytes(StandardCharsets.UTF_8), headers), byte[].class);
    }

    private JsonNode json(ResponseEntity<byte[]> response) throws Exception {
        byte[] body = response.getBody() == null ? new byte[0] : response.getBody();
        return MAPPER.readTree(new String(body, StandardCharsets.UTF_8));
    }

    private String count(ResponseEntity<byte[]> response) throws Exception {
        return json(response).path("count").asText();
    }

    private static String body400() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 20; i++) {
            for (int j = 0; j < 20; j++) {
                if (i + j > 0) {
                    sb.append(' ');
                }
                sb.append('w').append(i * 20 + j);
            }
        }
        return sb.toString();
    }

    @BeforeEach
    void awaitReady() {
        long deadline = System.currentTimeMillis() + 15_000;
        while (System.currentTimeMillis() < deadline) {
            try {
                if (rest.getForEntity("/count/health", byte[].class).getStatusCode() == HttpStatus.OK) {
                    return;
                }
            } catch (RuntimeException notUpYet) {
                // context still binding the port — keep polling
            }
            try {
                Thread.sleep(250);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        throw new IllegalStateException("service did not become ready within 15s");
    }

    @Test
    void countsExactOn400WordBody() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"" + body400() + "\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("400", count(response));
    }

    @Test
    void countsUtf8MultibyteWords() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"héllo wörld — naïve café\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("5", count(response));
    }

    @Test
    void countsTabsAndMultipleSpaces() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"Hello\\tworld   again\"}");
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("3", count(response));
    }

    @Test
    void rejectsEmptyTextWith400AndErrorBody() throws Exception {
        ResponseEntity<byte[]> response = post("{\"text\": \"\"}");
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertFalse(json(response).path("error").asText().isEmpty());
    }

    @Test
    void rejectsMissingTextFieldWith400AndErrorBody() throws Exception {
        ResponseEntity<byte[]> response = post("{ }");
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertFalse(json(response).path("error").asText().isEmpty());
    }

    @Test
    void healthJsonShape() throws Exception {
        ResponseEntity<byte[]> response = rest.getForEntity("/count/health", byte[].class);
        assertEquals(HttpStatus.OK, response.getStatusCode());
        JsonNode body = json(response);
        assertEquals("ok", body.path("status").asText());
        assertFalse(body.path("service").asText().isEmpty());
    }
}
```

(`body400()` emits exactly 400 whitespace-separated tokens `w0`..`w399` on one line — verified arithmetic: 20 blocks × 20 words.)

- [ ] **Step 3: Verify the full build**

Run: `mvn -q -f wordcount-service/pom.xml verify`
Expected: BUILD SUCCESS — surefire summary `Tests run: 15, Failures: 0, Errors: 0` (unit + contract) and failsafe summary `Tests run: 6, Failures: 0, Errors: 0` (ITs boot the real context on a random port). Paste both summary lines in the result.

- [ ] **Step 4: Stage TI2's files and attach the patch**

```bash
git add -- wordcount-service/pom.xml \
  wordcount-service/src/test/java/dev/kanban/wordcount/it/WordCountServiceIT.java
git diff --cached -- wordcount-service > /tmp/t_46ad6f20.patch
hermes kanban --board smoke-test attach t_46ad6f20 /tmp/t_46ad6f20.patch
hermes kanban --board smoke-test complete t_46ad6f20 \
  --result "mvn -q -f wordcount-service/pom.xml verify GREEN: surefire Tests run: 15, Failures: 0; failsafe Tests run: 6, Failures: 0 (health polled until 200 before /count assertions). Staged: WordCountServiceIT.java + pom.xml failsafe wiring (Boot-managed 3.5.4). No other files touched." \
  --summary "TI2: 6 ITs GREEN, full verify 21/21."
```

---

## Risks / notes for reviewers

- **Generator version drift:** plan pins `openapi-generator-maven-plugin` 7.8.0 (the only 7.x in `~/.m2`). If generation fails offline, do NOT reach for the network — record the failure in the card result and let the reviewer decide.
- **`Error` model name shadows `java.lang.Error`** in `GlobalExceptionHandler` via single-type import — legal Java, intentional (schema name is contract-fixed by input-spec).
- **pom ownership chain** (TW2 minimal → C2 generator → TI2 failsafe) means three cards stage `wordcount-service/pom.xml`; each card's `git diff --cached` patch shows the full staged state at that moment. The Gc2 gate commits the final tree once.
- **Not in scope:** authentication, persistence, actuator, springdoc/swagger UI, `application.properties`, any root-pom aggregation of the two projects.
