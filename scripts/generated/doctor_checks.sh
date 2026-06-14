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

# Doctor checks generated from manifest
# Format: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL<TAB>RUN_AS
# Using tab delimiter to avoid conflicts with | in shell commands
# Commands are encoded (\n, \t, \\) and decoded via printf before execution

declare -a MANIFEST_CHECKS=(
    "base.system.1	Base packages + sane defaults	curl --version	required	root"
    "base.system.2	Base packages + sane defaults	git --version	required	root"
    "base.system.3	Base packages + sane defaults	jq --version	required	root"
    "base.system.4	Base packages + sane defaults	gpg --version	required	root"
    "users.ubuntu.1	Ensure target user + passwordless sudo + ssh keys	id \"\${TARGET_USER:-ubuntu}\"	required	root"
    "users.ubuntu.2	Ensure target user + passwordless sudo + ssh keys	[[ \"\${MODE:-vibe}\" != \"vibe\" ]] || runuser -u \"\${TARGET_USER:-ubuntu}\" -- sudo -n true	required	root"
    "base.filesystem.1	Create workspace and GTBI directories	test -d /data/projects	required	root"
    "base.filesystem.2	Create workspace and GTBI directories	test -f /data/projects/AGENTS.md	required	root"
    "base.filesystem.3	Create workspace and GTBI directories	# Resolve TARGET_HOME using generated helper functions. Doctor\\n# injects these helpers for manifest checks that reference\\n# gtbi_generated_* functions, so this stays consistent with\\n# installer target-home resolution and avoids inherited HOME leaks.\\nexplicit_target_home=\"\${TARGET_HOME:-}\"\\nif [[ -n \"\$explicit_target_home\" ]]; then\\n  explicit_target_home=\"\${explicit_target_home%/}\"\\nfi\\ntarget_home=\"\"\\nif [[ \"\${TARGET_USER:-ubuntu}\" == \"root\" ]]; then\\n  target_home=\"/root\"\\nelse\\n  _gtbi_passwd_entry=\"\$(gtbi_generated_getent_passwd_entry \"\${TARGET_USER:-ubuntu}\" 2>/dev/null || true)\"\\n  if [[ -n \"\$_gtbi_passwd_entry\" ]]; then\\n    target_home=\"\$(gtbi_generated_passwd_home_from_entry \"\$_gtbi_passwd_entry\" 2>/dev/null || true)\"\\n  else\\n    current_user=\"\$(gtbi_generated_resolve_current_user 2>/dev/null || true)\"\\n    current_home=\"\${HOME:-}\"\\n    if [[ -n \"\$current_home\" ]]; then\\n      current_home=\"\${current_home%/}\"\\n    fi\\n    if [[ -n \"\$current_user\" ]] && [[ \"\$current_user\" == \"\${TARGET_USER:-ubuntu}\" ]] && [[ -n \"\$current_home\" ]] && [[ \"\$current_home\" == /* ]] && [[ \"\$current_home\" != \"/\" ]] && { [[ -z \"\$explicit_target_home\" ]] || [[ \"\$current_home\" == \"\$explicit_target_home\" ]]; }; then\\n      target_home=\"\$current_home\"\\n    fi\\n    unset current_user current_home\\n  fi\\n  unset _gtbi_passwd_entry\\nfi\\nunset explicit_target_home\\nif [[ -z \"\$target_home\" ]] || [[ \"\$target_home\" == \"/\" ]] || [[ \"\$target_home\" != /* ]]; then\\n  echo \"ERROR: Unable to resolve TARGET_HOME for '\${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly (got: '\${target_home:-<empty>}')\" >&2\\n  exit 1\\nfi\\ntest -d \"\$target_home/.gtbi\"	required	root"
    "shell.zsh	Zsh shell package	zsh --version	required	root"
    "shell.omz.1	Oh My Zsh + Powerlevel10k + plugins + GTBI config	test -d ~/.oh-my-zsh	required	target_user"
    "shell.omz.2	Oh My Zsh + Powerlevel10k + plugins + GTBI config	test -f ~/.gtbi/zsh/gtbi.zshrc	required	target_user"
    "shell.omz.3	Oh My Zsh + Powerlevel10k + plugins + GTBI config	test -f ~/.p10k.zsh	required	target_user"
    "cli.modern.1	Modern CLI tools referenced by the zshrc intent	rg --version	required	root"
    "cli.modern.2	Modern CLI tools referenced by the zshrc intent	tmux -V	required	root"
    "cli.modern.3	Modern CLI tools referenced by the zshrc intent	fzf --version	required	root"
    "cli.modern.4	Modern CLI tools referenced by the zshrc intent	gh --version	required	root"
    "cli.modern.5	Modern CLI tools referenced by the zshrc intent	git-lfs version	required	root"
    "cli.modern.6	Modern CLI tools referenced by the zshrc intent	rsync --version	required	root"
    "cli.modern.7	Modern CLI tools referenced by the zshrc intent	strace --version	required	root"
    "cli.modern.8	Modern CLI tools referenced by the zshrc intent	sqlite3 --version	required	root"
    "cli.modern.9	Modern CLI tools referenced by the zshrc intent	command -v lsof	required	root"
    "cli.modern.10	Modern CLI tools referenced by the zshrc intent	command -v dig	required	root"
    "cli.modern.11	Modern CLI tools referenced by the zshrc intent	command -v nc	required	root"
    "cli.modern.12	Modern CLI tools referenced by the zshrc intent	command -v lsd || command -v eza	optional	root"
    "tools.lazygit	Lazygit (apt or binary fallback)	lazygit --version	required	root"
    "tools.lazydocker	Lazydocker (binary install)	lazydocker --version	required	root"
    "network.tailscale	Zero-config mesh VPN for secure remote VPS access	tailscale version	required	root"
    "network.ssh_keepalive.1	Configure SSH server keepalive to prevent VPN/NAT disconnects	grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config	optional	root"
    "network.ssh_keepalive.2	Configure SSH server keepalive to prevent VPN/NAT disconnects	grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config	optional	root"
    "lang.bun	Bun runtime for JS tooling and global CLIs	~/.bun/bin/bun --version	required	target_user"
    "lang.uv	uv Python tooling (fast venvs)	command -v uv >/dev/null 2>&1 && uv --version	required	target_user"
    "lang.rust.1	Rust nightly + cargo	~/.cargo/bin/cargo --version	required	target_user"
    "lang.rust.2	Rust nightly + cargo	~/.cargo/bin/rustup show | grep -q nightly	required	target_user"
    "lang.go	Go toolchain	go version	required	root"
    "lang.nvm	nvm + latest Node.js	export NVM_DIR=\"\$HOME/.nvm\"\\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"\\nnode --version	required	target_user"
    "tools.atuin	Atuin shell history (Ctrl-R superpowers)	~/.atuin/bin/atuin --version	required	target_user"
    "tools.zoxide	Zoxide (better cd)	command -v zoxide	required	root"
    "tools.ast_grep	ast-grep (syntax-aware code search/rewrite)	~/.cargo/bin/sg --version	required	target_user"
    "agents.claude	Claude Code	target_bin=\"\${GTBI_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help	required	target_user"
    "agents.codex	OpenAI Codex CLI	target_bin=\"\${GTBI_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help	required	target_user"
    "agents.gemini	Google Gemini CLI	target_bin=\"\${GTBI_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help	required	target_user"
    "agents.opencode	OpenCode (multi-provider agent harness)	opencode --version || opencode --help	optional	target_user"
    "stack.dolt	Dolt version-control database (required by bd/beads)	dolt version	required	root"
    "stack.bd	gastownhall beads (bd) - Dolt-backed local-first issue tracker for AI agents	bd --version	required	target_user"
    "stack.gastown	gastownhall Gastown (gt) - Go multi-agent orchestrator	gt version	required	target_user"
    "gtbi.workspace.1	Agent workspace with tmux session and project folder	test -d /data/projects/my_first_project	optional	target_user"
    "gtbi.workspace.2	Agent workspace with tmux session and project folder	gtbi_has_active_agents_alias() {\\n  local file=\"\${1:-}\"\\n  [[ -f \"\$file\" ]] || return 1\\n\\n  awk '\\n      /^[[:space:]]*#/ { next }\\n      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }\\n      END { exit(found ? 0 : 1) }\\n  ' \"\$file\" 2>/dev/null\\n}\\n\\ngtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc	optional	target_user"
    "gtbi.onboard	Onboarding TUI tutorial	onboard --help || command -v onboard	required	target_user"
    "gtbi.update	GTBI update command wrapper	gtbi-update --help || command -v gtbi-update	required	target_user"
    "gtbi.nightly	Nightly auto-update timer (systemd)	SYSTEMD_OFFLINE=1 systemctl --user is-enabled gtbi-nightly-update.timer 2>/dev/null	optional	target_user"
    "gtbi.doctor	GTBI doctor command for health checks	gtbi doctor --help || command -v gtbi	required	target_user"
)

# Execute a manifest check in the requested context without prompting.
run_manifest_check_command() {
    local run_as="$1"
    local cmd="$2"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-}"
    local explicit_target_home=""
    local resolved_target_home=""
    local target_path=""
    local current_user=""
    local current_home=""
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    explicit_target_home="$target_home"
    if [[ -n "$explicit_target_home" ]]; then
        explicit_target_home="${explicit_target_home%/}"
    fi

    if declare -f _gtbi_validate_target_user >/dev/null 2>&1; then
        _gtbi_validate_target_user "$target_user" "TARGET_USER" || return 1
    elif [[ -z "$target_user" ]] || [[ ! "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${target_user:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        return 1
    fi

    if declare -f _gtbi_resolve_target_home >/dev/null 2>&1; then
        resolved_target_home="$(_gtbi_resolve_target_home "$target_user" "$explicit_target_home" || true)"
    elif [[ "$target_user" == "root" ]]; then
        resolved_target_home="/root"
    else
        local _gtbi_passwd_entry=""
        _gtbi_passwd_entry="$(gtbi_generated_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$_gtbi_passwd_entry" ]]; then
            resolved_target_home="$(gtbi_generated_passwd_home_from_entry "$_gtbi_passwd_entry" 2>/dev/null || true)"
        else
            _gtbi_current_user="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"
            current_home="${HOME:-}"
            if [[ -n "$current_home" ]]; then
                current_home="${current_home%/}"
            fi
            if [[ "${_gtbi_current_user:-}" == "$target_user" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
                resolved_target_home="$current_home"
            fi
            unset _gtbi_current_user
        fi
        unset _gtbi_passwd_entry
    fi
    if [[ -n "$resolved_target_home" ]]; then
        target_home="${resolved_target_home%/}"
    fi

    if [[ "$cmd" == *"gtbi_generated_"* ]]; then
        local helper_prelude=""
        helper_prelude="$(declare -f gtbi_generated_system_binary_path gtbi_generated_resolve_current_user gtbi_generated_getent_passwd_entry gtbi_generated_passwd_home_from_entry 2>/dev/null || true)"
        if [[ -z "$helper_prelude" ]]; then
            log_error "Generated helper functions are unavailable for manifest check command"
            return 1
        fi
        cmd="${helper_prelude}"$'\n'"${cmd}"
    fi

    local env_bin=""
    local bash_bin=""
    env_bin="$(gtbi_generated_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(gtbi_generated_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then
        return 1
    fi

    case "$run_as" in
        target_user)
            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then
                log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
                return 1
            fi
            local target_bin="${GTBI_BIN_DIR:-$target_home/.local/bin}"
            if [[ -z "$target_bin" ]] || [[ "$target_bin" != /* ]] || [[ "$target_bin" == "/" ]]; then
                log_error "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${target_bin:-<empty>})"
                return 1
            fi
            local dir=""
            local seen_path=":"
            local target_path_prefix=""
            local -a target_path_entries=()
            for dir in \
                "$target_bin" \
                "$target_home/.local/bin" \
                "$target_home/.gtbi/bin" \
                "$target_home/.bun/bin" \
                "$target_home/.cargo/bin" \
                "$target_home/.atuin/bin" \
                "$target_home/go/bin" \
                "$target_home/google-cloud-sdk/bin" \
                "/usr/local/sbin" \
                "/usr/local/bin" \
                "/usr/sbin" \
                "/usr/bin" \
                "/sbin" \
                "/bin" \
                "/snap/bin"; do
                case "$seen_path" in
                    *":$dir:"*) ;;
                    *)
                        target_path_entries+=("$dir")
                        seen_path="${seen_path}${dir}:"
                        ;;
                esac
            done
            target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")
            target_path="$target_path_prefix${PATH:+:$PATH}"
            current_user="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"
            if [[ "${current_user:-}" == "$target_user" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            local runuser_bin=""
            runuser_bin="$(gtbi_generated_system_binary_path runuser 2>/dev/null || true)"
            if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
                "$runuser_bin" -u "$target_user" -- "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            local sudo_bin=""
            sudo_bin="$(gtbi_generated_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                "$sudo_bin" -n -u "$target_user" "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            return 1
            ;;
        root)
            if [[ $EUID -eq 0 ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            local sudo_bin=""
            sudo_bin="$(gtbi_generated_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            return 1
            ;;
        current|*)
            if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" "$bash_bin" -o pipefail -c "$cmd"
            else
                "$env_bin" TARGET_USER="$target_user" "$bash_bin" -o pipefail -c "$cmd"
            fi
            ;;
    esac
}

# Run all manifest checks
run_manifest_checks() {
    local passed=0
    local failed=0
    local skipped=0

    for check in "${MANIFEST_CHECKS[@]}"; do
        # Use tab as delimiter (safe - won't appear in commands)
        IFS=$'\t' read -r id desc cmd optional run_as <<< "$check"
        cmd="$(printf '%b' "$cmd")"
        run_as="${run_as:-current}"
        
        if run_manifest_check_command "$run_as" "$cmd" &>/dev/null; then
            echo -e "${GTBI_GREEN-\033[0;32m}[ok]${GTBI_NC-\033[0m} $id - $desc"
            ((passed += 1))
        elif [[ "$optional" = "optional" ]]; then
            echo -e "${GTBI_YELLOW-\033[0;33m}[skip]${GTBI_NC-\033[0m} $id - $desc"
            ((skipped += 1))
        else
            echo -e "${GTBI_RED-\033[0;31m}[fail]${GTBI_NC-\033[0m} $id - $desc"
            ((failed += 1))
        fi
    done

    echo ""
    echo "Passed: $passed, Failed: $failed, Skipped: $skipped"
    [[ $failed -eq 0 ]]
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    run_manifest_checks
fi
