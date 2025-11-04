#!/usr/bin/env bash
# v3: indentation-aware YAML-lite loader (pure Bash)
# Supports:
#   section:
#     key: value
#     list:
#       - item
#       - item
# No jq/yq required.

set -uo pipefail

declare -A CONFIG

log() { printf '[config] %s\n' "$*" >&2; }
dbg() { [[ "${DEBUG:-0}" == "1" ]] && printf '[debug] %s\n' "$*" >&2; }

_trim_quotes() {
  local s="${1:-}"
  [[ "$s" =~ ^\".*\"$ ]] && s="${s:1:${#s}-2}"
  [[ "$s" =~ ^\'.*\'$ ]] && s="${s:1:${#s}-2}"
  printf '%s' "$s"
}

_leading_spaces() {
  local str="$1"
  local n=${#str}
  local i=0
  while (( i < n )) && [[ ${str:i:1} == " " ]]; do ((i++)); done
  echo "$i"
}

cfg_load_yaml_lite() {
  (( $# >= 1 )) || { log "cfg_load_yaml_lite: need at least one file"; return 2; }

  local file raw line indent section="" key="" key_indent=-1 idx=0
  for file in "$@"; do
    [[ -f "$file" ]] || { log "warn: file not found: $file"; continue; }
    log "Loading: $file"
    section="" key="" key_indent=-1 idx=0

    while IFS= read -r raw || [[ -n "$raw" ]]; do
      # normalize CRLF -> LF and TABs -> 2 spaces
      line="${raw//$'\r'/}"
      line="${line//$'\t'/  }"
      # strip trailing spaces
      line="${line%"${line##*[![:space:]]}"}"
      # strip comments (naive)
      [[ "$line" == *"#"* ]] && line="${line%%#*}"
      # skip blank
      [[ -z "${line//[[:space:]]/}" ]] && continue

      indent=$(_leading_spaces "$line")
      # raw (with indent preserved)
      local trimmed="${line:indent}"

      # Top-level SECTION (indent == 0) : "name:"
      if (( indent == 0 )) && [[ "$trimmed" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*):[[:space:]]*$ ]]; then
        section="${BASH_REMATCH[1]}"
        dbg "section=$section"
        key="" ; key_indent=-1 ; idx=0
        continue
      fi

      # Key under a section: "key: value" or "key:" (indent > 0)
      if (( indent > 0 )) && [[ -n "$section" ]] && [[ "$trimmed" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        local val="$(_trim_quotes "${BASH_REMATCH[2]}")"
        CONFIG["$section.$key"]="$val"
        key_indent=$indent
        idx=0
        dbg "set $section.$key=$val (indent=$indent)"
        continue
      fi

      # List item under the *current key*: must be indented more than key line and start with '- '
      if (( indent > key_indent )) && [[ -n "$section" && -n "$key" ]] && [[ "$trimmed" =~ ^-[[:space:]]*(.*)$ ]]; then
        local item="$(_trim_quotes "${BASH_REMATCH[1]}")"
        CONFIG["$section.$key[$idx]"]="$item"
        dbg "push $section.$key[$idx]=$item (indent=$indent > key_indent=$key_indent)"
        ((idx++))
        continue
      fi

      dbg "skip: '$raw'"
    done < "$file"
  done

  log "Parsed ${#CONFIG[@]} keys"
}

# -------------------- Query API --------------------
cfg_get()  { local k="${1:?usage}"; [[ -n ${CONFIG[$k]+x} ]] && printf '%s\n' "${CONFIG[$k]}"; }
cfg_bool() { local v; v="$(cfg_get "$1" || true)"; [[ "$v" =~ ^(true|1|yes|on|TRUE|Yes|On)$ ]]; }
cfg_list() { local p="${1:?usage}"; local k; for k in "${!CONFIG[@]}"; do [[ $k == "$p"[[]* ]] && printf '%s\n' "${CONFIG[$k]}"; done; }
cfg_dump() { local k; for k in "${!CONFIG[@]}"; do printf '%s=%s\n' "$k" "${CONFIG[$k]}"; done | sort; }

# ---------------------- Demo -----------------------
main() {
  local base="${1:-example.cfg}"
  local hn="${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
  local host="${hn%%.*}.cfg"

  if [[ -f "$host" ]]; then
    log "Using base + host override: $base + $host"
    cfg_load_yaml_lite "$base" "$host"
  else
    log "Using base: $base"
    cfg_load_yaml_lite "$base"
  fi

  echo "== Quick queries =="
  printf 'admin group: %s\n' "$(cfg_get 'adminGroupNopass.adminGroup' || echo '(missing)')"
  printf 'admin enabled: %s\n' "$(cfg_bool 'adminGroupNopass.enabled' && echo yes || echo no)"
  printf 'NIS server: %s\n' "$(cfg_get 'nisSetup.server' || echo '(missing)')"
  printf 'Docker data root: %s\n' "$(cfg_get 'dockerDataRoot.target' || echo '(missing)')"

  echo
  echo "== Essentials packages =="
  cfg_list "essentials.packages" || true

  echo
  echo "== Java versions =="
  cfg_list "sdkmanJava.versions" || true

  # Uncomment for full dump
  # echo; echo "== Full dump =="; cfg_dump
}

main "$@"
