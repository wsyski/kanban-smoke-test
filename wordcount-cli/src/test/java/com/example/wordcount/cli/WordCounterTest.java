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
