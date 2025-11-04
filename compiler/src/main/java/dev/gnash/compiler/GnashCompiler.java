package dev.gnash.compiler;

import dev.gnash.antlr.GnashLexer;
import dev.gnash.antlr.GnashParser;
import org.antlr.v4.runtime.CharStream;
import org.antlr.v4.runtime.CharStreams;
import org.antlr.v4.runtime.CommonTokenStream;
import org.antlr.v4.runtime.tree.ParseTree;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Entry point for the Gnash-to-Bash compiler. This proof-of-concept wires
 * together the generated ANTLR4 lexer + parser with a simple emitter that
 * demonstrates how Bash output could be produced from the parse tree.
 */
public final class GnashCompiler {

    public static void main(String[] args) throws IOException {
        if (args.length != 2) {
            System.err.println("usage: GnashCompiler <source.gnash> <output.sh>");
            System.exit(2);
        }

        Path source = Path.of(args[0]);
        Path target = Path.of(args[1]);

        CharStream input = CharStreams.fromPath(source);
        GnashLexer lexer = new GnashLexer(input);
        CommonTokenStream tokens = new CommonTokenStream(lexer);
        GnashParser parser = new GnashParser(tokens);

        ParseTree tree = parser.compilationUnit();

        GnashToBashGenerator generator = new GnashToBashGenerator();
        String bash = generator.generate(tree, source);

        Files.createDirectories(target.getParent());
        Files.writeString(target, bash);
    }
}
