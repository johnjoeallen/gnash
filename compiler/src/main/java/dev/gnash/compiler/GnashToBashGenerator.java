package dev.gnash.compiler;

import dev.gnash.antlr.GnashBaseVisitor;
import dev.gnash.antlr.GnashParser;
import org.antlr.v4.runtime.tree.ParseTree;
import org.antlr.v4.runtime.tree.TerminalNode;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.StringJoiner;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A minimal parse-tree visitor that demonstrates how Gnash source could be
 * transformed into Bash. For now this simply records high-level structure and
 * emits a stub shell script so that the parser integration can be validated.
 * <p>
 * Future iterations can replace the stub emission logic with a full code
 * generator that mirrors the behaviour of the reference Bash output found
 * under build/app.
 */
final class GnashToBashGenerator extends GnashBaseVisitor<Void> {

    private static final class FunctionInfo {
        final String name;
        final List<String> parameters;
        final GnashParser.BlockContext body;

        FunctionInfo(String name, List<String> parameters, GnashParser.BlockContext body) {
            this.name = name;
            this.parameters = parameters;
            this.body = body;
        }
    }

    private static final class Condition {
        final String text;

        Condition(String text) {
            this.text = text.trim();
        }

        Condition negate() {
            if (text.startsWith("!")) {
                return new Condition(text.substring(1).trim());
            }
            if (text.startsWith("[[") || text.startsWith("[")) {
                return new Condition("! " + text);
            }
            if (text.startsWith("__gnash") || text.startsWith("echo") || text.startsWith("$(")) {
                return new Condition("! " + text);
            }
            return new Condition("! (" + text + ")");
        }

        String format() {
            return text;
        }

        Condition combine(Condition other, String operator) {
            return new Condition(this.text + " " + operator + " " + other.text);
        }
    }

    private static final class Call {
        final String target;
        final List<String> args;

        Call(String target, List<String> args) {
            this.target = target;
            this.args = args;
        }
    }

    private final List<FunctionInfo> functions = new ArrayList<>();
    private final List<GnashParser.ExpressionStatementContext> globalStatements = new ArrayList<>();
    private int tempCounter = 0;

    private static final String SUPPORT_FUNCTIONS = """
__gnash_die() {
  trap - ERR
  printf 'error: %s\\n' "$*" >&2
  exit 1
}

__gnash_warn() {
  printf 'warn: %s\\n' "$*" >&2
}

__gnash_debug() {
  if [[ "${GNASH_DEBUG_CONFIG:-}" == "1" ]]; then
    printf 'debug: %s\\n' "$*" >&2
  fi
}

# Emits a terse trace when an unexpected command failure triggers ERR.
__gnash_trap_err() {
  local rc=$?
  local line="${BASH_LINENO[0]:-?}"
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  printf 'error: command failed (exit %s) at %s:%s\\n' "$rc" "$src" "$line" >&2
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
  local __gnash_out_var=""
  local key
  local field
  if (( $# == 3 )); then
    __gnash_out_var="$1"
    key="$2"
    field="$3"
  else
    key="$1"
    field="$2"
  fi
  local array_name="${key}_${field}"
  local __gnash_tmp_list=""
  if declare -p "$array_name" &>/dev/null; then
    __gnash_list_from_array __gnash_tmp_list "$array_name"
  else
    local value="$(__gnash_config_step_value "$key" "$field")"
    if [[ -z "$value" ]]; then
      __gnash_list_empty __gnash_tmp_list
    else
      local -a __tmp_values=()
      IFS=',' read -r -a __tmp_values <<<"$value"
      __gnash_list_from_array __gnash_tmp_list __tmp_values
    fi
  fi
  if [[ -n "$__gnash_out_var" ]]; then
    printf -v "$__gnash_out_var" '%s' "${__gnash_tmp_list}"
  else
    printf '%s' "${__gnash_tmp_list}"
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
    printf '%s\\0' "$item" >>"$path"
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
  elif [[ "$value" == *$'\n'* ]]; then
    local -a __gnash_tmp_split=()
    IFS=$'\n' read -r -a __gnash_tmp_split <<<"$value"
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
  if [[ "$token" == *$'\n'* ]]; then
    IFS=$'\n' read -r -a out_ref <<<"$token"
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
  printf '%s\\n' "${_GNASH_TMP_VALUES[@]}"
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
    if [[ "$value" == *$'\n'* ]]; then
      encoding="b64"
      value=$(printf '%s' "$value" | base64 | tr -d '\\n')
    else
      value=$(printf '%s' "$value")
    fi
    printf '%s=%s:%s\\n' "$key" "$encoding" "$value"
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
""";

    private static final Pattern INTERPOLATION_PATTERN = Pattern.compile("\\$\\{([A-Za-z_][A-Za-z0-9_]*)}");
    private static final String EMPTY_LIST_SENTINEL = "$(__gnash_list_empty)";
    private static final String EMPTY_MAP_SENTINEL = "__GNASH_EMPTY_MAP__";
    private static final String OUT_PARAM_NAME = "__gnash_out";
    private static final String RETURN_VAR_NAME = "__gnash_ret";

    String generate(ParseTree tree, Path sourcePath) {
        Objects.requireNonNull(tree, "tree");
        Objects.requireNonNull(sourcePath, "sourcePath");

        // Walk the parse tree once to collect top-level metadata.
        visit(tree);

        boolean runnable = functions.stream().anyMatch(fn -> "main".equals(fn.name));

        StringBuilder script = new StringBuilder();
        if (runnable) {
            script.append("#!/usr/bin/env bash\n");
            script.append("# Generated from Gnash source ").append(sourcePath.getFileName()).append(" — DO NOT EDIT.\n");
            script.append("set -euo pipefail\n");
            script.append("set -E\n");
            script.append("IFS=$'\\n\\t'\n");
            script.append("\n");
            script.append(SUPPORT_FUNCTIONS);
            script.append("\n");
            script.append("__gnash_list_init\n");
            script.append("\n");
            script.append("if ! command -v __gnash_invoke >/dev/null 2>&1; then\n");
            script.append("  __gnash_invoke() {\n");
            script.append("    local target=\"$1\"\n");
            script.append("    shift\n");
            script.append("    local fn=\"gnash_fn_${target//./_}\"\n");
            script.append("    if ! command -v \"$fn\" >/dev/null 2>&1; then\n");
            script.append("      __gnash_warn \"invoke stub: $target\"\n");
            script.append("      return 1\n");
            script.append("    fi\n");
            script.append("    \"$fn\" \"\" \"$@\"\n");
            script.append("  }\n");
            script.append("fi\n\n");
            script.append("if ! command -v __gnash_call >/dev/null 2>&1; then\n");
            script.append("  __gnash_call() {\n");
            script.append("    local target=\"$1\"\n");
            script.append("    shift\n");
            script.append("    local fn=\"gnash_fn_${target//./_}\"\n");
            script.append("    if ! command -v \"$fn\" >/dev/null 2>&1; then\n");
            script.append("      __gnash_warn \"call stub: $target\"\n");
            script.append("      return 1\n");
            script.append("    fi\n");
            script.append("    local __gnash_result=\"\"\n");
            script.append("    \"$fn\" __gnash_result \"$@\"\n");
            script.append("    local rc=$?\n");
            script.append("    printf '%s\\\\n' \"${__gnash_result}\"\n");
            script.append("    return $rc\n");
            script.append("  }\n");
            script.append("fi\n\n");
        } else {
            script.append("# Library generated from Gnash source ")
                  .append(sourcePath.getFileName())
                  .append(" — requires runtime helpers to be sourced from a runnable script.\n\n");
        }

        renderGlobalStatements(script);

        for (FunctionInfo fn : functions) {
            renderFunction(script, fn);
        }

        if (runnable) {
            boolean hasMain = functions.stream().anyMatch(fn -> "main".equals(fn.name));
            if (hasMain) {
                script.append("gnash_fn_main \"\" \"$@\"\n");
            } else {
                script.append("# runnable script generated without main(); nothing to invoke\n");
            }
        }

        return script.toString();
    }

    @Override
    public Void visitFunctionDecl(GnashParser.FunctionDeclContext ctx) {
        String name = ctx.IDENTIFIER().getText();
        List<String> params = new ArrayList<>();
        GnashParser.ParameterListContext plist = ctx.parameterList();
        if (plist != null) {
            for (GnashParser.ParameterContext parameterContext : plist.parameter()) {
                params.add(parameterContext.getText());
            }
        }
        functions.add(new FunctionInfo(name, params, ctx.block()));
        return super.visitFunctionDecl(ctx);
    }

    @Override
    public Void visitGlobalStatement(GnashParser.GlobalStatementContext ctx) {
        if (ctx.expressionStatement() != null) {
            globalStatements.add(ctx.expressionStatement());
        }
        return super.visitGlobalStatement(ctx);
    }

    private void renderFunction(StringBuilder script, FunctionInfo fn) {
        script.append("gnash_fn_").append(fn.name).append("() {\n");
        Set<String> locals = new HashSet<>();
        indent(script, 1);
        script.append("local ").append(OUT_PARAM_NAME).append("=\"${1:-}\"\n");
        locals.add(OUT_PARAM_NAME);
        indent(script, 1);
        script.append("local ").append(RETURN_VAR_NAME).append("=\"\"\n");
        locals.add(RETURN_VAR_NAME);
        int index = 2;
        for (String param : fn.parameters) {
            String bashParam = toBashIdentifier(param);
            indent(script, 1);
            script.append("local ").append(bashParam).append("=\"${").append(index).append(":-}\"\n");
            locals.add(bashParam);
            index++;
        }
        if (fn.body != null) {
            renderBlock(script, fn.body, 1, locals);
        } else {
            indent(script, 1);
            script.append("# TODO: missing function body\n");
        }
        script.append("}\n\n");
    }

    private void renderGlobalStatements(StringBuilder script) {
        if (globalStatements.isEmpty()) {
            return;
        }
        for (GnashParser.ExpressionStatementContext ctx : globalStatements) {
            if (!renderExpressionStatement(script, ctx, 0, null)) {
                appendUnsupported(script, 0, ctx.getText());
            }
        }
        script.append('\n');
    }

    private void renderBlock(StringBuilder script, GnashParser.BlockContext block, int indentLevel, Set<String> locals) {
        for (GnashParser.StatementContext statement : block.statement()) {
            renderStatement(script, statement, indentLevel, locals);
        }
    }

    private void renderStatement(StringBuilder script, GnashParser.StatementContext statement, int indentLevel, Set<String> locals) {
        if (statement.expressionStatement() != null) {
            boolean handled = renderExpressionStatement(script, statement.expressionStatement(), indentLevel, locals);
            if (!handled) {
                appendUnsupported(script, indentLevel, statement.getText());
            }
            return;
        }
        if (statement.ifStatement() != null) {
            renderIfStatement(script, statement.ifStatement(), indentLevel, locals);
            return;
        }
        if (statement.tryStatement() != null) {
            renderTryStatement(script, statement.tryStatement(), indentLevel, locals);
            return;
        }
        if (statement.throwStatement() != null) {
            renderThrowStatement(script, statement.throwStatement(), indentLevel);
            return;
        }
        if (statement.continueStatement() != null) {
            indent(script, indentLevel);
            script.append("continue\n");
            return;
        }
        if (statement.forStatement() != null) {
            renderForStatement(script, statement.forStatement(), indentLevel, locals);
            return;
        }
        if (statement.returnStatement() != null) {
            renderReturnStatement(script, statement.returnStatement(), indentLevel);
            return;
        }
        appendUnsupported(script, indentLevel, statement.getText());
    }

    private boolean renderExpressionStatement(StringBuilder script,
                                              GnashParser.ExpressionStatementContext ctx,
                                              int indentLevel,
                                              Set<String> locals) {
        GnashParser.ExpressionContext expr = ctx.expression();
        if (expr == null) {
            return false;
        }
        GnashParser.AssignmentContext assignment = expr.assignment();
        if (assignment != null && renderAssignment(script, assignment, indentLevel, locals)) {
            return true;
        }
        Call call = tryRenderCall(expr);
        if (call != null) {
            String command = renderCallCommand(call);
            if (command != null) {
                indent(script, indentLevel);
                script.append(command).append('\n');
                return true;
            }
        }
        return false;
    }

    private void renderIfStatement(StringBuilder script,
                                   GnashParser.IfStatementContext ctx,
                                   int indentLevel,
                                   Set<String> locals) {
        Condition condition = renderCondition(ctx.expression());
        boolean placeholder = condition == null;
        String conditionText = placeholder ? ":" : condition.format();
        indent(script, indentLevel);
        script.append("if ").append(conditionText).append("; then\n");
        if (placeholder) {
            indent(script, indentLevel + 1);
            script.append("# TODO condition: ").append(truncate(ctx.expression().getText())).append('\n');
        }

        Set<String> thenLocals = new HashSet<>(locals);
        renderBlock(script, ctx.block(0), indentLevel + 1, thenLocals);
        locals.addAll(thenLocals);

        if (ctx.ifStatement() != null) {
            renderElseIf(script, ctx.ifStatement(), indentLevel, locals);
        } else if (ctx.block().size() > 1) {
            renderElseBlock(script, ctx.block(1), indentLevel, locals);
        }

        indent(script, indentLevel);
        script.append("fi\n");
    }

    private void renderElseIf(StringBuilder script,
                              GnashParser.IfStatementContext ctx,
                              int indentLevel,
                              Set<String> locals) {
        Condition condition = renderCondition(ctx.expression());
        boolean placeholder = condition == null;
        String conditionText = placeholder ? ":" : condition.format();
        indent(script, indentLevel);
        script.append("elif ").append(conditionText).append("; then\n");
        if (placeholder) {
            indent(script, indentLevel + 1);
            script.append("# TODO condition: ").append(truncate(ctx.expression().getText())).append('\n');
        }

        Set<String> branchLocals = new HashSet<>(locals);
        renderBlock(script, ctx.block(0), indentLevel + 1, branchLocals);
        locals.addAll(branchLocals);

        if (ctx.ifStatement() != null) {
            renderElseIf(script, ctx.ifStatement(), indentLevel, locals);
        } else if (ctx.block().size() > 1) {
            renderElseBlock(script, ctx.block(1), indentLevel, locals);
        }
    }

    private void renderElseBlock(StringBuilder script,
                                 GnashParser.BlockContext block,
                                 int indentLevel,
                                 Set<String> locals) {
        indent(script, indentLevel);
        script.append("else\n");
        Set<String> elseLocals = new HashSet<>(locals);
        renderBlock(script, block, indentLevel + 1, elseLocals);
        locals.addAll(elseLocals);
    }

    private void renderTryStatement(StringBuilder script,
                                    GnashParser.TryStatementContext ctx,
                                    int indentLevel,
                                    Set<String> locals) {
        String rcVar = nextTempVar("__gnash_try_rc");
        String blockVar = nextTempVar("__gnash_try_block");
        indent(script, indentLevel);
        script.append(blockVar).append("() {\n");
        renderBlock(script, ctx.block(), indentLevel + 1, locals == null ? null : new HashSet<>(locals));
        indent(script, indentLevel);
        script.append("}\n");
        indent(script, indentLevel);
        script.append(blockVar).append("\n");
        indent(script, indentLevel);
        script.append(rcVar).append("=$?\n");

        List<GnashParser.CatchClauseContext> catches = ctx.catchClause();
        if (!catches.isEmpty()) {
            GnashParser.CatchClauseContext catchCtx = catches.get(0);
            String catchVar = toBashIdentifier(catchCtx.IDENTIFIER().getText());
            Set<String> catchLocals = locals == null ? null : new HashSet<>(locals);
            indent(script, indentLevel);
            script.append("[ $").append(rcVar).append(" -ne 0 ] && {\n");
            indent(script, indentLevel + 1);
            if (catchLocals != null && !catchLocals.contains(catchVar)) {
                script.append("local ").append(catchVar).append("=$").append(rcVar).append('\n');
                catchLocals.add(catchVar);
            } else {
                script.append(catchVar).append("=$").append(rcVar).append('\n');
            }
            renderBlock(script, catchCtx.block(), indentLevel + 1, catchLocals);
            if (locals != null) {
                locals.add(catchVar);
            }
            indent(script, indentLevel);
            script.append("}\n");
        }

        if (ctx.finallyClause() != null) {
            renderBlock(script, ctx.finallyClause().block(), indentLevel, locals);
        }
    }

    private void renderForStatement(StringBuilder script,
                                    GnashParser.ForStatementContext ctx,
                                    int indentLevel,
                                    Set<String> locals) {
        String loopVar = toBashIdentifier(ctx.IDENTIFIER().getText());
        String iterableValue = renderExpression(ctx.expression());
        if (iterableValue == null) {
            appendUnsupported(script, indentLevel, ctx.getText());
            return;
        }
        String itemsVar = nextTempVar("__gnash_items");
        indent(script, indentLevel);
        script.append("local -a ").append(itemsVar).append("=()\n");
        indent(script, indentLevel);
        script.append("__gnash_list_to_array ").append('"').append(itemsVar).append('"').append(' ').append(iterableValue).append('\n');
        indent(script, indentLevel);
        script.append("for ").append(loopVar).append(" in \"${").append(itemsVar).append("[@]}\"; do\n");
        Set<String> bodyLocals = locals == null ? null : new HashSet<>(locals);
        if (bodyLocals != null) {
            bodyLocals.add(loopVar);
        }
        renderBlock(script, ctx.block(), indentLevel + 1, bodyLocals);
        if (locals != null && bodyLocals != null) {
            locals.addAll(bodyLocals);
        }
        indent(script, indentLevel);
        script.append("done\n");
    }

    private void renderReturnStatement(StringBuilder script,
                                       GnashParser.ReturnStatementContext ctx,
                                       int indentLevel) {
        if (ctx.expression() == null) {
            indent(script, indentLevel);
            script.append("return\n");
            return;
        }
        String value = renderExpression(ctx.expression());
        value = unwrapIdentifier(value);
        if (value != null) {
            if (isExitCodeValue(value)) {
                indent(script, indentLevel);
                script.append("return ").append(value).append('\n');
            } else {
                emitStringReturn(script, indentLevel, value);
            }
        } else {
            indent(script, indentLevel);
            script.append("# TODO return ").append(truncate(ctx.expression().getText())).append('\n');
        }
    }

    private void renderThrowStatement(StringBuilder script,
                                      GnashParser.ThrowStatementContext ctx,
                                      int indentLevel) {
        String value = null;
        if (ctx.expression() != null) {
            value = renderExpression(ctx.expression());
        }
        if (value == null) {
            appendUnsupported(script, indentLevel, ctx.getText());
            return;
        }
        value = unwrapIdentifier(value);
        emitStringReturn(script, indentLevel, value, 1);
    }

    private boolean renderAssignment(StringBuilder script,
                                     GnashParser.AssignmentContext assignment,
                                     int indentLevel,
                                     Set<String> locals) {
        if (assignment.destructuringPattern() == null) {
            return false;
        }
        GnashParser.DestructuringPatternContext pattern = assignment.destructuringPattern();
        List<TerminalNode> identifiers = pattern.IDENTIFIER();
        if (identifiers.isEmpty()) {
            return false;
        }
        GnashParser.AssignmentContext valueAssignment = assignment.assignment();
        String rhs = renderAssignmentValue(valueAssignment);
        if (identifiers.size() > 1) {
                if (rhs != null && identifiers.size() == 2) {
                String firstVar = toBashIdentifier(identifiers.get(0).getText());
                String secondVar = toBashIdentifier(identifiers.get(1).getText());
                writeAssignment(script, indentLevel, locals, firstVar, rhs);
                writeAssignment(script, indentLevel, locals, secondVar, "$?");
                return true;
            }
            if (renderDestructuringAssignment(script, assignment, indentLevel, locals, identifiers)) {
                return true;
            }
            return false;
        }
        String varName = identifiers.get(0).getText();
        String bashVar = toBashIdentifier(varName);
        if (rhs == null) {
            Condition boolCondition = renderConditionFromAssignment(valueAssignment);
            if (boolCondition != null) {
                writeAssignment(script, indentLevel, locals, bashVar, "\"\"");
                indent(script, indentLevel);
                script.append("if ").append(boolCondition.format()).append("; then\n");
                writeAssignment(script, indentLevel + 1, locals, bashVar, "\"true\"");
                indent(script, indentLevel);
                script.append("fi\n");
                return true;
            }
            return false;
        }
        if (EMPTY_MAP_SENTINEL.equals(rhs)) {
            indent(script, indentLevel);
            if (locals != null) {
                if (!locals.contains(bashVar)) {
                    script.append("local -A ");
                    locals.add(bashVar);
                } else {
                    script.append(bashVar).append("=()\n");
                    return true;
                }
                script.append(bashVar).append("=()\n");
            } else {
                script.append("declare -A ").append(bashVar).append("=()\n");
            }
            return true;
        }
        writeAssignment(script, indentLevel, locals, bashVar, rhs);
        return true;
    }

    private Condition renderCondition(GnashParser.ExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        return renderConditionFromAssignment(ctx.assignment());
    }

    private Condition renderConditionFromAssignment(GnashParser.AssignmentContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.destructuringPattern() != null) {
            return null;
        }
        return renderConditionFromLogicOr(ctx.logicOrExpression());
    }

    private Condition renderConditionFromLogicOr(GnashParser.LogicOrExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.LogicAndExpressionContext> parts = ctx.logicAndExpression();
        Condition result = null;
        for (GnashParser.LogicAndExpressionContext part : parts) {
            Condition next = renderConditionFromLogicAnd(part);
            if (next == null) {
                return null;
            }
            if (result == null) {
                result = next;
            } else {
                result = result.combine(next, "||");
            }
        }
        return result;
    }

    private Condition renderConditionFromLogicAnd(GnashParser.LogicAndExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.EqualityExpressionContext> parts = ctx.equalityExpression();
        Condition result = null;
        for (GnashParser.EqualityExpressionContext part : parts) {
            Condition next = renderConditionFromEquality(part);
            if (next == null) {
                return null;
            }
            if (result == null) {
                result = next;
            } else {
                result = result.combine(next, "&&");
            }
        }
        return result;
    }

    private Condition renderConditionFromEquality(GnashParser.EqualityExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.RelationalExpressionContext> parts = ctx.relationalExpression();
        if (parts.size() == 1) {
            return renderConditionFromRelational(parts.get(0));
        }
        if (parts.size() == 2 && ctx.getChildCount() >= 3) {
            String left = renderRelationalExpression(parts.get(0));
            String right = renderRelationalExpression(parts.get(1));
            if (left == null || right == null) {
                return null;
            }
            String op = ctx.getChild(1).getText();
            if ("==".equals(op)) {
                return new Condition("[[ " + left + " == " + right + " ]]");
            }
            if ("!=".equals(op)) {
                return new Condition("[[ " + left + " != " + right + " ]]");
            }
        }
        return null;
    }

    private Condition renderConditionFromRelational(GnashParser.RelationalExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.additiveExpression().size() == 2 && ctx.getChildCount() == 3) {
            String op = ctx.getChild(1).getText();
            if ("is".equals(op)) {
                String left = renderAdditiveExpression(ctx.additiveExpression(0));
                if (left == null) {
                    return null;
                }
                String typeText = ctx.additiveExpression(1).getText();
                if ("List".equals(typeText)) {
                    return new Condition("__gnash_is_list " + left);
                }
            }
        }
        if (ctx.additiveExpression().size() != 1) {
            return null;
        }
        return renderConditionFromAdditive(ctx.additiveExpression(0));
    }

    private Condition renderConditionFromAdditive(GnashParser.AdditiveExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.multiplicativeExpression().size() != 1) {
            return null;
        }
        return renderConditionFromMultiplicative(ctx.multiplicativeExpression(0));
    }

    private Condition renderConditionFromMultiplicative(GnashParser.MultiplicativeExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.unaryExpression().size() != 1) {
            return null;
        }
        return renderConditionFromUnary(ctx.unaryExpression(0));
    }

    private Condition renderConditionFromUnary(GnashParser.UnaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.postfixExpression() != null) {
            return renderConditionFromPostfix(ctx.postfixExpression());
        }
        GnashParser.UnaryExpressionContext inner = ctx.unaryExpression();
        if (inner != null && ctx.getChildCount() == 2) {
            String op = ctx.getChild(0).getText();
            Condition operand = renderConditionFromUnary(inner);
            if (operand == null) {
                return null;
            }
            if ("!".equals(op)) {
                return operand.negate();
            }
        }
        return null;
    }

    private Condition renderConditionFromPostfix(GnashParser.PostfixExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (!ctx.postfixOperator().isEmpty()) {
            Call call = tryRenderCall(ctx);
            if (call != null) {
                String command = renderCallCommand(call);
                if (command != null) {
                    return new Condition(command);
                }
            }
            String propertyValue = renderPropertyAccess(ctx);
            if (propertyValue != null) {
                return new Condition("[[ -n " + propertyValue + " ]]");
            }
            return null;
        }
        return renderConditionFromPrimary(ctx.primaryExpression());
    }

    private Condition renderConditionFromPrimary(GnashParser.PrimaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.literal() != null) {
            return renderConditionFromLiteral(ctx.literal());
        }
        if (ctx.IDENTIFIER() != null) {
            String bashVar = toBashIdentifier(ctx.IDENTIFIER().getText());
            return new Condition("[[ -n ${" + bashVar + ":-} ]]");
        }
        if (ctx.expression() != null) {
            return renderCondition(ctx.expression());
        }
        return null;
    }

    private Condition renderConditionFromLiteral(GnashParser.LiteralContext literal) {
        if (literal == null) {
            return null;
        }
        if ("true".equals(literal.getText())) {
            return new Condition(":");
        }
        if ("false".equals(literal.getText())) {
            return new Condition("false");
        }
        if ("null".equals(literal.getText())) {
            return new Condition("false");
        }
        if (literal.NUMBER() != null) {
            return new Condition("(( " + literal.NUMBER().getText() + " ))");
        }
        if (literal.STRING() != null) {
            return new Condition("[[ -n " + literal.STRING().getText() + " ]]");
        }
        return null;
    }

    private String renderAssignmentValue(GnashParser.AssignmentContext assignment) {
        if (assignment == null) {
            return null;
        }
        if (assignment.destructuringPattern() != null) {
            return null;
        }
        return renderLogicOrExpression(assignment.logicOrExpression());
    }

    private String renderLogicOrExpression(GnashParser.LogicOrExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.LogicAndExpressionContext> parts = ctx.logicAndExpression();
        if (parts.size() != 1) {
            return null;
        }
        return renderLogicAndExpression(parts.get(0));
    }

    private String renderLogicAndExpression(GnashParser.LogicAndExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.EqualityExpressionContext> parts = ctx.equalityExpression();
        if (parts.size() != 1) {
            return null;
        }
        return renderEqualityExpression(parts.get(0));
    }

    private String renderEqualityExpression(GnashParser.EqualityExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.relationalExpression().size() != 1) {
            return null;
        }
        return renderRelationalExpression(ctx.relationalExpression(0));
    }

    private String renderRelationalExpression(GnashParser.RelationalExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.additiveExpression().size() != 1) {
            return null;
        }
        return renderAdditiveExpression(ctx.additiveExpression(0));
    }

    private String renderAdditiveExpression(GnashParser.AdditiveExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.multiplicativeExpression().size() != 1) {
            return null;
        }
        return renderMultiplicativeExpression(ctx.multiplicativeExpression(0));
    }

    private String renderMultiplicativeExpression(GnashParser.MultiplicativeExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.unaryExpression().size() != 1) {
            return null;
        }
        return renderUnaryExpression(ctx.unaryExpression(0));
    }

    private String renderUnaryExpression(GnashParser.UnaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.postfixExpression() == null || ctx.getChildCount() != 1) {
            return null;
        }
        return renderPostfixExpression(ctx.postfixExpression());
    }

    private String renderPostfixExpression(GnashParser.PostfixExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (!ctx.postfixOperator().isEmpty()) {
            String callValue = renderCallValue(ctx);
            if (callValue != null) {
                return callValue;
            }
            String propertyValue = renderPropertyAccess(ctx);
            if (propertyValue != null) {
                return propertyValue;
            }
            return null;
        }
        return renderPrimaryExpression(ctx.primaryExpression());
    }

    private String renderPropertyAccess(GnashParser.PostfixExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.postfixOperator().size() != 1) {
            return null;
        }
        GnashParser.PostfixOperatorContext op = ctx.postfixOperator(0);
        if (op.arguments() != null) {
            return null;
        }
        if (op.IDENTIFIER() == null) {
            return null;
        }
        if (op.getChildCount() == 0 || !".".equals(op.getChild(0).getText())) {
            return null;
        }
        String base = extractIdentifier(ctx.primaryExpression());
        if (base == null) {
            return null;
        }
        String bashVar = toBashIdentifier(base);
        String property = op.IDENTIFIER().getText();
        StringBuilder builder = new StringBuilder();
        builder.append("\"$(__gnash_struct_get \\\"${")
               .append(bashVar)
               .append(":-}\\\" ")
               .append(singleQuote(property))
               .append(")\"");
        return builder.toString();
    }

    private String renderPrimaryExpression(GnashParser.PrimaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.literal() != null) {
            return renderLiteral(ctx.literal());
        }
        if (ctx.IDENTIFIER() != null) {
            String bashVar = toBashIdentifier(ctx.IDENTIFIER().getText());
            return "\"${" + bashVar + "}\"";
        }
        if (ctx.expression() != null) {
            return renderExpression(ctx.expression());
        }
        return null;
    }

    private String renderExpression(GnashParser.ExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        return renderAssignmentValue(ctx.assignment());
    }

    private Call tryRenderCall(GnashParser.ExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        return tryRenderCall(ctx.assignment());
    }

    private Call tryRenderCall(GnashParser.AssignmentContext ctx) {
        if (ctx == null || ctx.destructuringPattern() != null) {
            return null;
        }
        return tryRenderCall(ctx.logicOrExpression());
    }

    private Call tryRenderCall(GnashParser.LogicOrExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.LogicAndExpressionContext> parts = ctx.logicAndExpression();
        if (parts.size() != 1) {
            return null;
        }
        return tryRenderCall(parts.get(0));
    }

    private Call tryRenderCall(GnashParser.LogicAndExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.EqualityExpressionContext> parts = ctx.equalityExpression();
        if (parts.size() != 1) {
            return null;
        }
        return tryRenderCall(parts.get(0));
    }

    private Call tryRenderCall(GnashParser.EqualityExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.relationalExpression().size() != 1) {
            return null;
        }
        return tryRenderCall(ctx.relationalExpression(0));
    }

    private Call tryRenderCall(GnashParser.RelationalExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.additiveExpression().size() != 1) {
            return null;
        }
        return tryRenderCall(ctx.additiveExpression(0));
    }

    private Call tryRenderCall(GnashParser.AdditiveExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.multiplicativeExpression().size() != 1) {
            return null;
        }
        return tryRenderCall(ctx.multiplicativeExpression(0));
    }

    private Call tryRenderCall(GnashParser.MultiplicativeExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.unaryExpression().size() != 1) {
            return null;
        }
        return tryRenderCall(ctx.unaryExpression(0));
    }

    private Call tryRenderCall(GnashParser.UnaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.postfixExpression() == null || ctx.getChildCount() != 1) {
            return null;
        }
        return tryRenderCall(ctx.postfixExpression());
    }

    private Call tryRenderCall(GnashParser.PostfixExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        String base = extractIdentifier(ctx.primaryExpression());
        if (base == null) {
            return null;
        }
        String currentTarget = base;
        Call lastCall = null;
        for (GnashParser.PostfixOperatorContext op : ctx.postfixOperator()) {
            GnashParser.ArgumentsContext argsCtx = op.arguments();
            if (op.getChildCount() > 0 && ".".equals(op.getChild(0).getText())) {
                if (op.IDENTIFIER() != null) {
                    currentTarget = currentTarget + "." + op.IDENTIFIER().getText();
                }
                if (argsCtx != null) {
                    List<String> args = renderArguments(argsCtx);
                    if (args == null) {
                        return null;
                    }
                    lastCall = new Call(currentTarget, args);
                }
            } else if (argsCtx != null) {
                List<String> args = renderArguments(argsCtx);
                if (args == null) {
                    return null;
                }
                lastCall = new Call(currentTarget, args);
            }
        }
        return lastCall;
    }

    private List<String> renderArguments(GnashParser.ArgumentsContext ctx) {
        List<String> args = new ArrayList<>();
        if (ctx == null) {
            return args;
        }
        GnashParser.ArgumentListContext list = ctx.argumentList();
        if (list != null) {
            for (GnashParser.ExpressionContext expressionContext : list.expression()) {
                String value = renderExpression(expressionContext);
                if (value == null) {
                    return null;
                }
                args.add(value);
            }
        }
        return args;
    }

    private String extractIdentifier(GnashParser.PrimaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.IDENTIFIER() != null) {
            return ctx.IDENTIFIER().getText();
        }
        return null;
    }

    private String extractIdentifier(GnashParser.ExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        GnashParser.AssignmentContext assignment = ctx.assignment();
        if (assignment == null || assignment.destructuringPattern() != null) {
            return null;
        }
        return extractIdentifier(assignment.logicOrExpression());
    }

    private String extractIdentifier(GnashParser.LogicOrExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.LogicAndExpressionContext> parts = ctx.logicAndExpression();
        if (parts.size() != 1) {
            return null;
        }
        return extractIdentifier(parts.get(0));
    }

    private String extractIdentifier(GnashParser.LogicAndExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        List<GnashParser.EqualityExpressionContext> parts = ctx.equalityExpression();
        if (parts.size() != 1) {
            return null;
        }
        return extractIdentifier(parts.get(0));
    }

    private String extractIdentifier(GnashParser.EqualityExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.relationalExpression().size() != 1) {
            return null;
        }
        return extractIdentifier(ctx.relationalExpression(0));
    }

    private String extractIdentifier(GnashParser.RelationalExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.additiveExpression().size() != 1) {
            return null;
        }
        return extractIdentifier(ctx.additiveExpression(0));
    }

    private String extractIdentifier(GnashParser.AdditiveExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.multiplicativeExpression().size() != 1) {
            return null;
        }
        return extractIdentifier(ctx.multiplicativeExpression(0));
    }

    private String extractIdentifier(GnashParser.MultiplicativeExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.unaryExpression().size() != 1) {
            return null;
        }
        return extractIdentifier(ctx.unaryExpression(0));
    }

    private String extractIdentifier(GnashParser.UnaryExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (ctx.postfixExpression() == null || ctx.getChildCount() != 1) {
            return null;
        }
        return extractIdentifier(ctx.postfixExpression());
    }

    private String extractIdentifier(GnashParser.PostfixExpressionContext ctx) {
        if (ctx == null) {
            return null;
        }
        if (!ctx.postfixOperator().isEmpty()) {
            return null;
        }
        return extractIdentifier(ctx.primaryExpression());
    }

    private String renderCallValue(GnashParser.PostfixExpressionContext ctx) {
        Call call = tryRenderCall(ctx);
        if (call == null) {
            return null;
        }
        String listValue = renderListMethodValue(call);
        if (listValue != null) {
            return listValue;
        }
        String structGet = renderStructGetCall(call);
        if (structGet != null) {
            return structGet;
        }
        if (call.target.startsWith("__gnash_")) {
            StringBuilder direct = new StringBuilder("$(");
            direct.append(call.target);
            for (String arg : call.args) {
                direct.append(' ').append(arg);
            }
            direct.append(')');
            return direct.toString();
        }
        StringBuilder value = new StringBuilder("$(");
        value.append("__gnash_call ").append(singleQuote(call.target));
        for (String arg : call.args) {
            value.append(' ').append(arg);
        }
        value.append(')');
        return value.toString();
    }

    private String renderStructGetCall(Call call) {
        if (call == null || call.args.size() != 1) {
            return null;
        }
        if (!call.target.endsWith(".get")) {
            return null;
        }
        int idx = call.target.lastIndexOf('.');
        if (idx <= 0) {
            return null;
        }
        String receiver = call.target.substring(0, idx);
        if (receiver.isEmpty() || !Character.isLowerCase(receiver.charAt(0))) {
            return null;
        }
        String bashVar = toBashIdentifier(receiver);
        StringBuilder builder = new StringBuilder();
        builder.append("\"$(__gnash_struct_get \\\"${")
               .append(bashVar)
               .append(":-}\\\" ")
               .append(call.args.get(0))
               .append(")\"");
        return builder.toString();
    }

    private String renderCallCommand(Call call) {
        if (call == null) {
            return null;
        }
        String listCommand = renderListMethodCommand(call);
        if (listCommand != null) {
            return listCommand;
        }
        if (call.target.startsWith("__gnash_")) {
            StringBuilder direct = new StringBuilder(call.target);
            for (String arg : call.args) {
                direct.append(' ').append(arg);
            }
            return direct.toString();
        }
        if ("println".equals(call.target)) {
            if (call.args.isEmpty()) {
                return "echo";
            }
            StringBuilder echoCmd = new StringBuilder("echo ");
            for (int i = 0; i < call.args.size(); i++) {
                if (i > 0) {
                    echoCmd.append(' ');
                }
                echoCmd.append(unwrapIdentifier(call.args.get(i)));
            }
            return echoCmd.toString();
        }
        StringBuilder command = new StringBuilder("__gnash_invoke ");
        command.append(singleQuote(call.target));
        for (String arg : call.args) {
            command.append(' ').append(arg);
        }
        return command.toString();
    }

    private String renderListMethodCommand(Call call) {
        if (call == null) {
            return null;
        }
        int idx = call.target.indexOf('.');
        if (idx <= 0) {
            return null;
        }
        String receiver = call.target.substring(0, idx);
        String method = call.target.substring(idx + 1);
        String bashVar = toBashIdentifier(receiver);
        if ("add".equals(method) && !call.args.isEmpty()) {
            return "__gnash_list_append \"${" + bashVar + "}\" " + joinArguments(call.args);
        }
        if ("contains".equals(method) && !call.args.isEmpty()) {
            return "__gnash_list_contains \"${" + bashVar + "}\" " + joinArguments(call.args);
        }
        return null;
    }

    private String renderListMethodValue(Call call) {
        if (call == null) {
            return null;
        }
        int idx = call.target.indexOf('.');
        if (idx <= 0) {
            return null;
        }
        String receiver = call.target.substring(0, idx);
        String method = call.target.substring(idx + 1);
        String bashVar = toBashIdentifier(receiver);
        if ("contains".equals(method) && !call.args.isEmpty()) {
            StringBuilder builder = new StringBuilder();
            builder.append("$(__gnash_list_contains_value \"${")
                   .append(bashVar)
                   .append("}\" ")
                   .append(joinArguments(call.args))
                   .append(")");
            return builder.toString();
        }
        return null;
    }

    private String joinArguments(List<String> args) {
        if (args == null || args.isEmpty()) {
            return "";
        }
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < args.size(); i++) {
            if (i > 0) {
                builder.append(' ');
            }
            builder.append(args.get(i));
        }
        return builder.toString();
    }

    private String singleQuote(String text) {
        return "'" + text.replace("'", "'\"'\"'") + "'";
    }

    private String rewriteStringLiteral(String literal) {
        if (literal == null || literal.length() < 2) {
            return literal;
        }
        String inner = literal.substring(1, literal.length() - 1);
        Matcher matcher = INTERPOLATION_PATTERN.matcher(inner);
        StringBuffer buffer = new StringBuffer();
        while (matcher.find()) {
            String name = matcher.group(1);
            String replacement = name.equals(name.toUpperCase()) ? name : toBashIdentifier(name);
            matcher.appendReplacement(buffer, Matcher.quoteReplacement("${" + replacement + "}"));
        }
        matcher.appendTail(buffer);
        return "\"" + buffer + "\"";
    }


    private String renderLiteral(GnashParser.LiteralContext literal) {
        if (literal == null) {
            return null;
        }
        String rawText = literal.getText();
        if (rawText != null && rawText.startsWith("$\"") && rawText.endsWith("\"")) {
            return shellLiteralToCommand(rawText);
        }
        if (literal.STRING() != null) {
            return rewriteStringLiteral(literal.STRING().getText());
        }
        if (literal.NUMBER() != null) {
            return literal.NUMBER().getText();
        }
        if (literal.listLiteral() != null) {
            GnashParser.ListLiteralContext list = literal.listLiteral();
            if (list.expression().isEmpty()) {
                return EMPTY_LIST_SENTINEL;
            }
            List<String> values = new ArrayList<>();
            for (GnashParser.ExpressionContext expressionContext : list.expression()) {
                String value = renderExpression(expressionContext);
                if (value == null) {
                    return null;
                }
                values.add(value);
            }
            StringBuilder builder = new StringBuilder("$(__gnash_list_from_values");
            for (String value : values) {
                builder.append(' ').append(value);
            }
            builder.append(')');
            return builder.toString();
        }
        if (literal.mapLiteral() != null) {
            GnashParser.MapLiteralContext map = literal.mapLiteral();
            if (map.mapEntry().isEmpty()) {
                return EMPTY_MAP_SENTINEL;
            }
            return renderMapLiteral(map);
        }
        if (literal.getText().equals("true")) {
            return "1";
        }
        if (literal.getText().equals("false")) {
            return "0";
        }
        if (literal.getText().equals("null")) {
            return "\"\"";
        }
        return null;
    }

    private String renderMapLiteral(GnashParser.MapLiteralContext map) {
        if (map == null || map.mapEntry().isEmpty()) {
            return "\"$(__gnash_struct_pack)\"";
        }
        StringBuilder builder = new StringBuilder();
        builder.append("\"$(__gnash_struct_pack");
        for (GnashParser.MapEntryContext entry : map.mapEntry()) {
            String key = renderMapKey(entry.mapKey());
            if (key == null) {
                return null;
            }
            String value = renderExpression(entry.expression());
            if (value == null) {
                return null;
            }
            builder.append(' ').append(key).append(' ').append(value);
        }
        builder.append(")\"");
        return builder.toString();
    }

    private String renderMapKey(GnashParser.MapKeyContext keyCtx) {
        if (keyCtx == null) {
            return null;
        }
        if (keyCtx.IDENTIFIER() != null) {
            return singleQuote(keyCtx.IDENTIFIER().getText());
        }
        if (keyCtx.STRING() != null) {
            return rewriteStringLiteral(keyCtx.STRING().getText());
        }
        return null;
    }

    private void appendUnsupported(StringBuilder script, int indentLevel, String sourceText) {
        indent(script, indentLevel);
        script.append("# TODO: unsupported construct: ").append(truncate(sourceText)).append('\n');
    }

    private void indent(StringBuilder script, int level) {
        for (int i = 0; i < level; i++) {
            script.append("  ");
        }
    }

    private String nextTempVar(String prefix) {
        tempCounter++;
        return prefix + tempCounter;
    }

    private String unwrapIdentifier(String value) {
        if (value == null) {
            return null;
        }
        if (value.startsWith("\"${") && value.endsWith("}\"")) {
            int firstClose = value.indexOf('}');
            if (firstClose == value.length() - 2) {
                return "$" + value.substring(3, value.length() - 2);
            }
        }
        return value;
    }

    private boolean renderDestructuringAssignment(StringBuilder script,
                                                  GnashParser.AssignmentContext assignment,
                                                  int indentLevel,
                                                  Set<String> locals,
                                                  List<TerminalNode> identifiers) {
        if (identifiers.size() == 2) {
            GnashParser.LogicOrExpressionContext exprCtx = assignment.logicOrExpression();
            if (exprCtx != null) {
                String exprText = exprCtx.getText();
                if (exprText != null && exprText.startsWith("$\"") && exprText.endsWith("\"")) {
                    String command = shellLiteralToCommand(exprText);
                    String firstVar = toBashIdentifier(identifiers.get(0).getText());
                    String secondVar = toBashIdentifier(identifiers.get(1).getText());
                    writeAssignment(script, indentLevel, locals, firstVar, command);
                    writeAssignment(script, indentLevel, locals, secondVar, "$?");
                    return true;
                }
            }
        }
        return false;
    }

    private void writeAssignment(StringBuilder script,
                                 int indentLevel,
                                 Set<String> locals,
                                 String varName,
                                 String value) {
        boolean newLocal = locals != null && !locals.contains(varName);
        if (newLocal) {
            locals.add(varName);
            indent(script, indentLevel);
            script.append("local ").append(varName).append('\n');
        }
        indent(script, indentLevel);
        script.append(varName).append('=').append(value).append('\n');
    }

    private String shellLiteralToCommand(String literal) {
        if (literal == null || !literal.startsWith("$\"") || !literal.endsWith("\"")) {
            return null;
        }
        String inner = literal.substring(2, literal.length() - 1).trim();
        return "$(" + inner + ")";
    }

    private boolean isExitCodeValue(String value) {
        if (value == null) {
            return false;
        }
        if ("$?".equals(value)) {
            return true;
        }
        return value.matches("-?\\d+");
    }

    private void emitStringReturn(StringBuilder script, int indentLevel, String value) {
        emitStringReturn(script, indentLevel, value, 0);
    }

    private void emitStringReturn(StringBuilder script,
                                  int indentLevel,
                                  String value,
                                  int exitCode) {
        indent(script, indentLevel);
        script.append(RETURN_VAR_NAME).append('=').append(value).append('\n');
        indent(script, indentLevel);
        script.append("if [[ -n ${").append(OUT_PARAM_NAME).append(":-} ]]; then\n");
        indent(script, indentLevel + 1);
        script.append("printf -v \"${").append(OUT_PARAM_NAME).append("}\" '%s' \"${")
              .append(RETURN_VAR_NAME).append("}\"\n");
        indent(script, indentLevel);
        script.append("fi\n");
        indent(script, indentLevel);
        script.append("return ").append(exitCode).append('\n');
    }

    private String toBashIdentifier(String name) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < name.length(); i++) {
            char ch = name.charAt(i);
            if (Character.isUpperCase(ch)) {
                if (result.length() > 0) {
                    result.append('_');
                }
                result.append(Character.toLowerCase(ch));
            } else if (Character.isLetterOrDigit(ch) || ch == '_') {
                result.append(ch);
            } else {
                result.append('_');
            }
        }
        if (result.length() == 0 || Character.isDigit(result.charAt(0))) {
            result.insert(0, '_');
        }
        return result.toString();
    }

    private String truncate(String text) {
        if (text == null) {
            return "";
        }
        if (text.length() <= 60) {
            return text;
        }
        return text.substring(0, 57) + "...";
    }
}
