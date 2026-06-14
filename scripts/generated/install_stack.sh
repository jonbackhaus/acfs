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

# Category: stack
# Modules: 3

# Dolt version-control database (required by bd/beads)
install_stack_dolt() {
    local module_id="stack.dolt"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "stack.dolt already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.dolt"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if gtbi_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="dolt"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.dolt: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_root_shell; then
                            install_success=true
                        else
                            log_error "stack.dolt: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.dolt: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.dolt: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.dolt: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.dolt: gtbi_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.dolt"
                false
            fi
        }; then
            log_error "stack.dolt: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dolt version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_STACK_DOLT'
dolt version
INSTALL_STACK_DOLT
        then
            log_error "stack.dolt: verify failed: dolt version"
            return 1
        fi
    fi

    log_success "stack.dolt installed"
}

# gastownhall beads (bd) - Dolt-backed local-first issue tracker for AI agents
install_stack_bd() {
    local module_id="stack.bd"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "stack.bd already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$(uname -m)\" in (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BD'
BD_VER="1.0.4"
case "$(uname -m)" in
  x86_64)  BD_ARCH="amd64"; BD_SHA="643e602e27f666c8726abff0f22001e2b5883988fa960204bde20a3129d448a5" ;;
  aarch64|arm64) BD_ARCH="arm64"; BD_SHA="48cdf571cd8b64bae81da829c1309e402bc12e6a4cc6b87606dfc9220b7ece60" ;;
  *) echo "Unsupported arch for beads (bd): $(uname -m)"; exit 1 ;;
esac

BD_URL="https://github.com/gastownhall/beads/releases/download/v${BD_VER}/beads_${BD_VER}_linux_${BD_ARCH}.tar.gz"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_install.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL "$BD_URL" -o "$TMP_FILE"
echo "$BD_SHA  $TMP_FILE" | sha256sum -c - || { echo "Checksum failed for bd"; rm "$TMP_FILE"; exit 1; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gtbi_bd.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$TMP_FILE"' EXIT
tar -xzf "$TMP_FILE" -C "$TMP_DIR"
install -Dm755 "$TMP_DIR/bd" "$HOME/.local/bin/bd"
INSTALL_STACK_BD
        then
            log_error "stack.bd: install command failed: case \"\$(uname -m)\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: bd --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BD'
bd --version
INSTALL_STACK_BD
        then
            log_error "stack.bd: verify failed: bd --version"
            return 1
        fi
    fi

    log_success "stack.bd installed"
}

# gastownhall Gastown (gt) - Go multi-agent orchestrator
install_stack_gastown() {
    local module_id="stack.gastown"
    gtbi_require_contract "module:${module_id}" || return 1

    if [[ "${DRY_RUN:-false}" != "true" ]] \
        && declare -f gtbi_should_skip_module >/dev/null 2>&1 \
        && gtbi_should_skip_module "$module_id"; then
        log_info "stack.gastown already installed; skipping"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$(uname -m)\" in (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_GASTOWN'
GT_VER="1.2.1"
case "$(uname -m)" in
  x86_64)  GT_ARCH="amd64"; GT_SHA="cc81f0a55c1f30986759ec8a924e232316c1532900d61af241965ebc0127eb05" ;;
  aarch64|arm64) GT_ARCH="arm64"; GT_SHA="955066db97c1782935bf6413fd5ad9dc3c699a76a5b38eb34c0f192484a240d4" ;;
  *) echo "Unsupported arch for Gastown (gt): $(uname -m)"; exit 1 ;;
esac

GT_URL="https://github.com/gastownhall/gastown/releases/download/v${GT_VER}/gastown_${GT_VER}_linux_${GT_ARCH}.tar.gz"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gtbi_install.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL "$GT_URL" -o "$TMP_FILE"
echo "$GT_SHA  $TMP_FILE" | sha256sum -c - || { echo "Checksum failed for gastown (gt)"; rm "$TMP_FILE"; exit 1; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gtbi_gt.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$TMP_FILE"' EXIT
tar -xzf "$TMP_FILE" -C "$TMP_DIR"
install -Dm755 "$TMP_DIR/gt" "$HOME/.local/bin/gt"
INSTALL_STACK_GASTOWN
        then
            log_error "stack.gastown: install command failed: case \"\$(uname -m)\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: gt version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_GASTOWN'
gt version
INSTALL_STACK_GASTOWN
        then
            log_error "stack.gastown: verify failed: gt version"
            return 1
        fi
    fi

    log_success "stack.gastown installed"
}

# Install all stack modules
install_stack() {
    log_section "Installing stack modules"
    install_stack_dolt
    install_stack_bd
    install_stack_gastown
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_stack
fi
