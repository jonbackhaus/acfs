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

# Category: shell
# Modules: 2

# Zsh shell package
install_shell_zsh() {
    local module_id="shell.zsh"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "shell.zsh already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get install -yq zsh (root)"
    else
        if ! run_as_root_shell <<'INSTALL_SHELL_ZSH'
apt-get install -yq zsh
INSTALL_SHELL_ZSH
        then
            log_error "shell.zsh: install command failed: apt-get install -yq zsh"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: zsh --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_SHELL_ZSH'
zsh --version
INSTALL_SHELL_ZSH
        then
            log_error "shell.zsh: verify failed: zsh --version"
            return 1
        fi
    fi

    log_success "shell.zsh installed"
}

# Oh My Zsh + Powerlevel10k + plugins + GTBI config
install_shell_omz() {
    local module_id="shell.omz"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "shell.omz already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: shell.omz"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            # skip_if: already present — skip verified installer
            if test -d ~/.oh-my-zsh 2>/dev/null; then
                install_success=true
            else
                if gtbi_security_init; then
                    local known_installers_decl=""
                    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                    known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                    if [[ "$known_installers_decl" == declare\ -A* ]]; then
                        local tool="ohmyzsh"
                        local url=""
                        local expected_sha256=""

                        # Safe access with explicit empty default
                        url="${KNOWN_INSTALLERS[$tool]:-}"
                        if ! expected_sha256="$(get_checksum "$tool")"; then
                            log_error "shell.omz: get_checksum failed for tool '$tool'"
                            expected_sha256=""
                        fi

                        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                            if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'sh' '-s' '--' '--unattended' '--keep-zshrc'; then
                                install_success=true
                            else
                                log_error "shell.omz: verify_checksum or installer execution failed"
                            fi
                        else
                            if [[ -z "$url" ]]; then
                                log_error "shell.omz: KNOWN_INSTALLERS[$tool] not found"
                            fi
                            if [[ -z "$expected_sha256" ]]; then
                                log_error "shell.omz: checksum for '$tool' not found"
                            fi
                        fi
                    else
                        log_error "shell.omz: KNOWN_INSTALLERS array not available"
                    fi
                else
                    log_error "shell.omz: gtbi_security_init failed - check security.sh and checksums.yaml"
                fi
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for shell.omz"
                false
            fi
        }; then
            log_error "shell.omz: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install Powerlevel10k
if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-autosuggestions
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-syntax-highlighting
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.gtbi/zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install GTBI zshrc
GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
mkdir -p ~/.gtbi/zsh
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.gtbi/zsh/gtbi.zshrc "${GTBI_RAW}/gtbi/zsh/gtbi.zshrc"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: mkdir -p ~/.gtbi/zsh"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.gtbi/completions (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install GTBI shell completions (zsh)
GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
mkdir -p ~/.gtbi/completions
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.gtbi/completions/_gtbi "${GTBI_RAW}/scripts/completions/_gtbi"
# Also install bash completions for users who switch shells
curl "${CURL_ARGS[@]}" -o ~/.gtbi/completions/gtbi.bash "${GTBI_RAW}/scripts/completions/gtbi.bash"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: mkdir -p ~/.gtbi/completions"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if curl --help all 2>/dev/null | grep -q -- '--proto'; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install pre-configured Powerlevel10k settings (prevents config wizard on first login)
GTBI_RAW="${GTBI_RAW:-https://raw.githubusercontent.com/jonbackhaus/gtbi/${GTBI_REF:-main}}"
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.p10k.zsh "${GTBI_RAW}/gtbi/zsh/p10k.zsh"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if curl --help all 2>/dev/null | grep -q -- '--proto'; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -f ~/.zshrc ]] && ! gtbi_zshrc_is_managed_loader ~/.zshrc; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup loader .zshrc
gtbi_zshrc_is_managed_loader() {
  local file="${1:-}"

  [[ -f "$file" ]] || return 1
  awk '
    /^[[:space:]]*$/ { next }
    { lines[++line_count]=$0 }
    END {
      if (line_count == 2 &&
          lines[1] ~ /^# GTBI loader/ &&
          lines[2] == "source \"$HOME/.gtbi/zsh/gtbi.zshrc\"") {
        exit 0
      }
      exit 1
    }
  ' "$file" 2>/dev/null
}

if [[ -f ~/.zshrc ]] && ! gtbi_zshrc_is_managed_loader ~/.zshrc; then
  mv ~/.zshrc ~/.zshrc.bak.$(date +%s)
fi
echo '# GTBI loader' > ~/.zshrc
echo 'source "$HOME/.gtbi/zsh/gtbi.zshrc"' >> ~/.zshrc
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ -f ~/.zshrc ]] && ! gtbi_zshrc_is_managed_loader ~/.zshrc; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f ~/.profile ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup ~/.profile for bash login shells (prevents PATH warnings from installers)
profile_path_has_fragment() {
  local file="${1:-}"
  local fragment="${2:-}"

  [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
  awk -v fragment="$fragment" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
if [[ ! -f ~/.profile ]]; then
  echo '# ~/.profile: executed by bash for login shells' > ~/.profile
  echo '' >> ~/.profile
  echo '# User binary paths' >> ~/.profile
  echo "$profile_path_line" >> ~/.profile
elif grep -Fxq "$legacy_profile_path_line" ~/.profile; then
  sed -i "s|^$(printf '%s' "$legacy_profile_path_line" | sed 's/[][\\.^$*|]/\\&/g')$|$profile_path_line|" ~/.profile
elif ! profile_path_has_fragment ~/.profile '.local/bin' || ! profile_path_has_fragment ~/.profile '.atuin/bin'; then
  echo '' >> ~/.profile
  echo '# Added by GTBI - user binary paths' >> ~/.profile
  echo "$profile_path_line" >> ~/.profile
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -f ~/.profile ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f ~/.zprofile ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup ~/.zprofile for zsh login shells (zsh does NOT read ~/.profile)
profile_path_has_fragment() {
  local file="${1:-}"
  local fragment="${2:-}"

  [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
  awk -v fragment="$fragment" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
if [[ ! -f ~/.zprofile ]]; then
  echo '# ~/.zprofile: executed by zsh for login shells' > ~/.zprofile
  echo '' >> ~/.zprofile
  echo '# User binary paths' >> ~/.zprofile
  echo "$profile_path_line" >> ~/.zprofile
elif grep -Fxq "$legacy_profile_path_line" ~/.zprofile; then
  sed -i "s|^$(printf '%s' "$legacy_profile_path_line" | sed 's/[][\\.^$*|]/\\&/g')$|$profile_path_line|" ~/.zprofile
elif ! profile_path_has_fragment ~/.zprofile '.local/bin' || ! profile_path_has_fragment ~/.zprofile '.atuin/bin'; then
  echo '' >> ~/.zprofile
  echo '# Added by GTBI - user binary paths' >> ~/.zprofile
  echo "$profile_path_line" >> ~/.zprofile
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -f ~/.zprofile ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ \"\$SHELL\" != */zsh ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
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

# Set default shell
gtbi_external_shell_handoff_configured() {
  local bashrc_path="${1:-}"
  [[ -n "$bashrc_path" && -f "$bashrc_path" ]] || return 1

  awk '
      $0 == "# GTBI externally-managed shell handoff" { marker=1; next }
      marker && $0 ~ /^[[:space:]]*#/ { next }
      marker && index($0, "command -v zsh") && index($0, "GTBI_ZSH_HANDOFF_ACTIVE") { found=1; exit }
      marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
      END { exit(found ? 0 : 1) }
  ' "$bashrc_path" 2>/dev/null
}

if [[ "$SHELL" != */zsh ]]; then
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    echo "WARN: zsh not found; cannot set default shell automatically." >&2
    exit 0
  fi
  current_user="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"
  if [[ -z "$current_user" ]]; then
    echo "WARN: Unable to resolve current user; skipping default shell change." >&2
    exit 0
  fi
  passwd_entry="$(gtbi_generated_getent_passwd_entry "$current_user" 2>/dev/null || true)"
  local_entry=""
  if [[ -r /etc/passwd ]]; then
    local_entry="$(awk -F: -v user="$current_user" '$1 == user { print $0; exit }' /etc/passwd 2>/dev/null || true)"
  fi
  if [[ -n "$passwd_entry" ]] && [[ -z "$local_entry" ]]; then
    if ! gtbi_external_shell_handoff_configured ~/.bashrc; then
      if [[ -f ~/.bashrc ]] && [[ -s ~/.bashrc ]]; then
        last_char="$(tail -c 1 ~/.bashrc | od -An -t u1 | tr -d ' ' 2>/dev/null || true)"
        if [[ "$last_char" != "10" ]]; then
          printf '\n' >> ~/.bashrc
        fi
      fi
      {
        echo '# GTBI externally-managed shell handoff'
        echo 'if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${GTBI_ZSH_HANDOFF_ACTIVE:-}" ]]; then'
        echo '  export GTBI_ZSH_HANDOFF_ACTIVE=1'
        echo '  exec "$(command -v zsh)" -l'
        echo 'fi'
      } >> ~/.bashrc
    fi
    echo "WARN: $current_user is managed outside /etc/passwd; installed a bash-to-zsh handoff instead of using chsh." >&2
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chsh -s "$zsh_path" "$current_user"
  else
    if [[ -t 0 ]]; then
      if ! chsh -s "$zsh_path"; then
        echo "WARN: Could not change default shell automatically. Run: chsh -s $zsh_path" >&2
      fi
    else
      echo "WARN: Skipping shell change (no TTY). Run: chsh -s $zsh_path" >&2
    fi
  fi
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ \"\$SHELL\" != */zsh ]]; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d ~/.oh-my-zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -d ~/.oh-my-zsh
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -d ~/.oh-my-zsh"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -f ~/.gtbi/zsh/gtbi.zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -f ~/.gtbi/zsh/gtbi.zshrc
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -f ~/.gtbi/zsh/gtbi.zshrc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -f ~/.p10k.zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -f ~/.p10k.zsh
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -f ~/.p10k.zsh"
            return 1
        fi
    fi

    log_success "shell.omz installed"
}

# Install all shell modules
install_shell() {
    log_section "Installing shell modules"
    install_shell_zsh
    install_shell_omz
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_shell
fi
