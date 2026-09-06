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
        ResponseEntity<byte[]> response = post("{\"text\": \"Hello\tworld   again\"}");
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
