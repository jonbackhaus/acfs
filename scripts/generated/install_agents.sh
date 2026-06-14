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

# Category: agents
# Modules: 4

# Claude Code
install_agents_claude() {
    local module_id="agents.claude"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "agents.claude already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: agents.claude"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if gtbi_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="claude"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "agents.claude: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' 'latest'; then
                            install_success=true
                        else
                            log_error "agents.claude: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "agents.claude: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "agents.claude: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "agents.claude: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "agents.claude: gtbi_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for agents.claude"
                false
            fi
        }; then
            log_error "agents.claude: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: for candidate in \"\$HOME/.local/bin/claude\" \"\$HOME/.claude/bin/claude\" \"\$HOME/.claude/local/bin/claude\" \"\$HOME/.bun/bin/claude\"; do (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CLAUDE'
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

claude_candidate=""
for candidate in "$HOME/.local/bin/claude" "$HOME/.claude/bin/claude" "$HOME/.claude/local/bin/claude" "$HOME/.bun/bin/claude"; do
  if [[ -x "$candidate" ]]; then
    claude_candidate="$candidate"
    break
  fi
done
if [[ -z "$claude_candidate" ]] && [[ -d "$HOME/.claude" ]]; then
  claude_candidate="$(find "$HOME/.claude" -maxdepth 4 -type f -name claude -perm -111 -print -quit 2>/dev/null || true)"
fi
if [[ -z "$claude_candidate" ]] || [[ ! -x "$claude_candidate" ]]; then
  echo "Claude Code: installed but no runnable claude binary found" >&2
  exit 1
fi
primary_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"
if [[ "$claude_candidate" != "$primary_bin/claude" ]]; then
  gtbi_link_primary_bin_command "$claude_candidate" "claude"
fi
INSTALL_AGENTS_CLAUDE
        then
            log_error "agents.claude: install command failed: for candidate in \"\$HOME/.local/bin/claude\" \"\$HOME/.claude/bin/claude\" \"\$HOME/.claude/local/bin/claude\" \"\$HOME/.bun/bin/claude\"; do"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CLAUDE'
target_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/claude" --version || "$target_bin/claude" --help
INSTALL_AGENTS_CLAUDE
        then
            log_error "agents.claude: verify failed: \"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help"
            return 1
        fi
    fi

    log_success "agents.claude installed"
}

# OpenAI Codex CLI
install_agents_codex() {
    local module_id="agents.codex"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "agents.codex already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then
  echo "WARN: Codex CLI latest tag install failed; retrying @openai/codex" >&2
  ~/.bun/bin/bun install -g --trust @openai/codex
fi
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: install command failed: if ! ~/.bun/bin/bun install -g --trust @openai/codex@latest; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$wrapper_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
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

wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/gtbi-codex-wrapper.XXXXXX")"
trap 'rm -f "$wrapper_tmp"' EXIT
cat > "$wrapper_tmp" << 'WRAPPER'
#!/bin/bash
exec "$HOME/.bun/bin/bun" "$HOME/.bun/bin/codex" "$@"
WRAPPER
chmod 0755 "$wrapper_tmp"
gtbi_install_executable_into_primary_bin "$wrapper_tmp" "codex"
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: install command failed: trap 'rm -f \"\$wrapper_tmp\"' EXIT"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_CODEX'
target_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/codex" --version || "$target_bin/codex" --help
INSTALL_AGENTS_CODEX
        then
            log_error "agents.codex: verify failed: \"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help"
            return 1
        fi
    fi

    log_success "agents.codex installed"
}

# Google Gemini CLI
install_agents_gemini() {
    local module_id="agents.gemini"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "agents.gemini already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: ~/.bun/bin/bun install -g --trust @google/gemini-cli@latest (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
~/.bun/bin/bun install -g --trust @google/gemini-cli@latest
INSTALL_AGENTS_GEMINI
        then
            log_error "agents.gemini: install command failed: ~/.bun/bin/bun install -g --trust @google/gemini-cli@latest"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -f \"\$wrapper_tmp\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
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

wrapper_tmp="$(mktemp "${TMPDIR:-/tmp}/gtbi-gemini-wrapper.XXXXXX")"
trap 'rm -f "$wrapper_tmp"' EXIT
cat > "$wrapper_tmp" << 'WRAPPER'
#!/bin/bash
exec "$HOME/.bun/bin/bun" "$HOME/.bun/bin/gemini" "$@"
WRAPPER
chmod 0755 "$wrapper_tmp"
gtbi_install_executable_into_primary_bin "$wrapper_tmp" "gemini"
INSTALL_AGENTS_GEMINI
        then
            log_error "agents.gemini: install command failed: trap 'rm -f \"\$wrapper_tmp\"' EXIT"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f \"\$security_lib\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
security_lib="${GTBI_LIB_DIR:-$HOME/.gtbi/scripts/lib}/security.sh"
if [[ ! -f "$security_lib" ]]; then
  echo "agents.gemini: security library not found at $security_lib; skipping Gemini patch" >&2
  exit 0
fi
if [[ -n "${GTBI_CHECKSUMS_YAML:-}" ]]; then
  export CHECKSUMS_FILE="$GTBI_CHECKSUMS_YAML"
fi
# shellcheck disable=SC1090,SC1091
source "$security_lib"
if ! load_checksums; then
  echo "agents.gemini: checksum metadata unavailable; skipping Gemini patch" >&2
  exit 0
fi
find_nvm_node() {
  local node_path=""
  while IFS= read -r node_path; do
    if [[ -x "$node_path" ]]; then
      printf '%s\n' "$node_path"
      return 0
    fi
  done < <(compgen -G "$HOME/.nvm/versions/node/*/bin/node" | sort -Vr)
  return 1
}
if ! nvm_node="$(find_nvm_node)"; then
  nvm_url="${KNOWN_INSTALLERS[nvm]:-}"
  nvm_sha256="$(get_checksum nvm)"
  if [[ -z "$nvm_url" || -z "$nvm_sha256" ]]; then
    echo "agents.gemini: missing verified installer metadata for nvm; skipping Gemini patch" >&2
    exit 0
  fi
  if ! verify_checksum "$nvm_url" "$nvm_sha256" "nvm" | bash; then
    echo "agents.gemini: nvm installer verification failed; skipping Gemini patch" >&2
    exit 0
  fi
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "agents.gemini: nvm.sh not found at $NVM_DIR/nvm.sh; skipping Gemini patch" >&2
    exit 0
  fi
  . "$NVM_DIR/nvm.sh"
  if ! nvm install node || ! nvm alias default node; then
    echo "agents.gemini: failed to install Node.js via nvm; skipping Gemini patch" >&2
    exit 0
  fi
fi
if ! nvm_node="$(find_nvm_node)"; then
  echo "agents.gemini: nvm Node.js binary not found after install; skipping Gemini patch" >&2
  exit 0
fi
nvm_node_bin="${nvm_node%/node}"
if [[ -z "$nvm_node_bin" ]]; then
  echo "agents.gemini: nvm Node.js bin not found after install; skipping Gemini patch" >&2
  exit 0
fi
export PATH="$nvm_node_bin:$PATH"
patch_url="${KNOWN_INSTALLERS[gemini_patch]:-}"
patch_sha256="$(get_checksum gemini_patch)"
if [[ -z "$patch_url" || -z "$patch_sha256" ]]; then
  echo "agents.gemini: missing verified installer metadata for gemini_patch; skipping Gemini patch" >&2
  exit 0
fi
if ! verify_checksum "$patch_url" "$patch_sha256" "gemini_patch" | bash; then
  echo "agents.gemini: Gemini patch verification failed; skipping patch" >&2
  exit 0
fi
INSTALL_AGENTS_GEMINI
        then
            log_error "agents.gemini: install command failed: if [[ ! -f \"\$security_lib\" ]]; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: \"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_GEMINI'
target_bin="${GTBI_BIN_DIR:-$HOME/.local/bin}"
"$target_bin/gemini" --version || "$target_bin/gemini" --help
INSTALL_AGENTS_GEMINI
        then
            log_error "agents.gemini: verify failed: \"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help"
            return 1
        fi
    fi

    log_success "agents.gemini installed"
}

# OpenCode (multi-provider agent harness)
install_agents_opencode() {
    local module_id="agents.opencode"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "agents.opencode already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: agents.opencode"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if gtbi_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="opencode"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "agents.opencode: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "agents.opencode: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "agents.opencode: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "agents.opencode: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "agents.opencode: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "agents.opencode: gtbi_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for agents.opencode"
                false
            fi
        }; then
            log_warn "agents.opencode: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.opencode" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.opencode"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: opencode --version || opencode --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_AGENTS_OPENCODE'
opencode --version || opencode --help
INSTALL_AGENTS_OPENCODE
        then
            log_warn "agents.opencode: verify failed: opencode --version || opencode --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "agents.opencode" "verify failed: opencode --version || opencode --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "agents.opencode"
            fi
            return 0
        fi
    fi

    log_success "agents.opencode installed"
}

# Install all agents modules
install_agents() {
    log_section "Installing agents modules"
    install_agents_claude
    install_agents_codex
    install_agents_gemini
    install_agents_opencode
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_agents
fi
