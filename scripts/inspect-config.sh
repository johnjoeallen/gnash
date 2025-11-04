#!/usr/bin/env bash
set -euo pipefail
set -E

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECT_SOURCE="${ROOT_DIR}/src/gnash/scripts/InspectConfig.gnash"
INSPECT_OUTPUT="${ROOT_DIR}/build/out/InspectConfig.sh"

if [[ -z "${GNASH_RC_OVERRIDE:-}" ]]; then
  export GNASH_RC_OVERRIDE="${ROOT_DIR}/config/provision.rc"
fi

echo "[gnash] transpiling inspector..."
"${ROOT_DIR}/scripts/transpile-inspect.sh"

echo "[gnash] executing InspectConfig..."
bash "${INSPECT_OUTPUT}"

echo "[gnash] inspect run complete."
