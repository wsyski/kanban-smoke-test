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
