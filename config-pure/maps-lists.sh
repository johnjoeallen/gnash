#!/usr/bin/env bash
# maps-lists.sh — hierarchical config in Bash (real maps/lists, no dotted store)
# Safe under: set -u -o pipefail
set -uo pipefail

# ==============================================================================
# METADATA
# ==============================================================================
# Node types by dotted path:
#   CFG_TYPES["a.b"] = {map|list|scalar}
declare -Ag CFG_TYPES=()

# ==============================================================================
# UTIL
# ==============================================================================
log()   { printf '[cfg] %s\n' "$*" >&2; }
debug() { [[ "${CFG_DEBUG:-0}" == "1" ]] && printf '[cfg:dbg] %s\n' "$*" >&2; }

# Mangle a dotted path into a valid variable stem
cfgMangle() {
  local path="${1-}"
  local stem="${path//[^A-Za-z0-9_]/_}"
  stem="${stem//__/_}"; stem="${stem//__/_}"
  printf '%s' "CFG_${stem}"
}

# Get the backing variable name for a node (map/list/scalar)
cfgVar() {
  local path="${1-}" kind="${2-}"
  local stem; stem="$(cfgMangle "$path")"
  case "$kind" in
    map)    printf '%s__MAP' "$stem" ;;
    list)   printf '%s__LIST' "$stem" ;;
    scalar) printf '%s__SCALAR' "$stem" ;;
    *)      printf '%s__UNK' "$stem" ;;
  esac
}

# Split dotted path into segments, one per line
cfgSplitPath() {
  local path="${1-}" IFS='.'
  # shellcheck disable=SC2206
  local parts=($path)
  local seg
  for seg in "${parts[@]}"; do
    [[ -n "$seg" ]] && printf '%s\n' "$seg"
  done
}

# Return parent and leaf WITHOUT using blocking reads
# Prints two lines: parent\nleaf
cfgParentAndLeaf() {
  local path="${1-}"
  local parent="" leaf=""
  if [[ "$path" == *.* ]]; then
    parent="${path%.*}"
    leaf="${path##*.}"
  else
    parent=""
    leaf="$path"
  fi
  printf '%s\n%s\n' "$parent" "$leaf"
}

# Ensure all ancestor maps exist and link each parent→child as a map ("M")
cfgEnsureMapChainTo() {
  local path="${1-}"
  [[ -z "$path" ]] && return 0

  local IFS='.'
  # shellcheck disable=SC2206
  local parts=($path)
  local depth="${#parts[@]}"
  [[ "$depth" -lt 1 ]] && return 0

  local idx=0 parent="" child=""

  # Ensure root exists
  cfgEnsureMap "${parts[0]}"

  # Walk: for each step, ensure child map and mark it in parent
  for (( idx=1; idx<depth; idx++ )); do
    parent="${parts[*]:0:idx}"; parent="${parent// /.}"    # rejoin with dots
    child="${parts[$idx]}"

    cfgEnsureMap "$parent"
    local childPath="$parent.$child"
    cfgEnsureMap "$childPath"

    # Mark child in parent as a Map ('M')
    local parentVar; parentVar="$(cfgVar "$parent" map)"
    eval "$parentVar[\"$child\"]='M'"
  done
}

# (Optional) legacy helper: ensure maps up to parent; returns parent path
cfgEnsurePathMaps() {
  local path="${1-}"
  local parent=""
  if [[ "$path" == *.* ]]; then
    parent="${path%.*}"
  else
    parent=""
  fi
  [[ -n "$parent" ]] && cfgEnsureMapChainTo "$parent"
  printf '%s' "$parent"
}

# ==============================================================================
# CONSTRUCTORS
# ==============================================================================
cfgEnsureMap() {
  local path="${1-}"
  [[ -z "$path" ]] && return 0
  local t="${CFG_TYPES[$path]:-}"
  if [[ "$t" == "map" ]]; then return 0; fi
  if [[ -n "$t" && "$t" != "map" ]]; then
    log "type conflict at '$path' (was $t, want map)"; return 2
  fi
  local vn; vn="$(cfgVar "$path" map)"
  if ! declare -p "$vn" &>/dev/null; then
    declare -gA "$vn=()"
  fi
  CFG_TYPES["$path"]="map"
  debug "ensureMap: $path → $vn"
}

cfgEnsureList() {
  local path="${1-}"
  [[ -z "$path" ]] && return 0
  local t="${CFG_TYPES[$path]:-}"
  if [[ "$t" == "list" ]]; then return 0; fi
  if [[ -n "$t" && "$t" != "list" ]]; then
    log "type conflict at '$path' (was $t, want list)"; return 2
  fi
  local vn; vn="$(cfgVar "$path" list)"
  if ! declare -p "$vn" &>/dev/null; then
    declare -ga "$vn=()"
  fi
  CFG_TYPES["$path"]="list"
  debug "ensureList: $path → $vn"
}

cfgSetScalar() {
  local path="${1-}" value="${2-}"
  local t="${CFG_TYPES[$path]:-}"
  if [[ -n "$t" && "$t" != "scalar" ]]; then
    log "type conflict at '$path' (was $t, want scalar)"; return 2
  fi
  local vn; vn="$(cfgVar "$path" scalar)"
  printf -v "$vn" '%s' "$value"
  CFG_TYPES["$path"]="scalar"
  debug "setScalar: $path"
}

# ==============================================================================
# HIGH-LEVEL MUTATION
# ==============================================================================
# Put scalar at dotted path, auto-creating parents as maps
cfgPut() {
  local path="${1:?usage: cfgPut a.b.c value}" value="${2-}"
  local parent="" leaf=""
  if [[ "$path" == *.* ]]; then
    parent="${path%.*}"
    leaf="${path##*.}"
  else
    parent=""
    leaf="$path"
  fi

  if [[ -z "$parent" ]]; then
    # top-level scalar
    cfgSetScalar "$leaf" "$value"
    return
  fi

  # Ensure and link full chain to parent
  cfgEnsureMapChainTo "$parent"

  # Mark leaf in parent as Scalar ('S')
  cfgEnsureMap "$parent"
  local parentVar; parentVar="$(cfgVar "$parent" map)"
  eval "$parentVar[\"$leaf\"]='S'"

  cfgSetScalar "$path" "$value"
}

# Append scalar to list at dotted path (auto-creates map parents + list)
cfgAppend() {
  local path="${1:?usage: cfgAppend a.b.list value}" value="${2-}"
  local parent="" leaf=""
  if [[ "$path" == *.* ]]; then
    parent="${path%.*}"
    leaf="${path##*.}"
  else
    parent=""
    leaf="$path"
  fi
  [[ -z "$parent" ]] && { log "append: need parent for list ($path)"; return 2; }

  # Ensure and link full chain to parent
  cfgEnsureMapChainTo "$parent"

  cfgEnsureMap "$parent"
  cfgEnsureList "$path"

  local parentVar; parentVar="$(cfgVar "$parent" map)"
  eval "$parentVar[\"$leaf\"]='L'"

  local listVar; listVar="$(cfgVar "$path" list)"
  eval "$listVar+=(\"\$value\")"
  debug "append: $path += '$value'"
}

# Ensure a child path is a map (use before adding nested keys under it)
cfgEnsureChildMap() {
  local path="${1:?usage: cfgEnsureChildMap a.b.c}"
  local parent="" leaf=""
  if [[ "$path" == *.* ]]; then
    parent="${path%.*}"
    leaf="${path##*.}"
  else
    parent=""
    leaf="$path"
  fi

  if [[ -n "$parent" ]]; then
    # Ensure and link chain up to parent
    cfgEnsureMapChainTo "$parent"
    cfgEnsureMap "$parent"
    local parentVar; parentVar="$(cfgVar "$parent" map)"
    eval "$parentVar[\"$leaf\"]='M'"
  fi
  cfgEnsureMap "$path"
}

# ==============================================================================
# QUERY
# ==============================================================================
cfgTypeOf() { local path="${1-}"; printf '%s' "${CFG_TYPES[$path]:-}"; }

cfgIsMap()    { [[ "$(cfgTypeOf "$1")" == "map"    ]]; }
cfgIsList()   { [[ "$(cfgTypeOf "$1")" == "list"   ]]; }
cfgIsScalar() { [[ "$(cfgTypeOf "$1")" == "scalar" ]]; }

cfgGet() {
  local path="${1:?usage: cfgGet a.b.c}"
  if ! cfgIsScalar "$path"; then return 1; fi
  local vn; vn="$(cfgVar "$path" scalar)"
  eval "printf '%s\n' \"\${$vn-}\""
}

# Immediate children names of a map
cfgChildren() {
  local path="${1-}"
  if ! cfgIsMap "$path"; then return 1; fi
  local vn; vn="$(cfgVar "$path" map)"
  local k
  eval "for k in \"\${!$vn[@]}\"; do printf '%s\n' \"\$k\"; done"
}

cfgListLen() {
  local path="${1-}"
  if ! cfgIsList "$path"; then printf '0\n'; return 0; fi
  local vn n
  vn="$(cfgVar "$path" list)"
  eval "n=\${#$vn[@]}"
  printf '%s\n' "${n:-0}"
}

cfgListValues() {
  local path="${1-}"
  if ! cfgIsList "$path"; then return 1; fi
  local vn v
  vn="$(cfgVar "$path" list)"
  eval "for v in \"\${$vn[@]}\"; do printf '%s\n' \"\$v\"; done"
}

cfgIsBool() {
  local path="${1-}" v
  v="$(cfgGet "$path" 2>/dev/null || true)"
  v="${v,,}"
  [[ "$v" =~ ^(true|1|yes|on)$ ]]
}

# ==============================================================================
# DUMP (YAML-like; prints just leaf names for readability)
# ==============================================================================
cfgLeafName() {
  local path="${1-}"
  printf '%s' "${path##*.}"
}

_cfgDumpNode() {
  local path="${1-}" indent="${2-}"
  local t; t="$(cfgTypeOf "$path")"
  local name; name="$(cfgLeafName "$path")"
  case "$t" in
    scalar)
      printf '%s%s: %s\n' "$indent" "$name" "$(cfgGet "$path")"
      ;;
    map)
      printf '%s%s:\n' "$indent" "$name"
      local child
      while IFS= read -r child; do
        _cfgDumpNode "${path}.${child}" "  $indent"
      done < <(cfgChildren "$path" | sort)
      ;;
    list)
      printf '%s%s:\n' "$indent" "$name"
      local len; len="$(cfgListLen "$path")"
      local i=0 item vn
      vn="$(cfgVar "$path" list)"
      while (( i < len )); do
        eval "item=\${$vn[$i]-}"
        printf '%s  - %s\n' "$indent" "$item"
        ((i++))
      done
      ;;
    *)
      :
      ;;
  esac
}

cfgDump() {
  # Dump all roots (segment before the first '.')
  declare -A seen=()
  local p root
  for p in "${!CFG_TYPES[@]}"; do
    root="${p%%.*}"
    seen["$root"]=1
  done
  for root in $(printf '%s\n' "${!seen[@]}" | sort); do
    _cfgDumpNode "$root" ""
  done
}

# ==============================================================================
# DEMO (only when executed directly)
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # Build a small tree like your provisioning example
  cfgEnsureChildMap "provisioning.accounts.admin.groupNopass"
  cfgPut "provisioning.accounts.admin.groupNopass.enabled" "true"
  cfgPut "provisioning.accounts.admin.groupNopass.adminGroup" "admin"
  cfgPut "provisioning.accounts.admin.groupNopass.addCurrentUser" "true"
  cfgAppend "provisioning.accounts.admin.groupNopass.users" "jallen"

  cfgEnsureChildMap "provisioning.os.packages.essentials"
  cfgAppend "provisioning.os.packages.essentials.list" "curl"
  cfgAppend "provisioning.os.packages.essentials.list" "wget"
  cfgAppend "provisioning.os.packages.essentials.list" "zip"

  cfgEnsureChildMap "provisioning.os.time.ntp"
  cfgPut "provisioning.os.time.ntp.enabled" "true"

  cfgEnsureChildMap "provisioning.containers.docker.storage"
  cfgPut "provisioning.containers.docker.storage.dataRoot" "/data/docker"

  echo "== Queries =="
  echo "adminGroup: $(cfgGet 'provisioning.accounts.admin.groupNopass.adminGroup')"
  cfgIsBool "provisioning.os.time.ntp.enabled" && echo "NTP enabled ✅"
  echo "essentials count: $(cfgListLen 'provisioning.os.packages.essentials.list')"
  echo "first essential: $(cfgListValues 'provisioning.os.packages.essentials.list' | head -n1)"

  echo
  echo "== Dump =="
  cfgDump
fi
