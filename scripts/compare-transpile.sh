#!/usr/bin/env bash

# Rebuilds the Gnash compiler, regenerates Bash from the AdminGroupNopass step,
# and diffs the result against the reference script committed in build/app.

set -euo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/src/gnash/steps/AdminGroupNopass.gnash"
REFERENCE="${ROOT}/build/app/steps/AdminGroupNopass.sh"
OUTPUT="${ROOT}/build/out/AdminGroupNopass.sh"

if [[ ! -f "$SOURCE" ]]; then
  echo "missing source gnash script: $SOURCE" >&2
  exit 2
fi

if [[ ! -f "$REFERENCE" ]]; then
  echo "missing reference bash script: $REFERENCE" >&2
  exit 2
fi

if ! command -v mvn >/dev/null 2>&1; then
  echo "maven (mvn) must be installed to build the compiler" >&2
  exit 2
fi

if ! command -v java >/dev/null 2>&1; then
  echo "java runtime not found on PATH" >&2
  exit 2
fi

pushd "$ROOT" >/dev/null

echo "[gnash] building compiler via Maven..."
mvn -q clean package

echo "[gnash] resolving runtime classpath..."
mvn -q -DincludeScope=runtime -Dmdep.outputFile=target/runtime-classpath dependency:build-classpath
if [[ ! -f target/runtime-classpath ]]; then
  echo "[gnash] failed to compute runtime classpath" >&2
  exit 3
fi
RUNTIME_CP="$(< target/runtime-classpath)"

echo "[gnash] regenerating Bash from $SOURCE ..."
mkdir -p "$(dirname "$OUTPUT")"
java -cp "target/gnash-compiler-0.1.0-SNAPSHOT.jar:${RUNTIME_CP}" \
  dev.gnash.compiler.GnashCompiler \
  "$SOURCE" "$OUTPUT"

echo "[gnash] diffing generated output against reference..."
if ! diff -u "$REFERENCE" "$OUTPUT"; then
  echo "[gnash] differences detected (see diff above)"
  exit 1
fi

echo "[gnash] outputs match."

popd >/dev/null
