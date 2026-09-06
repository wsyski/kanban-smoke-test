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
        ResponseEntity<byte[]> response = post("{\"text\": \"Hello\tworld   again\"}");
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
        ResponseEntity<byte[]> response = post("{\"text\": \"one two\nthree four\"}");
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
