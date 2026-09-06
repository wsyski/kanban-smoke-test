package dev.kanban.wordcount.web;

public class InvalidTextException extends RuntimeException {

    public InvalidTextException(String message) {
        super(message);
    }
}
