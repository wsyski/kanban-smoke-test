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
