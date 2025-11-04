#!/usr/bin/env bash
set -euo pipefail
set -E

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECT_SOURCE="${ROOT_DIR}/src/gnash/scripts/InspectConfig.gnash"
INSPECT_OUTPUT="${ROOT_DIR}/build/out/InspectConfig.sh"

if [[ -z "${GNASH_RC_OVERRIDE:-}" ]]; then
  export GNASH_RC_OVERRIDE="${ROOT_DIR}/config/provision.rc"
fi

echo "[gnash] building compiler via Maven..."
mvn -q clean -DskipTests package

echo "[gnash] resolving runtime classpath..."
CLASSPATH_FILE="${ROOT_DIR}/target/.gnash-classpath"
mkdir -p "$(dirname "${CLASSPATH_FILE}")"
mvn -q -Dexec.classpathScope=runtime dependency:build-classpath \
  -Dmdep.outputAbsoluteArtifactFilename=true \
  -Dmdep.outputFile="${CLASSPATH_FILE}" \
  -Dmdep.includeScope=runtime >/dev/null
CLASSPATH=$(cat "${CLASSPATH_FILE}")

echo "[gnash] transpiling ${INSPECT_SOURCE} -> ${INSPECT_OUTPUT}"
java -cp "${ROOT_DIR}/target/classes:${CLASSPATH}" \
  dev.gnash.compiler.GnashCompiler "${INSPECT_SOURCE}" "${INSPECT_OUTPUT}"

echo "[gnash] executing InspectConfig..."
bash "${INSPECT_OUTPUT}"

echo "[gnash] inspect run complete."
