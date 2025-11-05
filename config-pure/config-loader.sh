#!/usr/bin/env bash
# config-loader.sh — YAML-lite multi-level loader (Bash port) v7.1
# - Dotted keys for nested maps; key[n] for lists
# - Arbitrary nesting via indent stack
# - Safe under: set -u -o pipefail
set -uo pipefail

# ------------------------------------------------------------------------------
# Globals
# ------------------------------------------------------------------------------
declare -Ag CONFIG=()     # e.g. provisioning.os.packages.essentials.list[0]=curl
declare -Ag INDEX_MAP=()  # next index per list base: INDEX_MAP["a.b.list"]=N

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
log()   { printf '[gnash:config] %s\n' "$*" >&2; }
debug() { [[ "${GNASH_DEBUG:-0}" == "1" ]] && printf '[gnash:debug] %s\n' "$*" >&2; }

# ------------------------------------------------------------------------------
# String helpers (nounset-safe)
# ------------------------------------------------------------------------------
trimQuotes() {
  local text="${1-}"; local n=${#text}
  if (( n >= 2 )); then
    local a="${text:0:1}" b="${text: -1}"
    if [[ "$a" == '"' && "$b" == '"' ]] || [[ "$a" == "'" && "$b" == "'" ]]; then
      printf '%s' "${text:1:n-2}"; return 0
    fi
  fi
  printf '%s' "$text"
}

_rstripWs() {
  local s="${1-}"
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

normalize() {
  local line="${1-}"
  line="${line//$'\r'/}"
  line="${line//$'\t'/  }"
  _rstripWs "$line"
}

leadingSpaces() {
  local s="${1-}"
  local i=0 n=${#s}
  while (( i < n )) && [[ "${s:i:1}" == " " ]]; do ((i++)); done
  echo "$i"
}

stripComment() {
  local s="${1-}"
  [[ "$s" == *"#"* ]] && printf '%s' "${s%%#*}" || printf '%s' "$s"
}

joinDot() {
  local left="${1-}" right="${2-}"
  [[ -z "$left" ]] && printf '%s' "$right" || printf '%s' "$left.$right"
}

# ------------------------------------------------------------------------------
# Tiny stack helpers (arrays by name)
# ------------------------------------------------------------------------------
stackPush() { local __arr="$1" __val="${2-}"; eval "$__arr+=(\"\$__val\")"; }
stackPop()  { local __arr="$1" __len; eval "__len=\${#$__arr[@]}"; (( __len>0 )) && eval "unset '$__arr[\$((__len-1))]'"; }
stackLast() { local __arr="$1" __len; eval "__len=\${#$__arr[@]}"; (( __len>0 )) && eval "printf '%s' \"\${$__arr[\$((__len-1))]}\"" || true; }

# ------------------------------------------------------------------------------
# List index mgmt
# ------------------------------------------------------------------------------
indexOf()        { local base="${1-}"; printf '%s' "${INDEX_MAP[$base]:-0}"; }
incrementIndex() { local base="${1-}"; INDEX_MAP["$base"]=$(( ${INDEX_MAP[$base]:-0} + 1 )); }

# ------------------------------------------------------------------------------
# Core loader (indent stack; last file wins)
# ------------------------------------------------------------------------------
load() {
  (( $# >= 1 )) || { log "load: no files provided"; return 2; }

  local -a indentStack=() pathStack=()
  local file="" raw="" line="" indentLevel=0 trimmed=""

  for file in "$@"; do
    if [[ ! -f "$file" ]]; then log "warn: file not found: $file"; continue; fi
    log "load: $file"
    indentStack=(); pathStack=()

    # read lines; preserve last without trailing newline
    while IFS= read -r raw || [[ -n "${raw-}" ]]; do
      line="$(normalize "${raw-}")"
      line="$(stripComment "$line")"
      [[ -z "${line//[[:space:]]/}" ]] && continue

      indentLevel="$(leadingSpaces "$line")"
      trimmed="${line:${indentLevel}}"

      # SECTION: "name:"
      if (( indentLevel == 0 )) && [[ "$trimmed" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*):[[:space:]]*$ ]]; then
        local sectionName="${BASH_REMATCH[1]}"
        indentStack=(0)
        pathStack=("$sectionName")
        CONFIG["$sectionName"]=""              # track parent existence
        debug "section=$sectionName"
        continue
      fi

      # KEY: "key:" or "key: value"
      if [[ "$trimmed" =~ ^([A-Za-z0-9_][A-Za-z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
        local keyName="${BASH_REMATCH[1]}"
        local rawValue="${BASH_REMATCH[2]-}"
        local value; value="$(trimQuotes "$rawValue")"

        # Pop until parent indent < current indentLevel
        while ((${#indentStack[@]} > 0)); do
          local topIndent="${indentStack[${#indentStack[@]}-1]}"
          (( topIndent >= indentLevel )) && { stackPop indentStack; stackPop pathStack; } || break
        done

        local parentPath; parentPath="$(stackLast pathStack || true)"
        local currentPath=""
        if [[ -z "$parentPath" ]]; then currentPath="$keyName"; else currentPath="$(joinDot "$parentPath" "$keyName")"; fi

        stackPush indentStack "$indentLevel"
        stackPush pathStack   "$currentPath"

        CONFIG["$currentPath"]="$value"
        : "${INDEX_MAP[$currentPath]:=0}"
        debug "set $currentPath=$value"
        continue
      fi

      # LIST item: "- value" with deeper indent than last key
      if (( ${#indentStack[@]} > 0 )) && [[ "$trimmed" =~ ^-[[:space:]]*(.*)$ ]]; then
        local lastIndent="${indentStack[${#indentStack[@]}-1]}"
        if (( indentLevel > lastIndent )); then
          local item; item="$(trimQuotes "${BASH_REMATCH[1]-}")"
          local listKey; listKey="$(stackLast pathStack || true)"
          # Guard against empty listKey under -u
          if [[ -n "$listKey" ]]; then
            local idx; idx="$(indexOf "$listKey")"
            CONFIG["$listKey[$idx]"]="$item"
            incrementIndex "$listKey"
            debug "push $listKey[$idx]=$item"
          else
            debug "skip: list item without a current key"
          fi
          continue
        fi
      fi

      debug "skip: $raw"
    done < "$file"
  done

  log "parsed: ${#CONFIG[@]} keys"
}

# ------------------------------------------------------------------------------
# Dotted-depth helpers / type checks
# ------------------------------------------------------------------------------
hasChildren() {
  local prefix="${1:?usage: hasChildren prefix}" k=""
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$prefix."* ]] && return 0
    [[ "$k" == "$prefix["* ]] && return 0
  done
  return 1
}

isList() {
  local base="${1-}" k="" pref=""
  [[ -z "$base" ]] && return 1
  pref="${base}["
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$pref"* ]] && return 0
  done
  return 1
}

listLen() {
  local base="${1-}" k="" count=0 pref=""
  [[ -z "$base" ]] && { printf '0\n'; return 0; }
  pref="${base}["
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$pref"* ]] && ((count++))
  done
  printf '%d\n' "$count"
}

listValues() {
  local base="${1-}" k="" pref=""
  [[ -z "$base" ]] && return 0
  pref="${base}["
  for k in "${!CONFIG[@]}"; do
    [[ "$k" == "$pref"* ]] && printf '%s\n' "${CONFIG[$k]}"
  done
}

isScalar() {
  local keyName="${1:?usage: isScalar key}"
  [[ -n ${CONFIG[$keyName]+x} ]] && ! isList "$keyName" && ! hasChildren "$keyName"
}

# ------------------------------------------------------------------------------
# Query API
# ------------------------------------------------------------------------------
get() { local keyName="${1:?usage: get key}"; [[ -n ${CONFIG[$keyName]+x} ]] && printf '%s\n' "${CONFIG[$keyName]}"; }

isBool() {
  local keyName="${1:?usage: isBool key}" v=""
  v="$(get "$keyName" || true)"; v="${v,,}"
  [[ "$v" =~ ^(true|1|yes|on)$ ]]
}

listLen() {
  local base="${1:?usage: listLen key}" k="" count=0 pref="${base}["
  for k in "${!CONFIG[@]}"; do [[ "$k" == "$pref"* ]] && ((count++)); done
  printf '%d\n' "$count"
}

listValues() {
  local base="${1:?usage: listValues key}" k="" pref="${base}["
  for k in "${!CONFIG[@]}"; do [[ "$k" == "$pref"* ]] && printf '%s\n' "${CONFIG[$k]}"; done
}

dump() {
  local k="" v=""
  for k in "${!CONFIG[@]}"; do
    v="${CONFIG[$k]-}"
    if [[ "$k" =~ \[[0-9]+\]$ ]]; then
      printf '%s=%s\n' "$k" "$v"
    elif isScalar "$k"; then
      printf '%s=%s\n' "$k" "$v"
    fi
  done | sort
}

# ------------------------------------------------------------------------------
# Auto-discovery (env → project → user → host)
# ------------------------------------------------------------------------------
autoLoad() {
  local files=()
  [[ -n "${GNASH_CONFIG:-}" && -f "$GNASH_CONFIG" ]] && files+=("$GNASH_CONFIG")
  [[ -f ./gnash.cfg ]] && files+=(./gnash.cfg)
  [[ -f "$HOME/.config/gnash/gnash.cfg" ]] && files+=("$HOME/.config/gnash/gnash.cfg")
  local hn="${HOSTNAME:-$(hostname -s 2>/dev/null || echo unknown)}"
  local hostFile="./${hn%%.*}.cfg"
  [[ -f "$hostFile" ]] && files+=("$hostFile")
  (( ${#files[@]} )) || { log "autoLoad: no config files found"; return 1; }
  load "${files[@]}"
}

# ------------------------------------------------------------------------------
# If executed directly: auto-load & dump leaves
# ------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  log "auto-loading config…"
  autoLoad
  log "dumping configuration:"
  dump
fi
