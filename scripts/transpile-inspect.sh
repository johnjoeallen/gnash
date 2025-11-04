#!/usr/bin/env bash
set -euo pipefail
set -E

SOURCE="src/gnash/scripts/InspectConfig.gnash"
OUTPUT="build/out/InspectConfig.sh"

echo "[gnash] building compiler via Maven..."
mvn -q -DskipTests package

echo "[gnash] resolving runtime classpath..."
CP_FILE="target/.gnash-classpath"
mkdir -p "$(dirname "${CP_FILE}")"
mvn -q -Dexec.classpathScope=runtime dependency:build-classpath \
  -Dmdep.outputAbsoluteArtifactFilename=true \
  -Dmdep.outputFile="${CP_FILE}" \
  -Dmdep.includeScope=runtime >/dev/null
CLASSPATH=$(cat "${CP_FILE}")

echo "[gnash] transpiling ${SOURCE} -> ${OUTPUT}"
java -cp "target/classes:${CLASSPATH}" dev.gnash.compiler.GnashCompiler "${SOURCE}" "${OUTPUT}"

echo "[gnash] done. Bash output at ${OUTPUT}"
