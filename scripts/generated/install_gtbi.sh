#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM gtbi.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Resolve relative helper paths first.
GTBI_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure logging functions available
if [[ -f "$GTBI_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$GTBI_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$GTBI_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$GTBI_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

gtbi_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

gtbi_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(gtbi_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(gtbi_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

gtbi_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(gtbi_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\n' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\n' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '%s\n' "$passwd_entry"
}

gtbi_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '%s\n' "${passwd_home%/}"
        return 0
    fi

    return 1
}

gtbi_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(gtbi_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

gtbi_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive GTBI paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _GTBI_DETECTED_USER="ubuntu"
        else
            _GTBI_DETECTED_USER="${SUDO_USER:-}"
            if [[ -z "$_GTBI_DETECTED_USER" ]]; then
                _GTBI_DETECTED_USER="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "$_GTBI_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="$_GTBI_DETECTED_USER"
    fi
    unset _GTBI_DETECTED_USER

    if declare -f _gtbi_validate_target_user >/dev/null 2>&1; then
        _gtbi_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "${TARGET_USER:-}" ]] || [[ ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="${MODE:-vibe}"

    _GTBI_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
    if [[ -n "$_GTBI_EXPLICIT_TARGET_HOME" ]]; then
        _GTBI_EXPLICIT_TARGET_HOME="${_GTBI_EXPLICIT_TARGET_HOME%/}"
    fi
    _GTBI_RESOLVED_TARGET_HOME=""
    if declare -f _gtbi_resolve_target_home >/dev/null 2>&1; then
        _GTBI_RESOLVED_TARGET_HOME="$(_gtbi_resolve_target_home "${TARGET_USER}" "$_GTBI_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "${TARGET_USER}" == "root" ]]; then
            _GTBI_RESOLVED_TARGET_HOME="/root"
        else
            _gtbi_passwd_entry="$(gtbi_generated_getent_passwd_entry "${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "$_gtbi_passwd_entry" ]]; then
                _GTBI_RESOLVED_TARGET_HOME="$(gtbi_generated_passwd_home_from_entry "$_gtbi_passwd_entry" 2>/dev/null || true)"
            else
                _gtbi_current_user="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"
                _gtbi_current_home="${HOME:-}"
                if [[ -n "$_gtbi_current_home" ]]; then
                    _gtbi_current_home="${_gtbi_current_home%/}"
                fi
                if [[ "${_gtbi_current_user:-}" == "${TARGET_USER}" ]] && [[ -n "$_gtbi_current_home" ]] && [[ "$_gtbi_current_home" == /* ]] && [[ "$_gtbi_current_home" != "/" ]] && { [[ -z "$_GTBI_EXPLICIT_TARGET_HOME" ]] || [[ "$_gtbi_current_home" == "$_GTBI_EXPLICIT_TARGET_HOME" ]]; }; then
                    _GTBI_RESOLVED_TARGET_HOME="$_gtbi_current_home"
                fi
                unset _gtbi_current_user _gtbi_current_home
            fi
            unset _gtbi_passwd_entry
        fi
    fi
    if [[ -z "$_GTBI_RESOLVED_TARGET_HOME" ]] && [[ $EUID -eq 0 ]] && ! gtbi_generated_target_user_exists "${TARGET_USER}"; then
        if [[ -n "$_GTBI_EXPLICIT_TARGET_HOME" ]] && [[ "$_GTBI_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_GTBI_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _GTBI_RESOLVED_TARGET_HOME="$_GTBI_EXPLICIT_TARGET_HOME"
        else
            _GTBI_RESOLVED_TARGET_HOME="$(gtbi_generated_default_home_for_new_user "${TARGET_USER}" 2>/dev/null || true)"
        fi
    fi
    if [[ -n "$_GTBI_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="${_GTBI_RESOLVED_TARGET_HOME%/}"
    fi
    unset _GTBI_EXPLICIT_TARGET_HOME _GTBI_RESOLVED_TARGET_HOME

    if [[ -z "${TARGET_HOME:-}" ]] || [[ "${TARGET_HOME}" == "/" ]] || [[ "${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '${TARGET_USER}': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${GTBI_BOOTSTRAP_DIR:-}" ]]; then
        GTBI_BOOTSTRAP_DIR="$(cd "$GTBI_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    GTBI_BIN_DIR="${GTBI_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -z "${GTBI_BIN_DIR:-}" ]] || [[ "${GTBI_BIN_DIR}" == "/" ]] || [[ "${GTBI_BIN_DIR}" != /* ]]; then
        log_error "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${GTBI_BIN_DIR:-<empty>})"
        exit 1
    fi
    GTBI_LIB_DIR="${GTBI_LIB_DIR:-$GTBI_BOOTSTRAP_DIR/scripts/lib}"
    GTBI_GENERATED_DIR="${GTBI_GENERATED_DIR:-$GTBI_BOOTSTRAP_DIR/scripts/generated}"
    GTBI_ASSETS_DIR="${GTBI_ASSETS_DIR:-$GTBI_BOOTSTRAP_DIR/gtbi}"
    GTBI_CHECKSUMS_YAML="${GTBI_CHECKSUMS_YAML:-$GTBI_BOOTSTRAP_DIR/checksums.yaml}"
    GTBI_MANIFEST_YAML="${GTBI_MANIFEST_YAML:-$GTBI_BOOTSTRAP_DIR/gtbi.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE GTBI_BIN_DIR
    export GTBI_BOOTSTRAP_DIR GTBI_LIB_DIR GTBI_GENERATED_DIR GTBI_ASSETS_DIR GTBI_CHECKSUMS_YAML GTBI_MANIFEST_YAML
fi

# Source contract validation
if [[ -f "$GTBI_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$GTBI_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: gtbi_security_init
GTBI_SECURITY_READY=false
gtbi_security_init() {
    if [[ "${GTBI_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$GTBI_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use GTBI_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${GTBI_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${GTBI_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    GTBI_SECURITY_READY=true
    return 0
}

# Category: gtbi
# Modules: 5

# Agent workspace with tmux session and project folder
install_gtbi_workspace() {
    local module_id="gtbi.workspace"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "gtbi.workspace already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p /data/projects/my_first_project (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
# Create project directory
mkdir -p /data/projects/my_first_project
cd /data/projects/my_first_project
git init 2>/dev/null || true
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: install command failed: mkdir -p /data/projects/my_first_project"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "install command failed: mkdir -p /data/projects/my_first_project"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.gtbi (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
# Create workspace instructions file
mkdir -p ~/.gtbi
printf '%s\n' "" \
  "  GTBI AGENT WORKSPACE - QUICK REFERENCE" \
  "  --------------------------------------" \
  "" \
  "  RECONNECT AFTER SSH:" \
  "    tmux attach -t agents    OR just type:  agents" \
  "" \
  "  WINDOWS (Ctrl-b + number):" \
  "    0:welcome  - This instructions window" \
  "    1:claude   - Claude Code (Anthropic)" \
  "    2:codex    - Codex CLI (OpenAI)" \
  "    3:gemini   - Gemini CLI (Google)" \
  "" \
  "  TMUX BASICS:" \
  "    Ctrl-b d        - Detach (keep session running)" \
  "    Ctrl-b c        - Create new window" \
  "    Ctrl-b n/p      - Next/previous window" \
  "    Ctrl-b [0-9]    - Switch to window number" \
  "" \
  "  START AN AGENT:" \
  "    claude          - Start Claude Code" \
  "    codex           - Start Codex CLI" \
  "    gemini          - Start Gemini CLI" \
  "" \
  "  PROJECT: /data/projects/my_first_project" \
  "  (Rename with: mv /data/projects/my_first_project /data/projects/NEW_NAME)" \
  "" > ~/.gtbi/workspace-instructions.txt
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: install command failed: mkdir -p ~/.gtbi"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "install command failed: mkdir -p ~/.gtbi"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
# Create tmux session with agent panes (if not already running)
SESSION_NAME="agents"
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  # Create session with first window for instructions
  tmux new-session -d -s "$SESSION_NAME" -n "welcome" -c /data/projects/my_first_project

  # Add agent windows
  tmux new-window -t "$SESSION_NAME" -n "claude" -c /data/projects/my_first_project
  tmux new-window -t "$SESSION_NAME" -n "codex" -c /data/projects/my_first_project
  tmux new-window -t "$SESSION_NAME" -n "gemini" -c /data/projects/my_first_project

  # Send instructions to welcome window
  tmux send-keys -t "$SESSION_NAME:welcome" "cat ~/.gtbi/workspace-instructions.txt" Enter

  # Select the welcome window
  tmux select-window -t "$SESSION_NAME:welcome"
fi
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: install command failed: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "install command failed: if ! tmux has-session -t \"\$SESSION_NAME\" 2>/dev/null; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! gtbi_has_active_agents_alias ~/.zshrc.local; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
# Add agents alias to zshrc.local if not already present
gtbi_has_active_agents_alias() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }
      END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

if ! gtbi_has_active_agents_alias ~/.zshrc.local; then
  touch ~/.zshrc.local 2>/dev/null || true
  echo '' >> ~/.zshrc.local
  echo '# GTBI agents workspace alias' >> ~/.zshrc.local
  echo 'alias agents="tmux attach -t agents 2>/dev/null || tmux new-session -s agents -c /data/projects"' >> ~/.zshrc.local
fi
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: install command failed: if ! gtbi_has_active_agents_alias ~/.zshrc.local; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "install command failed: if ! gtbi_has_active_agents_alias ~/.zshrc.local; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d /data/projects/my_first_project (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
test -d /data/projects/my_first_project
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: verify failed: test -d /data/projects/my_first_project"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "verify failed: test -d /data/projects/my_first_project"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_WORKSPACE'
gtbi_has_active_agents_alias() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }
      END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

gtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc
INSTALL_GTBI_WORKSPACE
        then
            log_warn "gtbi.workspace: verify failed: gtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.workspace" "verify failed: gtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.workspace"
            fi
            return 0
        fi
    fi

    log_success "gtbi.workspace installed"
}

# Onboarding TUI tutorial
install_gtbi_onboard() {
    local module_id="gtbi.onboard"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$onboard_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_ONBOARD'
# Generated helper functions used by this child shell.
gtbi_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
gtbi_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

gtbi_child_primary_bin_dir() {
    local primary_bin_dir="${GTBI_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            gtbi_child_log_error "GTBI_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        gtbi_child_log_error "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

gtbi_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

gtbi_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        gtbi_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(gtbi_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    gtbi_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${GTBI_BIN_DIR:-<unset>}"
    return 1
}

gtbi_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(gtbi_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        gtbi_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

gtbi_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(gtbi_child_primary_bin_tool_path mkdir)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

gtbi_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(gtbi_child_primary_bin_tool_path ln)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

gtbi_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(gtbi_child_primary_bin_tool_path install)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

onboard_tmp="$(mktemp "${TMPDIR:-/tmp}/gtbi-onboard.XXXXXX")"
trap 'rm -f "$onboard_tmp"' EXIT
# Install onboard script
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/packages/onboard/onboard.sh" "$onboard_tmp"
elif [[ -f "packages/onboard/onboard.sh" ]]; then
  cp "packages/onboard/onboard.sh" "$onboard_tmp"
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/packages/onboard/onboard.sh" -o "$onboard_tmp"
fi
gtbi_install_executable_into_primary_bin "$onboard_tmp" "onboard"
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1 && { [[ ! -e /usr/local/bin/onboard ]] || [[ -L /usr/local/bin/onboard ]]; }; then
  sudo -n ln -sf "$HOME/.gtbi/onboard/onboard.sh" /usr/local/bin/onboard
fi
INSTALL_GTBI_ONBOARD
        then
            log_error "gtbi.onboard: install command failed: trap 'rm -f \"\$onboard_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: onboard --help || command -v onboard (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_ONBOARD'
onboard --help || command -v onboard
INSTALL_GTBI_ONBOARD
        then
            log_error "gtbi.onboard: verify failed: onboard --help || command -v onboard"
            return 1
        fi
    fi

    log_success "gtbi.onboard installed"
}

# GTBI update command wrapper
install_gtbi_update() {
    local module_id="gtbi.update"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.gtbi/scripts (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_UPDATE'
mkdir -p ~/.gtbi/scripts
INSTALL_GTBI_UPDATE
        then
            log_error "gtbi.update: install command failed: mkdir -p ~/.gtbi/scripts"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_UPDATE'
# Install gtbi-update wrapper
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ~/.gtbi/scripts/nightly-update.sh
elif [[ -f "scripts/lib/nightly_update.sh" ]]; then
  cp "scripts/lib/nightly_update.sh" ~/.gtbi/scripts/nightly-update.sh
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/lib/nightly_update.sh" -o ~/.gtbi/scripts/nightly-update.sh
fi
chmod +x ~/.gtbi/scripts/nightly-update.sh
INSTALL_GTBI_UPDATE
        then
            log_error "gtbi.update: install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$update_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_UPDATE'
# Generated helper functions used by this child shell.
gtbi_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
gtbi_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

gtbi_child_primary_bin_dir() {
    local primary_bin_dir="${GTBI_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            gtbi_child_log_error "GTBI_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        gtbi_child_log_error "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

gtbi_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

gtbi_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        gtbi_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(gtbi_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    gtbi_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${GTBI_BIN_DIR:-<unset>}"
    return 1
}

gtbi_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(gtbi_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        gtbi_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

gtbi_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(gtbi_child_primary_bin_tool_path mkdir)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

gtbi_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(gtbi_child_primary_bin_tool_path ln)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

gtbi_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(gtbi_child_primary_bin_tool_path install)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

update_tmp="$(mktemp "${TMPDIR:-/tmp}/gtbi-update-wrapper.XXXXXX")"
trap 'rm -f "$update_tmp"' EXIT
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/gtbi-update" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/gtbi-update" "$update_tmp"
elif [[ -f "scripts/gtbi-update" ]]; then
  cp "scripts/gtbi-update" "$update_tmp"
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/gtbi-update" -o "$update_tmp"
fi
gtbi_install_executable_into_primary_bin "$update_tmp" "gtbi-update"
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1 && { [[ ! -e /usr/local/bin/gtbi-update ]] || [[ -L /usr/local/bin/gtbi-update ]]; }; then
  sudo -n ln -sf "$HOME/.gtbi/bin/gtbi-update" /usr/local/bin/gtbi-update
fi
INSTALL_GTBI_UPDATE
        then
            log_error "gtbi.update: install command failed: trap 'rm -f \"\$update_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gtbi-update --help || command -v gtbi-update (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_UPDATE'
gtbi-update --help || command -v gtbi-update
INSTALL_GTBI_UPDATE
        then
            log_error "gtbi.update: verify failed: gtbi-update --help || command -v gtbi-update"
            return 1
        fi
    fi

    log_success "gtbi.update installed"
}

# Nightly auto-update timer (systemd)
install_gtbi_nightly() {
    local module_id="gtbi.nightly"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "gtbi.nightly already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.gtbi/scripts ~/.config/systemd/user (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
mkdir -p ~/.gtbi/scripts ~/.config/systemd/user
INSTALL_GTBI_NIGHTLY
        then
            log_warn "gtbi.nightly: install command failed: mkdir -p ~/.gtbi/scripts ~/.config/systemd/user"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.nightly" "install command failed: mkdir -p ~/.gtbi/scripts ~/.config/systemd/user"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
# Install nightly update wrapper script
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh" ~/.gtbi/scripts/nightly-update.sh
elif [[ -f "scripts/lib/nightly_update.sh" ]]; then
  cp "scripts/lib/nightly_update.sh" ~/.gtbi/scripts/nightly-update.sh
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/lib/nightly_update.sh" -o ~/.gtbi/scripts/nightly-update.sh
fi
chmod +x ~/.gtbi/scripts/nightly-update.sh
INSTALL_GTBI_NIGHTLY
        then
            log_warn "gtbi.nightly: install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.nightly" "install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/lib/nightly_update.sh\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.timer\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
# Install systemd timer unit
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.timer" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.timer" ~/.config/systemd/user/gtbi-nightly-update.timer
elif [[ -f "scripts/templates/gtbi-nightly-update.timer" ]]; then
  cp "scripts/templates/gtbi-nightly-update.timer" ~/.config/systemd/user/gtbi-nightly-update.timer
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/templates/gtbi-nightly-update.timer" -o ~/.config/systemd/user/gtbi-nightly-update.timer
fi
INSTALL_GTBI_NIGHTLY
        then
            log_warn "gtbi.nightly: install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.timer\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.nightly" "install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.timer\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.service\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
# Install systemd service unit
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.service" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.service" ~/.config/systemd/user/gtbi-nightly-update.service
elif [[ -f "scripts/templates/gtbi-nightly-update.service" ]]; then
  cp "scripts/templates/gtbi-nightly-update.service" ~/.config/systemd/user/gtbi-nightly-update.service
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/templates/gtbi-nightly-update.service" -o ~/.config/systemd/user/gtbi-nightly-update.service
fi
INSTALL_GTBI_NIGHTLY
        then
            log_warn "gtbi.nightly: install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.service\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.nightly" "install command failed: if [[ -n \"\${GTBI_BOOTSTRAP_DIR:-}\" ]] && [[ -f \"\${GTBI_BOOTSTRAP_DIR}/scripts/templates/gtbi-nightly-update.service\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.nightly"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: systemctl --user daemon-reload 2>/dev/null || true (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
# Reload systemd and enable the timer (no-op in Docker/CI)
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now gtbi-nightly-update.timer 2>/dev/null || true
INSTALL_GTBI_NIGHTLY
        then
            log_warn "gtbi.nightly: install command failed: systemctl --user daemon-reload 2>/dev/null || true"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "gtbi.nightly" "install command failed: systemctl --user daemon-reload 2>/dev/null || true"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "gtbi.nightly"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): systemctl --user is-enabled gtbi-nightly-update.timer 2>/dev/null (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_NIGHTLY'
systemctl --user is-enabled gtbi-nightly-update.timer 2>/dev/null
INSTALL_GTBI_NIGHTLY
        then
            log_warn "Optional verify failed: gtbi.nightly"
        fi
    fi

    log_success "gtbi.nightly installed"
}

# GTBI doctor command for health checks
install_gtbi_doctor() {
    local module_id="gtbi.doctor"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$doctor_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_DOCTOR'
# Generated helper functions used by this child shell.
gtbi_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

# Primary-bin helper functions used by this child shell.
gtbi_child_log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

gtbi_child_primary_bin_dir() {
    local primary_bin_dir="${GTBI_BIN_DIR:-}"
    local fallback_home="${HOME:-}"

    if [[ -z "$primary_bin_dir" ]]; then
        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then
            gtbi_child_log_error "GTBI_BIN_DIR is unset and HOME is not a usable absolute path"
            return 1
        fi
        primary_bin_dir="$fallback_home/.local/bin"
    fi

    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then
        gtbi_child_log_error "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${primary_bin_dir:-<empty>})"
        return 1
    fi

    printf '%s\n' "$primary_bin_dir"
}

gtbi_child_primary_bin_requires_root() {
    local primary_bin_dir="$1"
    local target_home="${TARGET_HOME:-${HOME:-}}"

    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0
    case "$primary_bin_dir" in
        "$target_home"|"$target_home"/*) return 1 ;;
        *) return 0 ;;
    esac
}

gtbi_child_run_root_bin_command() {
    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then
        gtbi_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(gtbi_generated_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$@"
        return $?
    fi

    gtbi_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${GTBI_BIN_DIR:-<unset>}"
    return 1
}

gtbi_child_primary_bin_tool_path() {
    local name="${1:-}"
    local tool_path=""

    tool_path="$(gtbi_generated_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$tool_path" ]]; then
        gtbi_child_log_error "Unable to locate trusted $name for primary bin operation"
        return 1
    fi

    printf '%s\n' "$tool_path"
}

gtbi_child_ensure_primary_bin_dir() {
    local primary_bin_dir="$1"
    local mkdir_bin=""

    mkdir_bin="$(gtbi_child_primary_bin_tool_path mkdir)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"
        return $?
    fi

    "$mkdir_bin" -p "$primary_bin_dir"
}

gtbi_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local ln_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    ln_bin="$(gtbi_child_primary_bin_tool_path ln)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"
        return $?
    fi

    "$ln_bin" -sf "$source_path" "$dest_path"
}

gtbi_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local primary_bin_dir=""
    local dest_path=""
    local install_bin=""

    primary_bin_dir="$(gtbi_child_primary_bin_dir)" || return 1
    dest_path="$primary_bin_dir/$command_name"
    gtbi_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1
    install_bin="$(gtbi_child_primary_bin_tool_path install)" || return 1

    if gtbi_child_primary_bin_requires_root "$primary_bin_dir"; then
        gtbi_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    "$install_bin" -m 0755 "$src_path" "$dest_path"
}

doctor_tmp="$(mktemp "${TMPDIR:-/tmp}/gtbi-doctor.XXXXXX")"
trap 'rm -f "$doctor_tmp"' EXIT
# Install gtbi CLI (doctor.sh entrypoint)
if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "${GTBI_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" ]]; then
  cp "${GTBI_BOOTSTRAP_DIR}/scripts/lib/doctor.sh" "$doctor_tmp"
elif [[ -f "scripts/lib/doctor.sh" ]]; then
  cp "scripts/lib/doctor.sh" "$doctor_tmp"
else
  GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
  CURL_ARGS=(-fsSL)
  if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  fi
  curl "${CURL_ARGS[@]}" "${GTBI_RAW}/scripts/lib/doctor.sh" -o "$doctor_tmp"
fi
gtbi_install_executable_into_primary_bin "$doctor_tmp" "gtbi"
INSTALL_GTBI_DOCTOR
        then
            log_error "gtbi.doctor: install command failed: trap 'rm -f \"\$doctor_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gtbi doctor --help || command -v gtbi (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_GTBI_DOCTOR'
gtbi doctor --help || command -v gtbi
INSTALL_GTBI_DOCTOR
        then
            log_error "gtbi.doctor: verify failed: gtbi doctor --help || command -v gtbi"
            return 1
        fi
    fi

    log_success "gtbi.doctor installed"
}

# Install all gtbi modules
install_gtbi() {
    log_section "Installing gtbi modules"
    install_gtbi_workspace
    install_gtbi_onboard
    install_gtbi_update
    install_gtbi_nightly
    install_gtbi_doctor
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_gtbi
fi
