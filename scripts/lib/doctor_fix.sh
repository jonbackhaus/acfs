#!/usr/bin/env bash
# ============================================================
# GTBI Doctor --fix Implementation
# Safe, deterministic fixers with logging and undo capability
#
# Implements bd-31ps.6.2 based on spec in doctor_fix_spec.md
# ============================================================

# Prevent multiple sourcing
[[ -n "${_GTBI_DOCTOR_FIX_LOADED:-}" ]] && return 0
_GTBI_DOCTOR_FIX_LOADED=1

doctor_fix_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

doctor_fix_systemd_unit_reject_line_breaks() {
    local value="${1:-}"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

doctor_fix_systemd_unit_path_escape() {
    local value="${1:-}"
    local tab=$'\t'

    doctor_fix_systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//%/%%}"
    value="${value// /\\s}"
    value="${value//$tab/\\t}"
    printf '%s\n' "$value"
}

doctor_fix_systemd_unit_quote() {
    local value="${1:-}"
    local escape_dollar="${2:-false}"

    doctor_fix_systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    if [[ "$escape_dollar" == "true" ]]; then
        value="${value//\$/\$\$}"
    fi
    printf '"%s"\n' "$value"
}

doctor_fix_systemd_unit_exec_arg() {
    doctor_fix_systemd_unit_quote "${1:-}" true
}

doctor_fix_systemd_unit_exec_command() {
    doctor_fix_systemd_unit_quote "${1:-}" false
}

doctor_fix_systemd_unit_env_assignment() {
    local name="${1:-}"
    local value="${2:-}"

    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    doctor_fix_systemd_unit_quote "${name}=${value}" false
}

doctor_fix_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

doctor_fix_system_binary_path() {
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
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

doctor_fix_root_prefix() {
    local ref_name="${1:-}"

    [[ -n "$ref_name" ]] || return 1

    local -n _root_prefix_ref="$ref_name"
    _root_prefix_ref=()

    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    local sudo_bin=""
    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    [[ -n "$sudo_bin" ]] || return 1
    _root_prefix_ref=("$sudo_bin" -n)
}

doctor_fix_root_display_prefix() {
    local sudo_bin=""
    local display_prefix=""

    if [[ $EUID -eq 0 ]]; then
        printf '%s' ""
        return 0
    fi

    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        printf -v display_prefix '%q -n ' "$sudo_bin"
    else
        display_prefix="sudo -n "
    fi
    printf '%s' "$display_prefix"
}

doctor_fix_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(doctor_fix_system_binary_path getent 2>/dev/null || true)"
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

doctor_fix_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(doctor_fix_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(doctor_fix_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

doctor_fix_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(doctor_fix_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

doctor_fix_resolve_home_for_user() {
    local user="${1:-}"
    local home_candidate=""
    local passwd_entry=""

    doctor_fix_is_valid_username "$user" || [[ "$user" == "root" ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(doctor_fix_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        home_candidate="$(doctor_fix_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$home_candidate" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

doctor_fix_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(doctor_fix_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(doctor_fix_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

    if [[ -n "$base_home" ]] && [[ "$bin_dir" == "$base_home" || "$bin_dir" == "$base_home/"* ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.gtbi/bin) hinted_home="${bin_dir%/.gtbi/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
    esac
    hinted_home="$(doctor_fix_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(doctor_fix_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(doctor_fix_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

doctor_fix_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_home=""

    home_candidate="$(doctor_fix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"

    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ -n "$current_user" ]]; then
        passwd_home="$(doctor_fix_resolve_home_for_user "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_home" ]]; then
            printf '%s\n' "$passwd_home"
            return 0
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

doctor_fix_runtime_home() {
    local target_user_raw="${TARGET_USER:-}"
    local current_user=""
    local explicit_home=""
    local resolved_home=""

    explicit_home="$(doctor_fix_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -n "$target_user_raw" ]]; then
        doctor_fix_is_valid_username "$target_user_raw" || return 1

        resolved_home="$(doctor_fix_resolve_home_for_user "$target_user_raw" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "${resolved_home%/}"
            return 0
        fi

        current_user="$(doctor_fix_current_user 2>/dev/null || true)"
        if [[ -z "$current_user" ]] || [[ "$target_user_raw" != "$current_user" ]]; then
            return 1
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "${explicit_home%/}"
        return 0
    fi

    resolved_home="$(doctor_fix_resolve_current_home 2>/dev/null || true)"
    [[ -n "$resolved_home" ]] || return 1
    printf '%s\n' "${resolved_home%/}"
}

doctor_fix_runtime_gtbi_home() {
    local runtime_home=""
    local resolved_gtbi_home=""

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    resolved_gtbi_home="$(doctor_fix_sanitize_abs_nonroot_path "${GTBI_HOME:-}" 2>/dev/null || true)"

    if [[ -n "${TARGET_HOME:-}" ]] || [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s/.gtbi\n' "$runtime_home"
        return 0
    fi

    if [[ "$resolved_gtbi_home" == "$runtime_home/.gtbi" ]]; then
        printf '%s\n' "$resolved_gtbi_home"
        return 0
    fi

    if [[ -n "$resolved_gtbi_home" ]]; then
        printf '%s\n' "$resolved_gtbi_home"
        return 0
    fi

    printf '%s/.gtbi\n' "$runtime_home"
}

doctor_fix_runtime_user() {
    local runtime_user=""

    if [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s\n' "$TARGET_USER"
        return 0
    fi

    runtime_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ -n "$runtime_user" ]]; then
        printf '%s\n' "$runtime_user"
        return 0
    fi

    printf 'ubuntu\n'
}

doctor_fix_runtime_bin_dir() {
    local runtime_home=""
    local configured_bin=""

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    configured_bin="$(doctor_fix_validate_bin_dir_for_home "${GTBI_BIN_DIR:-}" "$runtime_home" 2>/dev/null || true)"
    if [[ -n "$configured_bin" ]]; then
        printf '%s\n' "$configured_bin"
        return 0
    fi

    printf '%s/.local/bin\n' "$runtime_home"
}

doctor_fix_binary_path() {
    local tool="$1"
    local runtime_home=""
    local primary_bin=""
    local candidate=""

    [[ -n "$tool" ]] || return 1

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    for candidate in \
        "$primary_bin/$tool" \
        "$runtime_home/.local/bin/$tool" \
        "$runtime_home/.gtbi/bin/$tool" \
        "$runtime_home/.cargo/bin/$tool" \
        "$runtime_home/.bun/bin/$tool" \
        "$runtime_home/.atuin/bin/$tool" \
        "$runtime_home/go/bin/$tool" \
        "$runtime_home/bin/$tool" \
        "/usr/local/go/bin/$tool" \
        "/usr/local/bin/$tool" \
        "/usr/bin/$tool" \
        "/bin/$tool" \
        "/usr/local/sbin/$tool" \
        "/usr/sbin/$tool" \
        "/sbin/$tool" \
        "/snap/bin/$tool"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

doctor_fix_runtime_path() {
    local runtime_home=""
    local primary_bin=""
    local current_path=""
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    runtime_home="$(doctor_fix_runtime_home)"
    [[ -n "$runtime_home" ]] || return 1

    primary_bin="$(doctor_fix_runtime_bin_dir)"
    current_path="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

    printf '%s\n' "$primary_bin:$runtime_home/.local/bin:$runtime_home/.gtbi/bin:$runtime_home/.cargo/bin:$runtime_home/.bun/bin:$runtime_home/.atuin/bin:$runtime_home/go/bin:$runtime_home/google-cloud-sdk/bin:$system_path_prefix:$current_path"
}

doctor_fix_curl() {
    local curl_bin=""

    curl_bin="$(doctor_fix_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

doctor_fix_system_curl() {
    local curl_bin=""

    curl_bin="$(doctor_fix_system_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

doctor_fix_log_file_path() {
    if [[ -n "${DOCTOR_FIX_LOG:-}" ]]; then
        printf '%s\n' "$DOCTOR_FIX_LOG"
        return 0
    fi

    printf '%s/.local/share/gtbi/doctor.log\n' "$(doctor_fix_runtime_home)"
}

# Seed autofix state paths from the resolved GTBI home before sourcing
# autofix.sh so direct root-home-mismatch invocations do not record changes in
# the caller HOME by accident.
if [[ -z "${GTBI_STATE_DIR:-}" ]]; then
    GTBI_STATE_DIR="$(doctor_fix_runtime_gtbi_home)/autofix"
fi
GTBI_CHANGES_FILE="${GTBI_CHANGES_FILE:-${GTBI_STATE_DIR}/changes.jsonl}"
GTBI_UNDOS_FILE="${GTBI_UNDOS_FILE:-${GTBI_STATE_DIR}/undos.jsonl}"
GTBI_BACKUPS_DIR="${GTBI_BACKUPS_DIR:-${GTBI_STATE_DIR}/backups}"
GTBI_LOCK_FILE="${GTBI_LOCK_FILE:-${GTBI_STATE_DIR}/.lock}"
GTBI_INTEGRITY_FILE="${GTBI_INTEGRITY_FILE:-${GTBI_STATE_DIR}/.integrity}"
export GTBI_STATE_DIR GTBI_CHANGES_FILE GTBI_UNDOS_FILE GTBI_BACKUPS_DIR GTBI_LOCK_FILE GTBI_INTEGRITY_FILE

# Source autofix library for change tracking
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "$SCRIPT_DIR/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$SCRIPT_DIR/autofix.sh"
elif [[ -f "$(doctor_fix_runtime_gtbi_home)/scripts/lib/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$(doctor_fix_runtime_gtbi_home)/scripts/lib/autofix.sh"
fi

# ============================================================
# Configuration
# ============================================================

DOCTOR_FIX_LOG="${DOCTOR_FIX_LOG:-}"
DOCTOR_FIX_DRY_RUN=false
DOCTOR_FIX_YES=false
DOCTOR_FIX_PROMPT=false

# Counters for fix summary
declare -g FIX_APPLIED=0
declare -g FIX_SKIPPED=0
declare -g FIX_FAILED=0
declare -g FIX_MANUAL=0

# Arrays to track fixes for summary
declare -ga FIXES_APPLIED=()
declare -ga FIXES_DRY_RUN=()
declare -ga FIXES_MANUAL=()
declare -ga FIXES_PROMPTED=()

# ============================================================
# Logging Helpers
# ============================================================

doctor_fix_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    local log_file=""
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_file="$(doctor_fix_log_file_path)"

    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$log_file"

    # Output to user
    case "$level" in
        INFO)  echo "  [fix] $message" ;;
        WARN)  echo "  [fix] WARNING: $message" >&2 ;;
        ERROR) echo "  [fix] ERROR: $message" >&2 ;;
        DRY)   echo "  [dry-run] Would: $message" ;;
    esac
}

# ============================================================
# Guard Helpers
# ============================================================

# Check if a file contains a specific line
file_contains_line() {
    local file="$1"
    local pattern="$2"

    [[ -f "$file" ]] && grep -qF "$pattern" "$file" 2>/dev/null
}

file_contains_exact_line() {
    local file="$1"
    local line="$2"

    [[ -f "$file" ]] && grep -Fxq "$line" "$file" 2>/dev/null
}

doctor_fix_sed_literal() {
    # This helper builds a basic-regex pattern for sed, not an extended regex.
    # Escaping literal parentheses would turn them into BRE capture groups and
    # make managed-marker removal miss lines like "(added by doctor --fix)".
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

doctor_fix_remove_exact_line_and_next() {
    local file="$1"
    local line="$2"
    local escaped_line=""

    [[ -f "$file" ]] || return 1
    escaped_line="$(doctor_fix_sed_literal "$line")"
    sed -i "\\|^${escaped_line}$|,+1d" "$file"
}

doctor_fix_file_has_active_gtbi_zshrc_source() {
    local file="${1:-}"

    [[ -f "$file" ]] || return 1
    awk '
        /^[[:space:]]*#/ { next }
        /(^|[[:space:];&|])(source|\.)[[:space:]]+.*\.gtbi\/zsh\/gtbi\.zshrc/ { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

# Check if directory is in PATH
dir_in_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

doctor_fix_nearest_existing_parent() {
    local path="${1:-}"
    path="$(dirname "$path")"

    while [[ "$path" != "/" && ! -d "$path" ]]; do
        path="$(dirname "$path")"
    done

    printf '%s\n' "$path"
}

doctor_fix_build_remove_path_rollback() {
    local target_path="${1:-}"
    local existing_parent="${2:-}"
    local target_parent=""
    local rollback_command=""

    target_parent="$(dirname "$target_path")"
    if [[ -z "$existing_parent" || "$existing_parent" == "$target_parent" ]]; then
        printf -v rollback_command 'rm -f %q' "$target_path"
        printf '%s\n' "$rollback_command"
        return 0
    fi

    printf -v rollback_command \
        'rm -f %q; cleanup_dir=%q; stop_dir=%q; while [[ "$cleanup_dir" != "$stop_dir" ]]; do rmdir "$cleanup_dir" 2>/dev/null || break; cleanup_dir=$(dirname "$cleanup_dir"); done' \
        "$target_path" "$target_parent" "$existing_parent"
    printf '%s\n' "$rollback_command"
}

doctor_fix_build_remove_tree_rollback() {
    local target_path="${1:-}"
    local existing_parent="${2:-}"
    local target_parent=""
    local rollback_command=""

    target_parent="$(dirname "$target_path")"
    if [[ -z "$existing_parent" || "$existing_parent" == "$target_parent" ]]; then
        printf -v rollback_command 'rm -rf %q' "$target_path"
        printf '%s\n' "$rollback_command"
        return 0
    fi

    printf -v rollback_command \
        'rm -rf %q; cleanup_dir=%q; stop_dir=%q; while [[ "$cleanup_dir" != "$stop_dir" ]]; do rmdir "$cleanup_dir" 2>/dev/null || break; cleanup_dir=$(dirname "$cleanup_dir"); done' \
        "$target_path" "$target_parent" "$existing_parent"
    printf '%s\n' "$rollback_command"
}

doctor_fix_build_remove_binary_rollback() {
    local target_path="${1:-}"
    local rollback_command=""

    [[ -n "$target_path" ]] || return 1
    printf -v rollback_command 'rm -f %q' "$target_path"
    printf '%s\n' "$rollback_command"
}

doctor_fix_run_rollback_command() {
    local rollback_command="$1"
    local requires_root="${2:-false}"
    local bash_bin=""
    local env_bin=""
    local sudo_bin=""
    local rollback_path="/usr/sbin:/usr/bin:/sbin:/bin"
    local -a rollback_env_args=()
    local -a sudo_cmd=()

    [[ -n "$rollback_command" ]] || return 1

    bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        doctor_fix_log ERROR "Rollback requires system bash but bash is unavailable"
        return 1
    fi

    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    if [[ -z "$env_bin" ]]; then
        doctor_fix_log ERROR "Rollback requires system env but env is unavailable"
        return 1
    fi

    if [[ "$requires_root" == "true" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
            [[ -n "$sudo_bin" ]] && sudo_cmd=("$sudo_bin" -n)
        fi
        if [[ $EUID -ne 0 && ${#sudo_cmd[@]} -eq 0 ]]; then
            doctor_fix_log ERROR "Rollback requires root but sudo is unavailable"
            return 1
        fi
    fi

    rollback_env_args=(
        -u BASH_ENV
        -u ENV
        -u SHELLOPTS
        -u BASHOPTS
        -u CDPATH
        -u GLOBIGNORE
        PATH="$rollback_path"
        "$bash_bin"
        --noprofile
        --norc
        -p
        -c "$rollback_command"
    )

    if [[ ${#sudo_cmd[@]} -gt 0 ]]; then
        "${sudo_cmd[@]}" "$env_bin" "${rollback_env_args[@]}"
    else
        "$env_bin" "${rollback_env_args[@]}"
    fi
}

doctor_fix_record_change_or_rollback() {
    local rollback_command="$1"
    local rollback_requires_root="${2:-false}"
    shift 2

    local description="${2:-change}"

    if record_change "$@" >/dev/null; then
        return 0
    fi

    doctor_fix_log ERROR "Failed to record change: $description"
    if [[ -n "$rollback_command" ]]; then
        if ! doctor_fix_run_rollback_command "$rollback_command" "$rollback_requires_root"; then
            doctor_fix_log ERROR "Failed to roll back after journaling failure: $description"
        fi
    fi

    return 1
}

doctor_fix_files_json() {
    autofix_files_json "$@"
}

doctor_fix_backups_json_array() {
    local backup_json="${1:-[]}"
    local jq_bin=""

    jq_bin="$(doctor_fix_system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        printf '%s\n' "${backup_json:-[]}" | "$jq_bin" -c 'if type == "object" then [.] else . end' 2>/dev/null && return 0
    fi

    printf '[]\n'
}

doctor_fix_require_security() {
    if [[ "${DOCTOR_FIX_SECURITY_READY:-false}" == "true" ]]; then
        return 0
    fi

    local security_script="$SCRIPT_DIR/security.sh"
    if [[ ! -r "$security_script" ]]; then
        security_script="$(doctor_fix_runtime_gtbi_home)/scripts/lib/security.sh"
    fi

    if [[ ! -r "$security_script" ]]; then
        doctor_fix_log WARN "security.sh not available; cannot verify upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$security_script" || return 1
    if ! load_checksums >/dev/null 2>&1; then
        doctor_fix_log WARN "checksums.yaml not available; refusing to run unverified installer scripts"
        return 1
    fi

    DOCTOR_FIX_SECURITY_READY=true
    return 0
}

doctor_fix_parse_env_assignment() {
    local assignment="${1:-}"
    local -n _name_ref="$2"
    local -n _value_ref="$3"

    _name_ref=""
    _value_ref=""
    [[ -n "$assignment" ]] || return 0

    if [[ "$assignment" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        _name_ref="${BASH_REMATCH[1]}"
        _value_ref="${BASH_REMATCH[2]}"
        return 0
    fi

    doctor_fix_log WARN "Invalid installer environment assignment: $assignment"
    return 1
}

doctor_fix_build_runtime_env_args() {
    local -n _env_args_ref="$1"
    local extra_env_assignment="${2:-}"
    local env_name=""
    local env_value=""
    local runtime_home=""
    local runtime_path=""
    local runtime_user=""

    _env_args_ref=()
    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
    runtime_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    if [[ -z "$runtime_home" || -z "$runtime_path" || -z "$runtime_user" ]]; then
        doctor_fix_log WARN "Unable to resolve runtime environment for verified installer"
        return 1
    fi
    doctor_fix_is_valid_username "$runtime_user" || [[ "$runtime_user" == "root" ]] || {
        doctor_fix_log WARN "Invalid runtime user for verified installer: $runtime_user"
        return 1
    }

    doctor_fix_parse_env_assignment "$extra_env_assignment" env_name env_value || return $?

    _env_args_ref=(
        "TARGET_USER=$runtime_user" \
        "TARGET_HOME=$runtime_home" \
        "HOME=$runtime_home" \
        "PATH=$runtime_path"
    )
    if [[ -n "$env_name" ]]; then
        _env_args_ref+=("$env_name=$env_value")
    fi
}

doctor_fix_run_in_runtime_context() {
    local extra_env_assignment="${1:-}"
    shift
    local env_bin=""
    local runuser_bin=""
    local runtime_user=""
    local sudo_bin=""
    local current_user=""
    local -a env_args=()

    [[ $# -gt 0 ]] || {
        doctor_fix_log WARN "doctor_fix_run_in_runtime_context requires a command"
        return 1
    }

    env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    [[ -n "$env_bin" ]] || {
        doctor_fix_log WARN "Unable to locate env for target-user command"
        return 1
    }

    doctor_fix_build_runtime_env_args env_args "$extra_env_assignment" || return $?

    runtime_user="${env_args[0]#TARGET_USER=}"
    current_user="$(doctor_fix_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$runtime_user" ]]; then
        "$env_bin" "${env_args[@]}" "$@"
        return $?
    fi

    runuser_bin="$(doctor_fix_system_binary_path runuser 2>/dev/null || true)"
    if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$runtime_user" -- "$env_bin" "${env_args[@]}" "$@"
        return $?
    fi

    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n -u "$runtime_user" "$env_bin" "${env_args[@]}" "$@"
        return $?
    fi

    doctor_fix_log WARN "Unable to run command as $runtime_user without passwordless sudo or root runuser"
    return 1
}

doctor_fix_run_verified_installer_with_env() {
    if [[ $# -lt 1 ]]; then
        doctor_fix_log WARN "doctor_fix_run_verified_installer_with_env requires a tool name"
        return 1
    fi

    local tool="$1"
    local installer_env_assignment=""
    shift
    if [[ $# -gt 0 ]]; then
        installer_env_assignment="$1"
        shift
    fi
    local bash_bin=""

    if ! doctor_fix_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256=""
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" || -z "$expected_sha256" ]]; then
        doctor_fix_log WARN "Missing verified installer metadata for $tool"
        return 1
    fi

    bash_bin="$(gtbi_security_required_binary_path bash)" || return $?

    (
        set -o pipefail
        verify_checksum "$url" "$expected_sha256" "$tool" | \
            doctor_fix_run_in_runtime_context "$installer_env_assignment" "$bash_bin" -s -- "$@"
    )
}

doctor_fix_run_verified_installer() {
    if [[ $# -lt 1 ]]; then
        doctor_fix_log WARN "doctor_fix_run_verified_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    shift

    doctor_fix_run_verified_installer_with_env "$tool" "" "$@"
}

doctor_fix_prepare_target_installer_tmpdir() {
    local tool="${1:-}"
    local runtime_home=""
    local tmpdir=""
    local tmpdir_parent=""
    local tmpdir_template=""

    [[ -n "$tool" ]] || {
        doctor_fix_log WARN "doctor_fix_prepare_target_installer_tmpdir requires a tool name"
        return 1
    }
    case "$tool" in
        .|..|*[!A-Za-z0-9._+-]*)
            doctor_fix_log WARN "Invalid tool name for installer TMPDIR: $tool"
            return 1
            ;;
    esac

    runtime_home="$(doctor_fix_runtime_home 2>/dev/null || true)"
    if [[ -z "$runtime_home" || "$runtime_home" != /* || "$runtime_home" == "/" ]]; then
        doctor_fix_log WARN "Cannot prepare installer TMPDIR without a valid runtime home"
        return 1
    fi

    tmpdir_parent="$runtime_home/.cache/gtbi/installer-tmp"
    tmpdir_template="$tmpdir_parent/${tool}.XXXXXX"
    case "$tmpdir_template" in
        *[[:space:]]*)
            doctor_fix_log WARN "Cannot prepare installer TMPDIR template with whitespace: $tmpdir_template"
            return 1
            ;;
    esac

    doctor_fix_run_in_runtime_context "" mkdir -p "$tmpdir_parent" || {
        doctor_fix_log WARN "Failed to prepare installer TMPDIR parent: $tmpdir_parent"
        return 1
    }

    tmpdir="$(doctor_fix_run_in_runtime_context "" mktemp -d "$tmpdir_template" 2>/dev/null)" || tmpdir=""
    if [[ -n "$tmpdir" ]]; then
        printf '%s\n' "$tmpdir"
        return 0
    fi

    doctor_fix_log WARN "Failed to create installer TMPDIR from template: $tmpdir_template"
    return 1
}

# ============================================================
# Fixer: PATH Ordering (fix.path.ordering)
# ============================================================

# Fix PATH ordering in shell config
# Ensures ~/.local/bin and other GTBI dirs are at front of PATH
fix_path_ordering() {
    local check_id="$1"
    local runtime_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    local target_file="${runtime_home}/.zshrc"

    # Required directories in order
    local -a path_dirs=(
        '$HOME/.local/bin'
        '$HOME/.bun/bin'
        '$HOME/.cargo/bin'
        '$HOME/go/bin'
        '$HOME/.atuin/bin'
    )

    # Build the export line
    local path_string
    path_string=$(IFS=:; echo "${path_dirs[*]}")
    local export_line="export PATH=\"${path_string}:\$PATH\""
    local marker="# GTBI PATH ordering (added by doctor --fix)"
    local marker_present=false

    # Guard: the marker alone is not enough; older fixes may lack newer paths.
    if file_contains_exact_line "$target_file" "$marker" &&
       file_contains_exact_line "$target_file" "$export_line"; then
        doctor_fix_log INFO "PATH ordering already configured in $target_file"
        return 0
    fi
    if file_contains_exact_line "$target_file" "$marker"; then
        marker_present=true
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.path.ordering|Prepend PATH directories to $target_file|$target_file|$export_line")
        doctor_fix_log DRY "Prepend PATH directories to $target_file"
        return 0
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    if [[ -f "$target_file" ]]; then
        backup_json=$(create_backup "$target_file" "path-ordering")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    else
        restore_command="if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file' && if ! grep -q '[^[:space:]]' '$target_file'; then rm -f '$target_file'; fi; fi"
    fi

    if [[ "$marker_present" == "true" ]]; then
        if ! doctor_fix_remove_exact_line_and_next "$target_file" "$marker"; then
            doctor_fix_log ERROR "Failed to remove stale PATH ordering block from $target_file"
            if [[ -n "$restore_command" ]]; then
                doctor_fix_run_rollback_command "$restore_command" false || true
            fi
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    fi

    # Apply fix
    if ! {
        echo ""
        echo "$marker"
        echo "$export_line"
    } >> "$target_file"; then
        doctor_fix_log ERROR "Failed to append PATH ordering to $target_file"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file'; fi}" \
        false \
        "path" "Added PATH ordering to $target_file" \
        "${restore_command:-if [[ -f '$target_file' ]]; then sed -i '/$marker/,+1d' '$target_file'; fi}" \
        false "info" "$(doctor_fix_files_json "$target_file")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Added PATH ordering to $target_file"
    FIXES_APPLIED+=("fix.path.ordering|Added PATH ordering to $target_file")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Config Copy (fix.config.copy)
# ============================================================

# Copy missing GTBI config files
fix_config_copy() {
    local check_id="$1"
    local src="$2"
    local dest="$3"
    local dest_parent=""
    local existing_parent=""
    local rollback_command=""

    # Guard: Source must exist
    if [[ ! -f "$src" ]]; then
        doctor_fix_log WARN "Source config not found: $src"
        return 1
    fi

    # Guard: Dest must not exist
    if [[ -f "$dest" ]]; then
        doctor_fix_log INFO "Config already exists: $dest"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.config.copy|Copy $(basename "$src") to $dest|$dest|cp -p $src $dest")
        doctor_fix_log DRY "Copy $(basename "$src") to $dest"
        return 0
    fi

    dest_parent="$(dirname "$dest")"
    existing_parent="$(doctor_fix_nearest_existing_parent "$dest")"
    rollback_command="$(doctor_fix_build_remove_path_rollback "$dest" "$existing_parent")"

    # Ensure parent directory exists
    if ! mkdir -p "$dest_parent"; then
        doctor_fix_log ERROR "Failed to create config destination directory: $dest_parent"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Copy file
    if ! cp -p "$src" "$dest"; then
        if ! doctor_fix_run_rollback_command "$rollback_command" false; then
            doctor_fix_log ERROR "Failed to clean copied-config destination after copy failure: $dest"
        fi
        doctor_fix_log ERROR "Failed to copy $(basename "$src") to $dest"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$rollback_command" \
        false \
        "config" "Copied config: $(basename "$src")" \
        "$rollback_command" \
        false "info" "$(doctor_fix_files_json "$dest")" "[]" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Copied $(basename "$src") to $dest"
    FIXES_APPLIED+=("fix.config.copy|Copied $(basename "$src") to $dest")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}


# ============================================================
# Fixer: Symlink Create (fix.symlink.create)
# ============================================================

# Create missing tool symlinks
fix_symlink_create() {
    local check_id="$1"
    local binary="$2"
    local symlink="$3"
    local symlink_parent=""
    local existing_parent=""
    local rollback_command=""

    # Guard: Binary must exist and be executable
    if [[ ! -x "$binary" ]]; then
        doctor_fix_log WARN "Binary not found or not executable: $binary"
        return 1
    fi

    # Guard: Symlink must not exist
    if [[ -e "$symlink" ]]; then
        doctor_fix_log INFO "Symlink already exists: $symlink"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.symlink.create|Create symlink $(basename "$symlink")|$symlink|ln -s $binary $symlink")
        doctor_fix_log DRY "Create symlink: $(basename "$symlink") -> $binary"
        return 0
    fi

    symlink_parent="$(dirname "$symlink")"
    existing_parent="$(doctor_fix_nearest_existing_parent "$symlink")"
    rollback_command="$(doctor_fix_build_remove_path_rollback "$symlink" "$existing_parent")"

    # Ensure symlink directory exists
    if ! mkdir -p "$symlink_parent"; then
        doctor_fix_log ERROR "Failed to create symlink directory: $symlink_parent"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Create symlink
    if ! ln -s "$binary" "$symlink"; then
        if ! doctor_fix_run_rollback_command "$rollback_command" false; then
            doctor_fix_log ERROR "Failed to clean symlink destination after symlink failure: $symlink"
        fi
        doctor_fix_log ERROR "Failed to create symlink: $symlink"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "$rollback_command" \
        false \
        "symlink" "Created symlink: $(basename "$symlink")" \
        "$rollback_command" \
        false "info" "$(doctor_fix_files_json "$symlink")" "[]" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Created symlink: $(basename "$symlink") -> $binary"
    FIXES_APPLIED+=("fix.symlink.create|Created symlink $(basename "$symlink")")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Plugin Clone (fix.plugin.clone)
# ============================================================

# Clone missing zsh plugins
fix_plugin_clone() {
    local check_id="$1"
    local plugin_name="$2"
    local repo_url="$3"
    local runtime_home=""
    local existing_parent=""
    local rollback_command=""
    runtime_home="$(doctor_fix_runtime_home)"

    local plugins_dir="${ZSH_CUSTOM:-$runtime_home/.oh-my-zsh/custom}/plugins"
    local target_dir="$plugins_dir/$plugin_name"

    # Guard: Must not already exist
    if [[ -d "$target_dir" ]]; then
        doctor_fix_log INFO "Plugin already installed: $plugin_name"
        return 0
    fi

    # Guard: Oh-my-zsh must be installed
    if [[ ! -d "$runtime_home/.oh-my-zsh" ]]; then
        doctor_fix_log WARN "Oh-my-zsh not installed, cannot install plugins"
        FIXES_MANUAL+=("fix.plugin.clone|Install Oh-my-zsh first|curl -fsSL https://install.ohmyz.sh/ | bash")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.plugin.clone|Clone zsh plugin: $plugin_name|$target_dir|git clone --depth 1 $repo_url $target_dir")
        doctor_fix_log DRY "Clone zsh plugin: $plugin_name"
        return 0
    fi

    existing_parent="$(doctor_fix_nearest_existing_parent "$target_dir")"
    rollback_command="$(doctor_fix_build_remove_tree_rollback "$target_dir" "$existing_parent")"

    # Ensure plugins directory exists
    if ! mkdir -p "$plugins_dir"; then
        doctor_fix_log ERROR "Failed to create plugins directory: $plugins_dir"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Clone plugin
    if git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null; then
        if ! doctor_fix_record_change_or_rollback \
            "$rollback_command" \
            false \
            "plugin" "Cloned zsh plugin: $plugin_name" \
            "$rollback_command" \
            false "info" "$(doctor_fix_files_json "$target_dir")" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Cloned zsh plugin: $plugin_name"
        FIXES_APPLIED+=("fix.plugin.clone|Cloned zsh plugin: $plugin_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        if [[ -d "$target_dir" ]]; then
            if ! doctor_fix_run_rollback_command "$rollback_command" false; then
                doctor_fix_log ERROR "Failed to clean partial plugin clone after clone failure: $plugin_name"
            fi
        fi
        doctor_fix_log ERROR "Failed to clone plugin: $plugin_name"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: GTBI Sourcing (fix.gtbi.sourcing)
# ============================================================

# Add GTBI config sourcing to .zshrc
fix_gtbi_sourcing() {
    local check_id="$1"
    local runtime_home=""
    local runtime_gtbi_home=""
    runtime_home="$(doctor_fix_runtime_home)"
    runtime_gtbi_home="$(doctor_fix_runtime_gtbi_home)"
    local zshrc="$runtime_home/.zshrc"
    local source_line='[[ -f ~/.gtbi/zsh/gtbi.zshrc ]] && source ~/.gtbi/zsh/gtbi.zshrc'
    local marker="# GTBI configuration (added by doctor --fix)"

    # Guard: comments mentioning gtbi.zshrc do not mean the loader is active.
    if doctor_fix_file_has_active_gtbi_zshrc_source "$zshrc"; then
        doctor_fix_log INFO "GTBI already sourced in .zshrc"
        return 0
    fi

    # Guard: Check if gtbi.zshrc exists
    if [[ ! -f "$runtime_gtbi_home/zsh/gtbi.zshrc" ]]; then
        doctor_fix_log WARN "GTBI config not found at ~/.gtbi/zsh/gtbi.zshrc"
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.gtbi.sourcing|Add GTBI sourcing to .zshrc|$zshrc|$source_line")
        doctor_fix_log DRY "Add GTBI sourcing to .zshrc"
        return 0
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    if [[ -f "$zshrc" ]]; then
        backup_json=$(create_backup "$zshrc" "gtbi-sourcing")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    else
        restore_command="if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc' && if ! grep -q '[^[:space:]]' '$zshrc'; then rm -f '$zshrc'; fi; fi"
    fi

    # Append sourcing line
    if ! {
        echo ""
        echo "$marker"
        echo "$source_line"
    } >> "$zshrc"; then
        doctor_fix_log ERROR "Failed to append GTBI sourcing to $zshrc"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Record change
    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc'; fi}" \
        false \
        "config" "Added GTBI sourcing to .zshrc" \
        "${restore_command:-if [[ -f '$zshrc' ]]; then sed -i '/$marker/,+1d' '$zshrc'; fi}" \
        false "info" "$(doctor_fix_files_json "$zshrc")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Added GTBI sourcing to .zshrc"
    FIXES_APPLIED+=("fix.gtbi.sourcing|Added GTBI sourcing to .zshrc")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fix Dispatcher
# ============================================================

# Dispatch a fix based on check ID
# Returns 0 if fix was applied or not needed, 1 if fix failed
dispatch_fix() {
    local check_id="$1"
    local check_status="$2"
    local fix_hint="${3:-}"  # Optional hint from check (e.g., file path)

    # Only fix failed or warned checks
    case "$check_status" in
        pass) return 0 ;;
        skip) return 0 ;;
    esac

    case "$check_id" in
        # PATH fixes
        path.*)
            fix_path_ordering "$check_id"
            ;;

        # Config file copies
        config.gtbi_zshrc)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../gtbi/zsh/gtbi.zshrc" \
                "$(doctor_fix_runtime_gtbi_home)/zsh/gtbi.zshrc"
            ;;
        config.tmux)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../gtbi/tmux/tmux.conf" \
                "$(doctor_fix_runtime_gtbi_home)/tmux/tmux.conf"
            ;;

        # Zsh plugins
        shell.plugins.zsh_autosuggestions)
            fix_plugin_clone "$check_id" "zsh-autosuggestions" \
                "https://github.com/zsh-users/zsh-autosuggestions"
            ;;
        shell.plugins.zsh_syntax_highlighting)
            fix_plugin_clone "$check_id" "zsh-syntax-highlighting" \
                "https://github.com/zsh-users/zsh-syntax-highlighting"
            ;;

        # GTBI sourcing
        shell.gtbi_sourced)
            fix_gtbi_sourcing "$check_id"
            ;;

        # SSH server (fixes #161/#162)
        network.ssh_server)
            fix_ssh_server "$check_id"
            ;;

        # SSH keepalive
        network.ssh_keepalive|network.ssh_keepalive.*)
            fix_ssh_keepalive "$check_id"
            ;;

        # Agent CLI tools (fixes #213)
        agent.claude)
            fix_verified_install "$check_id" "claude" "claude"
            ;;
        agent.codex)
            fix_stack_install "$check_id" "codex" \
                "bun install -g --trust @openai/codex@latest"
            ;;
        agent.gemini)
            fix_stack_install "$check_id" "gemini" \
                "bun install -g --trust @google/gemini-cli@latest"
            ;;

        # Agent aliases/functions (fixes #163)
        agent.alias.*)
            fix_gtbi_sourcing "$check_id"
            ;;

        # Identity fixes
        identity.passwordless_sudo)
            fix_passwordless_sudo "$check_id"
            ;;

        # Manual fixes (log suggestion only)
        shell.ohmyzsh|shell.p10k|*.apt_install|*.sudo_required)
            if [[ -n "$fix_hint" ]]; then
                FIXES_MANUAL+=("$check_id|Requires manual action|$fix_hint")
            fi
            FIX_MANUAL=$((FIX_MANUAL + 1))
            return 0
            ;;

        *)
            # Unknown check - skip silently
            FIX_SKIPPED=$((FIX_SKIPPED + 1))
            return 0
            ;;
    esac
}

# ============================================================
# Fixer: Stack Install (fix.stack.install)
# ============================================================

# Install missing stack tools via their upstream installer
fix_stack_install() {
    local check_id="$1"
    local binary_name="$2"
    local install_cmd="$3"
    local installed_path=""
    local rollback_command=""
    local runtime_home=""
    local runtime_path=""

    runtime_home="$(doctor_fix_runtime_home)"
    runtime_path="$(doctor_fix_runtime_path 2>/dev/null || true)"
    if [[ -z "$runtime_home" || -z "$runtime_path" ]]; then
        doctor_fix_log ERROR "Failed to resolve runtime environment for $binary_name install"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Guard: Check if already installed for the runtime home
    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        doctor_fix_log INFO "$binary_name already installed"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name|~/.local/bin/$binary_name|$install_cmd")
        doctor_fix_log DRY "Install $binary_name"
        return 0
    fi

    # Run installer inside the runtime home so shell expansions, relative paths,
    # and PATH resolution match the target account instead of the caller shell.
    if (
        cd "$runtime_home" &&
        env HOME="$runtime_home" PATH="$runtime_path" bash -c "$install_cmd"
    ) 2>/dev/null; then
        hash -r
        installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
        if [[ -z "$installed_path" ]]; then
            doctor_fix_log ERROR "Installer reported success but $binary_name is still unavailable"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        rollback_command="$(doctor_fix_build_remove_binary_rollback "$installed_path")"

        if ! doctor_fix_record_change_or_rollback \
            "$rollback_command" \
            false \
            "install" "Installed $binary_name" \
            "# Manual rollback required: remove $binary_name if undesired" \
            false "info" "$(doctor_fix_files_json "$installed_path")" "[]" "[]"; then
            hash -r
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed $binary_name"
        FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    fi

    doctor_fix_log ERROR "Failed to install $binary_name"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

fix_verified_install_with_env() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    local installer_env_assignment="$4"
    shift 4
    local args=("$@")
    local args_display="${args[*]:-}"
    local dry_run_env_display=""
    local installed_path=""
    local rollback_command=""

    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        if [[ "$binary_name" == "bv" && "$installed_path" == *"/google-cloud-sdk/"* ]]; then
            installed_path=""
        else
            doctor_fix_log INFO "$binary_name already installed"
            return 0
        fi
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        [[ -n "$installer_env_assignment" ]] && dry_run_env_display="${installer_env_assignment} "
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name via verified installer|~/.local/bin/$binary_name|verified:$tool ${dry_run_env_display}${args_display}")
        doctor_fix_log DRY "Install $binary_name via verified installer"
        return 0
    fi

    if doctor_fix_run_verified_installer_with_env "$tool" "$installer_env_assignment" "${args[@]}" >/dev/null 2>&1; then
        hash -r
        installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
        if [[ -n "$installed_path" ]]; then
            rollback_command="$(doctor_fix_build_remove_binary_rollback "$installed_path")"
            if ! doctor_fix_record_change_or_rollback \
                "$rollback_command" \
                false \
                "install" "Installed $binary_name via verified installer" \
                "# Manual rollback required: remove $binary_name if undesired" \
                false "info" "$(doctor_fix_files_json "$installed_path")" "[]" "[]"; then
                hash -r
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi

            doctor_fix_log INFO "Installed $binary_name via verified installer"
            FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name via verified installer")
            FIX_APPLIED=$((FIX_APPLIED + 1))
            return 0
        fi
    fi

    doctor_fix_log ERROR "Failed to install $binary_name via verified installer"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

fix_verified_install_with_target_tmpdir() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    shift 3
    local installer_tmpdir=""

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        installer_tmpdir="$(doctor_fix_runtime_home)/.cache/gtbi/installer-tmp/${tool}.XXXXXX"
    else
        installer_tmpdir="$(doctor_fix_prepare_target_installer_tmpdir "$tool")" || {
            doctor_fix_log ERROR "Failed to prepare installer TMPDIR for $binary_name"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        }
    fi

    fix_verified_install_with_env "$check_id" "$binary_name" "$tool" "TMPDIR=$installer_tmpdir" "$@"
}

fix_verified_install() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    shift 3
    local args=("$@")
    local args_display="${args[*]:-}"
    local installed_path=""
    local rollback_command=""

    installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
    if [[ -n "$installed_path" ]]; then
        if [[ "$binary_name" == "bv" && "$installed_path" == *"/google-cloud-sdk/"* ]]; then
            installed_path=""
        else
            doctor_fix_log INFO "$binary_name already installed"
            return 0
        fi
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name via verified installer|~/.local/bin/$binary_name|verified:$tool ${args_display}")
        doctor_fix_log DRY "Install $binary_name via verified installer"
        return 0
    fi

    if doctor_fix_run_verified_installer "$tool" "${args[@]}" >/dev/null 2>&1; then
        hash -r
        installed_path="$(doctor_fix_binary_path "$binary_name" 2>/dev/null || true)"
        if [[ -n "$installed_path" ]]; then
            rollback_command="$(doctor_fix_build_remove_binary_rollback "$installed_path")"
            if ! doctor_fix_record_change_or_rollback \
                "$rollback_command" \
                false \
                "install" "Installed $binary_name via verified installer" \
                "# Manual rollback required: remove $binary_name if undesired" \
                false "info" "$(doctor_fix_files_json "$installed_path")" "[]" "[]"; then
                hash -r
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi

            doctor_fix_log INFO "Installed $binary_name via verified installer"
            FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name via verified installer")
            FIX_APPLIED=$((FIX_APPLIED + 1))
            return 0
        fi
    fi

    doctor_fix_log ERROR "Failed to install $binary_name via verified installer"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: SSH Server (fix.ssh.server)
# ============================================================

# Install and enable SSH server
# ============================================================
# Fixer: Passwordless sudo (identity.passwordless_sudo)
# ============================================================

fix_passwordless_sudo() {
    local check_id="$1"
    local sudoers_file="${DOCTOR_FIX_SUDOERS_FILE:-/etc/sudoers.d/90-ubuntu-gtbi}"
    local target_user=""
    local root_display=""
    local tee_bin=""
    local chmod_bin=""
    local visudo_bin=""
    local -a root_cmd=()

    target_user="$(doctor_fix_runtime_user 2>/dev/null || true)"
    if [[ -z "$target_user" ]]; then
        doctor_fix_log ERROR "Cannot determine target user for passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    root_display="$(doctor_fix_root_display_prefix)"
    tee_bin="$(doctor_fix_system_binary_path tee 2>/dev/null || true)"
    chmod_bin="$(doctor_fix_system_binary_path chmod 2>/dev/null || true)"
    visudo_bin="$(doctor_fix_system_binary_path visudo 2>/dev/null || true)"

    # Guard: already configured (sudo -n true succeeds)
    local sudo_bin=""
    sudo_bin="$(doctor_fix_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]] && "$sudo_bin" -n true 2>/dev/null; then
        doctor_fix_log INFO "Passwordless sudo already configured"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("$check_id|Write passwordless sudoers entry for $target_user|$sudoers_file|${root_display}tee $sudoers_file")
        doctor_fix_log DRY "Write $sudoers_file with NOPASSWD for $target_user"
        return 0
    fi

    if [[ -z "$tee_bin" ]]; then
        doctor_fix_log ERROR "tee not found; cannot write sudoers file"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if [[ -z "$chmod_bin" ]]; then
        doctor_fix_log ERROR "chmod not found; cannot set sudoers file permissions"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if ! doctor_fix_root_prefix root_cmd; then
        doctor_fix_log ERROR "Cannot write sudoers file without root or passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Write the sudoers entry
    if ! printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$target_user" | "${root_cmd[@]}" "$tee_bin" "$sudoers_file" > /dev/null; then
        doctor_fix_log ERROR "Failed to write $sudoers_file"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    if ! "${root_cmd[@]}" "$chmod_bin" 440 "$sudoers_file"; then
        doctor_fix_log ERROR "Failed to set permissions on $sudoers_file"
        "${root_cmd[@]}" rm -f "$sudoers_file" 2>/dev/null || true
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Validate the sudoers file (remove it if invalid)
    if [[ -n "$visudo_bin" ]] && ! "${root_cmd[@]}" "$visudo_bin" -c -f "$sudoers_file" &>/dev/null; then
        doctor_fix_log ERROR "Generated sudoers file failed visudo validation; removing"
        "${root_cmd[@]}" rm -f "$sudoers_file" 2>/dev/null || true
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    local rollback_command
    printf -v rollback_command 'rm -f %q' "$sudoers_file"

    if ! doctor_fix_record_change_or_rollback \
        "$rollback_command" \
        true \
        "config" "Enabled passwordless sudo for $target_user" \
        "$rollback_command" \
        true "info" "$(doctor_fix_files_json "$sudoers_file")" "[]" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Enabled passwordless sudo for $target_user in $sudoers_file"
    FIXES_APPLIED+=("$check_id|Enabled passwordless sudo for $target_user")
    FIX_APPLIED=$((FIX_APPLIED + 1))
    return 0
}

fix_ssh_server() {
    local check_id="$1"
    local apt_get_bin=""
    local root_display=""
    local sshd_bin=""
    local systemctl_bin=""
    local -a root_cmd=()

    root_display="$(doctor_fix_root_display_prefix)"
    sshd_bin="$(doctor_fix_system_binary_path sshd 2>/dev/null || true)"
    systemctl_bin="$(doctor_fix_system_binary_path systemctl 2>/dev/null || true)"

    # Guard: Check if already installed
    if [[ -n "$sshd_bin" ]] || [[ -f /etc/ssh/sshd_config ]]; then
        # Check if running
        if [[ -n "$systemctl_bin" && -d /run/systemd/system ]]; then
            if "$systemctl_bin" is-active --quiet ssh 2>/dev/null || "$systemctl_bin" is-active --quiet sshd 2>/dev/null; then
                doctor_fix_log INFO "SSH server already installed and running"
                return 0
            fi

            # Installed but not running - enable and start
            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                FIXES_DRY_RUN+=("fix.ssh.server|Enable and start SSH server|/etc/ssh/sshd_config|${root_display}systemctl enable --now ssh")
                doctor_fix_log DRY "Enable and start SSH server"
                return 0
            fi

            if ! doctor_fix_root_prefix root_cmd; then
                doctor_fix_log ERROR "Cannot start SSH server without root or passwordless sudo"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi

            if "${root_cmd[@]}" "$systemctl_bin" enable --now ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" enable --now sshd 2>/dev/null; then
                if ! doctor_fix_record_change_or_rollback \
                    "$(printf '%q disable --now ssh 2>/dev/null || %q disable --now sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")" \
                    true \
                    "service" "Enabled and started SSH server" \
                    "$(printf '%q disable --now ssh 2>/dev/null || %q disable --now sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")" \
                    true "info" "[\"/etc/ssh/sshd_config\"]" "[]" "[]"; then
                    FIX_FAILED=$((FIX_FAILED + 1))
                    return 1
                fi

                doctor_fix_log INFO "Enabled and started SSH server"
                FIXES_APPLIED+=("fix.ssh.server|Enabled and started SSH server")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                return 0
            fi

            doctor_fix_log ERROR "Failed to start SSH server"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
        return 0
    fi

    # Not installed - install it
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.server|Install openssh-server|/etc/ssh/sshd_config|${root_display}apt-get install -y openssh-server")
        doctor_fix_log DRY "Install openssh-server"
        return 0
    fi

    apt_get_bin="$(doctor_fix_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        doctor_fix_log ERROR "apt-get not found; cannot install openssh-server"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if [[ -z "$systemctl_bin" ]]; then
        doctor_fix_log ERROR "systemctl not found; cannot enable SSH server"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if ! doctor_fix_root_prefix root_cmd; then
        doctor_fix_log ERROR "Cannot install openssh-server without root or passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    if "${root_cmd[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 "$apt_get_bin" install -y openssh-server 2>/dev/null; then
        if ! ("${root_cmd[@]}" "$systemctl_bin" enable --now ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" enable --now sshd 2>/dev/null); then
            doctor_fix_log ERROR "Installed openssh-server but failed to enable/start SSH service"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        if ! doctor_fix_record_change_or_rollback \
            "" \
            false \
            "install" "Installed and enabled openssh-server" \
            "# Manual rollback required: remove openssh-server if undesired" \
            true "info" "[\"/etc/ssh/sshd_config\"]" "[]" "[]"; then
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi

        doctor_fix_log INFO "Installed and enabled openssh-server"
        FIXES_APPLIED+=("fix.ssh.server|Installed and enabled openssh-server")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    fi

    doctor_fix_log ERROR "Failed to install openssh-server"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: SSH Keepalive (fix.ssh.keepalive)
# ============================================================

# Configure SSH keepalive settings
fix_ssh_keepalive() {
    local check_id="$1"
    local sshd_config="${DOCTOR_FIX_SSHD_CONFIG:-/etc/ssh/sshd_config}"
    local marker="# GTBI: SSH keepalive settings (added by doctor --fix)"
    local fallback_restore_command=""
    local root_display=""
    local systemctl_bin=""
    local tee_bin=""
    local -a root_cmd=()

    root_display="$(doctor_fix_root_display_prefix)"
    systemctl_bin="$(doctor_fix_system_binary_path systemctl 2>/dev/null || true)"
    tee_bin="$(doctor_fix_system_binary_path tee 2>/dev/null || true)"

    # Guard: sshd_config must exist
    if [[ ! -f "$sshd_config" ]]; then
        doctor_fix_log WARN "sshd_config not found, install openssh-server first"
        FIXES_MANUAL+=("$check_id|Install openssh-server first|${root_display}apt-get install -y openssh-server")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Guard: Check if already configured
    if grep -qE '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$sshd_config" 2>/dev/null; then
        doctor_fix_log INFO "SSH keepalive already configured"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.keepalive|Configure SSH keepalive|$sshd_config|${root_display}tee -a $sshd_config")
        doctor_fix_log DRY "Configure SSH keepalive in $sshd_config"
        return 0
    fi

    if [[ -z "$tee_bin" ]]; then
        doctor_fix_log ERROR "tee not found; cannot append SSH keepalive settings"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
    if ! doctor_fix_root_prefix root_cmd; then
        doctor_fix_log ERROR "Cannot configure SSH keepalive without root or passwordless sudo"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Create backup
    local backup_json=""
    local restore_command=""
    printf -v fallback_restore_command \
        "sed -i '/%s/,+2d' %q" \
        "$marker" "$sshd_config"
    if [[ -f "$sshd_config" ]]; then
        backup_json=$(create_backup "$sshd_config" "ssh-keepalive")
        restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    fi

    # Apply settings
    if ! {
        echo ""
        echo "$marker"
        echo "ClientAliveInterval 60"
        echo "ClientAliveCountMax 3"
    } | "${root_cmd[@]}" "$tee_bin" -a "$sshd_config" > /dev/null; then
        doctor_fix_log ERROR "Failed to append SSH keepalive settings to $sshd_config"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    # Restart sshd to apply
    if [[ -n "$systemctl_bin" ]]; then
        "${root_cmd[@]}" "$systemctl_bin" reload ssh 2>/dev/null || "${root_cmd[@]}" "$systemctl_bin" reload sshd 2>/dev/null || true
    fi

    local reload_rollback=""
    if [[ -n "$systemctl_bin" ]]; then
        reload_rollback="$(printf '%q reload ssh 2>/dev/null || %q reload sshd 2>/dev/null || true' "$systemctl_bin" "$systemctl_bin")"
    else
        reload_rollback="true"
    fi

    if ! doctor_fix_record_change_or_rollback \
        "${restore_command:-$fallback_restore_command}; $reload_rollback" \
        true \
        "config" "Configured SSH keepalive in $sshd_config" \
        "${restore_command:-$fallback_restore_command}; $reload_rollback" \
        true "info" "$(doctor_fix_files_json "$sshd_config")" "$(doctor_fix_backups_json_array "${backup_json:-[]}")" "[]"; then
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi

    doctor_fix_log INFO "Configured SSH keepalive (ClientAliveInterval 60, ClientAliveCountMax 3)"
    FIXES_APPLIED+=("fix.ssh.keepalive|Configured SSH keepalive settings")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}


# ============================================================
# Summary Output
# ============================================================

# Print fix summary
print_fix_summary() {
    echo ""
    echo "========================================================================"
    echo "  Doctor --fix Summary"
    echo "========================================================================"

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "  Mode: DRY-RUN (no changes made)"
        echo ""

        if [[ ${#FIXES_DRY_RUN[@]} -gt 0 ]]; then
            echo "  Would apply the following fixes:"
            for fix in "${FIXES_DRY_RUN[@]}"; do
                IFS='|' read -r id desc file cmd <<< "$fix"
                echo ""
                echo "    [$id]"
                echo "      Action: $desc"
                echo "      File: $file"
                echo "      Command: $cmd"
            done
        else
            echo "  No fixes needed."
        fi
    else
        echo "  Applied: $FIX_APPLIED"
        echo "  Skipped: $FIX_SKIPPED"
        echo "  Failed:  $FIX_FAILED"
        echo "  Manual:  $FIX_MANUAL"

        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            echo ""
            echo "  Applied fixes:"
            for fix in "${FIXES_APPLIED[@]}"; do
                IFS='|' read -r id desc <<< "$fix"
                echo "    [$id] $desc"
            done
        fi
    fi

    if [[ ${#FIXES_MANUAL[@]} -gt 0 ]]; then
        echo ""
        echo "  Manual fixes needed:"
        for fix in "${FIXES_MANUAL[@]}"; do
            IFS='|' read -r id desc cmd <<< "$fix"
            echo "    [$id] $desc"
            echo "      Run: $cmd"
        done
    fi

    echo ""
    echo "========================================================================"

    # Show undo hint if changes were made
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]] && [[ $FIX_APPLIED -gt 0 ]]; then
        echo ""
        echo "  To undo changes: gtbi undo --list"
        echo ""
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

# Run doctor --fix
# Usage: run_doctor_fix [--dry-run] [--yes] [--only <categories>]
run_doctor_fix() {
    local only_categories=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DOCTOR_FIX_DRY_RUN=true; shift ;;
            --yes) DOCTOR_FIX_YES=true; shift ;;
            --prompt) DOCTOR_FIX_PROMPT=true; shift ;;
            --only)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --only requires a category value" >&2
                    return 1
                fi
                only_categories="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done

    # Initialize autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        start_autofix_session || {
            echo "ERROR: Failed to start autofix session" >&2
            return 1
        }
    fi

    # Reset counters
    FIX_APPLIED=0
    FIX_SKIPPED=0
    FIX_FAILED=0
    FIX_MANUAL=0
    FIXES_APPLIED=()
    FIXES_DRY_RUN=()
    FIXES_MANUAL=()
    FIXES_PROMPTED=()

    echo ""
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: gtbi doctor --fix"
        echo "Scanning for fixable issues..."
    else
        echo "Running: gtbi doctor --fix"
        echo "Applying safe fixes..."
    fi
    echo ""

    # The actual fixes are dispatched by the caller (doctor.sh)
    # based on check results. This function sets up the environment.

    return 0
}

# Finalize doctor --fix
finalize_doctor_fix() {
    # Print summary
    print_fix_summary

    # End autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        if ! end_autofix_session; then
            echo "ERROR: Failed to finalize autofix session" >&2
            return 1
        fi

        # Print undo summary if changes were made
        if [[ $FIX_APPLIED -gt 0 ]]; then
            print_undo_summary
        fi
    fi

    # Return failure if any fixes failed
    if [[ $FIX_FAILED -gt 0 ]]; then
        return 1
    fi

    return 0
}
