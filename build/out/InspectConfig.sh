#!/usr/bin/env bash
# Generated from Gnash source InspectConfig.gnash — DO NOT EDIT.
set -euo pipefail
set -E
IFS=$'\n\t'

__gnash_die() {
  trap - ERR
  printf 'error: %s\n' "$*" >&2
  exit 1
}

__gnash_warn() {
  printf 'warn: %s\n' "$*" >&2
}

__gnash_debug() {
  if [[ "${GNASH_DEBUG_CONFIG:-}" == "1" ]]; then
    printf 'debug: %s\n' "$*" >&2
  fi
}

# Emits a terse trace when an unexpected command failure triggers ERR.
__gnash_trap_err() {
  local rc=$?
  local line="${BASH_LINENO[0]:-?}"
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  printf 'error: command failed (exit %s) at %s:%s\n' "$rc" "$src" "$line" >&2
}

trap '__gnash_trap_err' ERR

__gnash_bool_truthy() {
  local value="${1:-}"
  case "${value,,}" in
    1|y|yes|true|on) return 0 ;;
    0|n|no|false|off) return 1 ;;
    *) [[ -n "$value" ]] && return 0 || return 1 ;;
  esac
}

__gnash_bool_falsey() {
  __gnash_bool_truthy "$1"
  local rc=$?
  if (( rc == 0 )); then
    return 1
  fi
  return 0
}

__gnash_promote_assoc_locals() {
  local -n __gnash_seen_ref="$1"
  local __gnash_var=""
  while IFS= read -r __gnash_var; do
    [[ "$__gnash_var" == __gnash_* ]] && continue
    [[ "$__gnash_var" == BASH_* ]] && continue
    local __gnash_decl
    __gnash_decl=$(declare -p "$__gnash_var" 2>/dev/null) || continue
    [[ "$__gnash_decl" == "declare -A "* ]] || continue
    local __gnash_found=0
    for existing in "${__gnash_seen_ref[@]}"; do
      if [[ "$existing" == "$__gnash_var" ]]; then
        __gnash_found=1
        break
      fi
    done
    if (( !__gnash_found )); then
      __gnash_decl=${__gnash_decl/#declare -A /declare -gA }
      eval "$__gnash_decl"
      __gnash_seen_ref+=("$__gnash_var")
    fi
  done < <(compgen -A variable)
}

__gnash_load_rc() {
  if [[ "${GNASH_NO_RC:-0}" == "1" ]]; then
    return
  fi

  local -a __gnash_assoc_seen=()
  local __gnash_existing=""
  while IFS= read -r __gnash_existing; do
    local __gnash_decl
    __gnash_decl=$(declare -p "$__gnash_existing" 2>/dev/null) || continue
    [[ "$__gnash_decl" == "declare -A "* ]] || continue
    __gnash_assoc_seen+=("$__gnash_existing")
  done < <(compgen -A variable)

  local override="${GNASH_RC_OVERRIDE:-${GNASH_RC:-}}"
  if [[ -n "$override" ]]; then
    if [[ -r "$override" ]]; then
      # shellcheck disable=SC1090
      source "$override"
      __gnash_promote_assoc_locals __gnash_assoc_seen
    else
      __gnash_die "RC override '$override' not readable"
    fi
    return
  fi

  local candidates=(
    "./.gnashrc"
    "$HOME/.gnashrc"
    "/etc/gnashrc"
  )
  local rc=
  for candidate in "${candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      rc="$candidate"
      break
    fi
  done

  if [[ -n "$rc" ]]; then
    # shellcheck disable=SC1090
    source "$rc"
    __gnash_promote_assoc_locals __gnash_assoc_seen
  fi
}

__gnash_config_resolve() {
  local __gnash_dest="$1"
  local path="${2:-}"
  if [[ -z "$__gnash_dest" || -z "$path" ]]; then
    return 1
  fi

  local root="${path%%.*}"
  local remainder=""
  if [[ "$path" == "$root" ]]; then
    remainder=""
  else
    remainder="${path#${root}.}"
  fi

  case "$root" in
    steps)
      if __gnash_config_resolve_step "$__gnash_dest" "$remainder"; then
        return 0
      fi
      ;;
    globals)
      if __gnash_config_resolve_global "$__gnash_dest" "$remainder"; then
        return 0
      fi
      ;;
    *)
      if __gnash_config_resolve_global "$__gnash_dest" "$path"; then
        return 0
      fi
      ;;
  esac
  return 1
}

__gnash_config_resolve_step() {
  local __gnash_dest="$1"
  local remainder="${2:-}"
  if [[ -z "$__gnash_dest" || -z "$remainder" ]]; then
    return 1
  fi

  local step="${remainder%%.*}"
  if [[ -z "$step" ]]; then
    return 1
  fi

  local field=""
  if [[ "$remainder" == "$step" ]]; then
    field=""
  else
    field="${remainder#${step}.}"
  fi
  if [[ -z "$field" ]]; then
    return 1
  fi

  local assoc="${step}"
  if declare -p "$assoc" &>/dev/null; then
    # shellcheck disable=SC2178
    local -n ref="$assoc"
    if [[ "$field" == "enabled" && -n "${ref[enabled]+_}" ]]; then
      printf -v "$__gnash_dest" '%s' "${ref[enabled]}"
      return 0
    fi
    if [[ -n "${ref[$field]+_}" ]]; then
      printf -v "$__gnash_dest" '%s' "${ref[$field]}"
      return 0
    fi
  fi

  local normalized_field="${field//./_}"
  local array_name="${step}_${normalized_field}"
  if declare -p "$array_name" &>/dev/null; then
    local __gnash_tmp_token=""
    __gnash_list_from_array __gnash_tmp_token "$array_name"
    printf -v "$__gnash_dest" '%s' "$__gnash_tmp_token"
    return 0
  fi

  local var="${step}_${normalized_field}"
  if [[ -n "${!var+_}" ]]; then
    printf -v "$__gnash_dest" '%s' "${!var}"
    return 0
  fi

  if [[ "$field" == "enabled" ]]; then
    printf -v "$__gnash_dest" '%s' "true"
    return 0
  fi

  return 1
}

__gnash_config_resolve_global() {
  local __gnash_dest="$1"
  local key="${2:-}"
  if [[ -z "$__gnash_dest" || -z "$key" ]]; then
    return 1
  fi

  local var="${key//./_}"
  if [[ -n "${!var+_}" ]]; then
    printf -v "$__gnash_dest" '%s' "${!var}"
    return 0
  fi

  return 1
}

__gnash_config_get() {
  local path="$1"
  local default_value="${2:-}"
  local have_default=0
  if (( $# >= 2 )); then
    have_default=1
  fi
  local __gnash_value=""
  if __gnash_config_resolve "__gnash_value" "$path"; then
    printf '%s' "$__gnash_value"
    return 0
  fi
  if (( have_default )); then
    printf '%s' "$default_value"
  fi
  return 1
}

__gnash_config_get_or_default() {
  if (( $# < 2 )); then
    return 1
  fi
  __gnash_config_get "$1" "$2"
}

__gnash_config_list() {
  local __gnash_out_var=""
  local path=""
  if (( $# == 2 )); then
    __gnash_out_var="$1"
    path="$2"
  else
    path="$1"
  fi
  local __gnash_token=""
  local __gnash_value=""
  if __gnash_config_resolve "__gnash_value" "$path"; then
    if __gnash_is_list "$__gnash_value"; then
      __gnash_token="$__gnash_value"
    elif [[ -z "$__gnash_value" ]]; then
      __gnash_list_empty __gnash_token
    else
      __gnash_list_from_value __gnash_token "$__gnash_value"
    fi
  else
    __gnash_list_empty __gnash_token
  fi
  if [[ -n "$__gnash_out_var" ]]; then
    printf -v "$__gnash_out_var" '%s' "$__gnash_token"
  else
    printf '%s' "$__gnash_token"
  fi
}

__gnash_config_is_true_or_default() {
  local path="$1"
  local default_value="${2:-false}"
  local __gnash_value=""
  if __gnash_config_resolve "__gnash_value" "$path"; then
    if [[ -z "$__gnash_value" ]]; then
      __gnash_bool_truthy "$default_value"
      return
    fi
    __gnash_bool_truthy "$__gnash_value"
    return
  fi
  __gnash_bool_truthy "$default_value"
}

__gnash_config_is_true() {
  __gnash_config_is_true_or_default "$1" "false"
}

__gnash_config_is_true_value_or_default() {
  if __gnash_config_is_true_or_default "$1" "$2"; then
    printf 'true'
  else
    printf 'false'
  fi
}

__gnash_config_is_true_value() {
  if __gnash_config_is_true "$1"; then
    printf 'true'
  else
    printf 'false'
  fi
}

__gnash_config_is_set() {
  local path="$1"
  local __gnash_value=""
  if __gnash_config_resolve "__gnash_value" "$path"; then
    return 0
  fi
  return 1
}

__gnash_config_is_set_value() {
  if __gnash_config_is_set "$1"; then
    printf 'true'
  else
    printf 'false'
  fi
}

__gnash_config_step_enabled() {
  local key="$1"
  local path="steps.${key}.enabled"
  __gnash_config_is_true_or_default "$path" "true"
}

__gnash_config_step_value() {
  local key="$1"
  local field="$2"
  local path="steps.${key}.${field}"
  __gnash_config_get "$path"
}

__gnash_config_step_list() {
  if (( $# == 3 )); then
    local out="$1"
    local key="$2"
    local field="$3"
    local path="steps.${key}.${field}"
    __gnash_config_list "$out" "$path"
  else
    local key="$1"
    local field="$2"
    local path="steps.${key}.${field}"
    __gnash_config_list "$path"
  fi
}

__gnash_config_step_boolean() {
  local key="$1"
  local field="$2"
  local default_value="${3:-false}"
  local path="steps.${key}.${field}"
  if __gnash_config_is_true_or_default "$path" "$default_value"; then
    printf 'true'
  else
    printf 'false'
  fi
}

__GNASH_LIST_PREFIX="__gnash_list::"
__GNASH_LIST_DIR=""
__GNASH_LIST_CLEANUP_REGISTERED=0

__gnash_list_cleanup() {
  if [[ -n "$__GNASH_LIST_DIR" && -d "$__GNASH_LIST_DIR" ]]; then
    rm -rf "$__GNASH_LIST_DIR"
  fi
}

__gnash_list_init() {
  if [[ -n "$__GNASH_LIST_DIR" ]]; then
    return
  fi
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/gnash-list-XXXXXX") || __gnash_die "unable to allocate list storage"
  __GNASH_LIST_DIR="$dir"
  if (( BASH_SUBSHELL == 0 )) && (( !__GNASH_LIST_CLEANUP_REGISTERED )); then
    trap '__gnash_list_cleanup' EXIT
    __GNASH_LIST_CLEANUP_REGISTERED=1
  fi
}

__gnash_is_list() {
  local token="${1:-}"
  [[ "$token" == "$__GNASH_LIST_PREFIX"* ]]
}

__gnash_list_name() {
  local token="${1:-}"
  if ! __gnash_is_list "$token"; then
    return 1
  fi
  printf '%s' "${token#$__GNASH_LIST_PREFIX}"
}

__gnash_list_path() {
  local token="$1"
  printf '%s' "${token#$__GNASH_LIST_PREFIX}"
}

__gnash_list_alloc() {
  __gnash_list_init
  local path
  path=$(mktemp "${__GNASH_LIST_DIR}/list.XXXXXX") || __gnash_die "unable to create list buffer"
  printf '%s%s' "$__GNASH_LIST_PREFIX" "$path"
}

__gnash_list_write() {
  local token="$1"
  shift
  local path
  path=$(__gnash_list_path "$token")
  : >"$path"
  local item
  for item in "$@"; do
    printf '%s\0' "$item" >>"$path"
  done
}

__gnash_list_read() {
  local token="$1"
  local dest="$2"
  local path
  path=$(__gnash_list_path "$token")
  local -n out_ref="$dest"
  out_ref=()
  if [[ ! -f "$path" ]]; then
    return
  fi
  local __gnash_item
  while IFS= read -r -d '' __gnash_item; do
    out_ref+=("$__gnash_item")
  done <"$path"
}

__gnash_list_from_array() {
  local dest="$1"
  local src_name="$2"
  local token
  token=$(__gnash_list_alloc)
  local -n src_ref="$src_name"
  __gnash_list_write "$token" "${src_ref[@]}"
  printf -v "$dest" '%s' "$token"
}

__gnash_list_from_value() {
  local dest="$1"
  local value="${2:-}"
  local token
  token=$(__gnash_list_alloc)
  if __gnash_is_list "$value"; then
    local -a __gnash_tmp_values=()
    __gnash_list_read "$value" "__gnash_tmp_values"
    __gnash_list_write "$token" "${__gnash_tmp_values[@]}"
  elif [[ -z "$value" ]]; then
    __gnash_list_write "$token"
  elif [[ "$value" == *$'
'* ]]; then
    local -a __gnash_tmp_split=()
    IFS=$'
' read -r -a __gnash_tmp_split <<<"$value"
    __gnash_list_write "$token" "${__gnash_tmp_split[@]}"
  else
    __gnash_list_write "$token" "$value"
  fi
  printf -v "$dest" '%s' "$token"
}

__gnash_list_to_array() {
  local dest="$1"
  local token="${2:-}"
  local -n out_ref="$dest"
  out_ref=()
  if __gnash_is_list "$token"; then
    __gnash_list_read "$token" "$dest"
    return 0
  fi
  if [[ -z "$token" ]]; then
    return 0
  fi
  if [[ "$token" == *$'
'* ]]; then
    IFS=$'
' read -r -a out_ref <<<"$token"
  else
    out_ref=("$token")
  fi
}

__gnash_list_empty() {
  local token
  token=$(__gnash_list_alloc)
  __gnash_list_write "$token"
  if (( $# >= 1 )); then
    printf -v "$1" '%s' "$token"
    return
  fi
  printf '%s' "$token"
}

__gnash_list_from_values() {
  local token
  token=$(__gnash_list_alloc)
  __gnash_list_write "$token" "$@"
  printf '%s' "$token"
}

__gnash_list_append() {
  local token="${1:-}"
  local value="${2:-}"
  local -a __gnash_items=()
  __gnash_list_read "$token" "__gnash_items"
  __gnash_items+=("$value")
  __gnash_list_write "$token" "${__gnash_items[@]}"
}

__gnash_list_contains() {
  local token="${1:-}"
  local needle="${2:-}"
  if __gnash_is_list "$token"; then
    local -a __gnash_items=()
    __gnash_list_read "$token" "__gnash_items"
    local item
    for item in "${__gnash_items[@]}"; do
      if [[ "$item" == "$needle" ]]; then
        return 0
      fi
    done
    return 1
  fi
  [[ "$token" == "$needle" ]] || return 1
}

__gnash_list_contains_value() {
  if __gnash_list_contains "$1" "$2"; then
    printf 'true'
  else
    printf 'false'
  fi
}

# Determines whether a filesystem entry exists.
__gnash_file_exists() {
  local path="$1"
  [[ -e "$path" ]]
}

# Captures a timestamped backup of the managed path when it already exists.
__gnash_backup_file() {
  local path="$1"
  if ! __gnash_file_exists "$path"; then
    return
  fi
  local ts
  ts=$(date +%s)
  cp "$path" "${path}.bak.${ts}"
}

# Writes content to disk via printf, allowing multi-line strings.
__gnash_write_file() {
  local path="$1"
  local content="$2"
  printf '%s' "$content" >"$path"
}

# Ensures a file matches the desired content, backing up the previous version and
# enforcing the requested permissions when changes are applied.
__gnash_ensure_file_content() {
  local path="$1"
  local expected="$2"
  local mode="$3"
  if __gnash_file_exists "$path"; then
    local current
    current=$(cat "$path")
    if [[ "$current" == "$expected" ]]; then
      return 1
    fi
  fi
  __gnash_backup_file "$path"
  __gnash_write_file "$path" "$expected"
  chmod "$mode" "$path"
  return 0
}

# Normalises comma-delimited config entries into newline output.
__gnash_split_csv() {
  local value="$1"
  if [[ -z "$value" ]]; then
    return
  fi
  IFS=',' read -r -a _GNASH_TMP_VALUES <<<"$value"
  printf '%s\n' "${_GNASH_TMP_VALUES[@]}"
}

# Packs key/value pairs into a serialized structure string with newline-separated
# entries. Values containing newlines are base64 encoded so they can be safely
# transported via command substitution.
__gnash_struct_pack() {
  if (( $# % 2 != 0 )); then
    __gnash_die "__gnash_struct_pack requires key/value pairs"
  fi
  while (( $# > 0 )); do
    local key="$1"
    local value="$2"
    shift 2
    local encoding="raw"
    if [[ "$value" == *$'
'* ]]; then
      encoding="b64"
      value=$(printf '%s' "$value" | base64 | tr -d '\n')
    else
      value=$(printf '%s' "$value")
    fi
    printf '%s=%s:%s\n' "$key" "$encoding" "$value"
  done
}

# Retrieves a value from a serialized structure emitted by __gnash_struct_pack.
# When the stored value is base64 encoded it is transparently decoded.
__gnash_struct_get() {
  local struct="$1"
  local key="$2"
  local line
  while IFS= read -r line; do
    if [[ "${line%%=*}" == "$key" ]]; then
      local rest="${line#*=}"
      local encoding="${rest%%:*}"
      local data="${rest#*:}"
      if [[ "$encoding" == "b64" ]]; then
        printf '%s' "$data" | base64 --decode
      else
        printf '%s' "$data"
      fi
      return 0
    fi
  done <<<"$struct"
  return 1
}

__gnash_list_init

if ! command -v __gnash_invoke >/dev/null 2>&1; then
  __gnash_invoke() {
    local target="$1"
    shift
    local fn="gnash_fn_${target//./_}"
    if ! command -v "$fn" >/dev/null 2>&1; then
      __gnash_warn "invoke stub: $target"
      return 1
    fi
    "$fn" "" "$@"
  }
fi

if ! command -v __gnash_call >/dev/null 2>&1; then
  __gnash_call() {
    local target="$1"
    shift
    local fn="gnash_fn_${target//./_}"
    if ! command -v "$fn" >/dev/null 2>&1; then
      __gnash_warn "call stub: $target"
      return 1
    fi
    local __gnash_result=""
    "$fn" __gnash_result "$@"
    local rc=$?
    printf '%s\\n' "${__gnash_result}"
    return $rc
  }
fi

gnash_fn_main() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local args="${2:-}"
  echo "== Step Status =="
  __gnash_invoke 'dumpStepStatus' "adminGroupNopass"
  __gnash_invoke 'dumpStepStatus' "dockerGroup"
  __gnash_invoke 'dumpStepStatus' "essentials"
  __gnash_invoke 'dumpStepStatus' "sdkmanJava"
  echo "\n== Admin Group Settings =="
  __gnash_invoke 'dumpStepValue' "adminGroupNopass" "adminGroup"
  __gnash_invoke 'dumpStepValue' "adminGroupNopass" "addCurrentUser"
  __gnash_invoke 'dumpList' "adminGroupNopass" "users"
  echo "\n== Essentials Packages =="
  __gnash_invoke 'dumpList' "essentials" "packages"
  echo "\n== Docker Group Users =="
  __gnash_invoke 'dumpList' "dockerGroup" "users"
  echo "\n== SDKMAN Java Versions =="
  __gnash_invoke 'dumpStepValue' "sdkmanJava" "defaultJava"
  __gnash_invoke 'dumpList' "sdkmanJava" "javaVersions"
}

gnash_fn_dumpStepStatus() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local step_key="${2:-}"
  local status
  status="disabled"
  if __gnash_config_is_true_or_default "steps.${step_key}.enabled" 1; then
    status="enabled"
  fi
  echo "${step_key}: ${status}"
}

gnash_fn_dumpStepValue() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local step_key="${2:-}"
  local field="${3:-}"
  local value
  value=$(__gnash_config_get "steps.${step_key}.${field}")
  if ! [[ -n ${value:-} ]]; then
    echo "${step_key}.${field}: <empty>"
    return
  fi
  echo "${step_key}.${field}: ${value}"
}

gnash_fn_dumpList() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local step_key="${2:-}"
  local field="${3:-}"
  local value
  value=$(__gnash_config_get "steps.${step_key}.${field}")
  if ! [[ -n ${value:-} ]]; then
    echo "${step_key}.${field} raw: []"
    echo "  (no entries)"
    return
  fi
  if __gnash_is_list "${value}"; then
    echo "${step_key}.${field} raw: <list>"
    local entry_printed
    entry_printed=""
    local -a __gnash_items1=()
    __gnash_list_to_array "__gnash_items1" "${value}"
    for entry in "${__gnash_items1[@]}"; do
      echo "  - ${entry}"
      entry_printed="yes"
    done
    if ! [[ -n ${entry_printed:-} ]]; then
      echo "  (no entries)"
    fi
    return
  fi
  echo "${step_key}.${field} raw: [${value}]"
  echo "  - ${value}"
}

gnash_fn_main "" "$@"
