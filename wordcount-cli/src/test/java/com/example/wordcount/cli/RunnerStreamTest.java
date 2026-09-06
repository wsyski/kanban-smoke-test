package com.example.wordcount.cli;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;

class RunnerStreamTest {

    @Test
    void runnerPrintsCountAndNewlineToStdout() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("hello world\nworld again".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("4" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerHandlesEmptyStdin() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream(new byte[0]));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("0" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerReadsAllOfStdinNotJustFirstLine() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("a\nb\nc\nd\n".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("4" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }

    @Test
    void runnerIsUtf8Safe() throws Exception {
        PrintStream originalOut = System.out;
        InputStream originalIn = System.in;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream("smörgås 世界 world".getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
            CliApplication.runner().run(new String[0]);
        } finally {
            System.setIn(originalIn);
            System.setOut(originalOut);
        }
        assertEquals("3" + System.lineSeparator(), out.toString(StandardCharsets.UTF_8));
    }
}
