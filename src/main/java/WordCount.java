import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class WordCount {

    public static void main(String[] args) {
        if (args.length != 1) {
            System.err.println("Usage: java -cp target/classes WordCount <file>");
            System.exit(2);
        }
        Path path = Paths.get(args[0]);
        try {
            String content = Files.readString(path, StandardCharsets.UTF_8);
            System.out.println(countWords(content));
        } catch (IOException e) {
            System.err.println("Cannot read file '" + args[0] + "': " + e.getMessage());
            System.exit(2);
        }
    }

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
