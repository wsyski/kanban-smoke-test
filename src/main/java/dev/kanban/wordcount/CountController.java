package dev.kanban.wordcount;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CountController {

    @PostMapping("/count")
    public ResponseEntity<String> count(@RequestBody String text) {
        return ResponseEntity.ok(String.valueOf(countWords(text)));
    }

    // Same definition as the task 1 CLI: whitespace-separated tokens.
    static int countWords(String text) {
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
