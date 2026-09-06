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
