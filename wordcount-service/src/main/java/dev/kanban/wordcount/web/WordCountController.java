package dev.kanban.wordcount.web;

import dev.kanban.wordcount.api.CountApi;
import dev.kanban.wordcount.model.CountRequest;
import dev.kanban.wordcount.model.CountResponse;
import dev.kanban.wordcount.model.HealthResponse;
import dev.kanban.wordcount.service.WordCountService;
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
