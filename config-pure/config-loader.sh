#!/usr/bin/env bash
# GENERATED from src/gnash/config/Config.gnash — with source comments
# v4: robust to `set -u`; no tricky parameter expansions; safe rstrip.
set -uo pipefail

# --------------------------------------------------------------------------------
# Gnash:
# CONFIG = {}
# --------------------------------------------------------------------------------
declare -Ag CONFIG=()   # flattened key/value store

# --------------------------------------------------------------------------------
# Gnash:
# def log(msg) { printf("[gnash:config] %s\n", msg) }
# def dbg(msg) { if (env.get("GNASH_DEBUG") == "1") printf("[gnash:debug] %s\n", msg) }
# --------------------------------------------------------------------------------
gnash_config_log() { printf '[gnash:config] %s\n' "$*" >&2; }
gnash_config_dbg() { [[ "${GNASH_DEBUG:-0}" == "1" ]] && printf '[gnash:debug] %s\n' "$*" >&2; }

# --------------------------------------------------------------------------------
# Gnash helpers:
# def trimQuotes(s) { ... }
# def leadingSpaces(s) { ... }
# def normalize(line) { ... }
# def stripComment(line) { ... }
# def keyJoin(a,b) { a + "." + b }
# def idxKey(prefix,i) { prefix + "[" + i + "]" }
# --------------------------------------------------------------------------------

# -- SAFE trim_quotes (works with set -u, empty strings, 1-char strings) ------
gnash_config_trim_quotes() {
  # Use positional param safely; do NOT rely on unset expansion
  local s; s="${1-}"  # empty if missing
  local len=${#s}
  if (( len >= 2 )); then
    # First/last chars without regex to avoid edge cases
    local first=${s:0:1}
    local last=${s: -1}
    if [[ "$first" == '"' && "$last" == '"' ]]; then
      printf '%s' "${s:1:len-2}"
      return 0
    elif [[ "$first" == "'" && "$last" == "'" ]]; then
      printf '%s' "${s:1:len-2}"
      return 0
    fi
  fi
  printf '%s' "$s"
}

# -- SAFE rstrip (no nounset pitfalls, no nested parameter magic) --------------
_gnash_config_rstrip_ws() {
  local s; s="${1-}"
  # Trim trailing spaces, tabs, CR, LF
  while :; do
    case "$s" in
      *$'\r') s="${s%$'\r'}" ;;
      *$'\n') s="${s%$'\n'}" ;;
      *$'\t') s="${s%$'\t'}" ;;
      *" "  ) s="${s% }"     ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
}

# -- normalize: CRLF -> LF, TAB -> 2 spaces, then rstrip -----------------------
gnash_config_normalize() {
  local line; line="${1-}"
  line="${line//$'\r'/}"   # remove CRs
  line="${line//$'\t'/  }" # replace tabs with 2 spaces
  _gnash_config_rstrip_ws "$line"
}

# -- leading spaces (handles empty safely) -------------------------------------
gnash_config_leading_spaces() {
  local s; s="${1-}"
  local i=0 n=${#s}
  while (( i < n )) && [[ "${s:i:1}" == " " ]]; do ((i++)); done
  echo "$i"
}

# Safer rstrip that doesn’t tickle nounset
_gnash_config_rstrip_ws() {
  local s="${1-}"
  # Trim trailing space, tab, CR, LF
  while [[ "${s}" == *$'\r' ]] || [[ "${s}" == *$'\n' ]] || [[ "${s}" == *$'\t' ]] || [[ "${s}" == *" " ]]; do
    [[ "${s}" == *$'\r' ]] && s="${s%$'\r'}"
    [[ "${s}" == *$'\n' ]] && s="${s%$'\n'}"
    [[ "${s}" == *$'\t' ]] && s="${s%$'\t'}"
    [[ "${s}" == *" "   ]] && s="${s% }"
  done
  printf '%s' "${s}"
}

gnash_config_normalize() {
  local line="${1-}"
  line="${line//$'\r'/}"         # CRLF → LF
  line="${line//$'\t'/  }"       # TAB → 2 spaces
  _gnash_config_rstrip_ws "${line}"
}

# naive trailing comment stripper (good enough for infra configs)
gnash_config_strip_comment() {
  local s="${1-}"
  if [[ "${s}" == *"#"* ]]; then
    printf '%s' "${s%%#*}"
  else
    printf '%s' "${s}"
  fi
}

gnash_config_key_join() { printf '%s.%s' "$1" "$2"; }
gnash_config_idx_key()  { printf '%s[%s]' "$1" "$2"; }

# --------------------------------------------------------------------------------
# Gnash loader core:
#
# def load(files) {
#   for (f in files) {
#     lines = fs.lines(f)
#     for (raw in lines) {
#       parse indent/section/key/list
#       CONFIG.put(...)
# --------------------------------------------------------------------------------
gnash_config_load() {
  (( $# >= 1 )) || { gnash_config_log "load: need at least one file"; return 2; }

  local file raw L indent trimmed section="" key="" key_indent=-1 idx=0

  for file in "$@"; do
    if [[ ! -f "$file" ]]; then gnash_config_log "warn: file not found: $file"; continue; fi
    gnash_config_log "load: $file"
    section=""; key=""; key_indent=-1; idx=0

    # read lines; preserve last partial line
    while IFS= read -r raw || [[ -n "${raw-}" ]]; do
      # normalize & strip comments
      L="$(gnash_config_normalize "${raw-}")"
      L="$(gnash_config_strip_comment "${L-}")"
      # skip empty/whitespace lines fast
      [[ -z "${L//[[:space:]]/}" ]] && continue

      indent="$(gnash_config_leading_spaces "${L-}")"
      # substring from indent to end (safe even when indent==len)
      trimmed="${L:${indent}}"

      # SECTION: top-level "name:"
      if (( indent == 0 )) && [[ "${trimmed}" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*):[[:space:]]*$ ]]; then
        section="${BASH_REMATCH[1]}"
        gnash_config_dbg "section=${section}"
        key=""; key_indent=-1; idx=0
        continue
      fi

      # KEY: "  key: value" or "  key:"
      if (( indent > 0 )) && [[ -n "${section}" ]] && [[ "${trimmed}" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        local v; v="$(gnash_config_trim_quotes "${BASH_REMATCH[2]-}")"
        CONFIG["$(gnash_config_key_join "${section}" "${key}")"]="${v}"
        gnash_config_dbg "set ${section}.${key}=${v}"
        key_indent="${indent}"; idx=0
        continue
      fi

      # LIST item: deeper indent than key, "- item"
      if (( indent > key_indent )) && [[ -n "${section}" && -n "${key}" ]] && [[ "${trimmed}" =~ ^-[[:space:]]*(.*)$ ]]; then
        local item; item="$(gnash_config_trim_quotes "${BASH_REMATCH[1]-}")"
        local base; base="$(gnash_config_key_join "${section}" "${key}")"
        CONFIG["$(gnash_config_idx_key "${base}" "${idx}")"]="${item}"
        gnash_config_dbg "push ${base}[${idx}]=${item}"
        ((idx++))
        continue
      fi

      gnash_config_dbg "skip: '${raw-}'"
    done < "$file"
  done

  printf '[gnash:config] parsed: %s keys\n' "${#CONFIG[@]}" >&2
}

# --------------------------------------------------------------------------------
# Gnash query API:
#
# def get(k) { CONFIG[k] }
# def bool(k) { v.lower() in true|1|yes|on }
# def list(prefix) { for k in CONFIG.keys if prefix+"[" }
# def dump()
# --------------------------------------------------------------------------------
gnash_config_get()  { local k="${1:?usage}"; [[ -n ${CONFIG[$k]+x} ]] && printf '%s\n' "${CONFIG[$k]}"; }
gnash_config_bool() { local v; v="$(gnash_config_get "$1" || true)"; [[ "${v,,}" =~ ^(true|1|yes|on)$ ]]; }
gnash_config_list() { local p="${1:?usage}"; local k; for k in "${!CONFIG[@]}"; do [[ $k == "$p"[[]* ]] && printf '%s\n' "${CONFIG[$k]}"; done; }
gnash_config_dump() {
  local k
  for k in "${!CONFIG[@]}"; do
    # If key has [index], it's a list entry → always print
    if [[ "$k" =~ \[[0-9]+\]$ ]]; then
      printf '%s=%s\n' "$k" "${CONFIG[$k]}"
      continue
    fi

    # If key has no value AND list entries exist → skip
    if [[ -z "${CONFIG[$k]}" ]]; then
      # does any key start with k[ ?
      local prefix="$k["
      local found=""
      for x in "${!CONFIG[@]}"; do
        if [[ "$x" == "$prefix"* ]]; then
          found=1
          break
        fi
      done
      [[ -n "$found" ]] && continue
    fi

    # Otherwise print scalar
    printf '%s=%s\n' "$k" "${CONFIG[$k]}"
  done | sort
}

# Return 0 if key represents a list (i.e., there exist indexed entries key[0]...), else 1
# Usage: gnash_config_is_list "dockerGroup.users"
gnash_config_is_list() {
  local base="${1:?usage: gnash_config_is_list key}" k
  local prefix="${base}["
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$prefix"* ]] && return 0
  done
  return 1
}

# Return 0 if key is a scalar (exact key present AND not a list), else 1
# Usage: gnash_config_is_scalar "dockerGroup.enabled"
gnash_config_is_scalar() {
  local key="${1:?usage: gnash_config_is_scalar key}"
  if [[ -n "${CONFIG[$key]+x}" ]] && ! gnash_config_is_list "$key"; then
    return 0
  fi
  return 1
}

# Optional: echo list length (0 if not a list)
# Usage: gnash_config_list_len "dockerGroup.users"
gnash_config_list_len() {
  local base="${1:?usage: gnash_config_list_len key}" k count=0
  local prefix="${base}["
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$prefix"* ]] && ((count++))
  done
  printf '%d\n' "$count"
}

# --------------------------------------------------------------------------------
# Gnash autoLoad():
# checks env GNASH_CONFIG, ./gnash.cfg, ~/.config/gnash/gnash.cfg, ./$(hostname).cfg
# --------------------------------------------------------------------------------
gnash_config_auto_load() {
  local files=()
  [[ -n "${GNASH_CONFIG:-}" && -f "$GNASH_CONFIG" ]] && files+=("$GNASH_CONFIG")
  [[ -f ./gnash.cfg ]] && files+=(./gnash.cfg)
  [[ -f "$HOME/.config/gnash/gnash.cfg" ]] && files+=("$HOME/.config/gnash/gnash.cfg")
  local hn="${HOSTNAME:-$(hostname -s 2>/dev/null || echo unknown)}"
  local host="./${hn%%.*}.cfg"
  [[ -f "$host" ]] && files+=("$host")
  (( ${#files[@]} )) || { gnash_config_log "autoLoad: no config files found"; return 1; }
  gnash_config_load "${files[@]}"
}

# ------------------------------------------------------------------------------
# If executed directly, auto-load and dump config
# ------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  gnash_config_log "auto-loading config…"
  gnash_config_auto_load
  gnash_config_log "dumping configuration:"
  gnash_config_dump
fi
