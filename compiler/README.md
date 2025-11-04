# Gnash Compiler Prototype

This directory hosts a proof-of-concept Java entry point that wires the
`Gnash.g4` ANTLR grammar into a small driver for experimenting with DSL to Bash
code generation.

## Building with Maven

The top-level `pom.xml` is configured so that the Maven compiler uses
`compiler/src/main/java` and `compiler/src/test/java` as the source roots. It
also binds the ANTLR4 plugin to `grammar/Gnash.g4`.

```bash
mvn clean package
```

After the build completes, the stub CLI can be invoked with:

```bash
java -cp target/gnash-compiler-0.1.0-SNAPSHOT.jar \
  dev.gnash.compiler.GnashCompiler \
  src/gnash/steps/AdminGroupNopass.gnash build/out/AdminGroupNopass.sh
```

The current generator only emits a stub Bash script listing the parsed function
names. Replace `GnashToBashGenerator` with behaviour that mirrors the reference
Bash output under `build/app` to extend the proof-of-concept into a full
translator.

For a one-command comparison against the reference transpilation run:

```bash
scripts/compare-transpile.sh
```

The helper now compiles both `steps/AdminGroupNopass.gnash` and
`lib/ConfigLoader.gnash`, dropping the generated Bash into `build/out/` for
inspection.

The helper script expects `mvn` and `java` on your PATH and will report
differences between the generated and reference Bash scripts.
