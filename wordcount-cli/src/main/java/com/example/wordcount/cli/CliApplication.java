package com.example.wordcount.cli;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class CliApplication {

    public static void main(String[] args) {
        SpringApplication.run(CliApplication.class, args);
    }

    @Bean
    static CommandLineRunner runner() {
        return args -> {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = System.in.read(chunk)) != -1) {
                buffer.write(chunk, 0, n);
            }
            String text = new String(buffer.toByteArray(), StandardCharsets.UTF_8);
            System.out.print(WordCounter.count(text) + System.lineSeparator());
        };
    }
}
