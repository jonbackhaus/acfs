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

# Category: tools
# Modules: 5

# Lazygit (apt or binary fallback)
install_tools_lazygit() {
    local module_id="tools.lazygit"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "tools.lazygit already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if apt-get install -yq lazygit; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYGIT'
if apt-get install -yq lazygit; then
  exit 0
fi
# Fallback to binary install
LG_VER="0.44.1"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) LG_SHA="84682f4ad5a449d0a3ffbc8332200fe8651aee9dd91dcd8d87197ba6c2450dbc" ;;
  aarch64) LG_SHA="26a435f47b691325c086dad2f84daa6556df5af8efc52b6ed624fa657605c976" ;;
  *) echo "Unsupported arch for lazygit binary: $ARCH"; exit 0 ;;
esac

LG_URL="https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_Linux_${ARCH}.tar.gz"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_install.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL "$LG_URL" -o "$TMP_FILE"
echo "$LG_SHA $TMP_FILE" | sha256sum -c - || { echo "Checksum failed"; rm "$TMP_FILE"; exit 1; }

tar -xzf "$TMP_FILE" -C /usr/local/bin lazygit
chmod +x /usr/local/bin/lazygit
rm "$TMP_FILE"
INSTALL_TOOLS_LAZYGIT
        then
            log_error "tools.lazygit: install command failed: if apt-get install -yq lazygit; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: lazygit --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYGIT'
lazygit --version
INSTALL_TOOLS_LAZYGIT
        then
            log_error "tools.lazygit: verify failed: lazygit --version"
            return 1
        fi
    fi

    log_success "tools.lazygit installed"
}

# Lazydocker (binary install)
install_tools_lazydocker() {
    local module_id="tools.lazydocker"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "tools.lazydocker already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$ARCH\" in (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYDOCKER'
LD_VER="0.23.3"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) LD_SHA="1f3c7037326973b85cb85447b2574595103185f8ed067b605dd43cc201bc8786" ;;
  aarch64) LD_SHA="ae7bed0309289396d396b8502b2d78d153a4f8ce8add042f655332241e7eac31" ;;
  *) echo "Unsupported arch for lazydocker binary: $ARCH"; exit 0 ;;
esac

LD_URL="https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/lazydocker_${LD_VER}_Linux_${ARCH}.tar.gz"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_install.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL "$LD_URL" -o "$TMP_FILE"
echo "$LD_SHA $TMP_FILE" | sha256sum -c - || { echo "Checksum failed"; rm "$TMP_FILE"; exit 1; }

tar -xzf "$TMP_FILE" -C /usr/local/bin lazydocker
chmod +x /usr/local/bin/lazydocker
rm "$TMP_FILE"
INSTALL_TOOLS_LAZYDOCKER
        then
            log_error "tools.lazydocker: install command failed: case \"\$ARCH\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: lazydocker --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYDOCKER'
lazydocker --version
INSTALL_TOOLS_LAZYDOCKER
        then
            log_error "tools.lazydocker: verify failed: lazydocker --version"
            return 1
        fi
    fi

    log_success "tools.lazydocker installed"
}

# Atuin shell history (Ctrl-R superpowers)
install_tools_atuin() {
    local module_id="tools.atuin"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "tools.atuin already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: tools.atuin"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if gtbi_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="atuin"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "tools.atuin: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'sh' '-s' '--' '--non-interactive'; then
                            install_success=true
                        else
                            log_error "tools.atuin: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "tools.atuin: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "tools.atuin: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "tools.atuin: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "tools.atuin: gtbi_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for tools.atuin"
                false
            fi
        }; then
            log_error "tools.atuin: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.atuin/bin/atuin --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_ATUIN'
~/.atuin/bin/atuin --version
INSTALL_TOOLS_ATUIN
        then
            log_error "tools.atuin: verify failed: ~/.atuin/bin/atuin --version"
            return 1
        fi
    fi

    log_success "tools.atuin installed"
}

# Zoxide (better cd)
install_tools_zoxide() {
    local module_id="tools.zoxide"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "tools.zoxide already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if apt-get install -yq zoxide; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_ZOXIDE'
if apt-get install -yq zoxide; then
  exit 0
fi
# Fallback to pinned binary release. The upstream install.sh queries the
# GitHub JSON API (api.github.com), which is unauthenticated-rate-limited
# on CI runners; this redirect download is not.
ZOX_VER="0.9.9"
case "$(uname -m)" in
  x86_64)        ZOX_ARCH="x86_64-unknown-linux-musl";  ZOX_SHA="4ff057d3c4d957946937274c2b8be7af2a9bbae7f90a1b5e9baaa7cb65a20caa" ;;
  aarch64|arm64) ZOX_ARCH="aarch64-unknown-linux-musl"; ZOX_SHA="96e6ea2e47a71db42cb7ad5a36e9209c8cb3708f8ae00f6945573d0d93315cb0" ;;
  *) echo "Unsupported arch for zoxide: $(uname -m)"; exit 0 ;;
esac
ZOX_URL="https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOX_VER}/zoxide-${ZOX_VER}-${ZOX_ARCH}.tar.gz"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_zoxide.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT
curl -fsSL "$ZOX_URL" -o "$TMP_FILE"
echo "$ZOX_SHA $TMP_FILE" | sha256sum -c - || { echo "Checksum failed for zoxide"; rm "$TMP_FILE"; exit 1; }
tar -xzf "$TMP_FILE" -C /usr/local/bin zoxide
chmod +x /usr/local/bin/zoxide
INSTALL_TOOLS_ZOXIDE
        then
            log_error "tools.zoxide: install command failed: if apt-get install -yq zoxide; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v zoxide (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_ZOXIDE'
command -v zoxide
INSTALL_TOOLS_ZOXIDE
        then
            log_error "tools.zoxide: verify failed: command -v zoxide"
            return 1
        fi
    fi

    log_success "tools.zoxide installed"
}

# ast-grep (syntax-aware code search/rewrite)
install_tools_ast_grep() {
    local module_id="tools.ast_grep"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "tools.ast_grep already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$(uname -m)\" in (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_AST_GREP'
# Install the prebuilt release binary. `cargo install ast-grep` builds
# from source and fails to link on some Ubuntu releases (e.g. 25.10:
# rust-lld can't find crt*.o / -lc). The prebuilt binary is portable
# and reproducible (checksum-pinned).
AG_VER="0.43.0"
case "$(uname -m)" in
  x86_64)        AG_ARCH="x86_64-unknown-linux-gnu";  AG_SHA="a26253a9c821d935f7e383e40f0de7c2ca62a4121de1f73a6d81ec32eae631e0" ;;
  aarch64|arm64) AG_ARCH="aarch64-unknown-linux-gnu"; AG_SHA="e706846148493967f3ab8011334817edd86ce5acbec10718b2a7b40799c640ff" ;;
  *) echo "Unsupported arch for ast-grep: $(uname -m)"; exit 1 ;;
esac
AG_URL="https://github.com/ast-grep/ast-grep/releases/download/${AG_VER}/app-${AG_ARCH}.zip"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_astgrep.XXXXXX")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gtbi_astgrep_d.XXXXXX")"
trap 'rm -rf "$TMP_FILE" "$TMP_DIR"' EXIT
curl -fsSL "$AG_URL" -o "$TMP_FILE"
echo "$AG_SHA  $TMP_FILE" | sha256sum -c - || { echo "Checksum failed for ast-grep"; exit 1; }
unzip -o -q "$TMP_FILE" -d "$TMP_DIR"
mkdir -p "$HOME/.cargo/bin"
install -Dm755 "$TMP_DIR/sg" "$HOME/.cargo/bin/sg"
install -Dm755 "$TMP_DIR/ast-grep" "$HOME/.cargo/bin/ast-grep"
INSTALL_TOOLS_AST_GREP
        then
            log_error "tools.ast_grep: install command failed: case \"\$(uname -m)\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.cargo/bin/sg --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_AST_GREP'
~/.cargo/bin/sg --version
INSTALL_TOOLS_AST_GREP
        then
            log_error "tools.ast_grep: verify failed: ~/.cargo/bin/sg --version"
            return 1
        fi
    fi

    log_success "tools.ast_grep installed"
}

# Install all tools modules
install_tools() {
    log_section "Installing tools modules"
    install_tools_lazygit
    install_tools_lazydocker
    install_tools_atuin
    install_tools_zoxide
    install_tools_ast_grep
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_tools
fi
