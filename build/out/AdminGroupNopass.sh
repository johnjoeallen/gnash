#!/usr/bin/env bash
# Generated from Gnash source AdminGroupNopass.gnash — DO NOT EDIT.
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

__gnash_config_step_enabled() {
  local key="$1"
  local var="${key}_enabled"
  local value="${!var:-}"
  if [[ -z "$value" ]]; then
    return 0
  fi
  __gnash_bool_truthy "$value"
}

__gnash_config_step_value() {
  local key="$1"
  local field="$2"
  local assoc="${key}"
  if declare -p "$assoc" &>/dev/null; then
    # shellcheck disable=SC2178
    local -n ref="$assoc"
    printf '%s' "${ref[$field]:-}"
    return
  fi
  local var="${key}_${field}"
  printf '%s' "${!var:-}"
}

__gnash_config_step_list() {
  local key="$1"
  local field="$2"
  local array_name="${key}_${field}"
  local __gnash_tmp_list=""
  if declare -p "$array_name" &>/dev/null; then
    __gnash_list_from_array __gnash_tmp_list "$array_name"
    printf '%s' "${__gnash_tmp_list}"
    return
  fi
  local value="$(__gnash_config_step_value "$key" "$field")"
  if [[ -z "$value" ]]; then
    printf '%s' "$(__gnash_list_empty)"
    return
  fi
  local -a __tmp_values=()
  IFS=',' read -r -a __tmp_values <<<"$value"
  __gnash_list_from_array __gnash_tmp_list __tmp_values
  printf '%s' "${__gnash_tmp_list}"
}

__GNASH_LIST_PREFIX="__gnash_list::"
__GNASH_LIST_COUNTER=0

__gnash_list_alloc() {
  local __gnash_out_var="${1:-}"
  local name="__gnash_list_$((++__GNASH_LIST_COUNTER))"
  declare -g -a "$name"
  local -n arr="$name"
  arr=()
  local __gnash_token="${__GNASH_LIST_PREFIX}${name}"
  if [[ -n "$__gnash_out_var" ]]; then
    printf -v "$__gnash_out_var" '%s' "$__gnash_token"
  else
    printf '%s' "$__gnash_token"
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

__gnash_list_from_array() {
  local dest="$1"
  local src_name="$2"
  local token=""
  __gnash_list_alloc token
  local array_name="${token#$__GNASH_LIST_PREFIX}"
  local -n dest_ref="$array_name"
  local -n src_ref="$src_name"
  dest_ref=("${src_ref[@]}")
  local -n out_ref="$dest"
  out_ref="$token"
}

__gnash_list_from_value() {
  local dest="$1"
  local value="${2:-}"
  local token=""
  __gnash_list_alloc token
  local array_name="${token#$__GNASH_LIST_PREFIX}"
  local -n dest_ref="$array_name"
  if __gnash_is_list "$value"; then
    local src_name
    src_name=$(__gnash_list_name "$value") || true
    if [[ -n "$src_name" ]]; then
      local -n src_ref="$src_name"
      dest_ref=("${src_ref[@]}")
    else
      dest_ref=()
    fi
  elif [[ -z "$value" ]]; then
    dest_ref=()
  elif [[ "$value" == *$'
'* ]]; then
    local -a __gnash_tmp_split=()
    IFS=$'
' read -r -a __gnash_tmp_split <<<"$value"
    dest_ref=("${__gnash_tmp_split[@]}")
  else
    dest_ref=("$value")
  fi
  local -n out_ref="$dest"
  out_ref="$token"
}

__gnash_list_to_array() {
  local dest="$1"
  local token="${2:-}"
  local -n out_ref="$dest"
  out_ref=()
  if __gnash_is_list "$token"; then
    local name
    name=$(__gnash_list_name "$token") || return 0
    local -n src_ref="$name"
    out_ref=("${src_ref[@]}")
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
  local token=""
  __gnash_list_alloc token
  printf '%s' "$token"
}

__gnash_list_from_values() {
  local token=""
  __gnash_list_alloc token
  local name="${token#$__GNASH_LIST_PREFIX}"
  local -n arr="$name"
  arr=("$@")
  printf '%s' "$token"
}

__gnash_list_append() {
  local token="${1:-}"
  local value="${2:-}"
  local name
  name=$(__gnash_list_name "$token") || return 1
  local -n arr="$name"
  arr+=("$value")
}

__gnash_list_contains() {
  local token="${1:-}"
  local needle="${2:-}"
  if __gnash_is_list "$token"; then
    local name
    name=$(__gnash_list_name "$token") || return 1
    local -n arr="$name"
    for item in "${arr[@]}"; do
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
  local step_key
  step_key="adminGroupNopass"
  if ! __gnash_invoke 'ConfigLoader.stepEnabled' "${step_key}"; then
    echo "${step_key} disabled via configuration"
    return 0
  fi
  local step_config
  step_config=$(__gnash_call 'ConfigLoader.stepConfig' "${step_key}")
  local admin_group
  admin_group=$(__gnash_call 'normalizedString' "$(__gnash_struct_get \"${step_config:-}\" "adminGroup")")
  if ! [[ -n ${admin_group:-} ]]; then
    admin_group="admin"
  fi
  local add_current_user
  add_current_user=1
  if __gnash_invoke 'stepConfig.containsKey' "addCurrentUser"; then
    add_current_user=""
    if [[ "$(__gnash_struct_get \"${step_config:-}\" "addCurrentUser")" != 0 ]]; then
      add_current_user="true"
    fi
  fi
  local users
  users=$(__gnash_call 'collectUsers' "$(__gnash_struct_get \"${step_config:-}\" "users")")
  if [[ -n ${add_current_user:-} ]]; then
    local current_user
    current_user=$(__gnash_call 'firstNonBlank' $(__gnash_call 'env' "SUDO_USER") $(__gnash_call 'env' "USER"))
    if [[ -n ${current_user:-} ]] && [[ "${current_user}" != "root" ]] && ! __gnash_list_contains "${users}" "${current_user}"; then
      __gnash_list_append "${users}" "${current_user}"
    fi
  fi
  local changed
  changed=0
  if __gnash_invoke 'ensureGroupExists' "${admin_group}"; then
    changed=1
  fi
  if __gnash_invoke 'ensureSudoDefaults'; then
    changed=1
  fi
  if __gnash_invoke 'removeLegacySudoers'; then
    changed=1
  fi
  if __gnash_invoke 'ensureAdminDropIn' "${admin_group}"; then
    changed=1
  fi
  if __gnash_invoke 'ensureUsersInGroup' "${admin_group}" "${users}"; then
    changed=1
  fi
  __gnash_try_block2() {
    __gnash_invoke 'run' "visudo -c"
  }
  __gnash_try_block2
  __gnash_try_rc1=$?
  [ $__gnash_try_rc1 -ne 0 ] && {
    local err=$__gnash_try_rc1
    if __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_invoke 'die' "visudo -c failed:\n${err.output}"
    fi
    __gnash_ret=$err
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  }
  if [[ -n ${changed:-} ]]; then
    return 10
  fi
  return 0
}

gnash_fn_ensureGroupExists() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local group_name="${2:-}"
  __gnash_try_block4() {
    __gnash_invoke 'run' "getent group ${group_name}"
    return 0
  }
  __gnash_try_block4
  __gnash_try_rc3=$?
  [ $__gnash_try_rc3 -ne 0 ] && {
    local err=$__gnash_try_rc3
    if ! __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
    if ! __gnash_invoke 'missingLookup' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
  }
  __gnash_invoke 'run' "groupadd ${group_name}"
  return 1
}

gnash_fn_ensureSudoDefaults() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local sudoers_path
  sudoers_path="/etc/sudoers"
  if ! __gnash_invoke 'fileExists' "${sudoers_path}"; then
    return 0
  fi
  __gnash_try_block6() {
    __gnash_invoke 'run' "grep -Eq '^%sudo\\s+ALL=\\(ALL(:ALL)?\\)\\s+ALL$' ${sudoers_path}"
    return 0
  }
  __gnash_try_block6
  __gnash_try_rc5=$?
  [ $__gnash_try_rc5 -ne 0 ] && {
    local err=$__gnash_try_rc5
    if ! __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
    if [[ "$(__gnash_struct_get \"${err:-}\" 'exitCode')" != 1 ]]; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
  }
  local sudo_drop_path
  sudo_drop_path="/etc/sudoers.d/00-sudo-group"
  local content
  content="%sudo ALL=(ALL:ALL) ALL\n"
  __gnash_ret=$(__gnash_call 'ensureFileContent' "${sudo_drop_path}" "${content}" "0440")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_removeLegacySudoers() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local legacy_path
  legacy_path="/etc/sudoers.d/nopass"
  if ! __gnash_invoke 'fileExists' "${legacy_path}"; then
    return 0
  fi
  local content
  content=$(__gnash_call 'run' "cat ${legacy_path}")
  if ! __gnash_list_contains "${content}" "%sysadmin"; then
    return 0
  fi
  __gnash_invoke 'backupFile' "${legacy_path}"
  __gnash_try_block8() {
    __gnash_invoke 'run' "rm -f ${legacy_path}"
  }
  __gnash_try_block8
  __gnash_try_rc7=$?
  [ $__gnash_try_rc7 -ne 0 ] && {
    local err=$__gnash_try_rc7
    if __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_invoke 'die' "Unable to remove legacy sudoers file: ${legacy_path}\n${err.output}"
    fi
    __gnash_ret=$err
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  }
  return 1
}

gnash_fn_ensureAdminDropIn() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local admin_group="${2:-}"
  local path
  path="/etc/sudoers.d/99-admin-nopass"
  local content
  content="%${admin_group} ALL=(ALL) NOPASSWD: ALL\n"
  __gnash_ret=$(__gnash_call 'ensureFileContent' "${path}" "${content}" "0440")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_ensureUsersInGroup() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local group="${2:-}"
  local users="${3:-}"
  local changed
  changed=0
  local -a __gnash_items9=()
  __gnash_list_to_array __gnash_items9 "${users}"
  for user in "${__gnash_items9[@]}"; do
    if ! __gnash_invoke 'userExists' "${user}"; then
      echo "Skipping user ${user}; account not found. ⚠️"
      continue
    fi
    __gnash_try_block11() {
      __gnash_invoke 'run' "id -nG ${user} | tr ' ' '\\n' | grep -qx ${group}"
    }
    __gnash_try_block11
    __gnash_try_rc10=$?
    [ $__gnash_try_rc10 -ne 0 ] && {
      local err=$__gnash_try_rc10
      if ! __gnash_invoke 'isCommandError' "${err}"; then
        __gnash_ret=$err
        if [[ -n ${__gnash_out:-} ]]; then
          printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
        fi
        return 1
      fi
      if [[ "$(__gnash_struct_get \"${err:-}\" 'exitCode')" != 1 ]]; then
        __gnash_ret=$err
        if [[ -n ${__gnash_out:-} ]]; then
          printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
        fi
        return 1
      fi
      __gnash_invoke 'run' "usermod -aG ${group} ${user}"
      echo "Added ${user} to ${group}. Please log out and back in for group membership to apply. 🎉"
      changed=1
      continue
    }
  done
  __gnash_ret=$changed
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_userExists() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local user="${2:-}"
  __gnash_try_block13() {
    __gnash_invoke 'run' "id -u ${user}"
    return 1
  }
  __gnash_try_block13
  __gnash_try_rc12=$?
  [ $__gnash_try_rc12 -ne 0 ] && {
    local err=$__gnash_try_rc12
    if ! __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
    if [[ "$(__gnash_struct_get \"${err:-}\" 'exitCode')" == 1 ]]; then
      return 0
    fi
    __gnash_ret=$err
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  }
}

gnash_fn_ensureFileContent() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local path="${2:-}"
  local expected="${3:-}"
  local mode="${4:-}"
  if __gnash_invoke 'fileExists' "${path}"; then
    local current
    current=$(__gnash_call 'run' "cat ${path}")
    if [[ "${current}" == "${expected}" ]]; then
      return 0
    fi
  fi
  __gnash_invoke 'backupFile' "${path}"
  __gnash_invoke 'writeFile' "${path}" "${expected}"
  __gnash_invoke 'run' "chmod ${mode} ${path}"
  return 1
}

gnash_fn_writeFile() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local path="${2:-}"
  local content="${3:-}"
  local payload
  payload=$(__gnash_call 'escapeSingleQuotes' "${content}")
  __gnash_invoke 'run' "printf '%s' '${payload}' > ${path}"
}

gnash_fn_fileExists() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local path="${2:-}"
  __gnash_try_block15() {
    __gnash_invoke 'run' "test -e ${path}"
    return 1
  }
  __gnash_try_block15
  __gnash_try_rc14=$?
  [ $__gnash_try_rc14 -ne 0 ] && {
    local err=$__gnash_try_rc14
    if ! __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
    if [[ "$(__gnash_struct_get \"${err:-}\" 'exitCode')" == 1 ]]; then
      return 0
    fi
    __gnash_ret=$err
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  }
}

gnash_fn_backupFile() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local path="${2:-}"
  if ! __gnash_invoke 'fileExists' "${path}"; then
    return
  fi
  local stamp
  stamp=$(__gnash_call 'run' "date +%s")
  local ts
  ts=$(__gnash_call 'stamp.trim')
  __gnash_invoke 'run' "cp ${path} ${path}.bak.${ts}"
}

gnash_fn_collectUsers() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local value="${2:-}"
  local users
  users=$(__gnash_list_empty)
  if ! [[ -n ${value:-} ]]; then
    __gnash_ret=$users
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  fi
  if __gnash_is_list "${value}"; then
    local -a __gnash_items16=()
    __gnash_list_to_array __gnash_items16 "${value}"
    for entry in "${__gnash_items16[@]}"; do
      __gnash_invoke 'addNormalizedUser' "${users}" "${entry}"
    done
  else
    __gnash_invoke 'addNormalizedUser' "${users}" "${value}"
  fi
  __gnash_ret=$users
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_addNormalizedUser() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local users="${2:-}"
  local value="${3:-}"
  if ! [[ -n ${value:-} ]]; then
    return
  fi
  local name
  name=$(__gnash_call 'value.toString.trim')
  if ! [[ -n ${name:-} ]]; then
    return
  fi
  if ! __gnash_list_contains "${users}" "${name}"; then
    __gnash_list_append "${users}" "${name}"
  fi
}

gnash_fn_normalizedString() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local value="${2:-}"
  if ! [[ -n ${value:-} ]]; then
    __gnash_ret=""
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  fi
  local result
  result=$(__gnash_call 'value.toString.trim')
  if ! [[ -n ${result:-} ]]; then
    __gnash_ret=""
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  fi
  __gnash_ret=$result
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_firstNonBlank() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local a="${2:-}"
  local b="${3:-}"
  if [[ -n ${a:-} ]] && __gnash_invoke 'a.toString.trim'; then
    __gnash_ret=$(__gnash_call 'a.toString.trim')
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  fi
  if [[ -n ${b:-} ]] && __gnash_invoke 'b.toString.trim'; then
    __gnash_ret=$(__gnash_call 'b.toString.trim')
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  fi
  __gnash_ret=""
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_env() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local name="${2:-}"
  __gnash_try_block18() {
    local value
    value=$(__gnash_call 'run' "printenv ${name}")
    __gnash_ret=$(__gnash_call 'value.trim')
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 0
  }
  __gnash_try_block18
  __gnash_try_rc17=$?
  [ $__gnash_try_rc17 -ne 0 ] && {
    local err=$__gnash_try_rc17
    if ! __gnash_invoke 'isCommandError' "${err}"; then
      __gnash_ret=$err
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 1
    fi
    if [[ "$(__gnash_struct_get \"${err:-}\" 'exitCode')" == 1 ]]; then
      __gnash_ret=""
      if [[ -n ${__gnash_out:-} ]]; then
        printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
      fi
      return 0
    fi
    __gnash_ret=$err
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  }
}

gnash_fn_escapeSingleQuotes() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local text="${2:-}"
  __gnash_ret=$(__gnash_call 'text.replace' "'" "'\"'\"'")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_run() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local command="${2:-}"
  local output
  output=$(${command} 2>&1)
  local exit_code
  exit_code=$?
  if [[ "${exit_code}" != 0 ]]; then
    __gnash_ret=$(__gnash_call 'commandError' "${command}" "${exit_code}" "${output}")
    if [[ -n ${__gnash_out:-} ]]; then
      printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
    fi
    return 1
  fi
  __gnash_ret=$output
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_missingLookup() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local err="${2:-}"
  # TODO return err.exitCode==1||err.exitCode==2
}

gnash_fn_commandError() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local command="${2:-}"
  local exit_code="${3:-}"
  local output="${4:-}"
  __gnash_ret="$(__gnash_struct_pack 'kind' "CommandError" 'command' "${command}" 'exitCode' "${exit_code}" 'output' "${output}")"
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "${__gnash_out}" '%s' "${__gnash_ret}"
  fi
  return 0
}

gnash_fn_isCommandError() {
  local __gnash_out="${1:-}"
  local __gnash_ret=""
  local err="${2:-}"
  # TODO return errisMap&&err.get("kind")=="CommandError"
}

gnash_fn_main "" "$@"
