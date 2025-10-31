#!/usr/bin/env bash
# Generated from Gnash source steps/AdminGroupNopass.gnash — DO NOT EDIT.
# Summary: Create a passwordless admin sudo group and add configured users.
#
# Configuration is loaded from the first readable RC file among:
#   ${GNASH_RC_OVERRIDE:-${GNASH_RC}}
#   ./.gnashrc, ~/.gnashrc, /etc/gnashrc
# or skipped when GNASH_NO_RC=1. RC files may define:
#   adminGroupNopass_enabled=true|false
#   declare -A adminGroupNopass=([adminGroup]="admin" [addCurrentUser]=true)
#   adminGroupNopass_users=(alice bob)
# Scalar overrides can also be provided via the same variable names.

set -euo pipefail
IFS=$'\n\t'

__gnash_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

__gnash_warn() {
  printf 'warn: %s\n' "$*" >&2
}

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

__gnash_load_rc() {
  if [[ "${GNASH_NO_RC:-0}" == "1" ]]; then
    return
  fi

  local override="${GNASH_RC_OVERRIDE:-${GNASH_RC:-}}"
  if [[ -n "$override" ]]; then
    if [[ -r "$override" ]]; then
      # shellcheck disable=SC1090
      source "$override"
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
  if declare -p "$array_name" &>/dev/null; then
    local -n ref="$array_name"
    printf '%s\n' "${ref[@]}"
    return
  fi
  local value="$(__gnash_config_step_value "$key" "$field")"
  if [[ -n "$value" ]]; then
    IFS=',' read -r -a __tmp_values <<<"$value"
    printf '%s\n' "${__tmp_values[@]}"
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

# Normalises the configured users list into a newline-delimited array.
__gnash_collect_users() {
  local key="$1"
  mapfile -t _GNASH_COLLECTED_USERS < <(__gnash_config_step_list "$key" "users")
}

# Coordinates the adminGroupNopass provisioning step: loads configuration, applies
# sudo policy drop-ins, synchronises group membership, and signals change with exit 10.
__gnash_step_key="adminGroupNopass"

__gnash_load_rc

if ! __gnash_config_step_enabled "$__gnash_step_key"; then
  printf '%s disabled via configuration\n' "$__gnash_step_key"
  exit 0
fi

admin_group="$(__gnash_config_step_value "$__gnash_step_key" "adminGroup")"
admin_group="${admin_group//[$'\r\n']}"
if [[ -z "$admin_group" ]]; then
  admin_group="admin"
fi

add_current_raw="$(__gnash_config_step_value "$__gnash_step_key" "addCurrentUser")"
if [[ -z "$add_current_raw" ]]; then
  add_current_raw="true"
fi
if __gnash_bool_falsey "$add_current_raw"; then
  add_current_user=0
else
  add_current_user=1
fi

declare -a desired_users=()
__gnash_collect_users "$__gnash_step_key"
if [[ ${#_GNASH_COLLECTED_USERS[@]} -gt 0 ]]; then
  for user in "${_GNASH_COLLECTED_USERS[@]}"; do
    user="${user//[$'\r\n']}"
    if [[ -n "$user" ]]; then
      desired_users+=("$user")
    fi
  done
fi

# Augment configured users with the interactive account when invoked under sudo.
if (( add_current_user )); then
  current_user="${SUDO_USER:-${USER:-}}"
  if [[ -n "$current_user" && "$current_user" != "root" ]]; then
    found=0
    for existing in "${desired_users[@]}"; do
      if [[ "$existing" == "$current_user" ]]; then
        found=1
        break
      fi
    done
    if (( ! found )); then
      desired_users+=("$current_user")
    fi
  fi
fi

changed=0

# Ensure the admin group exists; create it when the NSS lookup fails.
if ! getent group "$admin_group" >/dev/null 2>&1; then
  groupadd "$admin_group"
  changed=1
fi

# Ensure the canonical %sudo policy is present by writing the 00-sudo-group drop-in
# when the primary sudoers file lacks the expected entry.
if [[ -f /etc/sudoers ]]; then
  if ! grep -Eq '^%sudo[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL$' /etc/sudoers; then
    sudo_drop_path="/etc/sudoers.d/00-sudo-group"
    sudo_content="%sudo ALL=(ALL:ALL) ALL
"
    if __gnash_ensure_file_content "$sudo_drop_path" "$sudo_content" "0440"; then
      changed=1
    fi
  fi
fi

# Remove the legacy /etc/sudoers.d/nopass drop-in when it still references %sysadmin.
legacy_path="/etc/sudoers.d/nopass"
if [[ -f "$legacy_path" ]]; then
  if grep -q "%sysadmin" "$legacy_path"; then
    __gnash_backup_file "$legacy_path"
    if ! rm -f "$legacy_path"; then
      __gnash_die "Unable to remove legacy sudoers file: $legacy_path"
    fi
    changed=1
  fi
fi

# Write /etc/sudoers.d/99-admin-nopass for the target admin group when content changes.
admin_drop_path="/etc/sudoers.d/99-admin-nopass"
admin_drop_content="%${admin_group} ALL=(ALL) NOPASSWD: ALL
"
if __gnash_ensure_file_content "$admin_drop_path" "$admin_drop_content" "0440"; then
  changed=1
fi

# Synchronise configured users with the admin group, skipping missing accounts and
# adding members when they are not already present.
for user in "${desired_users[@]}"; do
  if ! id -u "$user" >/dev/null 2>&1; then
    printf 'Skipping user %s; account not found. ⚠️\n' "$user"
    continue
  fi
  if ! id -nG "$user" | tr ' ' '\n' | grep -qx "$admin_group"; then
    usermod -aG "$admin_group" "$user"
    printf 'Added %s to %s. Please log out and back in for group membership to apply. 🎉\n' "$user" "$admin_group"
    changed=1
  fi
done

if ! visudo_output=$(visudo -c 2>&1); then
  printf '%s\n' "$visudo_output" >&2
  exit 1
fi

if (( changed )); then
  exit 10
fi
exit 0
