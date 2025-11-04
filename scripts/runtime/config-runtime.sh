#!/usr/bin/env bash
# Lightweight runtime bridge that exposes Config.* helpers to transpiled Bash.
# The generated scripts already provide __gnash_load_rc and the
# __gnash_config_step_* helpers. We wrap them here and add a thin path API.

if [[ -n "${GNASH_CONFIG_RUNTIME_LOADED:-}" ]]; then
  return
fi
GNASH_CONFIG_RUNTIME_LOADED=1

__config_runtime_ensure_loaded() {
  if [[ "${GNASH_NO_RC:-0}" == "1" ]]; then
    return
  fi
  if [[ -n "${__CONFIG_RUNTIME_INITIALISED:-}" ]]; then
    return
  fi
  if command -v __gnash_load_rc >/dev/null 2>&1; then
    __gnash_load_rc
  fi
  __CONFIG_RUNTIME_INITIALISED=1
}

__config_runtime_coerce_bool() {
  local value="${1:-}"
  case "${value,,}" in
    1|y|yes|true|on) printf 'true'; return 0 ;;
    0|n|no|false|off) printf 'false'; return 0 ;;
  esac
  [[ -n "$value" ]] && printf 'true' || printf 'false'
}

__config_runtime_truthy() {
  local value
  value=$(__config_runtime_coerce_bool "$1")
  [[ "$value" == "true" ]]
}

__config_runtime_step_enabled() {
  __config_runtime_ensure_loaded
  if ! command -v __gnash_config_step_enabled >/dev/null 2>&1; then
    return 0
  fi
  __gnash_config_step_enabled "$1"
}

__config_runtime_step_value() {
  __config_runtime_ensure_loaded
  if ! command -v __gnash_config_step_value >/dev/null 2>&1; then
    return
  fi
  __gnash_config_step_value "$1" "$2"
}

__config_runtime_step_list() {
  __config_runtime_ensure_loaded
  if ! command -v __gnash_config_step_list >/dev/null 2>&1; then
    return
  fi
  __gnash_config_step_list "$1" "$2"
}

__config_runtime_global_value() {
  local key="$1"
  local var="$key"
  printf '%s' "${!var:-}"
}

__config_runtime_get_path() {
  local path="$1"
  local default="$2"
  if [[ -z "$path" ]]; then
    printf '%s' "$default"
    return
  fi
  local trimmed="${path%.}"
  IFS='.' read -r -a parts <<<"$trimmed"
  if (( ${#parts[@]} >= 1 )) && [[ "${parts[0]}" == "steps" ]]; then
    local step="${parts[1]:-}"
    if [[ -z "$step" ]]; then
      printf '%s' "$default"
      return
    fi
    if (( ${#parts[@]} == 2 )); then
      local enabled="false"
      if __config_runtime_step_enabled "$step"; then
        enabled="true"
      fi
      printf 'enabled=%s' "$enabled"
      return
    fi
    local field="${parts[2]}"
    if [[ "$field" == "enabled" ]]; then
      if __config_runtime_step_enabled "$step"; then
        printf 'true'
      else
        printf 'false'
      fi
      return
    fi
    local token
    token=$(__config_runtime_step_list "$step" "$field")
    if [[ -n "$token" ]]; then
      printf '%s' "$token"
      return
    fi
    local value
    value=$(__config_runtime_step_value "$step" "$field")
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
    printf '%s' "$default"
    return
  fi
  local global
  global=$(__config_runtime_global_value "$trimmed")
  if [[ -n "$global" ]]; then
    printf '%s' "$global"
    return
  fi
  printf '%s' "$default"
}

gnash_fn_Config_reload() {
  unset __CONFIG_RUNTIME_INITIALISED
  __config_runtime_ensure_loaded
}

gnash_fn_Config_stepEnabled() {
  local __gnash_out="${1:-}"
  local step="${2:-}"
  if __config_runtime_step_enabled "$step"; then
    return 0
  fi
  return 1
}

gnash_fn_Config_stepValue() {
  local __gnash_out="${1:-}"
  local step="${2:-}"
  local field="${3:-}"
  local value
  value=$(__config_runtime_step_value "$step" "$field")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$value"
  else
    printf '%s' "$value"
  fi
}

gnash_fn_Config_stepList() {
  local __gnash_out="${1:-}"
  local step="${2:-}"
  local field="${3:-}"
  local token
  token=$(__config_runtime_step_list "$step" "$field")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$token"
  else
    printf '%s' "$token"
  fi
}

gnash_fn_Config_boolean() {
  local __gnash_out="${1:-}"
  local step="${2:-}"
  local field="${3:-}"
  local default="${4:-}"
  local value
  value=$(__config_runtime_step_value "$step" "$field")
  if [[ -z "$value" ]]; then
    value="$default"
  fi
  local coerced
  coerced=$(__config_runtime_coerce_bool "$value")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$coerced"
  else
    printf '%s' "$coerced"
  fi
  [[ "$coerced" == "true" ]]
}

gnash_fn_Config_string() {
  local __gnash_out="${1:-}"
  local step="${2:-}"
  local field="${3:-}"
  local default="${4:-}"
  local value
  value=$(__config_runtime_step_value "$step" "$field")
  if [[ -z "$value" ]]; then
    value="$default"
  fi
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$value"
  else
    printf '%s' "$value"
  fi
}

gnash_fn_Config_get() {
  local __gnash_out="${1:-}"
  local path="${2:-}"
  local result
  result=$(__config_runtime_get_path "$path" "")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$result"
  else
    printf '%s' "$result"
  fi
}

gnash_fn_Config_getOrDefault() {
  local __gnash_out="${1:-}"
  local path="${2:-}"
  local default="${3:-}"
  local result
  result=$(__config_runtime_get_path "$path" "$default")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$result"
  else
    printf '%s' "$result"
  fi
}

gnash_fn_Config_isTrue() {
  local __gnash_out="${1:-}"
  local path="${2:-}"
  local value
  value=$(__config_runtime_get_path "$path" "")
  if __config_runtime_truthy "$value"; then
    return 0
  fi
  return 1
}

gnash_fn_Config_isTrueOrDefault() {
  local __gnash_out="${1:-}"
  local path="${2:-}"
  local default="${3:-}"
  local value
  value=$(__config_runtime_get_path "$path" "$default")
  local coerced
  coerced=$(__config_runtime_coerce_bool "$value")
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$coerced"
  else
    printf '%s' "$coerced"
  fi
  [[ "$coerced" == "true" ]]
}

gnash_fn_Config_list() {
  local __gnash_out="${1:-}"
  local path="${2:-}"
  local result
  if [[ "$path" == steps.* ]]; then
    local trimmed="${path#steps.}"
    local step="${trimmed%%.*}"
    local field="${trimmed#${step}.}"
    result=$(__config_runtime_step_list "$step" "$field")
  else
    result=$(__config_runtime_global_value "$path")
  fi
  if [[ -n ${__gnash_out:-} ]]; then
    printf -v "$__gnash_out" '%s' "$result"
  else
    printf '%s' "$result"
  fi
}
