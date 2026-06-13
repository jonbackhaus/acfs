#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# GTBI - Gastown Batteries Included
# Main installer script
#
# Usage:
#   curl -fsSL "https://raw.githubusercontent.com/${GTBI_REPO_OWNER:-jonbackhaus}/${GTBI_REPO_NAME:-gtbi}/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
#
# Options:
#   --yes         Skip all prompts, use defaults
#   --mode vibe   Enable passwordless sudo, full agent permissions
#   --dry-run     Print what would be done without changing system
#   --print       Print upstream scripts/versions that will be run
#   --resume          Resume from checkpoint (default when state exists)
#   --force-reinstall Start fresh, ignore existing state
#   --reset-state     Move state file aside and exit (for debugging)
#   --interactive     Enable interactive prompts for resume decisions
#   --skip-preflight  Skip pre-flight system validation
#   --auto-fix        Enable auto-fix for pre-flight issues (prompt mode, default)
#   --no-auto-fix     Disable auto-fix (only warn about issues)
#   --auto-fix-accept-all  Auto-fix all issues without prompting (for CI)
#   --auto-fix-dry-run     Show what auto-fix would do without executing
#   --skip-ubuntu-upgrade  Skip automatic Ubuntu version upgrade
#   --target-ubuntu=VER    Set target Ubuntu version (default: 25.10)
#   --strict          Treat ALL tools as critical (any checksum mismatch aborts)
#   --list-modules    List available modules and exit
#   --print-plan      Print execution plan and exit (no installs)
#   --only <module>       Only run a specific module (repeatable)
#   --only-phase <phase>  Only run modules in a specific phase (repeatable)
#   --skip <module>       Skip a specific module (repeatable)
#   --no-deps             Disable automatic dependency closure (expert/debug)
#   --checksums-ref <ref> Fetch checksums.yaml from this ref (default: main for pinned tags/SHAs)
#   --offline-pack <dir>  Use an extracted gtbi-offline-pack/ and refuse live fallback
#   --ref <ref>          Git ref to install (branch, tag, or SHA). Equivalent to
#                        GTBI_REF env var but works reliably in curl|bash pipelines.
#   --pin-ref            Print resolved SHA and pinned command, then exit
# ============================================================

set -euo pipefail

# Enable shell tracing when GTBI_DEBUG=true (matches the hint in our error messages)
[[ "${GTBI_DEBUG:-}" == "true" ]] && set -x

# Prevent apt/dpkg from displaying interactive dialogs (kernel upgrade prompts,
# debconf questions, etc.) that corrupt the terminal with ncurses escape sequences
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a    # Automatically restart services without asking
export NEEDRESTART_SUSPEND=1 # Suppress needrestart prompts during installation
export DEBCONF_NONINTERACTIVE_SEEN=true

# ============================================================
# Configuration
# ============================================================
GTBI_VERSION="0.3.0"
# Allow fork installations by overriding these via environment variables
GTBI_REPO_OWNER="${GTBI_REPO_OWNER:-jonbackhaus}"
GTBI_REPO_NAME="${GTBI_REPO_NAME:-gtbi}"
GTBI_REF="${GTBI_REF:-main}"
# Preserve the original ref (branch/tag/sha) before resolving to a commit SHA.
GTBI_REF_INPUT="$GTBI_REF"
# Checksums ref defaults to GTBI_REF_INPUT, but pinned tags/SHAs fall back to main
# to avoid stale checksums for fast-moving upstream installers.
_GTBI_CHECKSUMS_REF_FROM_ENV="${GTBI_CHECKSUMS_REF:-}"
GTBI_CHECKSUMS_REF_EXPLICIT=false
GTBI_CHECKSUMS_REF="$_GTBI_CHECKSUMS_REF_FROM_ENV"
if [[ -z "$GTBI_CHECKSUMS_REF" ]]; then
    if [[ "$GTBI_REF_INPUT" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)*$ ]] || [[ "$GTBI_REF_INPUT" =~ ^[0-9a-f]{7,40}$ ]]; then
        GTBI_CHECKSUMS_REF="main"
    else
        GTBI_CHECKSUMS_REF="$GTBI_REF_INPUT"
    fi
else
    GTBI_CHECKSUMS_REF_EXPLICIT=true
fi
unset _GTBI_CHECKSUMS_REF_FROM_ENV
GTBI_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_REF}"
GTBI_CHECKSUMS_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_CHECKSUMS_REF}"
export GTBI_RAW GTBI_CHECKSUMS_REF GTBI_CHECKSUMS_RAW GTBI_CHECKSUMS_REF_EXPLICIT GTBI_VERSION
export CHECKSUMS_FILE="${GTBI_CHECKSUMS_YAML:-${CHECKSUMS_FILE:-}}"
GTBI_OFFLINE_PACK="${GTBI_OFFLINE_PACK:-}"
GTBI_OFFLINE_NETWORK_MODE="${GTBI_OFFLINE_NETWORK_MODE:-}"
GTBI_OFFLINE_PACK_REQUIRED="${GTBI_OFFLINE_PACK_REQUIRED:-}"
export GTBI_OFFLINE_PACK GTBI_OFFLINE_NETWORK_MODE GTBI_OFFLINE_PACK_REQUIRED
GTBI_COMMIT_SHA=""       # Short SHA for display (12 chars)
GTBI_COMMIT_SHA_FULL=""  # Full SHA for pinning resume scripts (40 chars)

# Early curl defaults: enforce HTTPS (including redirects) when supported.
# This is used before security.sh is available (bootstrap / early library sourcing).
GTBI_EARLY_CURL_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)
# Note: GTBI_HOME is set after TARGET_HOME is determined
GTBI_LOG_DIR="/var/log/gtbi"
_GTBI_BOOTSTRAP_DIR_OWNED=false
_GTBI_BOOTSTRAP_DIR_CREATED=""
_GTBI_BOOTSTRAP_DIR_TMP_ROOT=""
# SCRIPT_DIR is empty when running via curl|bash (stdin; no file on disk)
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Early PATH setup: ensure ~/.local/bin is available for native installers
# when HOME is present, without assuming stripped environments already set it.
_GTBI_EARLY_PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
if [[ -n "${HOME:-}" ]]; then
    export PATH="$HOME/.local/bin:$_GTBI_EARLY_PATH"
else
    export PATH="$_GTBI_EARLY_PATH"
fi
unset _GTBI_EARLY_PATH

gtbi_early_system_binary_path() {
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
        echo "$candidate"
        return 0
    done

    return 1
}

gtbi_early_sudo_binary_path() {
    if [[ -n "${SUDO:-}" && "$SUDO" == /* && -x "$SUDO" ]]; then
        printf '%s\n' "$SUDO"
        return 0
    fi

    gtbi_early_system_binary_path sudo
}

_gtbi_early_curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
_gtbi_early_grep_bin="$(gtbi_early_system_binary_path grep 2>/dev/null || true)"
if [[ -n "$_gtbi_early_curl_bin" && -n "$_gtbi_early_grep_bin" ]] && "$_gtbi_early_curl_bin" --help all 2>/dev/null | "$_gtbi_early_grep_bin" -q -- '--proto'; then
    GTBI_EARLY_CURL_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
fi
unset _gtbi_early_curl_bin _gtbi_early_grep_bin

gtbi_early_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(gtbi_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(gtbi_early_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    echo "$current_user"
}

gtbi_early_getent_passwd_entry() {
    local user="${1:-}"
    local getent_bin=""
    local passwd_line=""
    local passwd_user=""

    getent_bin="$(gtbi_early_system_binary_path getent 2>/dev/null || true)"
    if [[ -n "$getent_bin" ]]; then
        if [[ -n "$user" ]]; then
            "$getent_bin" passwd "$user" 2>/dev/null
        else
            "$getent_bin" passwd 2>/dev/null
        fi
        return $?
    fi

    [[ -r /etc/passwd ]] || return 1

    if [[ -n "$user" ]]; then
        while IFS= read -r passwd_line; do
            IFS=: read -r passwd_user _ <<< "$passwd_line"
            if [[ "$passwd_user" == "$user" ]]; then
                echo "$passwd_line"
                return 0
            fi
        done < /etc/passwd
        return 1
    fi

    while IFS= read -r passwd_line; do
        echo "$passwd_line"
    done < /etc/passwd
}
# Default options
YES_MODE=false
DRY_RUN=false
PRINT_MODE=false
PIN_REF_MODE=false
MODE="vibe"
STRICT_MODE=false

# Manifest-driven selection options (mjt.5.3)
LIST_MODULES=false
PRINT_PLAN_MODE=false
ONLY_MODULES=()
ONLY_PHASES=()
SKIP_MODULES=()
NO_DEPS=false

# Resume/reinstall options (used by state.sh confirm_resume)
export GTBI_FORCE_RESUME=false
export GTBI_FORCE_REINSTALL=false
# NOTE: When unset/empty, downstream libs default to interactive behavior when a TTY is available.
# install.sh forces non-interactive behavior in --yes mode.
export GTBI_INTERACTIVE="${GTBI_INTERACTIVE:-}"
RESET_STATE_ONLY=false
GTBI_INSTALL_LOCK_FD=""
GTBI_INSTALL_LOCK_FILE=""

# Preflight options
SKIP_PREFLIGHT=false

# Auto-fix options (bd-19y9.3.4)
# Modes: "prompt" (default, interactive), "yes" (accept all), "no" (disable), "dry-run" (preview only)
AUTO_FIX_MODE="prompt"
export AUTO_FIX_MODE

# Ubuntu upgrade options (nb4: integrate upgrade phase)
SKIP_UBUNTU_UPGRADE=false
TARGET_UBUNTU_VERSION="25.10"
TARGET_UBUNTU_VERSION_EXPLICIT=false  # true when user passes --target-ubuntu

# Target user configuration
# Default: detect the current user (or SUDO_USER if running under sudo).
# Override with env var: TARGET_USER=myuser
# Note: Previously defaulted to "ubuntu" which broke non-ubuntu VPS installs.
if [[ -z "${TARGET_USER:-}" ]]; then
    if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
        _GTBI_DETECTED_USER="ubuntu"
    else
        _GTBI_DETECTED_USER="${SUDO_USER:-}"
        if [[ -z "$_GTBI_DETECTED_USER" ]]; then
            _GTBI_DETECTED_USER="$(gtbi_early_resolve_current_user 2>/dev/null || true)"
        fi
        if [[ -z "$_GTBI_DETECTED_USER" ]]; then
            printf 'ERROR: Unable to resolve the current user for TARGET_USER\n' >&2
            exit 1
        fi
    fi
    TARGET_USER="$_GTBI_DETECTED_USER"
fi
unset _GTBI_DETECTED_USER
# Export TARGET_USER early so subprocesses (e.g. preflight.sh) can use it
# to determine the correct installation partition for disk-space checks (#243).
export TARGET_USER
# Leave TARGET_HOME unset by default; init_target_paths derives it from the
# real passwd entry when possible and otherwise fails closed.
TARGET_HOME="${TARGET_HOME:-}"
export TARGET_HOME

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Check if gum is available for enhanced UI
HAS_GUM=false
if gtbi_early_system_binary_path gum &>/dev/null; then
    HAS_GUM=true
fi

# ============================================================
# Prevent logging.sh from overwriting our inline gum-enhanced functions
# ============================================================
export _GTBI_LOGGING_SH_LOADED=1

# ============================================================
# Minimal error-tracking fallbacks
# These are replaced once scripts/lib/error_tracking.sh is sourced (detect_environment()).
# ============================================================
type -t set_phase &>/dev/null || set_phase() { :; }
type -t try_step &>/dev/null || try_step() { shift; "$@"; }
type -t try_step_eval &>/dev/null || try_step_eval() {
    local bash_bin=""
    bash_bin="$(gtbi_early_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || return 127
    shift
    "$bash_bin" -e -o pipefail -c "$1"
}

# ============================================================
# Installer libraries are sourced later in main() via detect_environment(), after
# bootstrapping the repo archive for curl|bash runs (prevents mixed refs).
# ============================================================

# ============================================================
# Source Ubuntu upgrade library for auto-upgrade functionality (nb4)
# ============================================================
_source_ubuntu_upgrade_lib() {
    # Already loaded?
    if [[ -n "${GTBI_UBUNTU_UPGRADE_LOADED:-}" ]]; then
        return 0
    fi

    # Prefer bootstrapped libs when available (curl|bash mode), to avoid mixed refs.
    if [[ -n "${GTBI_LIB_DIR:-}" ]] && [[ -f "$GTBI_LIB_DIR/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$GTBI_LIB_DIR/ubuntu_upgrade.sh"
        export GTBI_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Try local file first (when running from repo)
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/lib/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$SCRIPT_DIR/scripts/lib/ubuntu_upgrade.sh"
        export GTBI_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Try relative path (when running from repo root)
    if [[ -f "./scripts/lib/ubuntu_upgrade.sh" ]]; then
        source "./scripts/lib/ubuntu_upgrade.sh"
        export GTBI_UBUNTU_UPGRADE_LOADED=1
        return 0
    fi

    # Download for curl|bash scenario
    local curl_bin=""
    curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -n "$curl_bin" ]]; then
        local tmp_upgrade=""
        local mktemp_bin=""
        mktemp_bin="$(gtbi_early_system_binary_path mktemp 2>/dev/null || true)"
        if [[ -n "$mktemp_bin" ]]; then
            tmp_upgrade="$("$mktemp_bin" "${TMPDIR:-/tmp}/gtbi-ubuntu-upgrade.XXXXXX" 2>/dev/null)" || tmp_upgrade=""
        fi
        if [[ -n "$tmp_upgrade" ]]; then
            if "$curl_bin" "${GTBI_EARLY_CURL_ARGS[@]}" "$GTBI_RAW/scripts/lib/ubuntu_upgrade.sh" -o "$tmp_upgrade" 2>/dev/null; then
                source "$tmp_upgrade"
                rm -f "$tmp_upgrade"
                export GTBI_UBUNTU_UPGRADE_LOADED=1
                return 0
            fi
            rm -f "$tmp_upgrade"
        fi
    fi

    # If we can't load it, return failure (caller should handle)
    return 1
}

# GTBI Color scheme (Catppuccin Mocha inspired)
GTBI_PRIMARY="#89b4fa"
GTBI_SUCCESS="#a6e3a1"
GTBI_WARNING="#f9e2af"
GTBI_ERROR="#f38ba8"
GTBI_MUTED="#6c7086"

# ============================================================
# Fetch commit SHA and date from GitHub API
# This ensures we always know exactly which version is running
# ============================================================
export GTBI_COMMIT_DATE=""  # exported for child processes/debugging
GTBI_COMMIT_AGE=""

fetch_commit_sha() {
    # Already have it? Skip
    if [[ -n "$GTBI_COMMIT_SHA" && "$GTBI_COMMIT_SHA" != "(unknown)" ]]; then
        return 0
    fi

    # Need curl
    local curl_bin=""
    curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        GTBI_COMMIT_SHA="(curl not available)"
        return 0
    fi

    # Fetch from GitHub API - get the commit SHA for the ref
    local api_url="https://api.github.com/repos/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/commits/${GTBI_REF}"
    local response

    if response=$("$curl_bin" -sf --max-time 5 "$api_url" 2>/dev/null); then
        # Try to use python3 for robust JSON parsing if available
        local sha=""
        local commit_date=""

        local python3_bin=""
        python3_bin="$(gtbi_early_system_binary_path python3 2>/dev/null || true)"
        if [[ -n "$python3_bin" ]]; then
            # Python parsing - robust against JSON formatting changes
            sha=$(echo "$response" | "$python3_bin" -c "import sys, json; print(json.load(sys.stdin).get('sha', ''))" 2>/dev/null)
            commit_date=$(echo "$response" | "$python3_bin" -c "import sys, json; print(json.load(sys.stdin).get('commit', {}).get('author', {}).get('date', ''))" 2>/dev/null)
        else
            # Fallback: Extract SHA from JSON using grep/sed (works without jq/python)
            # Use grep -o to handle minified JSON (puts matches on new lines)
            # || true: head -n 1 causes SIGPIPE on grep when response has many sha fields; result is still valid
            sha=$(echo "$response" | grep -o '"sha":[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([a-f0-9]*\)".*/\1/') || true

            # Extract commit date (format: "2025-12-21T10:30:00Z")
            commit_date=$(echo "$response" | grep -o '"date":[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)".*/\1/') || true
        fi

        if [[ -n "$sha" && ${#sha} -ge 7 ]]; then
            GTBI_COMMIT_SHA="${sha:0:12}"
            # shellcheck disable=SC2034  # Used by scripts/lib/ubuntu_upgrade.sh to pin resume scripts to a specific commit.
            [[ ${#sha} -ge 40 ]] && GTBI_COMMIT_SHA_FULL="$sha"
        fi

        if [[ -n "$commit_date" ]]; then
            GTBI_COMMIT_DATE="$commit_date"
            # Calculate age
            local now commit_ts age_seconds
            now=$(date +%s 2>/dev/null || echo 0)
            # Parse ISO 8601 date - handle both GNU and BSD date
            if date -d "$commit_date" +%s &>/dev/null; then
                # GNU date
                commit_ts=$(date -d "$commit_date" +%s 2>/dev/null || echo 0)
            else
                # BSD date - try simpler parsing
                commit_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$commit_date" +%s 2>/dev/null || echo 0)
            fi

            if [[ "$now" -gt 0 && "$commit_ts" -gt 0 ]]; then
                age_seconds=$((now - commit_ts))
                # Handle negative age (clock skew / future commit)
                if [[ $age_seconds -lt 0 ]]; then
                    GTBI_COMMIT_AGE="just now"
                elif [[ $age_seconds -lt 60 ]]; then
                    GTBI_COMMIT_AGE="${age_seconds}s ago"
                elif [[ $age_seconds -lt 3600 ]]; then
                    GTBI_COMMIT_AGE="$((age_seconds / 60))m ago"
                elif [[ $age_seconds -lt 86400 ]]; then
                    GTBI_COMMIT_AGE="$((age_seconds / 3600))h ago"
                else
                    GTBI_COMMIT_AGE="$((age_seconds / 86400))d ago"
                fi
            fi
        fi

        if [[ -n "$GTBI_COMMIT_SHA" ]]; then
            return 0
        fi
    fi

    # Fallback
    GTBI_COMMIT_SHA="(unknown)"
}

# ============================================================
# Install gum FIRST for beautiful UI from the start
# ============================================================
install_gum_early() {
    # Already have gum? Great!
    if gtbi_early_system_binary_path gum &>/dev/null; then
        HAS_GUM=true
        return 0
    fi

    # Respect dry-run / print-only modes: do not modify the system just to
    # improve UI.
    if [[ "${DRY_RUN:-false}" == "true" ]] || [[ "${PRINT_MODE:-false}" == "true" ]]; then
        return 0
    fi

    # Only attempt early gum install on supported Ubuntu systems.
    # Preflight/ensure_ubuntu will stop execution later, but this prevents
    # partial modifications (apt repo/key) on unsupported OS versions.
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        local version_id="${VERSION_ID:-}"
        local version_major="${version_id%%.*}"
        if [[ "${ID:-}" != "ubuntu" ]] || [[ -z "$version_id" ]] || [[ "$version_major" -lt 22 ]]; then
            return 0
        fi
    else
        return 0
    fi

    local curl_bin=""
    local gpg_bin=""
    local apt_get_bin=""
    local timeout_bin=""
    local mkdir_bin=""
    local tee_bin=""

    # Need curl to fetch gum - if curl isn't installed yet, skip early install
    # (gum will be installed later in install_cli_tools after ensure_base_deps)
    curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        return 0
    fi

    # Need gpg for apt key handling
    gpg_bin="$(gtbi_early_system_binary_path gpg 2>/dev/null || true)"
    if [[ -z "$gpg_bin" ]]; then
        return 0
    fi

    # Need apt-get for installation
    apt_get_bin="$(gtbi_early_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        return 0
    fi
    timeout_bin="$(gtbi_early_system_binary_path timeout 2>/dev/null || true)"
    if [[ -z "$timeout_bin" ]]; then
        return 0
    fi
    mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
    tee_bin="$(gtbi_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" || -z "$tee_bin" ]]; then
        return 0
    fi

    # Need root/sudo for apt operations
    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        else
            # Can't install gum without sudo, fall back to plain output
            return 0
        fi
    fi

    echo -e "\033[0;90m    → Installing gum for enhanced UI...\033[0m" >&2

    # Step 1: Fetch Charm GPG key (with timeout)
    echo -e "\033[0;90m      ↳ Fetching Charm repository key...\033[0m" >&2
    "${sudo_cmd[@]}" "$mkdir_bin" -p /etc/apt/keyrings 2>/dev/null || true
    if ! "$curl_bin" --connect-timeout 10 --max-time 30 -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null | \
        "${sudo_cmd[@]}" "$gpg_bin" --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        echo -e "\033[0;33m      ⚠ Could not fetch Charm key (skipping gum, will retry later)\033[0m" >&2
        return 0
    fi

    # Step 2: Add apt repository (using DEB822 format to avoid .migrate warnings on upgrade)
    "${sudo_cmd[@]}" "$tee_bin" /etc/apt/sources.list.d/charm.sources > /dev/null 2>&1 << 'EOF'
Types: deb
URIs: https://repo.charm.sh/apt/
Suites: *
Components: *
Signed-By: /etc/apt/keyrings/charm.gpg
EOF

    # Step 3: Update apt (this can be slow on fresh systems)
    # Disable fancy progress to prevent terminal cursor issues
    echo -e "\033[0;90m      ↳ Updating package lists (may take 30-60s on fresh systems)...\033[0m" >&2
    if ! DEBIAN_FRONTEND=noninteractive "$timeout_bin" 120 "${sudo_cmd[@]}" "$apt_get_bin" update -y \
        -o Dpkg::Progress-Fancy="0" -o APT::Color="0" >/dev/null 2>&1; then
        # Reset terminal line position in case apt left cursor in bad state
        echo -e "\r\033[K\033[0;33m      ⚠ apt-get update slow/failed (skipping gum, will retry later)\033[0m" >&2
        return 0
    fi

    # Step 4: Install gum
    # Use DEBIAN_FRONTEND=noninteractive and disable fancy progress to prevent
    # terminal cursor position issues when apt-get fails or times out
    echo -e "\033[0;90m      ↳ Installing gum package...\033[0m" >&2
    local apt_output
    if apt_output=$(DEBIAN_FRONTEND=noninteractive "$timeout_bin" 60 "${sudo_cmd[@]}" "$apt_get_bin" install -yq \
        -o Dpkg::Progress-Fancy="0" -o APT::Color="0" gum 2>&1); then
        HAS_GUM=true
        # Reset terminal line position and show success
        echo -e "\r\033[K\033[0;32m    ✓ gum installed - enhanced UI enabled!\033[0m" >&2
    else
        # Reset terminal line position in case apt left cursor in bad state
        echo -e "\r\033[K\033[0;33m      ⚠ gum install failed (continuing without enhanced UI)\033[0m" >&2
        # Show brief reason if available (e.g., "Unable to locate package", timeout, etc.)
        if echo "$apt_output" | grep -qi "unable to locate\|not found\|timeout"; then
            echo -e "\033[0;90m        (Charm repository may be unavailable or package not found)\033[0m" >&2
        fi
    fi
}

# ============================================================
# ASCII Art Banner
# ============================================================
print_banner() {
    # Ensure terminal is in a clean state before printing banner
    # (previous apt/dpkg operations may have left cursor in bad position)
    echo -e "\r\033[K" >&2

    # Build version line with proper padding (63 chars inner width)
    local version_text="Gastown Batteries Included v${GTBI_VERSION}"
    local padding=$(( (63 - ${#version_text}) / 2 ))
    local version_line
    version_line=$(printf "║%*s%s%*s║" "$padding" "" "$version_text" "$((63 - padding - ${#version_text}))" "")

    # Build commit info line
    local commit_text=""
    if [[ -n "$GTBI_COMMIT_SHA" && "$GTBI_COMMIT_SHA" != "(unknown)" ]]; then
        commit_text="Commit: ${GTBI_COMMIT_SHA}"
        if [[ -n "$GTBI_COMMIT_AGE" ]]; then
            commit_text="${commit_text} (${GTBI_COMMIT_AGE})"
        fi
    fi
    local commit_padding=$(( (63 - ${#commit_text}) / 2 ))
    local commit_line
    if [[ -n "$commit_text" ]]; then
        commit_line=$(printf "║%*s%s%*s║" "$commit_padding" "" "$commit_text" "$((63 - commit_padding - ${#commit_text}))" "")
    else
        commit_line="║                                                               ║"
    fi

    local banner="
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                  ██████╗ ████████╗██████╗ ██╗                 ║
║                 ██╔════╝ ╚══██╔══╝██╔══██╗██║                 ║
║                 ██║  ███╗   ██║   ██████╔╝██║                 ║
║                 ██║   ██║   ██║   ██╔══██╗██║                 ║
║                 ╚██████╔╝   ██║   ██████╔╝██║                 ║
║                  ╚═════╝    ╚═╝   ╚═════╝ ╚═╝                 ║
║                                                               ║
${version_line}
${commit_line}
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "$banner" | gum style --foreground "$GTBI_PRIMARY" --bold >&2
    else
        echo -e "${BLUE}$banner${NC}" >&2
    fi
}

# ============================================================
# Pinned Ref Output (bd-31ps.8.1)
# Prints resolved SHA and copy-pasteable pinned command
# ============================================================
print_pinned_ref() {
    local sha="${GTBI_COMMIT_SHA_FULL:-$GTBI_COMMIT_SHA}"

    if [[ -z "$sha" || "$sha" == "(unknown)" || "$sha" == "(curl not available)" ]]; then
        echo "Error: Could not resolve ref '$GTBI_REF' to SHA" >&2
        echo "" >&2
        echo "Possible causes:" >&2
        echo "  - Invalid ref (branch, tag, or SHA)" >&2
        echo "  - GitHub API rate limit or network issue" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  export GTBI_REF=main  # use main branch" >&2
        echo "  export GTBI_REF=v1.0  # use a tag" >&2
        exit 1
    fi

    local short_sha="${sha:0:12}"
    local install_url="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${sha}/install.sh"

    echo ""
    echo "═════════════════════════════════════════════════════════════════"
    echo "                    GTBI Pinned Reference"
    echo "═════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Requested ref:  ${GTBI_REF_INPUT:-$GTBI_REF}"
    echo "  Resolved SHA:   ${short_sha}"
    if [[ -n "${GTBI_COMMIT_SHA_FULL:-}" ]]; then
        echo "  Full SHA:       ${GTBI_COMMIT_SHA_FULL}"
    fi
    if [[ -n "${GTBI_COMMIT_DATE:-}" ]]; then
        echo "  Commit date:    ${GTBI_COMMIT_DATE}"
    fi
    if [[ -n "${GTBI_COMMIT_AGE:-}" ]]; then
        echo "  Commit age:     ${GTBI_COMMIT_AGE}"
    fi
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo "Copy-paste this command to install from this exact commit:"
    echo ""
    echo "  curl -fsSL \"${install_url}\" | bash -s -- --yes --mode vibe --ref \"${sha}\""
    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    echo "Tip: Pinned refs ensure reproducible installs across machines."
    echo "     Use tags (e.g., v1.0.0) for stable releases."
    echo ""
}

# ============================================================
# Logging functions (with gum enhancement)
# ============================================================
log_step() {
    local step="${1:-}"
    local message="${2:-}"

    # Allow single-arg usage: treat the arg as the message
    if [[ -z "$message" ]]; then
        message="$step"
        step="*"
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$GTBI_PRIMARY" --bold "[$step]" | tr -d '\n' >&2
        echo -n " " >&2
        gum style "$message" >&2
    else
        echo -e "${BLUE}[$step]${NC} $message" >&2
    fi
}

log_detail() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$GTBI_MUTED" --margin "0 0 0 4" "→ $1" >&2
    else
        echo -e "${GRAY}    → $1${NC}" >&2
    fi
}

log_info() {
    log_detail "$1"
}

log_success() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$GTBI_SUCCESS" --bold "✓ $1" >&2
    else
        echo -e "${GREEN}✓ $1${NC}" >&2
    fi
}

log_warn() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$GTBI_WARNING" "⚠ $1" >&2
    else
        echo -e "${YELLOW}⚠ $1${NC}" >&2
    fi
}

log_error() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$GTBI_ERROR" --bold "✖ $1" >&2
    else
        echo -e "${RED}✖ $1${NC}" >&2
    fi
}

log_fatal() {
    log_error "$1"
    exit 1
}

log_section() {
    if [[ "$HAS_GUM" == "true" ]]; then
        echo "" >&2
        gum style --foreground "$GTBI_PRIMARY" --bold "═══ $1 ═══" >&2
    else
        echo "" >&2
        echo -e "${BLUE}═══ $1 ═══${NC}" >&2
    fi
}

# ============================================================
# Log file capture (tee stderr to file)
# ============================================================

# Initialize log file capture: tee stderr to a timestamped log file.
# After calling, all stderr output is captured to GTBI_LOG_FILE.
gtbi_log_init() {
    local log_dir="${1:-${GTBI_HOME:+${GTBI_HOME}/logs}}"
    local saved_stderr_fd=""

    # Fallback if GTBI_HOME not set or empty
    if [[ -z "$log_dir" ]]; then
        log_dir="${GTBI_LOG_DIR:-/var/log/gtbi}"
    fi

    GTBI_LOG_INITIALIZED=false
    GTBI_LOG_STDERR_CAPTURED=false
    GTBI_LOG_ORIGINAL_STDERR_FD=""

    # Create log directory
    mkdir -p "$log_dir" 2>/dev/null || return 1

    GTBI_LOG_FILE="${log_dir}/install-$(date +%Y%m%d_%H%M%S).log"
    export GTBI_LOG_FILE

    # Write log header
    {
        printf '=== GTBI Install Log ===\n'
        printf 'Started: %s\n' "$(date -Iseconds)"
        printf 'Version: %s\n' "${GTBI_VERSION:-unknown}"
        printf 'User: %s\n' "${TARGET_USER:-unknown}"
        printf 'Home: %s\n' "${TARGET_HOME:-unknown}"
        printf 'Mode: %s\n' "${MODE:-unknown}"
        printf 'Bash: %s\n' "${BASH_VERSION:-unknown}"
        printf '========================\n\n'
    } > "$GTBI_LOG_FILE" 2>/dev/null || return 1
    GTBI_LOG_INITIALIZED=true

    # Fix ownership so target user can read logs
    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$log_dir" "$GTBI_LOG_FILE" 2>/dev/null || true
    fi

    # Tee stderr: all stderr output goes to both terminal and log file.
    # fd 3 = original stderr (preserved for terminal output).
    #
    # NOTE: Process substitution >(tee ...) can fail on some systems
    # (especially Ubuntu 25.04 with bash 5.3+). We use a subshell guard
    # to prevent set -e from exiting the entire script on failure.
    # If tee logging fails, we fall back to simple file redirection.
    local tee_logging_ok=false
    if command -v tee >/dev/null 2>&1; then
        # Test if process substitution works before committing to it.
        # On bash 5.3+, bare `exec` under set -e can exit the script
        # before `if` catches the failure, so we test in a subshell.
        # shellcheck disable=SC2261
        if (exec 3>&1; echo test > >(cat >/dev/null)) 2>/dev/null; then
            # Process substitution works - set up tee logging
            # Save original stderr first. Use an GTBI-owned dynamic fd instead
            # of fd 3, because BATS and other callers may already own fd 3.
            if exec {saved_stderr_fd}>&2; then
                GTBI_LOG_ORIGINAL_STDERR_FD="$saved_stderr_fd"
                # Now redirect stderr to tee (which sends to both log and original stderr)
                # shellcheck disable=SC2261
                # Use subshell test first to prevent exec from exiting under bash 5.3+
                if (set +e; exec 2> >(tee -a "$GTBI_LOG_FILE" >&"$saved_stderr_fd")) 2>/dev/null; then
                    if exec 2> >(tee -a "$GTBI_LOG_FILE" >&"$saved_stderr_fd"); then
                        tee_logging_ok=true
                        GTBI_LOG_STDERR_CAPTURED=true
                    fi
                fi
            fi
        fi
    fi

    if [[ "$tee_logging_ok" != "true" ]]; then
        if [[ -n "${GTBI_LOG_ORIGINAL_STDERR_FD:-}" ]]; then
            { exec {GTBI_LOG_ORIGINAL_STDERR_FD}>&-; } 2>/dev/null || true
            GTBI_LOG_ORIGINAL_STDERR_FD=""
        fi
        # Fallback: redirect stderr to both terminal (via original fd) and log file
        # This is less elegant but works on all bash versions
        echo "Note: Tee logging unavailable on this system, using fallback" >&2 || true
        # Save original stderr, then append to log file for each command
        # We'll rely on explicit logging calls instead of automatic tee
        GTBI_LOG_FALLBACK=true
        export GTBI_LOG_FALLBACK
    fi

    log_detail "Log file: $GTBI_LOG_FILE"
}

# Close log file capture and restore stderr.
# Strips ANSI color codes from the log for clean text output.
gtbi_log_close() {
    # Restore only an fd that gtbi_log_init opened. Callers and test harnesses
    # often use fd 3 themselves; inheriting it must not make us redirect/close it.
    if [[ "${GTBI_LOG_STDERR_CAPTURED:-false}" == "true" && -n "${GTBI_LOG_ORIGINAL_STDERR_FD:-}" ]]; then
        exec 2>&"${GTBI_LOG_ORIGINAL_STDERR_FD}" || true
        { exec {GTBI_LOG_ORIGINAL_STDERR_FD}>&-; } 2>/dev/null || true
        GTBI_LOG_ORIGINAL_STDERR_FD=""
        GTBI_LOG_STDERR_CAPTURED=false
    fi

    if [[ "${GTBI_LOG_INITIALIZED:-false}" == "true" && -n "${GTBI_LOG_FILE:-}" && -f "$GTBI_LOG_FILE" ]]; then
        # Strip ANSI escape codes for clean log
        sed -i $'s/\033\[[0-9;]*m//g' "$GTBI_LOG_FILE" 2>/dev/null || true

        # Append footer
        {
            printf '\n========================\n'
            printf 'Finished: %s\n' "$(date -Iseconds)"
            printf '========================\n'
        } >> "$GTBI_LOG_FILE"

        # Fix ownership
        if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
            chown "${TARGET_USER}:${TARGET_USER}" "$GTBI_LOG_FILE" 2>/dev/null || true
        fi
    fi
    GTBI_LOG_INITIALIZED=false
}

# ============================================================
# Install summary JSON (bd-31ps.3.2)
# ============================================================

# Emit a local performance budget artifact derived from an install summary.
# Usage: gtbi_performance_budget_emit <summary_file>
# Output: ~/.gtbi/logs/performance_budget_<timestamp>.json
gtbi_performance_budget_emit() {
    local summary_file="$1"

    command -v jq &>/dev/null || return 0
    [[ -f "$summary_file" ]] || return 0

    local summary_dir summary_base budget_suffix budget_file generated_at
    summary_dir="$(dirname "$summary_file")"
    summary_base="$(basename "$summary_file")"
    budget_suffix="${summary_base#install_summary_}"
    if [[ "$budget_suffix" == "$summary_base" ]]; then
        budget_suffix="$(date +%Y%m%d_%H%M%S).json"
    fi
    budget_file="${summary_dir}/performance_budget_${budget_suffix}"
    generated_at="$(date -Iseconds)"

    jq -n \
        --slurpfile summary "$summary_file" \
        --arg generated_at "$generated_at" \
        --arg source_summary "$summary_base" '
        ($summary[0] // {}) as $s |
        def budget_status($actual; $warn; $fail):
            if ($actual == null) then "unknown"
            elif ($actual >= $fail) then "fail"
            elif ($actual >= $warn) then "warn"
            else "pass"
            end;
        def aggregate_status($items):
            if any($items[]?; .status == "fail") then "fail"
            elif any($items[]?; .status == "warn") then "warn"
            elif any($items[]?; .status == "unknown") then "unknown"
            else "pass"
            end;
        ($s.total_seconds // null) as $total_seconds |
        2700 as $total_warn |
        4500 as $total_fail |
        900 as $phase_warn |
        1800 as $phase_fail |
        [
            {
                name: "total_duration_seconds",
                actual: $total_seconds,
                warn: $total_warn,
                fail: $total_fail,
                unit: "seconds",
                status: budget_status($total_seconds; $total_warn; $total_fail)
            }
        ] as $budgets |
        (($s.phases // []) | map({
            id: (.id // "unknown"),
            duration_seconds: (.duration_seconds // null),
            warn_seconds: $phase_warn,
            fail_seconds: $phase_fail,
            status: budget_status((.duration_seconds // null); $phase_warn; $phase_fail)
        })) as $phases |
        {
            schema_version: 1,
            generated_at: $generated_at,
            threshold_profile: "installer_factory_v1",
            status: aggregate_status($budgets + $phases),
            scenario: {
                kind: "installer",
                backend: "local",
                ubuntu_final: ($s.environment.ubuntu_version // "unknown"),
                mode: ($s.environment.mode // "unknown"),
                host_class: "unknown"
            },
            run: {
                run_id: ($source_summary | sub("^install_summary_"; "") | sub("\\.json$"; "")),
                gtbi_version: ($s.environment.gtbi_version // "unknown"),
                completed_at: ($s.timestamp // null),
                duration_seconds: $total_seconds,
                install_status: ($s.status // "unknown")
            },
            budgets: $budgets,
            phases: $phases,
            probes: [],
            resources: [],
            artifacts: [
                {
                    path: $source_summary,
                    kind: "source_summary",
                    redacted: true
                }
            ],
            comparison: {
                baseline_source: "none",
                delta_pct: null,
                status: "unknown"
            },
            recommendations: []
        }' > "$budget_file" 2>/dev/null || return 0

    GTBI_PERFORMANCE_BUDGET_FILE="$budget_file"
    export GTBI_PERFORMANCE_BUDGET_FILE

    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$budget_file" 2>/dev/null || true
    fi

    log_detail "Performance budget: $budget_file"
}

# Emit a JSON summary of the install run for downstream tooling.
# Usage: gtbi_summary_emit <status> [total_seconds]
#   status: "success" or "failure"
#   total_seconds: total wall-clock time (optional, default 0)
# Output: ~/.gtbi/logs/install_summary_<timestamp>.json
gtbi_summary_emit() {
    local status="$1"
    local total_seconds="${2:-0}"

    # Require jq (installed by ensure_base_deps before phases run)
    command -v jq &>/dev/null || return 1

    local resolved_target_home=""
    local explicit_target_home=""
    if [[ -n "${TARGET_HOME:-}" ]] && [[ "${TARGET_HOME}" == /* ]] && [[ "${TARGET_HOME}" != "/" ]]; then
        explicit_target_home="${TARGET_HOME%/}"
    fi
    resolved_target_home="$(gtbi_home_for_user "${TARGET_USER:-ubuntu}" "$explicit_target_home" 2>/dev/null || true)"
    resolved_target_home="${resolved_target_home%/}"
    if [[ -z "$resolved_target_home" ]] || [[ "$resolved_target_home" == "/" ]] || [[ "$resolved_target_home" != /* ]]; then
        return 1
    fi

    local summary_home="${GTBI_HOME:-}"
    if [[ -z "$summary_home" ]]; then
        summary_home="${resolved_target_home}/.gtbi"
    fi

    local summary_dir="${summary_home}/logs"
    mkdir -p "$summary_dir" 2>/dev/null || return 1

    GTBI_SUMMARY_FILE="${summary_dir}/install_summary_$(date +%Y%m%d_%H%M%S).json"
    export GTBI_SUMMARY_FILE

    # Read phase data from state.json if available
    local phases_json="[]"
    local failure_json="null"
    if [[ -f "${GTBI_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
        # Build phases array: [{id, name, duration_seconds}] in completion order
        phases_json=$(jq -r '
            (.completed_phases // []) as $completed |
            (.phase_durations // {}) as $durations |
            [$completed[] | {id: ., duration_seconds: ($durations[.] // null)}]
        ' "$GTBI_STATE_FILE" 2>/dev/null) || phases_json="[]"

        # Build failure object if present with precise resume hint (bd-31ps.9.1)
        local failed_phase
        failed_phase=$(jq -r '.failed_phase // empty' "$GTBI_STATE_FILE" 2>/dev/null) || true
        if [[ -n "$failed_phase" ]]; then
            local resume_hint
            resume_hint=$(generate_resume_hint "$failed_phase" "")
            failure_json=$(jq -n \
                --arg phase "$failed_phase" \
                --arg step "$(jq -r '.failed_step // empty' "$GTBI_STATE_FILE" 2>/dev/null)" \
                --arg error "$(jq -r '.failed_error // empty' "$GTBI_STATE_FILE" 2>/dev/null)" \
                --arg resume_hint "$resume_hint" \
                '{phase: $phase, step: (if $step == "" then null else $step end), error: (if $error == "" then null else $error end), resume_hint: $resume_hint}')
        fi
    fi

    # Get Ubuntu version
    local ubuntu_version="unknown"
    if command -v lsb_release &>/dev/null; then
        ubuntu_version=$(lsb_release -rs 2>/dev/null) || ubuntu_version="unknown"
    fi

    # Construct the summary JSON
    jq -n \
        --argjson schema_version 1 \
        --arg status "$status" \
        --arg timestamp "$(date -Iseconds)" \
        --argjson total_seconds "$total_seconds" \
        --arg gtbi_version "${GTBI_VERSION:-unknown}" \
        --arg mode "${MODE:-unknown}" \
        --arg ubuntu_version "$ubuntu_version" \
        --arg target_user "${TARGET_USER:-unknown}" \
        --arg target_home "${resolved_target_home:-unknown}" \
        --argjson phases "$phases_json" \
        --argjson failure "$failure_json" \
        --arg log_file "${GTBI_LOG_FILE:-}" \
        '{
            schema_version: $schema_version,
            status: $status,
            timestamp: $timestamp,
            total_seconds: $total_seconds,
            environment: {
                gtbi_version: $gtbi_version,
                mode: $mode,
                ubuntu_version: $ubuntu_version,
                target_user: $target_user,
                target_home: $target_home
            },
            phases: $phases,
            failure: $failure,
            log_file: (if $log_file != "" then $log_file else null end)
        }' > "$GTBI_SUMMARY_FILE" 2>/dev/null || return 1

    # Fix ownership so target user can read
    if [[ -n "${TARGET_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
        chown "${TARGET_USER}:${TARGET_USER}" "$GTBI_SUMMARY_FILE" 2>/dev/null || true
    fi

    gtbi_performance_budget_emit "$GTBI_SUMMARY_FILE" 2>/dev/null || true

    log_detail "Summary: $GTBI_SUMMARY_FILE"
}

# ============================================================
# Resume Hint Generation (bd-31ps.9.1)
# ============================================================
# Generates a precise, copyable command to resume installation from failure.
# Includes all relevant flags to reproduce the original invocation.
generate_resume_hint() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"

    # Start with base command
    local cmd=""
    local install_url=""
    local install_url_q=""
    local arg_q=""
    local resume_ref=""
    local resume_ref_pinned_from_commit=false
    local -a resume_args=(--resume)

    # Prefer curl|bash one-liner for curl invocations; local script for local runs
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        # curl|bash invocation - use one-liner format
        cmd="curl -fsSL"
        if [[ -n "${GTBI_COMMIT_SHA_FULL:-}" ]]; then
            # Pin to exact commit SHA for reproducibility
            install_url="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_COMMIT_SHA_FULL}/install.sh"
        elif [[ -n "${GTBI_REF_INPUT:-}" && "${GTBI_REF_INPUT}" != "main" ]]; then
            install_url="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_REF_INPUT}/install.sh"
        else
            install_url="https://gtbi.sh"
        fi
        printf -v install_url_q '%q' "$install_url"
        cmd="$cmd $install_url_q"
        cmd="$cmd | bash -s --"
    else
        # Local script invocation
        local local_install
        local_install="${SCRIPT_DIR%/}/install.sh"
        printf -v local_install '%q' "$local_install"
        cmd="bash $local_install"
    fi

    # Always add --resume flag (skips completed phases via state.json)

    # Add mode if not default
    if [[ "${MODE:-vibe}" != "vibe" ]]; then
        resume_args+=(--mode "$MODE")
    fi

    # Propagate --ref so the resume uses the same git ref (avoids the
    # curl|bash env-var pitfall where GTBI_REF only reaches curl, not bash)
    if [[ -z "${SCRIPT_DIR:-}" && -n "${GTBI_COMMIT_SHA_FULL:-}" ]]; then
        resume_ref="$GTBI_COMMIT_SHA_FULL"
        resume_ref_pinned_from_commit=true
    elif [[ -n "${GTBI_REF_INPUT:-}" && "${GTBI_REF_INPUT}" != "main" ]]; then
        resume_ref="$GTBI_REF_INPUT"
    fi
    if [[ -n "$resume_ref" ]]; then
        resume_args+=(--ref "$resume_ref")
    fi

    # Preserve checksum metadata that would otherwise be lost when replaying
    # the resume command with a different --ref than the original invocation.
    if [[ "${GTBI_CHECKSUMS_REF_EXPLICIT:-false}" == "true" && -n "${GTBI_CHECKSUMS_REF:-}" ]]; then
        resume_args+=(--checksums-ref "$GTBI_CHECKSUMS_REF")
    elif [[ "$resume_ref_pinned_from_commit" == "true" && -n "${GTBI_CHECKSUMS_REF:-}" && "$GTBI_CHECKSUMS_REF" != "main" ]]; then
        # Pinning --ref to an exact SHA would otherwise make parse_args derive
        # checksum metadata from main, not the symbolic branch used originally.
        resume_args+=(--checksums-ref "$GTBI_CHECKSUMS_REF")
    fi
    if [[ -n "${GTBI_OFFLINE_PACK:-}" ]]; then
        resume_args+=(--offline-pack "$GTBI_OFFLINE_PACK")
    fi

    # Add skip flags that were used
    [[ "${SKIP_PREFLIGHT:-false}" == "true" ]] && resume_args+=(--skip-preflight)
    [[ "${SKIP_UBUNTU_UPGRADE:-false}" == "true" ]] && resume_args+=(--skip-ubuntu-upgrade)

    # Add --yes if original run was non-interactive
    [[ "${YES_MODE:-false}" == "true" ]] && resume_args+=(--yes)

    # Add --strict if it was set
    [[ "${STRICT_MODE:-false}" == "true" || "${GTBI_STRICT_MODE:-false}" == "true" ]] && resume_args+=(--strict)

    for arg_q in "${resume_args[@]}"; do
        printf -v arg_q '%q' "$arg_q"
        cmd="$cmd $arg_q"
    done

    echo "$cmd"
}

# Print the resume hint with explanation and copyable block
print_resume_hint() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"
    local resume_cmd=""
    if ! resume_cmd=$(generate_resume_hint "${failed_phase:-}" "${failed_step:-}" 2>/dev/null); then
        if [[ -n "${SCRIPT_DIR:-}" ]]; then
            local local_install
            local_install="${SCRIPT_DIR%/}/install.sh"
            printf -v local_install '%q' "$local_install"
            resume_cmd="bash $local_install --resume --yes"
        else
            resume_cmd="curl -fsSL https://gtbi.sh | bash -s -- --resume --yes"
        fi
    fi

    log_info ""
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║  To resume installation from this point:                     ║"
    log_info "╚══════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "  $resume_cmd"
    log_info ""

    if [[ -n "${failed_phase:-}" ]]; then
        log_detail "Failed phase: ${failed_phase:-}"
    fi
    if [[ -n "${failed_step:-}" ]]; then
        log_detail "Failed step: ${failed_step:-}"
    fi

    # Also persist the precise resume hint into state.json, but only through the
    # state library so we keep same-directory atomic writes and target-user ownership.
    if [[ -f "${GTBI_STATE_FILE:-}" ]] && type -t state_set_resume_hint &>/dev/null; then
        state_set_resume_hint "${resume_cmd:-}" 2>/dev/null || true
    fi
}

# ============================================================
# Error handling
# ============================================================
# Track whether cleanup was triggered by a signal (not a normal EXIT).
_GTBI_SIGNAL_RECEIVED=""

_gtbi_signal_handler() {
    _GTBI_SIGNAL_RECEIVED="$1"
    # Exit with 128+signum (standard convention) to trigger the EXIT trap.
    case "$1" in
        TERM) exit 143 ;;
        INT)  exit 130 ;;
        HUP)  exit 129 ;;
        *)    exit 1   ;;
    esac
}

gtbi_bootstrap_dir_is_owned_temp() {
    local dir="${1:-}"
    local tmp_root="${_GTBI_BOOTSTRAP_DIR_TMP_ROOT:-}"

    [[ "${_GTBI_BOOTSTRAP_DIR_OWNED:-false}" == "true" ]] || return 1
    [[ -n "$dir" ]] || return 1
    [[ -n "${_GTBI_BOOTSTRAP_DIR_CREATED:-}" ]] || return 1
    [[ "$dir" == "$_GTBI_BOOTSTRAP_DIR_CREATED" ]] || return 1

    dir="${dir%/}"
    [[ "$dir" == /* ]] || return 1
    [[ "$dir" != "/" ]] || return 1
    [[ "$tmp_root" == /* ]] || return 1
    [[ "$dir" == "$tmp_root"/gtbi-bootstrap-* ]] || return 1
    [[ -d "$dir" ]] || return 1
}

gtbi_remember_install_lock() {
    GTBI_INSTALL_LOCK_FD="$1"
    GTBI_INSTALL_LOCK_FILE="$2"
}

gtbi_release_install_lock() {
    case "${GTBI_INSTALL_LOCK_FD:-}" in
        198)
            flock -u 198 2>/dev/null || true
            { exec 198>&-; } 2>/dev/null || true
            ;;
        199)
            flock -u 199 2>/dev/null || true
            { exec 199>&-; } 2>/dev/null || true
            ;;
    esac
    GTBI_INSTALL_LOCK_FD=""
    GTBI_INSTALL_LOCK_FILE=""
}

cleanup() {
    # Capture exit code FIRST, before any other commands can overwrite $?
    local exit_code=$?

    # Cleanup must never abort — disable errexit for the entire function.
    set +e

    if gtbi_bootstrap_dir_is_owned_temp "${GTBI_BOOTSTRAP_DIR:-}"; then
        rm -rf -- "$GTBI_BOOTSTRAP_DIR" 2>/dev/null || true
    fi

    if [[ -n "${GTBI_TMP_ARCHIVE:-}" ]] && [[ -f "$GTBI_TMP_ARCHIVE" ]]; then
        rm -f "$GTBI_TMP_ARCHIVE" 2>/dev/null || true
    fi

    if [[ -n "${GTBI_TMP_SLB:-}" ]] && [[ -d "$GTBI_TMP_SLB" ]]; then
        rm -rf "$GTBI_TMP_SLB" 2>/dev/null || true
    fi

    if [[ -n "${GTBI_TMP_INSTALL:-}" ]] && [[ -f "$GTBI_TMP_INSTALL" ]]; then
        rm -f "$GTBI_TMP_INSTALL" 2>/dev/null || true
    fi

    # If a signal triggered this cleanup, mark state as interrupted so
    # resume logic does not see a partially-started phase.
    if [[ -n "${_GTBI_SIGNAL_RECEIVED:-}" ]]; then
        if type -t state_mark_interrupted &>/dev/null; then
            state_mark_interrupted 2>/dev/null || true
        fi
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error ""
        if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
            log_error "GTBI installation completed, but the post-install smoke test failed."
        else
            log_error "GTBI installation failed!"
        fi
        log_error ""
        log_error "To debug:"
        if [[ -n "${GTBI_LOG_FILE:-}" ]] && [[ -f "${GTBI_LOG_FILE:-}" ]]; then
            log_error "  1. Check the log: cat ${GTBI_LOG_FILE:-}"
        elif [[ -n "${GTBI_LOG_DIR:-}" ]] && [[ -d "${GTBI_LOG_DIR:-}" ]]; then
            log_error "  1. Check the log: cat ${GTBI_LOG_DIR:-}/install.log"
        else
            log_error "  1. Re-run with GTBI_DEBUG=true for detailed output"
        fi
        log_error "  2. If installed, run: gtbi doctor (try as ${TARGET_USER:-ubuntu})"
        log_error "     (If you ran the installer as root: sudo -u ${TARGET_USER:-ubuntu} -i bash -lc 'gtbi doctor')"
        log_error ""
        # Print precise resume hint if available (bd-31ps.9.1)
        # Get failed phase from state if available
        local failed_phase=""
        local failed_step=""
        if [[ -f "${GTBI_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
            failed_phase=$(jq -r '.failed_phase // empty' "${GTBI_STATE_FILE:-}" 2>/dev/null) || true
            failed_step=$(jq -r '.failed_step // empty' "${GTBI_STATE_FILE:-}" 2>/dev/null) || true
        fi
        print_resume_hint "${failed_phase:-}" "${failed_step:-}"
        log_error ""
        # Emit failure summary (best-effort)
        gtbi_summary_emit "failure" 0 2>/dev/null || true
        # Send webhook notification for failure (bd-2zqr)
        if type -t webhook_notify &>/dev/null; then
            webhook_notify "failure" "${GTBI_SUMMARY_FILE:-}" 2>/dev/null || true
        fi
        # Send ntfy.sh notification for failure (bd-2igt6)
        if type -t gtbi_notify_install_failure &>/dev/null; then
            gtbi_notify_install_failure 2>/dev/null || true
        fi
    fi
    gtbi_release_install_lock
    # Finalize log file (restore stderr, strip colors, add footer)
    gtbi_log_close 2>/dev/null || true
}
trap cleanup EXIT
trap '_gtbi_signal_handler TERM' TERM
trap '_gtbi_signal_handler INT'  INT
trap '_gtbi_signal_handler HUP'  HUP

# ============================================================
# Parse arguments
# ============================================================
gtbi_require_ref_arg_value() {
    local flag="$1"
    local value="${2:-}"
    local example="$3"

    if [[ -z "$value" || "$value" == -* ]]; then
        log_fatal "$flag requires a ref (e.g., $example)"
    fi
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        log_fatal "$flag requires a single-line ref"
    fi
    if ((${#value} > 120)); then
        log_fatal "$flag ref is too long"
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        log_fatal "$flag contains unsafe ref characters; use letters, numbers, '.', '_', '-', and '/'"
    fi
    case "$value" in
        @|.|..|/*|*/|.*|*.|*//*|*/.*|*..*|*.lock)
            log_fatal "$flag has invalid git ref syntax"
            ;;
    esac
}

gtbi_resolve_offline_pack_dir() {
    local flag="$1"
    local value="${2:-}"
    local candidate=""
    local resolved=""

    if [[ -z "$value" || "$value" == -* ]]; then
        log_fatal "$flag requires a directory"
    fi
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        log_fatal "$flag requires a single-line directory"
    fi

    case "$value" in
        /*) candidate="$value" ;;
        *) candidate="$PWD/$value" ;;
    esac
    candidate="${candidate%/}"

    if [[ -z "$candidate" || ! -d "$candidate" ]]; then
        log_fatal "$flag must point to an existing extracted offline pack directory (got: $value)"
    fi

    resolved="$(cd "$candidate" && pwd -P)" || {
        log_fatal "$flag could not resolve directory: $value"
    }

    if [[ ! -r "$resolved/manifest.json" && ! -r "$resolved/gtbi-offline-pack/manifest.json" ]]; then
        log_fatal "$flag must point to gtbi-offline-pack/ or its parent directory with manifest.json"
    fi

    printf '%s\n' "$resolved"
}

gtbi_normalize_offline_pack_configuration() {
    if [[ -z "${GTBI_OFFLINE_PACK:-}" ]]; then
        return 0
    fi

    GTBI_OFFLINE_PACK="$(gtbi_resolve_offline_pack_dir "GTBI_OFFLINE_PACK" "$GTBI_OFFLINE_PACK")"
    if [[ -z "${GTBI_OFFLINE_NETWORK_MODE:-}" ]]; then
        GTBI_OFFLINE_NETWORK_MODE=offline
    fi
    if [[ "${GTBI_OFFLINE_NETWORK_MODE:-}" == "offline" && -z "${GTBI_OFFLINE_PACK_REQUIRED:-}" ]]; then
        GTBI_OFFLINE_PACK_REQUIRED=true
    fi
    export GTBI_OFFLINE_PACK GTBI_OFFLINE_NETWORK_MODE GTBI_OFFLINE_PACK_REQUIRED
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --print)
                PRINT_MODE=true
                shift
                ;;
            --mode)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--mode requires a value (e.g., --mode vibe)"
                fi
                MODE="$2"
                case "$MODE" in
                    vibe|safe) ;;
                    *)
                        log_fatal "Invalid --mode '$MODE' (expected: vibe or safe)"
                        ;;
                esac
                shift 2
                ;;
            --resume)
                export GTBI_FORCE_RESUME=true
                shift
                ;;
            --force-reinstall)
                export GTBI_FORCE_REINSTALL=true
                shift
                ;;
            --reset-state)
                RESET_STATE_ONLY=true
                shift
                ;;
            --interactive)
                export GTBI_INTERACTIVE=true
                shift
                ;;
            --strict)
                # Treat all tools as critical - any checksum mismatch aborts
                # Related: bead 8mv, tools.sh GTBI_STRICT_MODE handling
                STRICT_MODE=true
                export GTBI_STRICT_MODE=true
                shift
                ;;
            --skip-preflight)
                SKIP_PREFLIGHT=true
                shift
                ;;
            --auto-fix)
                # Enable auto-fix with prompts (default for interactive)
                AUTO_FIX_MODE="prompt"
                shift
                ;;
            --no-auto-fix)
                # Disable auto-fix entirely - only show warnings
                AUTO_FIX_MODE="no"
                shift
                ;;
            --auto-fix-accept-all)
                # Non-interactive: fix all issues without prompting
                AUTO_FIX_MODE="yes"
                shift
                ;;
            --auto-fix-dry-run)
                # Show what auto-fix would do without executing
                AUTO_FIX_MODE="dry-run"
                shift
                ;;
            --checksums-ref|--checksums-ref=*)
                if [[ "$1" == "--checksums-ref" ]]; then
                    gtbi_require_ref_arg_value "--checksums-ref" "${2:-}" "--checksums-ref main"
                    GTBI_CHECKSUMS_REF="$2"
                    shift 2
                else
                    GTBI_CHECKSUMS_REF="${1#*=}"
                    gtbi_require_ref_arg_value "--checksums-ref" "$GTBI_CHECKSUMS_REF" "--checksums-ref=main"
                    shift
                fi
                GTBI_CHECKSUMS_REF_EXPLICIT=true
                GTBI_CHECKSUMS_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_CHECKSUMS_REF}"
                export GTBI_CHECKSUMS_REF GTBI_CHECKSUMS_RAW GTBI_CHECKSUMS_REF_EXPLICIT
                ;;
            --offline-pack|--offline-pack=*)
                if [[ "$1" == "--offline-pack" ]]; then
                    if [[ -z "${2:-}" || "$2" == -* ]]; then
                        log_fatal "--offline-pack requires a directory"
                    fi
                    GTBI_OFFLINE_PACK="$2"
                    shift 2
                else
                    GTBI_OFFLINE_PACK="${1#*=}"
                    if [[ -z "$GTBI_OFFLINE_PACK" ]]; then
                        log_fatal "--offline-pack requires a directory"
                    fi
                    shift
                fi
                GTBI_OFFLINE_NETWORK_MODE=offline
                GTBI_OFFLINE_PACK_REQUIRED=true
                export GTBI_OFFLINE_PACK GTBI_OFFLINE_NETWORK_MODE GTBI_OFFLINE_PACK_REQUIRED
                ;;
            --pin-ref|--confirm-ref)
                # Print resolved SHA and pinned command, then exit
                PIN_REF_MODE=true
                shift
                ;;
            --ref|--ref=*)
                # Set GTBI_REF from CLI (fixes curl|bash where env vars
                # bind to curl, not bash: GTBI_REF=v1 curl ... | bash
                # doesn't propagate to the bash process)
                if [[ "$1" == "--ref" ]]; then
                    gtbi_require_ref_arg_value "--ref" "${2:-}" "--ref main"
                    GTBI_REF="$2"
                    shift 2
                else
                    GTBI_REF="${1#*=}"
                    gtbi_require_ref_arg_value "--ref" "$GTBI_REF" "--ref=main"
                    shift
                fi
                GTBI_REF_INPUT="$GTBI_REF"
                GTBI_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_REF}"
                # Recalculate checksums ref for the new install ref unless the
                # user explicitly pinned checksum metadata with --checksums-ref
                # or GTBI_CHECKSUMS_REF.
                if [[ "${GTBI_CHECKSUMS_REF_EXPLICIT:-false}" != "true" ]]; then
                    if [[ "$GTBI_REF" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)*$ ]] || [[ "$GTBI_REF" =~ ^[0-9a-f]{7,40}$ ]]; then
                        GTBI_CHECKSUMS_REF="main"
                    else
                        GTBI_CHECKSUMS_REF="$GTBI_REF"
                    fi
                fi
                GTBI_CHECKSUMS_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_CHECKSUMS_REF}"
                export GTBI_REF GTBI_RAW GTBI_CHECKSUMS_REF GTBI_CHECKSUMS_RAW GTBI_CHECKSUMS_REF_EXPLICIT
                ;;
            --skip-ubuntu-upgrade)
                # Skip automatic Ubuntu version upgrade (nb4)
                # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                SKIP_UBUNTU_UPGRADE=true
                shift
                ;;
            --target-ubuntu|--target-ubuntu=*)
                # Set target Ubuntu version for auto-upgrade (nb4)
                if [[ "$1" == "--target-ubuntu" ]]; then
                    if [[ -z "${2:-}" || "$2" == -* ]]; then
                        log_fatal "--target-ubuntu requires a version (e.g., --target-ubuntu 25.10)"
                    fi
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="$2"
                    TARGET_UBUNTU_VERSION_EXPLICIT=true
                    shift 2
                else
                    # Handle --target-ubuntu=25.10 format
                    # shellcheck disable=SC2034  # used by run_ubuntu_upgrade_phase
                    TARGET_UBUNTU_VERSION="${1#*=}"
                    TARGET_UBUNTU_VERSION_EXPLICIT=true
                    shift
                fi
                ;;
            --list-modules)
                LIST_MODULES=true
                shift
                ;;
            --print-plan)
                PRINT_PLAN_MODE=true
                shift
                ;;
            --only)
                # Add module to ONLY_MODULES list (for manifest-driven selection)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--only requires a module ID"
                fi
                ONLY_MODULES+=("$2")
                shift 2
                ;;
            --only-phase)
                # Add phase to ONLY_PHASES list
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--only-phase requires a phase number"
                fi
                ONLY_PHASES+=("$2")
                shift 2
                ;;
            --skip)
                # Add module to SKIP_MODULES list
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_fatal "--skip requires a module ID"
                fi
                SKIP_MODULES+=("$2")
                shift 2
                ;;
            --no-deps)
                # Disable automatic dependency resolution
                NO_DEPS=true
                shift
                ;;
            --webhook|--webhook=*)
                # Webhook URL for install completion notification (bd-2zqr)
                if [[ "$1" == "--webhook" ]]; then
                    if [[ -z "${2:-}" ]]; then
                        log_fatal "--webhook requires a URL (e.g., --webhook https://hooks.slack.com/...)"
                    fi
                    export GTBI_WEBHOOK_URL="$2"
                    shift 2
                else
                    # Handle --webhook=https://... format
                    export GTBI_WEBHOOK_URL="${1#*=}"
                    shift
                fi
                ;;
            *)
                log_warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# ============================================================
# Utility functions
# ============================================================
normalize_read_only_modes() {
    if [[ "${DRY_RUN:-false}" != "true" ]] && [[ "${PRINT_MODE:-false}" != "true" ]]; then
        return 0
    fi

    case "${AUTO_FIX_MODE:-prompt}" in
        no|dry-run)
            ;;
        *)
            AUTO_FIX_MODE="dry-run"
            ;;
    esac
}

command_exists() {
    local cmd="${1:-}"

    [[ -n "$cmd" ]] || return 1
    case "$cmd" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    command -v "$cmd" &>/dev/null
}

# Interactive yes/no confirmation prompt
# Returns 0 for yes, 1 for no
confirm() {
    local prompt="${1:-Continue?}"
    local response=""

    # In --yes mode, auto-accept all prompts (fixes non-TTY curl|bash failure)
    if [[ "${YES_MODE:-false}" == "true" ]]; then
        return 0
    fi

    if [[ -t 0 ]]; then
        read -r -p "$prompt [y/N] " response < /dev/tty
    else
        # Non-interactive mode - default to no
        return 1
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================
# Auto-Fix Handler (bd-19y9.3.4)
# Dispatches auto-fix actions based on AUTO_FIX_MODE
# ============================================================
#
# Usage: handle_autofix <fix_name> <description> <fix_function>
#   fix_name     - Short identifier (e.g., "unattended_upgrades")
#   description  - Human-readable description of the issue
#   fix_function - Function to call for fixing (receives "fix" or "dry-run" as $1)
#
# Returns:
#   0 - Issue was fixed (or dry-run shown)
#   1 - User declined to fix or auto-fix is disabled
#   2 - Fix function failed
#
handle_autofix() {
    local fix_name="$1"
    local description="$2"
    local fix_function="$3"

    case "${AUTO_FIX_MODE:-prompt}" in
        "no")
            # Just warn, don't fix
            log_warn "[PRE-FLIGHT] $description"
            log_warn "[PRE-FLIGHT] Use --auto-fix to resolve automatically"
            return 1
            ;;
        "dry-run")
            # Show what would be done
            log_info "[DRY-RUN] Would auto-fix: $description"
            if type -t "$fix_function" &>/dev/null; then
                "$fix_function" "dry-run" || true
            fi
            return 0
            ;;
        "yes")
            # Fix automatically without prompting
            log_info "[AUTO-FIX] Fixing: $description"
            if type -t "$fix_function" &>/dev/null; then
                if "$fix_function" "fix"; then
                    log_success "[AUTO-FIX] Fixed: $fix_name"
                    return 0
                else
                    log_error "[AUTO-FIX] Failed to fix: $fix_name"
                    return 2
                fi
            else
                log_error "[AUTO-FIX] Fix function not found: $fix_function"
                return 2
            fi
            ;;
        "prompt"|*)
            # Interactive: ask user before fixing
            log_warn "[PRE-FLIGHT] $description"
            if [[ "${YES_MODE:-false}" == "true" ]]; then
                # In --yes mode, default to accepting auto-fix
                log_info "[AUTO-FIX] Fixing (--yes mode): $description"
                if type -t "$fix_function" &>/dev/null; then
                    if "$fix_function" "fix"; then
                        log_success "[AUTO-FIX] Fixed: $fix_name"
                        return 0
                    else
                        log_error "[AUTO-FIX] Failed to fix: $fix_name"
                        return 2
                    fi
                fi
            else
                # Interactive prompt
                local response=""
                printf "%b" "${GTBI_YELLOW:-}Would you like GTBI to fix this automatically? [Y/n] ${GTBI_NC:-}" >&2
                read -r response </dev/tty 2>/dev/null || response="y"
                case "${response:-y}" in
                    [Yy]|[Yy][Ee][Ss]|"")
                        log_info "[AUTO-FIX] Fixing: $description"
                        if type -t "$fix_function" &>/dev/null; then
                            if "$fix_function" "fix"; then
                                log_success "[AUTO-FIX] Fixed: $fix_name"
                                return 0
                            else
                                log_error "[AUTO-FIX] Failed to fix: $fix_name"
                                return 2
                            fi
                        fi
                        ;;
                    *)
                        log_info "[PRE-FLIGHT] Skipped auto-fix for: $fix_name"
                        return 1
                        ;;
                esac
            fi
            ;;
    esac
}

# Export for use in preflight and autofix scripts
export -f handle_autofix 2>/dev/null || true

# ============================================================
# Environment Detection (mjt.5.3)
# Sets up paths for libs and generated scripts BEFORE sourcing them.
# ============================================================
detect_environment() {
    # Set lib and generated script directories based on context
    if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]]; then
        # curl|bash mode: use bootstrap archive
        GTBI_LIB_DIR="$GTBI_BOOTSTRAP_DIR/scripts/lib"
        GTBI_GENERATED_DIR="$GTBI_BOOTSTRAP_DIR/scripts/generated"
        GTBI_ASSETS_DIR="${GTBI_ASSETS_DIR:-$GTBI_BOOTSTRAP_DIR/gtbi}"
        GTBI_CHECKSUMS_YAML="${GTBI_CHECKSUMS_YAML:-$GTBI_BOOTSTRAP_DIR/checksums.yaml}"
        GTBI_MANIFEST_YAML="${GTBI_MANIFEST_YAML:-$GTBI_BOOTSTRAP_DIR/gtbi.manifest.yaml}"
    elif [[ -n "${SCRIPT_DIR:-}" ]]; then
        # Local checkout mode
        GTBI_LIB_DIR="$SCRIPT_DIR/scripts/lib"
        GTBI_GENERATED_DIR="$SCRIPT_DIR/scripts/generated"
        GTBI_ASSETS_DIR="$SCRIPT_DIR/gtbi"
        GTBI_CHECKSUMS_YAML="$SCRIPT_DIR/checksums.yaml"
        GTBI_MANIFEST_YAML="$SCRIPT_DIR/gtbi.manifest.yaml"
    else
        # Fallback: current directory (only valid for testing from repo root)
        # This should NOT be reached in curl-pipe mode since bootstrap_repo_archive
        # sets GTBI_BOOTSTRAP_DIR. If we reach here without SCRIPT_DIR, something is wrong.
        GTBI_LIB_DIR="./scripts/lib"
        GTBI_GENERATED_DIR="./scripts/generated"
        GTBI_ASSETS_DIR="./gtbi"
        GTBI_CHECKSUMS_YAML="./checksums.yaml"
        GTBI_MANIFEST_YAML="./gtbi.manifest.yaml"
    fi

    export GTBI_LIB_DIR GTBI_GENERATED_DIR GTBI_ASSETS_DIR GTBI_CHECKSUMS_YAML GTBI_MANIFEST_YAML

    # Validate that library directory exists - if not, fail early with a clear message
    if [[ ! -d "$GTBI_LIB_DIR" ]]; then
        local abs_lib_dir="$GTBI_LIB_DIR"
        # Try to show absolute path for better debugging
        if [[ "$GTBI_LIB_DIR" == ./* ]]; then
            abs_lib_dir="$(pwd)/${GTBI_LIB_DIR#./}"
        fi
        echo "ERROR: Library directory not found: $abs_lib_dir" >&2
        echo "This typically means bootstrap failed or the script is being run from an unexpected location." >&2
        echo "For curl|bash installation, ensure network connectivity to GitHub." >&2
        echo "For local installation, run from the repository root directory." >&2
        exit 1
    fi

    # Source minimal libs in correct order (logging, then helpers)
    if [[ -f "$GTBI_LIB_DIR/logging.sh" ]]; then
        # shellcheck source=scripts/lib/logging.sh
        source "$GTBI_LIB_DIR/logging.sh"
    fi

    # Verify internal script integrity before sourcing (bd-3tpl.5)
    # Fail-closed: abort if any tracked script has been modified.
    # Gracefully skips if checksums file is missing (pre-migration compat).
    if [[ -f "$GTBI_GENERATED_DIR/internal_checksums.sh" ]]; then
        # shellcheck source=scripts/generated/internal_checksums.sh
        source "$GTBI_GENERATED_DIR/internal_checksums.sh"
        if declare -p GTBI_INTERNAL_CHECKSUMS &>/dev/null; then
            local _ics_base
            if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]]; then
                _ics_base="$GTBI_BOOTSTRAP_DIR"
            elif [[ -n "${SCRIPT_DIR:-}" ]]; then
                _ics_base="$SCRIPT_DIR"
            else
                _ics_base="."
            fi
            local _ics_fail=0
            for _ics_path in "${!GTBI_INTERNAL_CHECKSUMS[@]}"; do
                local _ics_expected="${GTBI_INTERNAL_CHECKSUMS[$_ics_path]}"
                local _ics_file="$_ics_base/$_ics_path"
                if [[ -f "$_ics_file" ]]; then
                    local _ics_actual
                    _ics_actual="$(gtbi_calculate_file_sha256 "$_ics_file" 2>/dev/null || true)"
                    if [[ -z "$_ics_actual" ]]; then
                        _ics_fail=$((_ics_fail + 1))
                        if declare -f log_error &>/dev/null; then
                            log_error "INTEGRITY: failed to checksum $_ics_path"
                        else
                            echo "ERROR: INTEGRITY: failed to checksum $_ics_path" >&2
                        fi
                        continue
                    fi
                    if [[ "$_ics_actual" != "$_ics_expected" ]]; then
                        _ics_fail=$((_ics_fail + 1))
                        if declare -f log_error &>/dev/null; then
                            log_error "INTEGRITY: $_ics_path checksum mismatch (expected ${_ics_expected:0:12}… got ${_ics_actual:0:12}…)"
                        else
                            echo "ERROR: INTEGRITY: $_ics_path checksum mismatch" >&2
                        fi
                    fi
                else
                    _ics_fail=$((_ics_fail + 1))
                    if declare -f log_error &>/dev/null; then
                        log_error "INTEGRITY: $_ics_path missing (expected checksum ${_ics_expected:0:12}…)"
                    else
                        echo "ERROR: INTEGRITY: $_ics_path missing" >&2
                    fi
                fi
            done
            if [[ "$_ics_fail" -gt 0 ]]; then
                local _msg="Internal script integrity check failed: $_ics_fail file(s) modified. Run 'bun run generate' to regenerate checksums."
                if declare -f log_error &>/dev/null; then
                    log_error "$_msg"
                else
                    echo "ERROR: $_msg" >&2
                fi
                exit 1
            fi
            if [[ "$_ics_fail" -eq 0 ]] && declare -f log_success &>/dev/null; then
                log_success "Internal script integrity verified (${GTBI_INTERNAL_CHECKSUMS_COUNT:-?} scripts)"
            fi
        fi
    fi

    if [[ -f "$GTBI_LIB_DIR/security.sh" ]]; then
        # shellcheck source=scripts/lib/security.sh
        source "$GTBI_LIB_DIR/security.sh"
    fi

    if [[ -f "$GTBI_LIB_DIR/contract.sh" ]]; then
        # shellcheck source=scripts/lib/contract.sh
        source "$GTBI_LIB_DIR/contract.sh"
    fi

    if [[ -f "$GTBI_LIB_DIR/install_helpers.sh" ]]; then
        # shellcheck source=scripts/lib/install_helpers.sh
        source "$GTBI_LIB_DIR/install_helpers.sh"
    fi

    if [[ -f "$GTBI_LIB_DIR/user.sh" ]]; then
        # shellcheck source=scripts/lib/user.sh
        source "$GTBI_LIB_DIR/user.sh"
    fi

    # Source state management for resume/progress tracking (mjt.5.8)
    if [[ -f "$GTBI_LIB_DIR/state.sh" ]]; then
        # shellcheck source=scripts/lib/state.sh
        source "$GTBI_LIB_DIR/state.sh"
    fi

    # Source error pattern matcher (report.sh uses get_suggested_fix when available).
    if [[ -f "$GTBI_LIB_DIR/errors.sh" ]]; then
        # shellcheck source=scripts/lib/errors.sh
        source "$GTBI_LIB_DIR/errors.sh"
    fi

    # Source structured failure/success reporting (mjt.5.8).
    if [[ -f "$GTBI_LIB_DIR/report.sh" ]]; then
        # shellcheck source=scripts/lib/report.sh
        source "$GTBI_LIB_DIR/report.sh"
    fi

    # Source error tracking for try_step wrappers (mjt.5.8)
    if [[ -f "$GTBI_LIB_DIR/error_tracking.sh" ]]; then
        # shellcheck source=scripts/lib/error_tracking.sh
        source "$GTBI_LIB_DIR/error_tracking.sh"
    fi

    # Source Ubuntu upgrade library from the same lib dir when available (nb4).
    if [[ -f "$GTBI_LIB_DIR/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$GTBI_LIB_DIR/ubuntu_upgrade.sh"
        export GTBI_UBUNTU_UPGRADE_LOADED=1
    fi

    # Source tailscale installer (bt5)
    if [[ -f "$GTBI_LIB_DIR/tailscale.sh" ]]; then
        # shellcheck source=scripts/lib/tailscale.sh
        source "$GTBI_LIB_DIR/tailscale.sh"
    fi

    # Source finalize library
    if [[ -f "$GTBI_LIB_DIR/finalize.sh" ]]; then
        # shellcheck source=scripts/lib/finalize.sh
        source "$GTBI_LIB_DIR/finalize.sh"
    fi

    # Source auto-fix modules (bd-19y9.3.4)
    if [[ -f "$GTBI_LIB_DIR/autofix.sh" ]]; then
        # shellcheck source=scripts/lib/autofix.sh
        source "$GTBI_LIB_DIR/autofix.sh"
        export GTBI_AUTOFIX_LOADED=1
    fi
    if [[ -f "$GTBI_LIB_DIR/autofix_unattended.sh" ]]; then
        # shellcheck source=scripts/lib/autofix_unattended.sh
        source "$GTBI_LIB_DIR/autofix_unattended.sh"
    fi
    if [[ -f "$GTBI_LIB_DIR/autofix_existing.sh" ]]; then
        # shellcheck source=scripts/lib/autofix_existing.sh
        source "$GTBI_LIB_DIR/autofix_existing.sh"
    fi

    # Source webhook notification library (bd-2zqr)
    if [[ -f "$GTBI_LIB_DIR/webhook.sh" ]]; then
        # shellcheck source=scripts/lib/webhook.sh
        source "$GTBI_LIB_DIR/webhook.sh"
    fi
    # Source ntfy.sh notification library (bd-2igt6)
    if [[ -f "$GTBI_LIB_DIR/notify.sh" ]]; then
        # shellcheck source=scripts/lib/notify.sh
        source "$GTBI_LIB_DIR/notify.sh"
    fi

    # Source manifest index (data-only, safe to source)
    if [[ -f "$GTBI_GENERATED_DIR/manifest_index.sh" ]]; then
        # shellcheck source=scripts/generated/manifest_index.sh
        source "$GTBI_GENERATED_DIR/manifest_index.sh"
        GTBI_MANIFEST_INDEX_LOADED=true
    else
        GTBI_MANIFEST_INDEX_LOADED=false
    fi

    export GTBI_MANIFEST_INDEX_LOADED
}

# ============================================================
# Source Generated Installers (mjt.5.6)
# Loads generated category scripts for module functions.
# ============================================================
source_generated_installers() {
    if [[ "${GTBI_GENERATED_SOURCED:-false}" == "true" ]]; then
        return 0
    fi

    if [[ -z "${GTBI_GENERATED_DIR:-}" ]]; then
        log_warn "GTBI_GENERATED_DIR not set; cannot source generated installers"
        return 0
    fi

    if [[ ! -d "$GTBI_GENERATED_DIR" ]]; then
        log_warn "Generated installers directory not found: $GTBI_GENERATED_DIR"
        return 0
    fi

    local script=""
    local scripts=(
        "install_users.sh"
        "install_base.sh"
        "install_filesystem.sh"
        "install_shell.sh"
        "install_cli.sh"
        "install_network.sh"
        "install_lang.sh"
        "install_tools.sh"
        "install_agents.sh"
        "install_stack.sh"
        "install_gtbi.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$GTBI_GENERATED_DIR/$script" ]]; then
            # shellcheck source=/dev/null
            source "$GTBI_GENERATED_DIR/$script"
        fi
    done

    GTBI_GENERATED_SOURCED=true
    export GTBI_GENERATED_SOURCED
}

# ============================================================
# List Modules (mjt.5.3)
# Prints available modules from manifest_index.sh
# ============================================================
list_modules() {
    if [[ "${GTBI_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "Error: Manifest index not loaded. Cannot list modules." >&2
        return 1
    fi

    echo "Available GTBI Modules"
    echo "======================"
    echo ""

    local current_phase=""
    local module=""
    local phase=""
    local category=""
    local deps=""
    local enabled=""
    local key=""
    local enabled_marker=""
    for module in "${GTBI_MODULES_IN_ORDER[@]}"; do
        # Use key variable to prevent arithmetic evaluation with dots
        key="$module"
        phase="${GTBI_MODULE_PHASE[$key]:-?}"
        category="${GTBI_MODULE_CATEGORY[$key]:-?}"
        deps="${GTBI_MODULE_DEPS[$key]:-none}"
        enabled="${GTBI_MODULE_DEFAULT[$key]:-1}"

        if [[ "$phase" != "$current_phase" ]]; then
            echo ""
            echo "Phase $phase:"
            current_phase="$phase"
        fi

        enabled_marker="+"
        if [[ "$enabled" == "0" || "$enabled" == "false" ]]; then
            enabled_marker="-"
        fi

        echo "  [$enabled_marker] $module ($category)"
        if [[ -n "$deps" ]] && [[ "$deps" != "none" ]]; then
            echo "      deps: $deps"
        fi
    done

    echo ""
    echo "Legend: [+] enabled by default, [-] optional"
    echo "Total: ${#GTBI_MODULES_IN_ORDER[@]} modules"
}

# ============================================================
# Print Plan (mjt.5.3)
# Prints the effective execution plan without running installs.
# ============================================================
print_execution_plan() {
    if [[ "${GTBI_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "Error: Manifest index not loaded. Cannot print plan." >&2
        return 1
    fi

    echo "GTBI Installation Plan"
    echo "======================"
    echo ""
    echo "Mode: $MODE"
    echo "Selected modules: ${#GTBI_EFFECTIVE_PLAN[@]} of ${#GTBI_MODULES_IN_ORDER[@]} available"
    echo ""

    # Show selection settings if non-default
    if [[ ${#ONLY_MODULES[@]} -gt 0 ]]; then
        echo "Selection: --only ${ONLY_MODULES[*]}"
    elif [[ ${#ONLY_PHASES[@]} -gt 0 ]]; then
        echo "Selection: --only-phase ${ONLY_PHASES[*]}"
    fi
    if [[ ${#SKIP_MODULES[@]} -gt 0 ]]; then
        echo "Skipped:   --skip ${SKIP_MODULES[*]}"
    fi
    if [[ "${NO_DEPS:-false}" == "true" ]]; then
        echo "⚠ --no-deps: dependencies NOT auto-installed"
    fi
    echo ""
    echo "Execution order:"
    echo ""

    local idx=1
    local module phase func key reason
    for module in "${GTBI_EFFECTIVE_PLAN[@]}"; do
        # Use key variable to prevent arithmetic evaluation with dots
        key="$module"
        phase="${GTBI_MODULE_PHASE[$key]:-?}"
        func="${GTBI_MODULE_FUNC[$key]:-?}"
        reason="${GTBI_PLAN_REASON[$key]:-}"
        if [[ -n "$reason" ]]; then
            printf "  %2d. [Phase %s] %s -> %s()  (%s)\n" "$idx" "$phase" "$module" "$func" "$reason"
        else
            printf "  %2d. [Phase %s] %s -> %s()\n" "$idx" "$phase" "$module" "$func"
        fi
        ((++idx))  # Use ++idx to avoid exit on zero under set -e
    done

    echo ""
    echo "This is a preview. Run without --print-plan to execute."
}

# ============================================================
# Auto-Fix Functions (bd-19y9.3.4)
# ============================================================
# Handles automatic fixing of pre-flight issues based on AUTO_FIX_MODE

# Handle a single auto-fix item based on current mode
# Usage: handle_autofix <fix_name> <description>
handle_autofix() {
    local fix_name="$1"
    local description="$2"
    local fix_func="autofix_${fix_name}_fix"

    case "$AUTO_FIX_MODE" in
        "no")
            log_warn "[PRE-FLIGHT] $description"
            log_warn "[PRE-FLIGHT] Use --auto-fix to resolve automatically"
            ;;
        "dry-run")
            log_info "[DRY-RUN] Would auto-fix: $description"
            if type "$fix_func" &>/dev/null; then
                "$fix_func" dry-run 2>&1 | while IFS= read -r line; do
                    log_detail "  $line"
                done
            fi
            ;;
        "yes")
            log_info "[AUTO-FIX] Fixing: $description"
            if type "$fix_func" &>/dev/null; then
                "$fix_func" fix
            else
                log_warn "[AUTO-FIX] Fix function not available: $fix_func"
            fi
            ;;
        "prompt")
            log_warn "[PRE-FLIGHT] $description"
            # In --yes mode or non-TTY (curl|bash), auto-accept the fix
            if [[ "${YES_MODE:-false}" == "true" ]] || [[ ! -t 0 ]]; then
                log_info "[AUTO-FIX] Fixing (non-interactive): $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                else
                    log_warn "[AUTO-FIX] Fix function not available: $fix_func"
                fi
            elif confirm "Would you like GTBI to fix this automatically?"; then
                log_info "[AUTO-FIX] Fixing: $description"
                if type "$fix_func" &>/dev/null; then
                    "$fix_func" fix
                else
                    log_warn "[AUTO-FIX] Fix function not available: $fix_func"
                fi
            else
                log_warn "[PRE-FLIGHT] Skipped auto-fix for: $description"
            fi
            ;;
    esac
}

# Run auto-fix checks before main preflight validation
run_autofix_checks() {
    # Skip if auto-fix modules not loaded
    if [[ "${GTBI_AUTOFIX_LOADED:-0}" != "1" ]]; then
        return 0
    fi

    # Skip if auto-fix disabled
    if [[ "$AUTO_FIX_MODE" == "no" ]]; then
        log_debug "Auto-fix disabled via --no-auto-fix" 2>/dev/null || true
        return 0
    fi

    log_info "Running auto-fix pre-flight checks..."

    # Check for existing GTBI installation
    # Skip this check when --only or --only-phase is specified, since the user
    # is targeting a specific module on an already-installed system
    if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
        if type autofix_existing_gtbi_needs_handling &>/dev/null; then
            if autofix_existing_gtbi_needs_handling 2>/dev/null; then
                local version
                version=$(get_installed_version 2>/dev/null || echo "unknown")
                handle_autofix "existing" "Existing GTBI installation detected (version: $version)"
            fi
        fi
    else
        log_debug "Skipping existing-installation check (--only/--only-phase mode)"
    fi

    # Check for unattended-upgrades issues
    if type autofix_unattended_upgrades_needs_fix &>/dev/null; then
        if autofix_unattended_upgrades_needs_fix 2>/dev/null; then
            handle_autofix "unattended_upgrades" "unattended-upgrades service may cause apt lock conflicts"
        fi
    fi

    # Add more auto-fix checks here as they are implemented
    # e.g., nvm/pyenv conflicts from bd-19y9.3.2

    log_debug "Auto-fix pre-flight checks complete"
}

# ============================================================
# Pre-Flight Validation
# ============================================================
# Runs system validation checks before installation begins.
# Related beads: gastown_batteries_included-545

run_preflight_checks() {
    log_step "0/8" "Running pre-flight validation..."

    local preflight_script=""
    local preflight_tmp=""

    # Try to find preflight script in different locations
    if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "$GTBI_BOOTSTRAP_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$GTBI_BOOTSTRAP_DIR/scripts/preflight.sh"
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/scripts/preflight.sh" ]]; then
        preflight_script="$SCRIPT_DIR/scripts/preflight.sh"
    elif [[ -f "./scripts/preflight.sh" ]]; then
        preflight_script="./scripts/preflight.sh"
    else
        # Download preflight script for curl | bash scenario (if curl available)
        local curl_bin=""
        curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
        if [[ -n "$curl_bin" ]]; then
            log_detail "Downloading preflight script..."
            local mktemp_bin=""
            mktemp_bin="$(gtbi_early_system_binary_path mktemp 2>/dev/null || true)"
            if [[ -n "$mktemp_bin" ]]; then
                preflight_tmp="$("$mktemp_bin" "${TMPDIR:-/tmp}/gtbi-preflight.XXXXXX" 2>/dev/null)" || preflight_tmp=""
            fi
            if [[ -n "$preflight_tmp" ]] && gtbi_curl -o "$preflight_tmp" "$GTBI_RAW/scripts/preflight.sh" 2>/dev/null; then
                local chmod_bin=""
                chmod_bin="$(gtbi_early_system_binary_path chmod 2>/dev/null || true)"
                if [[ -n "$chmod_bin" ]]; then
                    "$chmod_bin" +x "$preflight_tmp"
                fi
                preflight_script="$preflight_tmp"
            else
                log_warn "Could not download preflight script - skipping checks"
                return 0
            fi
        else
            log_warn "curl not available - skipping preflight checks"
            return 0
        fi
    fi

    # Run preflight checks and capture exit code correctly
    # (can't use "if ! cmd; then exit_code=$?" because $? would be 0 from the negation)
    local exit_code=0
    local bash_bin=""
    bash_bin="$(gtbi_early_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        log_warn "bash not available - skipping preflight checks"
        return 0
    fi
    "$bash_bin" "$preflight_script" || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "" >&2
        log_error "Pre-flight validation failed!"
        echo "" >&2
        log_info "Run preflight checks for details:"
        log_info "  bash $preflight_script"
        echo "" >&2
        log_info "Use --skip-preflight to bypass (not recommended)"
        echo "" >&2
        if [[ -n "$preflight_tmp" ]]; then
            rm -f "$preflight_tmp"
        fi
        exit 1
    fi

    # Cleanup downloaded preflight script on success
    if [[ -n "$preflight_tmp" ]]; then
        rm -f "$preflight_tmp"
    fi

    log_success "[0/9] Pre-flight validation passed"
    echo ""
}

GTBI_CURL_BASE_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)
_gtbi_early_curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
_gtbi_early_grep_bin="$(gtbi_early_system_binary_path grep 2>/dev/null || true)"
if [[ -n "$_gtbi_early_curl_bin" && -n "$_gtbi_early_grep_bin" ]] && "$_gtbi_early_curl_bin" --help all 2>/dev/null | "$_gtbi_early_grep_bin" -q -- '--proto'; then
    GTBI_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
fi
unset _gtbi_early_curl_bin _gtbi_early_grep_bin

gtbi_curl() {
    local curl_bin=""
    curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        log_error "Unable to locate curl"
        return 1
    fi

    "$curl_bin" "${GTBI_CURL_BASE_ARGS[@]}" "$@"
}

# Automatic retry for transient network errors (fast total budget).
GTBI_CURL_RETRY_DELAYS=(0 5 15)

gtbi_is_retryable_curl_exit_code() {
    local exit_code="${1:-0}"
    case "$exit_code" in
        6|7|28|35|52|56) return 0 ;; # DNS/connect/timeout/SSL/empty reply/recv error
        *) return 1 ;;
    esac
}

gtbi_curl_with_retry() {
    local url="$1"
    local output_path="$2"

    if [[ -z "$url" || -z "$output_path" ]]; then
        log_error "gtbi_curl_with_retry: missing url or output path"
        return 1
    fi

    local attempt delay exit_code
    local max_attempts="${#GTBI_CURL_RETRY_DELAYS[@]}"
    if (( max_attempts == 0 )); then
        GTBI_CURL_RETRY_DELAYS=(0 5 15)
        max_attempts="${#GTBI_CURL_RETRY_DELAYS[@]}"
    fi

    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${GTBI_CURL_RETRY_DELAYS[$attempt]}"
        if (( attempt > 0 )); then
            log_detail "Retry ${attempt}/${max_attempts} (waiting ${delay}s)..."
            sleep "$delay"
        fi

        if gtbi_curl -o "$output_path" "$url"; then
            return 0
        else
            exit_code=$?
        fi
        if ! gtbi_is_retryable_curl_exit_code "$exit_code"; then
            return "$exit_code"
        fi
    done

    return 1
}

gtbi_calculate_file_sha256() {
    local file_path="$1"

    if command_exists sha256sum; then
        sha256sum "$file_path" | cut -d' ' -f1
        return 0
    fi

    if command_exists shasum; then
        shasum -a 256 "$file_path" | cut -d' ' -f1
        return 0
    fi

    log_error "No SHA256 tool available (need sha256sum or shasum)"
    return 1
}

gtbi_download_file_and_verify_sha256() {
    local url="$1"
    local output_path="$2"
    local expected_sha256="$3"
    local label="${4:-download}"

    if [[ -z "$url" || -z "$output_path" || -z "$expected_sha256" ]]; then
        log_error "gtbi_download_file_and_verify_sha256: missing url, output path, or expected sha256"
        return 1
    fi

    if [[ "$url" != https://* ]]; then
        log_error "Security error: upstream URL is not HTTPS: $url"
        return 1
    fi

    if ! gtbi_curl_with_retry "$url" "$output_path"; then
        log_error "Failed to download $label"
        log_detail "URL: $url"
        return 1
    fi

    local actual_sha256=""
    actual_sha256="$(gtbi_calculate_file_sha256 "$output_path")" || actual_sha256=""

    if [[ -z "$actual_sha256" ]] || [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "Security error: checksum mismatch for $label"
        log_detail "URL: $url"
        log_detail "Expected: $expected_sha256"
        log_detail "Actual:   ${actual_sha256:-<missing>}"
        return 1
    fi

    return 0
}

bootstrap_repo_archive() {
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        return 0
    fi

    local ref="$GTBI_REF"
    # Cache-bust GitHub's CDN to ensure we get the latest archive
    # GitHub caches archives for up to 5 minutes; this ensures fresh downloads
    local cache_buster
    cache_buster="$(date +%s)"
    local archive_url="https://github.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/archive/${ref}.tar.gz?cb=${cache_buster}"
    local ref_safe="${ref//[^a-zA-Z0-9._-]/_}"
    local tmp_dir
    local mktemp_bin=""
    local chmod_bin=""
    local tar_bin=""
    local rm_bin=""
    local find_bin=""
    local bash_bin=""
    local grep_bin=""
    local head_bin=""
    local cut_bin=""
    local tr_bin=""

    tar_bin="$(gtbi_early_system_binary_path tar 2>/dev/null || true)"
    if [[ -z "$tar_bin" ]]; then
        log_error "Bootstrap requires tar (install tar or run from a local checkout)"
        return 1
    fi
    mktemp_bin="$(gtbi_early_system_binary_path mktemp 2>/dev/null || true)"
    chmod_bin="$(gtbi_early_system_binary_path chmod 2>/dev/null || true)"
    rm_bin="$(gtbi_early_system_binary_path rm 2>/dev/null || true)"
    find_bin="$(gtbi_early_system_binary_path find 2>/dev/null || true)"
    bash_bin="$(gtbi_early_system_binary_path bash 2>/dev/null || true)"
    grep_bin="$(gtbi_early_system_binary_path grep 2>/dev/null || true)"
    head_bin="$(gtbi_early_system_binary_path head 2>/dev/null || true)"
    cut_bin="$(gtbi_early_system_binary_path cut 2>/dev/null || true)"
    tr_bin="$(gtbi_early_system_binary_path tr 2>/dev/null || true)"
    if [[ -z "$mktemp_bin" || -z "$chmod_bin" || -z "$rm_bin" || -z "$find_bin" || -z "$bash_bin" || -z "$grep_bin" || -z "$head_bin" || -z "$cut_bin" || -z "$tr_bin" ]]; then
        log_error "Bootstrap requires core system utilities (mktemp, chmod, rm, find, bash, grep, head, cut, tr)"
        return 1
    fi

    # mktemp portability: BSD mktemp requires Xs at end of template; tar doesn't need a .tar.gz suffix.
    GTBI_TMP_ARCHIVE="$("$mktemp_bin" "${TMPDIR:-/tmp}/gtbi-archive-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp file for archive"
    }

    tmp_dir="$("$mktemp_bin" -d "${TMPDIR:-/tmp}/gtbi-bootstrap-${ref_safe}.XXXXXX" 2>/dev/null)" || {
        log_fatal "Failed to create temp dir for extraction"
    }
    GTBI_BOOTSTRAP_DIR="$tmp_dir"
    _GTBI_BOOTSTRAP_DIR_CREATED="$tmp_dir"
    _GTBI_BOOTSTRAP_DIR_TMP_ROOT="${TMPDIR:-/tmp}"
    _GTBI_BOOTSTRAP_DIR_TMP_ROOT="${_GTBI_BOOTSTRAP_DIR_TMP_ROOT%/}"
    _GTBI_BOOTSTRAP_DIR_OWNED=true
    # Make bootstrap dir world-readable so ubuntu user can access scripts
    "$chmod_bin" 755 "$tmp_dir"

    log_step "Bootstrapping GTBI archive (${ref})"

    # Test-mode hook: offline bootstrap checks cannot use PATH-based curl
    # stubs because gtbi_curl resolves curl via absolute paths only (intentional
    # hardening, commit 958e2ee2). The hook lets tests point the bootstrap at
    # a locally-staged archive and skip the network entirely. Gated on an
    # explicit GTBI_TEST_MODE=1 so accidentally setting GTBI_TEST_ARCHIVE in
    # production cannot bypass the network path.
    if [[ "${GTBI_TEST_MODE:-}" == "1" && -n "${GTBI_TEST_ARCHIVE:-}" ]]; then
        local cp_bin
        cp_bin="$(gtbi_early_system_binary_path cp 2>/dev/null || true)"
        if [[ -z "$cp_bin" ]]; then
            log_error "Test-mode bootstrap requires cp"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
        if [[ ! -f "$GTBI_TEST_ARCHIVE" ]]; then
            log_error "GTBI_TEST_MODE=1 but GTBI_TEST_ARCHIVE is not a regular file: $GTBI_TEST_ARCHIVE"
            "$rm_bin" -f "$GTBI_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
        log_detail "Test mode: using local archive $GTBI_TEST_ARCHIVE"
        if ! "$cp_bin" "$GTBI_TEST_ARCHIVE" "$GTBI_TMP_ARCHIVE"; then
            log_error "Failed to stage local archive for bootstrap"
            "$rm_bin" -f "$GTBI_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
    else
        log_detail "Downloading ${archive_url}"
        if ! gtbi_curl_with_retry "$archive_url" "$GTBI_TMP_ARCHIVE"; then
            log_error "Failed to download GTBI archive. Try again, or pin GTBI_REF to a tag/sha."
            "$rm_bin" -f "$GTBI_TMP_ARCHIVE"
            "$rm_bin" -rf "$tmp_dir"
            return 1
        fi
    fi

    log_detail "Extracting runtime assets"
    if ! "$tar_bin" -xzf "$GTBI_TMP_ARCHIVE" -C "$tmp_dir" --strip-components=1 \
        --wildcards --wildcards-match-slash \
        "*/scripts/**" \
        "*/gtbi/**" \
        "*/checksums.yaml" \
        "*/gtbi.manifest.yaml" \
        "*/VERSION"; then
        log_error "Failed to extract GTBI bootstrap archive (tar error)"
        "$rm_bin" -f "$GTBI_TMP_ARCHIVE"
        return 1
    fi
    "$rm_bin" -f "$GTBI_TMP_ARCHIVE"

    if [[ ! -f "$tmp_dir/gtbi.manifest.yaml" ]] || [[ ! -f "$tmp_dir/checksums.yaml" ]] || [[ ! -f "$tmp_dir/VERSION" ]]; then
        log_error "Bootstrap archive missing required manifest/checksums/VERSION files"
        return 1
    fi

    if [[ ! -f "$tmp_dir/scripts/generated/manifest_index.sh" ]]; then
        log_error "Bootstrap archive missing scripts/generated/manifest_index.sh"
        return 1
    fi

    log_detail "Validating extracted shell scripts (bash -n)"
    local shellcheck_failed=false
    while IFS= read -r -d '' script_file; do
        if ! "$bash_bin" -n "$script_file" >/dev/null 2>&1; then
            log_error "Syntax error in extracted script: $script_file"
            shellcheck_failed=true
            break
        fi
    done < <("$find_bin" "$tmp_dir" -type f -name "*.sh" -print0)

    if [[ "$shellcheck_failed" == "true" ]]; then
        log_error "Bootstrap validation failed. Retry or pin GTBI_REF to a known-good tag/sha."
        return 1
    fi

    local manifest_sha expected_sha
    manifest_sha="$(gtbi_calculate_file_sha256 "$tmp_dir/gtbi.manifest.yaml")" || return 1
    expected_sha="$("$grep_bin" -E '^GTBI_MANIFEST_SHA256=' "$tmp_dir/scripts/generated/manifest_index.sh" | "$head_bin" -n 1 | "$cut_bin" -d'=' -f2 | "$tr_bin" -d '"[:space:]\r' || true)"

    if [[ -z "$expected_sha" ]]; then
        log_error "Bootstrap manifest index missing GTBI_MANIFEST_SHA256"
        return 1
    fi

    if [[ "$manifest_sha" != "$expected_sha" ]]; then
        log_error "Bootstrap mismatch: generated scripts do not match manifest."
        log_detail "Expected: $expected_sha"
        log_detail "Actual:   $manifest_sha"
        return 1
    fi

    GTBI_BOOTSTRAP_DIR="$tmp_dir"
    GTBI_LIB_DIR="$tmp_dir/scripts/lib"
    GTBI_GENERATED_DIR="$tmp_dir/scripts/generated"
    GTBI_ASSETS_DIR="$tmp_dir/gtbi"
    GTBI_CHECKSUMS_YAML="$tmp_dir/checksums.yaml"
    GTBI_MANIFEST_YAML="$tmp_dir/gtbi.manifest.yaml"

    export GTBI_BOOTSTRAP_DIR GTBI_LIB_DIR GTBI_GENERATED_DIR GTBI_ASSETS_DIR GTBI_CHECKSUMS_YAML GTBI_MANIFEST_YAML

    log_success "Bootstrap archive ready"
    return 0
}

_gtbi_install_asset_has_symlink_component_under_prefix() {
    local prefix="$1"
    local dest_path="$2"

    case "$dest_path" in
        "$prefix" | "$prefix"/*) ;;
        *) return 1 ;; # Not under prefix; no signal
    esac

    local rel="${dest_path#"$prefix"}"
    rel="${rel#/}"

    local current="$prefix"
    if [[ -L "$current" ]]; then
        return 0
    fi

    if [[ -z "$rel" ]]; then
        return 1
    fi

    local -a parts=()
    IFS='/' read -r -a parts <<< "$rel"
    local part=""

    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        current="$current/$part"
        if [[ -L "$current" ]]; then
            return 0
        fi
    done

    return 1
}

install_asset() {
    local rel_path="$1"
    local dest_path="$2"

    # Security: Validate rel_path doesn't contain path traversal
    if [[ "$rel_path" == *".."* ]]; then
        log_error "install_asset: Invalid path (contains '..'): $rel_path"
        return 1
    fi

    if [[ -z "${GTBI_HOME:-}" ]] || [[ -z "${TARGET_HOME:-}" ]]; then
        log_error "install_asset: GTBI_HOME/TARGET_HOME not set (call init_target_paths first)"
        return 1
    fi

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local cp_bin=""
    mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_asset: Unable to locate mkdir"
        return 1
    fi
    cp_bin="$(gtbi_early_system_binary_path cp 2>/dev/null || true)"
    if [[ -z "$cp_bin" ]]; then
        log_error "install_asset: Unable to locate cp"
        return 1
    fi

    # Security: Validate dest_path is under expected directories
    local allowed_prefixes=("$GTBI_HOME" "$TARGET_HOME" "/data" "/usr/local/bin")
    if [[ -n "${GTBI_BIN_DIR:-}" ]] && [[ "$GTBI_BIN_DIR" == /* ]] && [[ "$GTBI_BIN_DIR" != "/" ]]; then
        allowed_prefixes+=("$GTBI_BIN_DIR")
    fi
    local valid_dest=false
    for prefix in "${allowed_prefixes[@]}"; do
        [[ -n "$prefix" ]] || continue
        case "$dest_path" in
            "$prefix" | "$prefix"/*)
                valid_dest=true
                break
                ;;
        esac
    done
    if [[ "$valid_dest" != "true" ]]; then
        log_error "install_asset: Destination outside allowed paths: $dest_path"
        return 1
    fi

    # Ensure destination directory exists (matches install_asset_from_path behavior)
    local _ia_dest_dir
    _ia_dest_dir="$(dirname "$dest_path")"
    if [[ ! -d "$_ia_dest_dir" ]]; then
        if [[ -w "$(dirname "$_ia_dest_dir" 2>/dev/null)" ]] || [[ $EUID -eq 0 ]]; then
            "$mkdir_bin" -p "$_ia_dest_dir" 2>/dev/null || true
        elif [[ ${#sudo_cmd[@]} -gt 0 ]]; then
            "${sudo_cmd[@]}" "$mkdir_bin" -p "$_ia_dest_dir" 2>/dev/null || true
        fi
    fi

    # If running with elevated privileges, refuse to write through symlink path
    # components for sensitive destinations (prevents symlink clobber attacks).
    if [[ $EUID -eq 0 ]]; then
        if _gtbi_install_asset_has_symlink_component_under_prefix "$GTBI_HOME" "$dest_path" || \
           _gtbi_install_asset_has_symlink_component_under_prefix "$TARGET_HOME" "$dest_path" || \
           _gtbi_install_asset_has_symlink_component_under_prefix "/usr/local/bin" "$dest_path"; then
            log_error "install_asset: Refusing to write through symlink path component: $dest_path"
            return 1
        fi
        if [[ -n "${GTBI_BIN_DIR:-}" ]] && [[ "$GTBI_BIN_DIR" == /* ]] && [[ "$GTBI_BIN_DIR" != "/" ]] && \
           [[ "$GTBI_BIN_DIR" != "/usr/local/bin" ]] && \
           _gtbi_install_asset_has_symlink_component_under_prefix "$GTBI_BIN_DIR" "$dest_path"; then
            log_error "install_asset: Refusing to write through symlink path component: $dest_path"
            return 1
        fi
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_asset: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -f "$GTBI_BOOTSTRAP_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! "${sudo_cmd[@]}" "$cp_bin" "$GTBI_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from bootstrap: $rel_path"
                return 1
            fi
        elif ! "$cp_bin" "$GTBI_BOOTSTRAP_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from bootstrap: $rel_path"
            return 1
        fi
    elif [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
        if [[ "$need_sudo" == "true" ]]; then
            if ! "${sudo_cmd[@]}" "$cp_bin" "$SCRIPT_DIR/$rel_path" "$dest_path"; then
                log_error "install_asset: Failed to copy from script dir: $rel_path"
                return 1
            fi
        elif ! "$cp_bin" "$SCRIPT_DIR/$rel_path" "$dest_path"; then
            log_error "install_asset: Failed to copy from script dir: $rel_path"
            return 1
        fi
    else
        if [[ "$need_sudo" == "true" ]]; then
            local curl_bin=""
            curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
            if [[ -z "$curl_bin" ]]; then
                log_error "install_asset: Unable to locate curl"
                return 1
            fi
            if ! "${sudo_cmd[@]}" "$curl_bin" "${GTBI_CURL_BASE_ARGS[@]}" -o "$dest_path" "$GTBI_RAW/$rel_path"; then
                log_error "install_asset: Failed to download: $rel_path"
                return 1
            fi
        elif ! gtbi_curl -o "$dest_path" "$GTBI_RAW/$rel_path"; then
            log_error "install_asset: Failed to download: $rel_path"
            return 1
        fi
    fi

    # Verify the file was actually created
    if [[ ! -f "$dest_path" ]]; then
        log_error "install_asset: File not created: $dest_path"
        return 1
    fi
}

install_asset_from_path() {
    local src_path="$1"
    local dest_path="$2"

    if [[ -z "$src_path" || -z "$dest_path" ]]; then
        log_error "install_asset_from_path: Missing source or destination path"
        return 1
    fi

    if [[ ! -f "$src_path" ]]; then
        log_error "install_asset_from_path: Source file not found: $src_path"
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local cp_bin=""
    mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_asset_from_path: Unable to locate mkdir"
        return 1
    fi
    cp_bin="$(gtbi_early_system_binary_path cp 2>/dev/null || true)"
    if [[ -z "$cp_bin" ]]; then
        log_error "install_asset_from_path: Unable to locate cp"
        return 1
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_asset_from_path: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ "$need_sudo" == "true" ]]; then
        if ! "${sudo_cmd[@]}" "$mkdir_bin" -p "$dest_dir"; then
            log_error "install_asset_from_path: Failed to create destination directory: $dest_dir"
            return 1
        fi
        if ! "${sudo_cmd[@]}" "$cp_bin" "$src_path" "$dest_path"; then
            log_error "install_asset_from_path: Failed to copy $src_path to $dest_path"
            return 1
        fi
    else
        if ! "$mkdir_bin" -p "$dest_dir"; then
            log_error "install_asset_from_path: Failed to create destination directory: $dest_dir"
            return 1
        fi
        if ! "$cp_bin" "$src_path" "$dest_path"; then
            log_error "install_asset_from_path: Failed to copy $src_path to $dest_path"
            return 1
        fi
    fi

    if [[ ! -f "$dest_path" ]]; then
        log_error "install_asset_from_path: File not created: $dest_path"
        return 1
    fi
}

install_checksums_yaml() {
    local dest_path="$1"

    if [[ -z "$dest_path" ]]; then
        log_error "install_checksums_yaml: Missing destination path"
        return 1
    fi

    # If checksums ref matches the install ref, use the standard asset path.
    if [[ -z "${GTBI_CHECKSUMS_REF:-}" || -z "${GTBI_REF_INPUT:-}" || "$GTBI_CHECKSUMS_REF" == "$GTBI_REF_INPUT" ]]; then
        install_asset "checksums.yaml" "$dest_path"
        return $?
    fi

    # Otherwise, fetch checksums from the dedicated checksums ref.
    local content=""
    content="$(gtbi_fetch_fresh_checksums_via_api)" || {
        local cb
        cb="$(date +%s)"
        content="$(gtbi_fetch_url_content "$GTBI_CHECKSUMS_RAW/checksums.yaml?cb=${cb}")" || {
            log_error "Failed to fetch checksums.yaml from ref '${GTBI_CHECKSUMS_REF}'"
            return 1
        }
    }
    if ! ( gtbi_parse_checksums_content "$content" && gtbi_validate_upstream_checksums ); then
        log_error "Fetched checksums.yaml from ref '${GTBI_CHECKSUMS_REF}' failed validation"
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "$dest_path")"

    local -a sudo_cmd=()
    local sudo_bin=""
    if [[ $EUID -ne 0 ]]; then
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            sudo_cmd=("$sudo_bin")
        fi
    fi

    local mkdir_bin=""
    local tee_bin=""
    mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
    if [[ -z "$mkdir_bin" ]]; then
        log_error "install_checksums_yaml: Unable to locate mkdir"
        return 1
    fi
    tee_bin="$(gtbi_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$tee_bin" ]]; then
        log_error "install_checksums_yaml: Unable to locate tee"
        return 1
    fi

    if [[ ! -d "$dest_dir" ]]; then
        if [[ -w "$(dirname "$dest_dir" 2>/dev/null)" ]] || [[ $EUID -eq 0 ]]; then
            "$mkdir_bin" -p "$dest_dir" 2>/dev/null || true
        elif [[ ${#sudo_cmd[@]} -gt 0 ]]; then
            "${sudo_cmd[@]}" "$mkdir_bin" -p "$dest_dir" 2>/dev/null || true
        fi
    fi

    local need_sudo=false
    if [[ -e "$dest_path" ]]; then
        [[ -w "$dest_path" ]] || need_sudo=true
    else
        [[ -w "$dest_dir" ]] || need_sudo=true
    fi

    if [[ "$need_sudo" == "true" ]] && [[ ${#sudo_cmd[@]} -eq 0 ]]; then
        log_error "install_checksums_yaml: Destination not writable and sudo not available: $dest_path"
        return 1
    fi

    if [[ "$need_sudo" == "true" ]]; then
        if ! printf '%s' "$content" | "${sudo_cmd[@]}" "$tee_bin" "$dest_path" >/dev/null; then
            log_error "install_checksums_yaml: Failed to write $dest_path"
            return 1
        fi
    else
        if ! printf '%s' "$content" > "$dest_path"; then
            log_error "install_checksums_yaml: Failed to write $dest_path"
            return 1
        fi
    fi

    if [[ ! -f "$dest_path" ]]; then
        log_error "install_checksums_yaml: File not created: $dest_path"
        return 1
    fi
}

run_as_target() {
    local user="$TARGET_USER"
    local explicit_user_home="${TARGET_HOME:-}"
    local explicit_user_home_for_repair=""
    local user_home=""
    local passwd_entry=""
    local passwd_home=""
    local primary_bin_dir=""
    local gtbi_home_for_target=""
    local env_bin=""
    local bash_bin=""
    local sh_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""
    local -a command_argv=()

    if [[ -z "$user" ]] || [[ ! "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${user:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        return 1
    fi
    env_bin="$(gtbi_early_system_binary_path env 2>/dev/null || true)"
    if [[ -z "$env_bin" ]]; then
        log_error "Unable to locate env for target-user command"
        return 1
    fi
    bash_bin="$(gtbi_early_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        log_error "Unable to locate bash for target-user command"
        return 1
    fi
    sh_bin="$(gtbi_early_system_binary_path sh 2>/dev/null || true)"
    if [[ -z "$sh_bin" ]]; then
        log_error "Unable to locate sh for target-user command"
        return 1
    fi

    if [[ "$user" == "root" ]]; then
        user_home="/root"
    else
        passwd_entry="$(gtbi_early_getent_passwd_entry "$user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
            if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
                user_home="${passwd_home%/}"
            fi
        fi
    fi

    if [[ "$explicit_user_home" == /* ]] && [[ "$explicit_user_home" != "/" ]]; then
        explicit_user_home_for_repair="${explicit_user_home%/}"
        [[ "$explicit_user_home_for_repair" != "/" ]] || explicit_user_home_for_repair=""
    fi

    if [[ -z "$user_home" ]]; then
        user_home="$(gtbi_home_for_user "$user" || true)"
    fi
    if [[ -z "$user_home" ]] || [[ "$user_home" == "/" ]] || [[ "$user_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$user': ${user_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi

    primary_bin_dir="${GTBI_BIN_DIR:-$user_home/.local/bin}"
    if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
        case "$primary_bin_dir" in
            "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                primary_bin_dir="$user_home/.local/bin"
                ;;
        esac
    fi
    gtbi_home_for_target="${GTBI_HOME:-}"
    if [[ -n "$explicit_user_home_for_repair" ]] && [[ "$explicit_user_home_for_repair" != "$user_home" ]]; then
        case "$gtbi_home_for_target" in
            "$explicit_user_home_for_repair"|"$explicit_user_home_for_repair"/*)
                gtbi_home_for_target="$user_home/.gtbi"
                ;;
        esac
    fi

    local target_path_prefix="$primary_bin_dir:$user_home/.local/bin:$user_home/.gtbi/bin:$user_home/.cargo/bin:$user_home/.bun/bin:$user_home/.atuin/bin:$user_home/go/bin"
    local current_path="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

    # Environment variables to set for target user commands
    # UV_NO_CONFIG prevents uv from looking for config in /root when running via sudo
    # HOME is set explicitly to ensure consistent home directory.
    # PATH must include the target user's tool bins because we intentionally
    # avoid login shells and therefore cannot rely on profile files.
    # XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS let user services work even when
    # install.sh is running as root and switching to TARGET_USER non-interactively.
    local -a env_args=("UV_NO_CONFIG=1" "HOME=$user_home" "PATH=$target_path_prefix:$current_path" "TARGET_USER=$user" "TARGET_HOME=$user_home")
    local target_uid=""
    local target_runtime_dir=""
    local id_bin=""
    local current_user=""
    id_bin="$(gtbi_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]] && target_uid="$($id_bin -u "$user" 2>/dev/null)"; then
        target_runtime_dir="/run/user/$target_uid"
        if [[ -d "$target_runtime_dir" ]]; then
            env_args+=("XDG_RUNTIME_DIR=$target_runtime_dir")
            if [[ -S "$target_runtime_dir/bus" ]]; then
                env_args+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$target_runtime_dir/bus")
            fi
        fi
    fi

    # Pass GTBI context variables to target user environment
    if [[ -n "$gtbi_home_for_target" ]]; then env_args+=("GTBI_HOME=$gtbi_home_for_target"); fi
    if [[ -n "${GTBI_BIN_DIR:-}" ]]; then env_args+=("GTBI_BIN_DIR=$primary_bin_dir"); fi
    if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]]; then env_args+=("GTBI_BOOTSTRAP_DIR=$GTBI_BOOTSTRAP_DIR"); fi
    if [[ -n "${GTBI_LIB_DIR:-}" ]]; then env_args+=("GTBI_LIB_DIR=$GTBI_LIB_DIR"); fi
    if [[ -n "${GTBI_GENERATED_DIR:-}" ]]; then env_args+=("GTBI_GENERATED_DIR=$GTBI_GENERATED_DIR"); fi
    if [[ -n "${GTBI_ASSETS_DIR:-}" ]]; then env_args+=("GTBI_ASSETS_DIR=$GTBI_ASSETS_DIR"); fi
    if [[ -n "${GTBI_CHECKSUMS_YAML:-}" ]]; then env_args+=("GTBI_CHECKSUMS_YAML=$GTBI_CHECKSUMS_YAML"); fi
    if [[ -n "${GTBI_MANIFEST_YAML:-}" ]]; then env_args+=("GTBI_MANIFEST_YAML=$GTBI_MANIFEST_YAML"); fi
    if [[ -n "${CHECKSUMS_FILE:-}" ]]; then env_args+=("CHECKSUMS_FILE=$CHECKSUMS_FILE"); fi
    if [[ -n "${SCRIPT_DIR:-}" ]]; then env_args+=("SCRIPT_DIR=$SCRIPT_DIR"); fi
    if [[ -n "${GTBI_RAW:-}" ]]; then env_args+=("GTBI_RAW=$GTBI_RAW"); fi
    if [[ -n "${GTBI_VERSION:-}" ]]; then env_args+=("GTBI_VERSION=$GTBI_VERSION"); fi
    if [[ -n "${GTBI_REF:-}" ]]; then env_args+=("GTBI_REF=$GTBI_REF"); fi

    command_argv=("$@")
    if [[ ${#command_argv[@]} -gt 0 ]]; then
        case "${command_argv[0]}" in
            env)
                command_argv[0]="$env_bin"
                local env_command_index=1
                while [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; do
                    case "${command_argv[env_command_index]}" in
                        *=*) ((env_command_index += 1)) ;;
                        --) ((env_command_index += 1)); break ;;
                        -*) break ;;
                        *) break ;;
                    esac
                done
                if [[ "$env_command_index" -lt "${#command_argv[@]}" ]]; then
                    case "${command_argv[env_command_index]}" in
                        env) command_argv[env_command_index]="$env_bin" ;;
                        bash) command_argv[env_command_index]="$bash_bin" ;;
                        sh) command_argv[env_command_index]="$sh_bin" ;;
                    esac
                fi
                ;;
            bash) command_argv[0]="$bash_bin" ;;
            sh) command_argv[0]="$sh_bin" ;;
        esac
    fi

    # Already the target user
    current_user="$(gtbi_early_resolve_current_user 2>/dev/null || true)"
    if [[ "${current_user:-}" == "$user" ]]; then
        (
            if ! cd "$user_home"; then
                log_error "Unable to enter target home for '$user': $user_home"
                exit 1
            fi
            "$env_bin" "${env_args[@]}" "${command_argv[@]}"
        )
        return $?
    fi

    # IMPORTANT: Do NOT use sudo -i as it sources profile files (.profile, .bashrc)
    # which may be corrupted by third-party installers (e.g., uv adds lines that
    # reference non-existent files). Instead:
    # - Use noninteractive sudo to switch user without sourcing profiles
    # - Set HOME explicitly in the environment
    # - Use sh -c to cd to home directory before executing
    #
    # The sh -c wrapper: 'cd "$HOME" && exec "$@"' _ "$@"
    # - First $@ expands inside sh -c to become positional params
    # - _ is $0 (script name placeholder)
    # - exec "$@" replaces sh with the target command, preserving stdin
    sudo_bin="$(gtbi_early_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        "$sudo_bin" -n -u "$user" "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        return $?
    fi

    # Fallbacks (root-only typically)
    # Note: Avoid -l flag to prevent sourcing profiles
    runuser_bin="$(gtbi_early_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        # shellcheck disable=SC2016  # $HOME/$@ expand inside sh -c
        "$runuser_bin" -u "$user" -- "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "${command_argv[@]}"
        return $?
    fi

    su_bin="$(gtbi_early_system_binary_path su 2>/dev/null || true)"
    if [[ -z "$su_bin" ]]; then
        log_error "Unable to locate sudo, runuser, or su for target-user command"
        return 1
    fi

    # su without - to avoid sourcing login shell profiles
    local env_assignments=""
    local kv=""
    for kv in "${env_args[@]}"; do
        env_assignments+=" $(printf '%q' "$kv")"
    done
    env_assignments="${env_assignments# }"
    local user_home_q
    local env_bin_q
    user_home_q=$(printf '%q' "$user_home")
    env_bin_q=$(printf '%q' "$env_bin")
    "$su_bin" "$user" -c "cd $user_home_q || exit 1; $env_bin_q $env_assignments $(printf '%q ' "${command_argv[@]}")"
}

# ============================================================
# Upstream installer verification (checksums.yaml)
# ============================================================

declare -A GTBI_UPSTREAM_URLS=()
declare -A GTBI_UPSTREAM_SHA256=()
GTBI_UPSTREAM_LOADED=false

gtbi_calculate_sha256() {
    if command_exists sha256sum; then
        sha256sum | cut -d' ' -f1
        return 0
    fi

    if command_exists shasum; then
        shasum -a 256 | cut -d' ' -f1
        return 0
    fi

    log_error "No SHA256 tool available (need sha256sum or shasum)"
    return 1
}

gtbi_fetch_url_content() {
    local url="$1"

    if [[ "$url" != https://* ]]; then
        log_error "Security error: upstream URL is not HTTPS: $url"
        return 1
    fi

    local sentinel="__GTBI_EOF_SENTINEL__"
    local max_attempts="${#GTBI_CURL_RETRY_DELAYS[@]}"
    local retries=$((max_attempts - 1))

    local attempt delay
    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${GTBI_CURL_RETRY_DELAYS[$attempt]}"
        if (( attempt > 0 )); then
            log_info "Retry ${attempt}/${retries} for fetching upstream URL (waiting ${delay}s)..."
            sleep "$delay"
        fi

        local content status=0
        # IMPORTANT: keep this `curl` call set -e-safe so transient failures
        # don't abort the installer before our retry loop can run.
        content="$(
            gtbi_curl "$url" 2>/dev/null || exit $?
            printf '%s' "$sentinel"
        )" || status=$?

        if (( status == 0 )) && [[ "$content" == *"$sentinel" ]]; then
            (( attempt > 0 )) && log_info "Succeeded on retry ${attempt} for fetching upstream URL"
            printf '%s' "${content%"$sentinel"}"
            return 0
        fi

        if ! gtbi_is_retryable_curl_exit_code "$status"; then
            log_error "Failed to fetch upstream URL: $url"
            return 1
        fi
    done

    log_error "Failed to fetch upstream URL after ${max_attempts} attempts: $url"
    return 1
}

# Fetch checksums.yaml directly via GitHub API (bypasses CDN caching entirely).
# This is used as a fallback when cached checksums don't match upstream.
# Uses GTBI_CHECKSUMS_REF to avoid stale checksums when GTBI_REF is pinned.
# Uses the raw content header to get the file directly without base64 encoding.
gtbi_fetch_fresh_checksums_via_api() {
    local api_url="https://api.github.com/repos/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/contents/checksums.yaml?ref=${GTBI_CHECKSUMS_REF}"
    local curl_bin=""

    # Use application/vnd.github.raw to get raw file content directly (no base64)
    local content
    curl_bin="$(gtbi_early_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        log_detail "curl unavailable for GitHub API request"
        return 1
    fi
    content="$("$curl_bin" --connect-timeout 30 --max-time 300 -fsSL \
        -H "Accept: application/vnd.github.raw" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url" 2>/dev/null)" || {
        log_detail "GitHub API request failed for checksums.yaml"
        return 1
    }

    if [[ -z "$content" ]]; then
        log_detail "Empty content from GitHub API"
        return 1
    fi

    # Verify it looks like valid checksums.yaml (should start with a comment or "installers:")
    if [[ ! "$content" =~ ^[[:space:]]*(#|installers:) ]]; then
        log_detail "GitHub API returned unexpected content format"
        return 1
    fi

    printf '%s' "$content"
}

# Parse checksums.yaml content into associative arrays.
# Takes YAML content as argument, populates GTBI_UPSTREAM_URLS and GTBI_UPSTREAM_SHA256.
gtbi_parse_checksums_content() {
    local content="$1"
    local in_installers=false
    local installers_indent=0
    local current_tool=""
    local tool_indent=""
    local -A parsed_urls=()
    local -A parsed_sha256=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        local indent="${line%%[^ ]*}"
        local indent_len="${#indent}"

        if [[ "$in_installers" == "false" ]]; then
            if [[ "$line" =~ ^[[:space:]]*installers:[[:space:]]*$ ]]; then
                in_installers=true
                installers_indent="$indent_len"
                current_tool=""
                tool_indent=""
            fi
            continue
        fi

        if (( indent_len <= installers_indent )); then
            in_installers=false
            current_tool=""
            tool_indent=""
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([[:alnum:]_-]+):[[:space:]]*$ ]]; then
            if [[ -z "$tool_indent" ]]; then
                tool_indent="$indent_len"
            fi

            if (( indent_len == tool_indent )); then
                current_tool="${BASH_REMATCH[1]}"
                continue
            fi
        fi

        [[ -n "$current_tool" ]] || continue

        # Robust parsing: handle quoted or unquoted values, strip comments
        if [[ "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%%#*}"                    # Strip comments
            val="${val%"${val##*[![:space:]]}"}" # Trim trailing space
            val="${val#"${val%%[![:space:]]*}"}" # Trim leading space
            val="${val%\"}" val="${val#\"}"      # Strip double quotes
            val="${val%\'}" val="${val#\'}"      # Strip single quotes

            if [[ "$val" =~ ^https://[^[:space:]]+$ ]]; then
                parsed_urls["$current_tool"]="$val"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*sha256:[[:space:]]*(.*)$ ]]; then
            local val="${BASH_REMATCH[1]}"
            val="${val%%#*}"
            val="${val%"${val##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%\"}" val="${val#\"}"
            val="${val%\'}" val="${val#\'}"

            if [[ "$val" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                parsed_sha256["$current_tool"]="${val,,}"
            fi
            continue
        fi
    done <<< "$content"

    if [[ ${#parsed_sha256[@]} -eq 0 ]]; then
        return 1
    fi

    # Commit parsed data only after the new content has at least one usable
    # checksum, so a malformed refresh cannot erase a previously loaded table.
    GTBI_UPSTREAM_URLS=()
    GTBI_UPSTREAM_SHA256=()
    local tool
    for tool in "${!parsed_sha256[@]}"; do
        GTBI_UPSTREAM_SHA256["$tool"]="${parsed_sha256[$tool]}"
        if [[ -n "${parsed_urls[$tool]:-}" ]]; then
            GTBI_UPSTREAM_URLS["$tool"]="${parsed_urls[$tool]}"
        fi
    done

    return 0
}

gtbi_required_upstream_tools() {
    printf '%s\n' \
        atuin bun claude dolt gemini_patch nvm ohmyzsh opencode rust uv zoxide
}

gtbi_validate_upstream_checksums() {
    local missing_required_tools=false
    local tool

    while IFS= read -r tool; do
        if [[ -z "${GTBI_UPSTREAM_URLS[$tool]:-}" ]] || [[ -z "${GTBI_UPSTREAM_SHA256[$tool]:-}" ]]; then
            log_error "checksums.yaml missing entry for '$tool'"
            missing_required_tools=true
        fi
    done < <(gtbi_required_upstream_tools)

    [[ "$missing_required_tools" != "true" ]]
}

gtbi_load_upstream_checksums() {
    if [[ "$GTBI_UPSTREAM_LOADED" == "true" ]]; then
        return 0
    fi

    local content=""
    local checksums_file=""
    local checksums_source="unknown"
    local prefer_local_checksums=true

    # If checksums ref differs from the install ref, avoid using bootstrapped/local
    # checksums which may be stale for fast-moving upstream installers.
    if [[ -n "${GTBI_CHECKSUMS_REF:-}" && -n "${GTBI_REF_INPUT:-}" && "$GTBI_CHECKSUMS_REF" != "$GTBI_REF_INPUT" ]]; then
        prefer_local_checksums=false
        log_detail "Using checksums from ref '${GTBI_CHECKSUMS_REF}' (install ref: '${GTBI_REF_INPUT}')"
    fi

    if [[ "$prefer_local_checksums" == "true" && -n "${GTBI_CHECKSUMS_YAML:-}" ]] && [[ -r "$GTBI_CHECKSUMS_YAML" ]]; then
        checksums_file="$GTBI_CHECKSUMS_YAML"
        checksums_source="bootstrap"
    elif [[ "$prefer_local_checksums" == "true" && -n "${SCRIPT_DIR:-}" ]] && [[ -r "$SCRIPT_DIR/checksums.yaml" ]]; then
        checksums_file="$SCRIPT_DIR/checksums.yaml"
        checksums_source="local"
    elif [[ "$prefer_local_checksums" == "true" && -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -r "$GTBI_BOOTSTRAP_DIR/checksums.yaml" ]]; then
        checksums_file="$GTBI_BOOTSTRAP_DIR/checksums.yaml"
        checksums_source="bootstrap"
    fi

    if [[ -n "$checksums_file" ]]; then
        content="$(cat "$checksums_file")"
    else
        # Fetch via GitHub API (bypasses CDN caching entirely)
        content="$(gtbi_fetch_fresh_checksums_via_api)" || {
            # Fallback to raw.githubusercontent.com with cache-bust
            local cb
            cb="$(date +%s)"
            content="$(gtbi_fetch_url_content "$GTBI_CHECKSUMS_RAW/checksums.yaml?cb=${cb}")" || {
                log_error "Failed to fetch checksums.yaml from any source"
                return 1
            }
            checksums_source="raw-cdn"
        }
        # If we didn't fall back to raw-cdn, the API succeeded
        [[ "$checksums_source" == "unknown" ]] && checksums_source="github-api"
    fi

    if ! gtbi_parse_checksums_content "$content"; then
        log_error "checksums.yaml contains no valid installer checksums"
        return 1
    fi

    if ! gtbi_validate_upstream_checksums; then
        return 1
    fi

    GTBI_UPSTREAM_LOADED=true
    return 0
}

#
# Upstream installers are pinned by checksums.yaml.
# On checksum mismatch, we attempt a fresh fetch via GitHub API to handle CDN caching.
# If still mismatched after fresh fetch, we fail closed (never execute unverified scripts).

gtbi_run_verified_upstream_script_as_target_with_env() {
    if [[ $# -lt 2 ]]; then
        log_error "gtbi_run_verified_upstream_script_as_target_with_env requires a tool and runner"
        return 1
    fi

    local tool="$1"
    local runner="$2"
    local runner_env_assignment="${3:-}"
    if [[ $# -ge 3 ]]; then
        shift 3
    else
        set --
    fi

    gtbi_load_upstream_checksums || return $?

    local url="${GTBI_UPSTREAM_URLS[$tool]:-}"
    local expected_sha256="${GTBI_UPSTREAM_SHA256[$tool]:-}"
    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        log_error "No checksum recorded for upstream installer: $tool"
        return 1
    fi
    if [[ -n "$runner_env_assignment" ]] && [[ ! "$runner_env_assignment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+$ ]]; then
        log_error "Invalid inline env assignment for upstream installer '$tool': $runner_env_assignment"
        return 1
    fi

    # Preserve trailing newlines when capturing remote script content.
    # Bash command substitution trims trailing newlines, which would change the
    # checksum we compute vs the exact bytes we execute. Append an EOF sentinel
    # so the captured output never ends with a newline, then strip it.
    local sentinel="__GTBI_EOF_SENTINEL__"
    local content_with_sentinel
    content_with_sentinel="$(
        gtbi_fetch_url_content "$url" || exit $?
        printf '%s' "$sentinel"
    )" || return 1

    if [[ "$content_with_sentinel" != *"$sentinel" ]]; then
        log_error "Failed to fetch upstream URL: $url"
        return 1
    fi

    local content="${content_with_sentinel%"$sentinel"}"

    local actual_sha256
    actual_sha256="$(printf '%s' "$content" | gtbi_calculate_sha256)" || return 1

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        # Checksum mismatch - but this might be due to CDN caching of our checksums.yaml.
        # Try fetching FRESH checksums directly via GitHub API (bypasses all CDN caching).
        log_detail "Checksum mismatch for '$tool' - fetching fresh checksums via GitHub API..."

        local fresh_content
        fresh_content="$(gtbi_fetch_fresh_checksums_via_api)" || {
            log_detail "GitHub API fallback failed, cannot verify with fresh checksums"
            log_error "Security error: checksum mismatch for '$tool'"
            log_detail "URL: $url"
            log_detail "Expected: $expected_sha256"
            log_detail "Actual:   $actual_sha256"
            log_error "Refusing to execute unverified installer script."
            return 1
        }

        # Parse fresh checksums and get the updated installer contract.  An
        # installer URL can change during upstream migrations, so re-fetch
        # before comparing against the fresh hash when the contract moved.
        if ! gtbi_parse_checksums_content "$fresh_content"; then
            log_error "Fresh checksums.yaml contains no valid installer checksums"
            return 1
        fi
        local fresh_url="${GTBI_UPSTREAM_URLS[$tool]:-$url}"
        local fresh_expected_sha256="${GTBI_UPSTREAM_SHA256[$tool]:-}"

        if [[ -z "$fresh_url" ]]; then
            log_error "Fresh checksums.yaml missing URL for '$tool'"
            return 1
        fi
        if [[ -z "$fresh_expected_sha256" ]]; then
            log_error "Fresh checksums.yaml missing entry for '$tool'"
            return 1
        fi

        if [[ "$fresh_url" != "$url" ]]; then
            log_detail "Fresh checksums changed URL for '$tool'; refetching installer..."
            content_with_sentinel="$(
                gtbi_fetch_url_content "$fresh_url" || exit $?
                printf '%s' "$sentinel"
            )" || return 1

            if [[ "$content_with_sentinel" != *"$sentinel" ]]; then
                log_error "Failed to fetch upstream URL: $fresh_url"
                return 1
            fi

            url="$fresh_url"
            content="${content_with_sentinel%"$sentinel"}"
            actual_sha256="$(printf '%s' "$content" | gtbi_calculate_sha256)" || return 1
        fi
        expected_sha256="$fresh_expected_sha256"

        # Re-verify with fresh checksum
        if [[ "$actual_sha256" == "$expected_sha256" ]]; then
            log_success "Verified '$tool' with fresh checksums from GitHub API"
            # Note: GTBI_UPSTREAM_SHA256 already updated by gtbi_parse_checksums_content above
        else
            # Still doesn't match even with fresh checksums - this is a real problem
            log_error "Security error: checksum mismatch for '$tool' (verified with fresh checksums)"
            log_detail "URL: $url"
            log_detail "Expected (fresh): $expected_sha256"
            log_detail "Actual:           $actual_sha256"
            log_error "Refusing to execute unverified installer script."
            log_error "This could indicate:"
            log_error "  1. Upstream changed their installer very recently (wait and retry)"
            log_error "  2. Potential tampering (investigate before proceeding)"
            log_error "  3. Network issue corrupting downloads (retry on different network)"

            if [[ "${GTBI_STRICT_MODE:-false}" == "true" ]]; then
                log_fatal "Strict mode: aborting due to checksum mismatch for '$tool'"
            fi

            return 1
        fi
    fi

    if [[ -n "$runner_env_assignment" ]]; then
        printf '%s' "$content" | run_as_target env "$runner_env_assignment" "$runner" -s -- "$@"
    else
        printf '%s' "$content" | run_as_target "$runner" -s -- "$@"
    fi
}

gtbi_run_verified_upstream_script_as_target() {
    if [[ $# -lt 2 ]]; then
        log_error "gtbi_run_verified_upstream_script_as_target requires a tool and runner"
        return 1
    fi

    local tool="$1"
    local runner="$2"
    if [[ $# -ge 2 ]]; then
        shift 2
    else
        set --
    fi
    gtbi_run_verified_upstream_script_as_target_with_env "$tool" "$runner" "" "$@"
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]]; then
            SUDO="$sudo_bin"
        elif [[ "$DRY_RUN" == "true" ]]; then
            # Dry-run should be able to print actions even on systems without sudo.
            SUDO="sudo"
            log_warn "sudo not found (dry-run mode). No commands will be executed."
        else
            log_fatal "This script requires root privileges. Please run as root or install sudo."
        fi
    else
        SUDO=""
    fi
}

# Disable needrestart's apt hook to prevent installation hangs.
# On Ubuntu 22.04+, needrestart hooks into apt via /usr/lib/needrestart/apt-pinvoke
# and can wait for interactive input even with NEEDRESTART_SUSPEND=1, because sudo
# drops the environment variable. This function disables the hook proactively.
disable_needrestart_apt_hook() {
    local apt_hook="/usr/lib/needrestart/apt-pinvoke"
    local nr_conf_dir="/etc/needrestart/conf.d"
    local chmod_bin=""
    local mkdir_bin=""
    local tee_bin=""
    local -a sudo_cmd=()

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$apt_hook" ]]; then
            log_detail "dry-run: would disable needrestart apt hook at $apt_hook"
        fi
        return 0
    fi

    chmod_bin="$(gtbi_early_system_binary_path chmod 2>/dev/null || true)"
    mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
    tee_bin="$(gtbi_early_system_binary_path tee 2>/dev/null || true)"
    if [[ -z "$chmod_bin" || -z "$mkdir_bin" || -z "$tee_bin" ]]; then
        log_warn "Skipping needrestart apt hook hardening: required coreutils unavailable"
        return 0
    fi
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        [[ -n "$sudo_bin" ]] || return 0
        sudo_cmd=("$sudo_bin")
    fi

    # Method 1: Disable the apt hook executable (prevents it from running)
    if [[ -f "$apt_hook" && -x "$apt_hook" ]]; then
        log_detail "Disabling needrestart apt hook to prevent installation hangs"
        "${sudo_cmd[@]}" "$chmod_bin" -x "$apt_hook" 2>/dev/null || true
    fi

    # Method 2: Configure needrestart to auto-restart services without prompting
    if [[ -d "$nr_conf_dir" ]] || "${sudo_cmd[@]}" "$mkdir_bin" -p "$nr_conf_dir" 2>/dev/null; then
        echo '$nrconf{restart} = '\''a'\'';' | "${sudo_cmd[@]}" "$tee_bin" "$nr_conf_dir/50-gtbi-noninteractive.conf" >/dev/null 2>&1 || true
    fi
}

gtbi_chown_tree() {
    local owner_group="$1"
    local path="$2"

    if [[ -z "$owner_group" ]]; then
        log_error "gtbi_chown_tree: owner/group is required"
        return 1
    fi
    if [[ -z "$path" ]]; then
        log_error "gtbi_chown_tree: path is required"
        return 1
    fi
    if [[ "$path" == "/" ]]; then
        log_error "gtbi_chown_tree: refusing to chown '/'"
        return 1
    fi

    # SECURITY: Prevent recursive chown from dereferencing symlinks under the tree.
    # For top-level symlinks (e.g., symlinked /data), resolve to the real path so
    # ownership is applied to the intended directory.
    local resolved="$path"
    if [[ -L "$path" ]]; then
        if ! command_exists readlink; then
            log_error "gtbi_chown_tree: readlink is required to resolve symlink: $path"
            return 1
        fi
        resolved="$(readlink -f "$path" 2>/dev/null || true)"
        if [[ -z "$resolved" ]] || [[ "$resolved" == "/" ]]; then
            log_error "gtbi_chown_tree: refusing to chown unresolved/unsafe symlink: $path"
            return 1
        fi
    fi

    # Guardrail: prevent catastrophic recursive chown if a caller misconfigures
    # TARGET_HOME (or other paths) to a system directory.
    #
    # If you *really* need to chown one of these paths, you can override with:
    #   GTBI_ALLOW_UNSAFE_CHOWN=1
    if [[ "${GTBI_ALLOW_UNSAFE_CHOWN:-0}" != "1" ]]; then
        local unsafe_prefix=""
        for unsafe_prefix in /etc /usr /bin /sbin /lib /lib64 /boot /proc /sys /dev /run /var /opt; do
            if [[ "$resolved" == "$unsafe_prefix" || "$resolved" == "$unsafe_prefix/"* ]]; then
                log_error "gtbi_chown_tree: refusing to chown unsafe system path: $resolved"
                log_error "If you intended this (rare), re-run with GTBI_ALLOW_UNSAFE_CHOWN=1"
                return 1
            fi
        done
    fi

    # GNU coreutils: -h = do not dereference symlinks; -R = recursive.
    # Transient files (SSH control sockets, etc.) may vanish during the
    # recursive walk of a live home directory.  Only fail on non-transient errors.
    local _chown_err=""
    _chown_err=$($SUDO chown -hR "$owner_group" "$resolved" 2>&1) || {
        local _real_err
        _real_err=$(printf '%s\n' "$_chown_err" | grep -v "No such file or directory" || true)
        if [[ -n "$_real_err" ]]; then
            log_error "gtbi_chown_tree: chown failed for $resolved"
            return 1
        fi
        log_detail "gtbi_chown_tree: transient file warnings during chown (safe to ignore)"
    }
}

confirm_or_exit() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$YES_MODE" == "true" ]]; then
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]] && [[ -r /dev/tty ]]; then
        gum confirm "Proceed with GTBI install? (mode=$MODE)" < /dev/tty > /dev/tty || exit 1
        return 0
    fi

    local reply=""
    if [[ -t 0 ]]; then
        read -r -p "Proceed with GTBI install? (mode=$MODE) [y/N] " reply
    elif [[ -r /dev/tty ]]; then
        read -r -p "Proceed with GTBI install? (mode=$MODE) [y/N] " reply < /dev/tty
    else
        log_fatal "--yes is required when no TTY is available"
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) exit 1 ;;
    esac
}

# Resolve a user's home directory from NSS when possible.
gtbi_home_for_user() {
    local user="${1:-}"
    local expected_home="${2:-}"
    local passwd_entry=""
    local current_user=""
    local current_home=""
    local passwd_home=""

    [[ -n "$user" ]] || return 1
    if [[ -n "$expected_home" ]] && [[ "$expected_home" == /* ]] && [[ "$expected_home" != "/" ]]; then
        expected_home="${expected_home%/}"
    else
        expected_home=""
    fi

    if [[ "$user" == "root" ]]; then
        echo /root
        return 0
    fi

    passwd_entry="$(gtbi_early_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
        if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
            echo "${passwd_home%/}"
            return 0
        fi
    fi

    current_user="$(gtbi_early_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$user" ]] && [[ -n "${HOME:-}" ]] && [[ "${HOME}" == /* ]] && [[ "${HOME}" != "/" ]]; then
        current_home="${HOME%/}"
        if [[ -z "$expected_home" ]] || [[ "$current_home" == "$expected_home" ]]; then
            echo "$current_home"
            return 0
        fi
    fi

    return 1
}

gtbi_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# Set up target-specific paths
# Must be called after ensure_root
init_target_paths() {
    validate_target_user

    # Resolve the target user's actual home directory through NSS/getent first.
    # Inherited TARGET_HOME is a hint only; if it cannot be validated against
    # passwd/root/current-HOME, fail closed instead of operating in a stale home.
    local explicit_target_home_raw="${TARGET_HOME:-}"
    local current_user=""
    local explicit_target_home=""
    local resolved_target_home=""
    if [[ "$explicit_target_home_raw" == /* ]] && [[ "$explicit_target_home_raw" != "/" ]]; then
        explicit_target_home="${explicit_target_home_raw%/}"
        [[ "$explicit_target_home" != "/" ]] || explicit_target_home=""
    fi
    resolved_target_home="$(gtbi_home_for_user "$TARGET_USER" "$explicit_target_home" 2>/dev/null || true)"
    if [[ -n "$resolved_target_home" ]]; then
        TARGET_HOME="$resolved_target_home"
    elif [[ $EUID -eq 0 ]] && ! id "$TARGET_USER" &>/dev/null; then
        if [[ -n "$explicit_target_home" ]]; then
            TARGET_HOME="$explicit_target_home"
        else
            TARGET_HOME="$(gtbi_default_home_for_new_user "$TARGET_USER" 2>/dev/null || true)"
        fi
    elif [[ -n "$explicit_target_home" ]]; then
        current_user="$(gtbi_early_resolve_current_user 2>/dev/null || true)"
        if [[ -n "$current_user" && "$TARGET_USER" == "$current_user" ]]; then
            TARGET_HOME="$explicit_target_home"
        else
            TARGET_HOME=""
        fi
    else
        TARGET_HOME=""
    fi

    if [[ -z "$TARGET_HOME" ]]; then
        log_fatal "Unable to resolve TARGET_HOME for '$TARGET_USER'; export TARGET_HOME explicitly"
    fi

    if [[ -z "$TARGET_HOME" ]] || [[ "$TARGET_HOME" == "/" ]]; then
        log_fatal "Invalid TARGET_HOME: '${TARGET_HOME:-<empty>}'"
    fi
    if [[ "$TARGET_HOME" != /* ]]; then
        log_fatal "TARGET_HOME must be an absolute path (got: $TARGET_HOME)"
    fi

    # Configurable binary install directory (fixes #211).
    # Override via GTBI_BIN_DIR for shared/multi-user machines:
    #   GTBI_BIN_DIR=/usr/local/bin ./install.sh
    GTBI_BIN_DIR="${GTBI_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$GTBI_BIN_DIR" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                GTBI_BIN_DIR="$TARGET_HOME/.local/bin"
                ;;
        esac
    fi
    if [[ -z "$GTBI_BIN_DIR" ]] || [[ "$GTBI_BIN_DIR" == "/" ]] || [[ "$GTBI_BIN_DIR" != /* ]]; then
        log_fatal "GTBI_BIN_DIR must be an absolute path and cannot be '/' (got: ${GTBI_BIN_DIR:-<empty>})"
    fi

    # GTBI directories for target user
    GTBI_HOME="${GTBI_HOME:-$TARGET_HOME/.gtbi}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$GTBI_HOME" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                GTBI_HOME="$TARGET_HOME/.gtbi"
                ;;
        esac
    fi
    GTBI_STATE_FILE="${GTBI_STATE_FILE:-$GTBI_HOME/state.json}"
    if [[ -n "$explicit_target_home" ]] && [[ "$explicit_target_home" != "$TARGET_HOME" ]]; then
        case "$GTBI_STATE_FILE" in
            "$explicit_target_home"|"$explicit_target_home"/*)
                GTBI_STATE_FILE="$GTBI_HOME/state.json"
                ;;
        esac
    fi

    # Basic hardening: refuse to use a symlinked GTBI_HOME when running with
    # elevated privileges (prevents clobbering arbitrary paths via symlink tricks).
    if [[ -e "$GTBI_HOME" ]] && [[ -L "$GTBI_HOME" ]]; then
        log_fatal "Refusing to use GTBI_HOME because it is a symlink: $GTBI_HOME"
    fi

    log_detail "Target user: $TARGET_USER"
    log_detail "Target home: $TARGET_HOME"

    # Export for generated installers (run via subshells).
    export TARGET_USER TARGET_HOME GTBI_HOME GTBI_STATE_FILE GTBI_BIN_DIR

    # Add target user's bin directories to PATH early so that tools installed
    # later (like Claude Code) see the correct PATH and don't warn about it.
    export PATH="$GTBI_BIN_DIR:$TARGET_HOME/.local/bin:$TARGET_HOME/.gtbi/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.atuin/bin:$TARGET_HOME/go/bin:$PATH"
}

gtbi_primary_bin_dir_uses_root() {
    [[ -n "${GTBI_BIN_DIR:-}" ]] || return 1
    [[ -n "${TARGET_HOME:-}" ]] || return 1

    case "$GTBI_BIN_DIR" in
        "$TARGET_HOME"|"$TARGET_HOME"/*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

gtbi_ensure_primary_bin_dir() {
    if gtbi_primary_bin_dir_uses_root; then
        "$SUDO" mkdir -p "$GTBI_BIN_DIR"
        return $?
    fi

    run_as_target mkdir -p "$GTBI_BIN_DIR"
}

gtbi_link_primary_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local dest_path="$GTBI_BIN_DIR/$command_name"

    gtbi_ensure_primary_bin_dir || return 1

    if gtbi_primary_bin_dir_uses_root; then
        "$SUDO" ln -sf "$source_path" "$dest_path"
        return $?
    fi

    run_as_target ln -sf "$source_path" "$dest_path"
}

gtbi_link_global_bin_command() {
    local source_path="$1"
    local command_name="$2"
    local dest_path="/usr/local/bin/$command_name"

    if [[ -e "$dest_path" && ! -L "$dest_path" ]]; then
        log_error "Refusing to replace existing non-symlink global command: $dest_path"
        return 1
    fi

    if [[ -n "$SUDO" ]]; then
        "$SUDO" ln -sf "$source_path" "$dest_path"
        return $?
    fi

    ln -sf "$source_path" "$dest_path"
}

configure_gtbi_nightly_timer() {
    local output=""
    local status=0

    output="$(run_as_target bash -c '
set -euo pipefail

gtbi_home="${GTBI_HOME:-$HOME/.gtbi}"
service_src="$gtbi_home/scripts/templates/gtbi-nightly-update.service"
timer_src="$gtbi_home/scripts/templates/gtbi-nightly-update.timer"
wrapper="$gtbi_home/scripts/nightly-update.sh"

if ! command -v systemctl >/dev/null 2>&1; then
    printf "%s\n" "GTBI_NIGHTLY_SYSTEMD_UNAVAILABLE: systemctl not found"
    exit 0
fi

if ! systemctl --user show-environment >/dev/null 2>&1; then
    printf "%s\n" "GTBI_NIGHTLY_SYSTEMD_UNAVAILABLE: user systemd manager unavailable"
    exit 0
fi

for required_path in "$service_src" "$timer_src" "$wrapper"; do
    if [[ ! -e "$required_path" ]]; then
        printf "missing required nightly asset: %s\n" "$required_path" >&2
        exit 1
    fi
done

mkdir -p "$HOME/.config/systemd/user"
cp "$service_src" "$HOME/.config/systemd/user/gtbi-nightly-update.service"
cp "$timer_src" "$HOME/.config/systemd/user/gtbi-nightly-update.timer"
chmod 755 "$wrapper"
systemctl --user daemon-reload
systemctl --user enable --now gtbi-nightly-update.timer
systemctl --user is-enabled gtbi-nightly-update.timer >/dev/null
' 2>&1)" || status=$?

    if [[ "$status" -ne 0 ]]; then
        log_error "Failed to enable GTBI nightly update timer"
        if [[ -n "$output" ]]; then
            log_detail "$output"
        fi
        return "$status"
    fi

    if [[ "$output" == *"GTBI_NIGHTLY_SYSTEMD_UNAVAILABLE"* ]]; then
        log_warn "Skipping GTBI nightly update timer because user systemd is unavailable"
        if [[ -n "$output" ]]; then
            log_detail "$output"
        fi
        return 0
    fi

    log_detail "GTBI nightly update timer enabled"
}

gtbi_install_executable_into_primary_bin() {
    local src_path="$1"
    local command_name="$2"
    local dest_path="$GTBI_BIN_DIR/$command_name"

    gtbi_ensure_primary_bin_dir || return 1

    if gtbi_primary_bin_dir_uses_root; then
        "$SUDO" install -m 0755 "$src_path" "$dest_path"
        return $?
    fi

    if [[ $EUID -eq 0 ]]; then
        "$SUDO" install -m 0755 "$src_path" "$dest_path" || return 1
        "$SUDO" chown "$TARGET_USER:$TARGET_USER" "$dest_path"
        return $?
    fi

    run_as_target install -m 0755 "$src_path" "$dest_path"
}

validate_target_user() {
    if [[ -z "${TARGET_USER:-}" ]]; then
        log_fatal "TARGET_USER is empty"
    fi

    # Hard-stop on unsafe usernames (prevents injection into sudoers/paths).
    if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_fatal "Invalid TARGET_USER '$TARGET_USER' (expected: lowercase user name like 'ubuntu')"
    fi
}

ensure_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_fatal "Cannot detect OS. GTBI supports Ubuntu 22.04+ only."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_fatal "Unsupported OS: ${PRETTY_NAME:-${ID:-unknown}}. GTBI supports Ubuntu 22.04+ only."
    fi

    local version_id="${VERSION_ID:-}"
    if [[ -z "$version_id" ]]; then
        log_fatal "Cannot detect Ubuntu version (VERSION_ID missing)"
    fi

    local VERSION_MAJOR="${version_id%%.*}"
    if [[ "$VERSION_MAJOR" -lt 22 ]]; then
        log_fatal "Unsupported Ubuntu version: ${version_id}. GTBI supports Ubuntu 22.04+ only."
    fi

    if [[ "$VERSION_MAJOR" -lt 24 ]]; then
        log_warn "Ubuntu $version_id detected. Recommended: Ubuntu 24.04+ or 25.x"
    fi

    log_detail "OS: Ubuntu $version_id"
}

# ============================================================
# Ubuntu Auto-Upgrade Phase (nb4)
# Runs as "Phase -1" before all other installation phases.
# Handles multi-reboot upgrade sequences (e.g., 24.04 → 25.04 → 25.10; EOL releases like 24.10 may be skipped)
# ============================================================
run_ubuntu_upgrade_phase() {
    # Skip if user requested
    if [[ "$SKIP_UBUNTU_UPGRADE" == "true" ]]; then
        log_detail "Skipping Ubuntu upgrade (--skip-ubuntu-upgrade)"
        return 0
    fi

    # Only upgrade actual Ubuntu systems
    if [[ ! -f /etc/os-release ]]; then
        log_detail "Not an Ubuntu system, skipping upgrade"
        return 0
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_detail "Not Ubuntu (detected: $ID), skipping upgrade"
        return 0
    fi

    # If the user did NOT explicitly pass --target-ubuntu, check whether this
    # is a fully-patched LTS release.  LTS users (e.g., 24.04) should not be
    # forced to upgrade to a non-LTS target just because the default
    # TARGET_UBUNTU_VERSION is ahead of them.
    if [[ "$TARGET_UBUNTU_VERSION_EXPLICIT" != "true" ]]; then
        local _current_ver="${VERSION_ID:-}"
        # Ubuntu LTS releases have .04 minor versions (e.g., 22.04, 24.04)
        if [[ "$_current_ver" == *.04 ]]; then
            # Check whether all packages are up to date (0 upgradable)
            local _upgradable=0
            if command -v apt-get &>/dev/null; then
                # apt-get update may need root; try non-destructively first
                _upgradable=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
            fi
            if [[ "$_upgradable" -eq 0 ]]; then
                log_detail "Ubuntu $_current_ver LTS is fully patched (0 packages upgradable); skipping auto-upgrade"
                log_detail "  (pass --target-ubuntu=<VER> to force an upgrade)"
                return 0
            fi
        fi
    fi

    # CRITICAL: Ensure jq is installed for state tracking (state.sh depends on it).
    if ! gtbi_early_system_binary_path jq &>/dev/null; then
        log_detail "Installing jq for upgrade state tracking..."
        local apt_get_bin=""
        apt_get_bin="$(gtbi_early_system_binary_path apt-get 2>/dev/null || true)"
        if [[ -z "$apt_get_bin" ]]; then
            log_warn "apt-get not found; cannot install jq for upgrade state tracking"
        elif [[ $EUID -eq 0 ]]; then
            "$apt_get_bin" update -qq && "$apt_get_bin" install -y jq >/dev/null 2>&1 || true
        else
            local sudo_bin=""
            sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                "$sudo_bin" -n "$apt_get_bin" update -qq && "$sudo_bin" -n "$apt_get_bin" install -y jq >/dev/null 2>&1 || true
            fi
        fi
    fi

    # Source upgrade library
    if ! _source_ubuntu_upgrade_lib; then
        log_warn "Could not load ubuntu_upgrade.sh library"
        log_warn "Skipping Ubuntu auto-upgrade"
        return 0
    fi

    # Get current version (as number for comparison, as string for display)
    local current_version_num current_version_str
    current_version_str=$(ubuntu_get_version_string)
    current_version_num=$(ubuntu_get_version_number)
    log_detail "Current Ubuntu version: $current_version_str"

    # Upgrade tracking state must survive reboots and cannot depend on the
    # target user's home existing yet (user normalization runs later).
    # Use a root-owned, persistent state file under the resume directory.
    local upgrade_state_file="${GTBI_RESUME_DIR:-/var/lib/gtbi}/state.json"
    local had_state_file=false
    local previous_state_file="${GTBI_STATE_FILE:-}"
    if [[ "${GTBI_STATE_FILE+x}" == "x" ]]; then
        had_state_file=true
    fi
    export GTBI_STATE_FILE="$upgrade_state_file"

    # Convert target version string to number for comparison
    # TARGET_UBUNTU_VERSION is "25.10", need 2510
    local target_version_num
    local target_major target_minor
    target_major="${TARGET_UBUNTU_VERSION%%.*}"
    target_minor="${TARGET_UBUNTU_VERSION#*.}"
    target_version_num=$(printf "%d%02d" "$((10#$target_major))" "$((10#$target_minor))")

    # Ensure ubuntu_upgrade.sh uses the requested target (not just its defaults).
    export UBUNTU_TARGET_VERSION="$TARGET_UBUNTU_VERSION"
    export UBUNTU_TARGET_VERSION_NUM="$target_version_num"

    # Check if we're resuming an upgrade after reboot
    local upgrade_stage
    upgrade_stage=$(state_upgrade_get_stage 2>/dev/null || echo "not_started")

    case "$upgrade_stage" in
        initializing|upgrading|awaiting_reboot|resumed|step_complete)
            log_error "Detected Ubuntu upgrade in progress (stage: $upgrade_stage)"
            log_error "Refusing to continue normal installation during an active upgrade."
            log_info "Monitoring:"
            log_info "  - /var/lib/gtbi/check_status.sh"
            log_info "  - journalctl -u gtbi-upgrade-resume -f"
            log_info "  - tail -f /var/log/gtbi/upgrade_resume.log"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
            ;;
        pre_upgrade_reboot)
            # We just rebooted to clear pending package updates
            log_success "Pre-upgrade reboot complete. Continuing with upgrade..."
            # Clear the stage so we proceed normally
            if type -t state_update &>/dev/null; then
                if ! state_update ".ubuntu_upgrade.current_stage = \"not_started\" | .ubuntu_upgrade.enabled = false"; then
                    log_error "Failed to clear pre_upgrade_reboot stage; aborting to prevent stale state."
                    restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                    return 1
                fi
            else
                log_error "State tracking is unavailable; cannot continue upgrade safely."
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi
            # Set flag to skip redundant warning (user already confirmed before reboot)
            local skip_upgrade_warning=true
            # Fall through to continue with upgrade
            ;;
        error)
            log_error "Previous Ubuntu upgrade attempt failed (stage: error)"
            log_error "Check logs:"
            log_info "  journalctl -u gtbi-upgrade-resume"
            log_info "  tail -100 /var/log/gtbi/upgrade_resume.log"
            log_error "To reset and retry upgrade:"
            log_info "  sudo mv -- '${upgrade_state_file}' '${upgrade_state_file}.backup.\$(date +%Y%m%d_%H%M%S)'"
            log_error "To proceed without upgrading:"
            log_info "  Re-run with --skip-ubuntu-upgrade (not recommended)"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
            ;;
    esac

    # Check if upgrade is needed (using numeric comparison)
    if ubuntu_version_gte "$current_version_num" "$target_version_num"; then
        log_detail "Ubuntu $current_version_str meets target ($TARGET_UBUNTU_VERSION)"
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 0
    fi

    # Ubuntu distribution upgrades require root (do-release-upgrade, systemd units,
    # /var/lib/gtbi state). If the installer is being run as a sudo-capable user,
    # abort with clear guidance rather than failing mid-upgrade.
    if [[ $EUID -ne 0 ]]; then
        log_error "Ubuntu auto-upgrade requires running the installer as root"
        log_info "Re-run as root (e.g., run 'sudo -i' then run the install command again), or use --skip-ubuntu-upgrade."
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 1
    fi

    # Calculate upgrade path (function takes target version NUMBER, determines current internally)
    # Returns newline-separated list of version strings to upgrade through
    local upgrade_path
    upgrade_path=$(ubuntu_calculate_upgrade_path "$target_version_num")

    if [[ -z "$upgrade_path" ]]; then
        log_detail "No upgrade path found from $current_version_str to $TARGET_UBUNTU_VERSION"
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 0
    fi

    log_step "-1/9" "Ubuntu Auto-Upgrade"
    # Format path for display (e.g., "25.04 → 25.10")
    local upgrade_path_display
    upgrade_path_display=$(echo "$upgrade_path" | tr '\n' ' ' | sed 's/ $//; s/ / → /g')
    log_info "Upgrade path: $current_version_str → $upgrade_path_display"

    # Show warning and get confirmation (unless --yes mode or resuming from pre-reboot)
    if [[ "${skip_upgrade_warning:-}" != "true" ]]; then
        if type -t ubuntu_show_upgrade_warning &>/dev/null; then
            ubuntu_show_upgrade_warning
        fi

        if [[ "$YES_MODE" != "true" ]]; then
            log_warn "Ubuntu upgrade will take 30-60 minutes per version and require reboots."
            log_warn "Your SSH session will disconnect. Reconnect after each reboot."
            echo ""

            if [[ -t 0 ]]; then
                read -r -p "Proceed with Ubuntu upgrade? [y/N] " response
            elif [[ -r /dev/tty ]]; then
                echo -n "Proceed with Ubuntu upgrade? [y/N] " >&2
                read -r response < /dev/tty
            else
                log_fatal "--yes is required when no TTY is available"
            fi

            if [[ ! "$response" =~ ^[Yy] ]]; then
                log_info "Ubuntu upgrade skipped by user"
                log_info "Continuing with GTBI installation on Ubuntu $current_version_str"
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 0
            fi
        fi
    fi

    local upgrade_lock_acquired=false
    if ! type -t upgrade_acquire_lock &>/dev/null; then
        log_error "Ubuntu upgrade lock is unavailable; refusing to continue upgrade."
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 1
    fi
    if ! upgrade_acquire_lock; then
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 1
    fi
    upgrade_lock_acquired=true

    # Check if system requires reboot before upgrade (package updates pending)
    # This must be handled before preflight checks, otherwise do-release-upgrade fails
    if [[ -f /var/run/reboot-required ]]; then
        log_warn "System requires reboot before upgrade can proceed"
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            log_detail "Packages requiring reboot: $(tr '\n' ' ' < /var/run/reboot-required.pkgs | sed 's/ $//')"
        fi

        if [[ "$YES_MODE" == "true" ]]; then
            log_info "Automatically rebooting to clear pending updates..."

            # Initialize state file early for tracking
            # Try without sudo first, fall back to sudo for system directories
            local mkdir_bin=""
            mkdir_bin="$(gtbi_early_system_binary_path mkdir 2>/dev/null || true)"
            if [[ -n "$mkdir_bin" ]] && ! "$mkdir_bin" -p "${GTBI_RESUME_DIR:-/var/lib/gtbi}" 2>/dev/null; then
                local sudo_bin=""
                local chown_bin=""
                local id_bin=""
                sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
                chown_bin="$(gtbi_early_system_binary_path chown 2>/dev/null || true)"
                id_bin="$(gtbi_early_system_binary_path id 2>/dev/null || true)"
                if [[ $EUID -ne 0 && -n "$sudo_bin" ]]; then
                    "$sudo_bin" -n "$mkdir_bin" -p "${GTBI_RESUME_DIR:-/var/lib/gtbi}"
                    if [[ -n "$chown_bin" && -n "$id_bin" ]]; then
                        "$sudo_bin" -n "$chown_bin" "$("$id_bin" -u):$("$id_bin" -g)" "${GTBI_RESUME_DIR:-/var/lib/gtbi}" 2>/dev/null || true
                    fi
                fi
            fi
            if type -t state_ensure_valid &>/dev/null; then
                state_ensure_valid || true
            fi
            if type -t state_init &>/dev/null; then
                state_load >/dev/null 2>&1 || state_init || true
            fi

            # Set stage so we know to continue after reboot
            if type -t state_update_with_args &>/dev/null; then
                if ! state_update_with_args '
                    .ubuntu_upgrade.enabled = true |
                    .ubuntu_upgrade.current_stage = "pre_upgrade_reboot" |
                    .ubuntu_upgrade.original_version = $current_version |
                    .ubuntu_upgrade.target_version = $target_version
                ' --arg current_version "$current_version_str" --arg target_version "$TARGET_UBUNTU_VERSION"; then
                    log_error "Failed to record upgrade stage; cannot safely auto-reboot."
                    log_info "Please reboot manually and re-run the installer."
                    release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
                    restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                    return 1
                fi
            else
                log_error "State tracking is unavailable; cannot safely auto-reboot."
                log_info "Please reboot manually and re-run the installer."
                release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi

            # Set up resume infrastructure
            local gtbi_source_dir=""
            if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
                gtbi_source_dir="$SCRIPT_DIR"
            elif [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -d "$GTBI_BOOTSTRAP_DIR" ]]; then
                gtbi_source_dir="$GTBI_BOOTSTRAP_DIR"
            fi

            if [[ -z "$gtbi_source_dir" ]] || ! type -t upgrade_setup_infrastructure &>/dev/null; then
                log_error "Resume infrastructure is unavailable. Cannot safely auto-reboot."
                log_info "Please reboot manually and re-run the installer."
                release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi
            if ! upgrade_setup_infrastructure "$gtbi_source_dir" "$@"; then
                log_error "Failed to set up resume infrastructure. Cannot safely reboot."
                log_info "Please reboot manually and re-run the installer."
                release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi

            # Update MOTD before reboot
            upgrade_update_motd "Rebooting for upgrade to ${UBUNTU_TARGET_VERSION:-Ubuntu}..."

            # Trigger reboot
            log_warn "Rebooting in 10 seconds..."
            echo ""
            log_info "After reconnecting via SSH, the upgrade continues automatically in the background."
            log_info "To monitor progress:"
            log_info "  journalctl -u gtbi-upgrade-resume -f"
            log_info "  tail -f /var/log/gtbi/upgrade_resume.log"
            echo ""
            sleep 10
            shutdown -r now "GTBI: Rebooting to apply pending updates before Ubuntu upgrade"
            exit 0
        else
            log_error "Manual action required: reboot the system first"
            log_info "Run: sudo reboot"
            log_info "Then re-run the GTBI installer"
            release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi

    # Run preflight checks
    if type -t ubuntu_preflight_checks &>/dev/null; then
        if ! ubuntu_preflight_checks; then
            log_error "Preflight checks failed. Cannot proceed with upgrade."
            log_info "Use --skip-ubuntu-upgrade to bypass (not recommended)"
            release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi

    # Ensure a state file exists so upgrade tracking can persist progress.
    # (The main install resume prompt/state init happens later, but upgrades
    # need state_update/state_upgrade_* to be able to write immediately.)
    if type -t state_ensure_valid &>/dev/null; then
        if ! state_ensure_valid; then
            log_error "State validation failed. Aborting Ubuntu upgrade."
            release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi
    fi
    if type -t state_load &>/dev/null && type -t state_init &>/dev/null; then
        if ! state_load >/dev/null 2>&1; then
            log_detail "Initializing state file for Ubuntu upgrade tracking..."
            if ! state_init; then
                log_error "Failed to initialize state file. Aborting Ubuntu upgrade."
                release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
                restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
                return 1
            fi
        fi
    fi

    # Start the upgrade sequence
    # This will trigger reboots and the resume service will continue
    log_info "Starting Ubuntu upgrade sequence..."

    if type -t ubuntu_start_upgrade_sequence &>/dev/null; then
        # Provide a source directory so we can copy upgrade-resume assets.
        # Local checkout: SCRIPT_DIR is set.
        # curl|bash: bootstrap_repo_archive prepared GTBI_BOOTSTRAP_DIR.
        local gtbi_source_dir=""
        if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
            gtbi_source_dir="$SCRIPT_DIR"
        elif [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -d "$GTBI_BOOTSTRAP_DIR" ]]; then
            gtbi_source_dir="$GTBI_BOOTSTRAP_DIR"
        else
            gtbi_source_dir="."
        fi

        if ! ubuntu_start_upgrade_sequence "$gtbi_source_dir" "$@"; then
            log_error "Ubuntu upgrade failed to start"
            release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
            restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
            return 1
        fi

        # If we get here, the script is about to exit for reboot
        # The resume service will take over after reboot
        log_info "Upgrade initiated. System will reboot shortly."
        log_info "Reconnect via SSH after reboot - upgrade will continue automatically."
        exit 0
    else
        log_warn "ubuntu_start_upgrade_sequence not available"
        log_warn "Continuing with GTBI installation on current Ubuntu version"
        release_ubuntu_upgrade_lock_if_acquired "$upgrade_lock_acquired"
        restore_previous_gtbi_state_file "$had_state_file" "$previous_state_file"
        return 0
    fi
}

release_ubuntu_upgrade_lock_if_acquired() {
    local upgrade_lock_acquired="${1:-false}"
    if [[ "$upgrade_lock_acquired" == "true" ]] && type -t upgrade_release_lock &>/dev/null; then
        upgrade_release_lock
    fi
}

restore_previous_gtbi_state_file() {
    local had_state_file=${1:-false}
    local previous_state_file=${2-}

    if [[ "$had_state_file" == "true" ]]; then
        export GTBI_STATE_FILE="$previous_state_file"
    else
        unset GTBI_STATE_FILE
    fi
}

ensure_base_deps() {
    set_phase "base_deps" "Base Dependencies" 1
    log_step "0/8" "Checking base dependencies..."
    local apt_get_bin=""
    local -a sudo_cmd=()

    if gtbi_use_generated_category "base"; then
        log_detail "Using generated installers for base (phase 1)"
        gtbi_run_generated_category_phase "base" "1" || return 1
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        local sudo_prefix=""
        if [[ -n "${SUDO:-}" ]]; then
            sudo_prefix="$SUDO "
        fi

        log_detail "dry-run: would run: ${sudo_prefix}apt-get update -y"
        log_detail "dry-run: would install: curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg libssl-dev pkg-config"
        return 0
    fi

    apt_get_bin="$(gtbi_early_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        log_error "apt-get not found; cannot install base dependencies"
        return 1
    fi
    if [[ $EUID -ne 0 ]]; then
        local sudo_bin=""
        sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
        if [[ -z "$sudo_bin" ]]; then
            log_error "sudo not found; cannot install base dependencies"
            return 1
        fi
        sudo_cmd=("$sudo_bin")
    fi

    log_detail "Updating apt package index"
    try_step "Updating apt package index" "${sudo_cmd[@]}" "$apt_get_bin" update -y || return 1

    log_detail "Installing base packages"
    try_step "Installing base packages" "${sudo_cmd[@]}" "$apt_get_bin" install -yq curl git ca-certificates unzip tar xz-utils jq build-essential sudo gnupg libssl-dev pkg-config zstd || return 1
}

# ============================================================
# Phase 1: User normalization
# ============================================================
gtbi_generate_random_password() {
    local password=""
    local digest=""

    if command_exists openssl; then
        password="$(openssl rand -base64 32 2>/dev/null || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    if command_exists python3; then
        password="$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    if [[ -r /dev/urandom ]] && command_exists tr && command_exists head; then
        # Under pipefail, tr exits with SIGPIPE after head reads enough bytes.
        # The output is still valid, so force the pipeline status back to zero.
        password="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    if command_exists sha256sum; then
        digest="$(date +%s%N | sha256sum 2>/dev/null || true)"
        digest="${digest%% *}"
        if [[ -n "$digest" ]]; then
            printf '%s\n' "${digest:0:32}"
            return 0
        fi
    fi

    return 1
}

normalize_user() {
    set_phase "user_setup" "User Normalization"
    log_step "1/8" "Normalizing user account..."

    if [[ $EUID -eq 0 ]] && type -t prompt_ssh_key &>/dev/null; then
        if ! prompt_ssh_key; then
            log_warn "SSH key prompt failed or was skipped; continuing"
        fi
    fi

    if gtbi_use_generated_category "users"; then
        log_detail "Using generated installers for users (phase 2)"
        gtbi_run_generated_category_phase "users" "2" || return 1
        log_success "User normalization complete"
        return 0
    fi
    # Legacy path: users category is orchestration-only; call ensure_user directly.
    if type -t ensure_user >/dev/null 2>&1; then
        ensure_user || return 1
        local mode="${MODE:-${GTBI_MODE:-vibe}}"
        if [[ "$mode" == "vibe" ]] && type -t enable_passwordless_sudo >/dev/null 2>&1; then
            enable_passwordless_sudo || true
        fi
        if type -t migrate_ssh_keys >/dev/null 2>&1; then
            migrate_ssh_keys || true
        fi
        log_success "User normalization complete"
        return 0
    fi
    log_warn "User normalization skipped (ensure_user not available)"
    return 0
}

# ============================================================
# Phase 2: Filesystem setup
# ============================================================
setup_filesystem() {
    set_phase "filesystem" "Filesystem Setup"
    log_step "2/8" "Setting up filesystem..."

    if gtbi_use_generated_category "filesystem"; then
        log_detail "Using generated installers for filesystem (phase 3)"
        gtbi_run_generated_category_phase "filesystem" "3" || return 1
        log_success "Filesystem setup complete"
        return 0
    fi
    log_warn "Generated filesystem installers not found; skipping"
    return 0
}

# ============================================================
# Phase 3: Shell setup (zsh + oh-my-zsh + p10k)
# ============================================================
gtbi_get_local_passwd_entry() {
    local user="${1:-}"
    local passwd_line=""
    local passwd_user=""

    [[ -n "$user" ]] || return 1
    [[ -r /etc/passwd ]] || return 1

    while IFS= read -r passwd_line; do
        IFS=: read -r passwd_user _ <<< "$passwd_line"
        if [[ "$passwd_user" == "$user" ]]; then
            echo "$passwd_line"
            return 0
        fi
    done < /etc/passwd

    return 1
}
gtbi_is_externally_managed_user() {
    local user="${1:-}"
    local passwd_entry=""
    local local_entry=""

    [[ -n "$user" ]] || return 1
    passwd_entry="$(gtbi_early_getent_passwd_entry "$user" 2>/dev/null || true)"
    [[ -n "$passwd_entry" ]] || return 1

    local_entry="$(gtbi_get_local_passwd_entry "$user" || true)"
    [[ -z "$local_entry" ]]
}

gtbi_external_shell_handoff_configured() {
    local target_home="${1:-}"
    local bashrc_path=""

    [[ -n "$target_home" ]] || return 1
    bashrc_path="$target_home/.bashrc"
    [[ -f "$bashrc_path" ]] || return 1

    awk '
        $0 == "# GTBI externally-managed shell handoff" { marker=1; next }
        marker && $0 ~ /^[[:space:]]*#/ { next }
        marker && index($0, "command -v zsh") && index($0, "GTBI_ZSH_HANDOFF_ACTIVE") { found=1; exit }
        marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
        END { exit(found ? 0 : 1) }
    ' "$bashrc_path" 2>/dev/null
}

gtbi_append_external_shell_handoff() {
    local bashrc_path="${1:-}"
    [[ -n "$bashrc_path" ]] || return 1

    if [[ -f "$bashrc_path" ]] && [[ -s "$bashrc_path" ]]; then
        local last_char=""
        last_char=$(tail -c 1 "$bashrc_path" | od -An -t u1 | tr -d ' ' 2>/dev/null || true)
        if [[ "$last_char" != "10" ]]; then
            printf '\n' >> "$bashrc_path"
        fi
    fi

    cat >> "$bashrc_path" << 'EOF'
# GTBI externally-managed shell handoff
if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${GTBI_ZSH_HANDOFF_ACTIVE:-}" ]]; then
    export GTBI_ZSH_HANDOFF_ACTIVE=1
    exec "$(command -v zsh)" -l
fi
EOF
}

gtbi_configure_external_shell_handoff() {
    local target_home="${1:-}"
    local target_user="${2:-}"

    [[ -n "$target_home" ]] || return 1
    [[ -n "$target_user" ]] || return 1

    if gtbi_external_shell_handoff_configured "$target_home"; then
        return 0
    fi

    gtbi_append_external_shell_handoff "$target_home/.bashrc" || return 1

    $SUDO chown "$target_user:$target_user" "$target_home/.bashrc" 2>/dev/null || true
    return 0
}

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

profile_path_sed_literal() {
    # This is used in sed's default BRE mode with | as the delimiter.
    # Do not escape literal parentheses: \(...\) is a BRE capture group.
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

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

setup_shell() {
    set_phase "shell_setup" "Shell Setup"
    log_step "3/8" "Setting up shell..."

    if gtbi_use_generated_category "shell"; then
        log_detail "Using generated installers for shell (phase 4)"
        gtbi_run_generated_category_phase "shell" "4" || return 1
        log_success "Shell setup complete"
        return 0
    fi
    log_warn "Generated shell installers not found; skipping"
    return 0
}

# ============================================================
# Phase 4: CLI tools

install_cli_tools() {
    set_phase "cli_tools" "CLI Tools"
    log_step "4/8" "Installing CLI tools..."

    local used_generated_cli=false
    local used_generated_network=false

    if gtbi_use_generated_category "cli"; then
        log_detail "Using generated installers for cli (phase 5)"
        gtbi_run_generated_category_phase "cli" "5" || return 1
        used_generated_cli=true
    fi

    if gtbi_use_generated_category "network"; then
        log_detail "Using generated installers for network (phase 5)"
        gtbi_run_generated_category_phase "network" "5" || return 1
        used_generated_network=true
    fi

    # tools phase 5: lazygit, lazydocker — bug #146 audit follow-up
    if gtbi_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 5)"
        gtbi_run_generated_category_phase "tools" "5" || return 1
    fi

    log_success "CLI tools installed"
    return 0
}

# ============================================================
# Phase 5: Language runtimes

install_languages() {
    set_phase "languages" "Language Runtimes"
    log_step "5/8" "Installing language runtimes..."

    if gtbi_use_generated_category "lang"; then
        log_detail "Using generated installers for lang (phase 6)"
        gtbi_run_generated_category_phase "lang" "6" || return 1
    fi

    if gtbi_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 6)"
        gtbi_run_generated_category_phase "tools" "6" || return 1
    fi

    log_success "Language runtimes installed"
    return 0
}

# ============================================================
# Phase 6: Coding agents
# ============================================================
install_agents_phase() {
    set_phase "agents" "Coding Agents"
    log_step "6/8" "Installing coding agents..."

    if gtbi_use_generated_category "agents"; then
        log_detail "Using generated installers for agents (phase 7)"
        gtbi_run_generated_category_phase "agents" "7" || return 1

        # CI/doctor expectations: ensure `claude` resolves to ~/.local/bin/claude.
        # The native installer can choose non-standard paths, and bun installs land in ~/.bun/bin.
        local claude_bin_local="$GTBI_BIN_DIR/claude"
        if [[ ! -x "$claude_bin_local" ]]; then
            gtbi_ensure_primary_bin_dir 2>/dev/null || true

            local claude_candidate=""
            local candidates=(
                "$TARGET_HOME/.claude/bin/claude"
                "$TARGET_HOME/.claude/local/bin/claude"
                "$TARGET_HOME/.bun/bin/claude"
            )
            for claude_candidate in "${candidates[@]}"; do
                if [[ -x "$claude_candidate" ]]; then
                    break
                fi
                claude_candidate=""
            done

            if [[ -z "$claude_candidate" ]] && [[ -d "$TARGET_HOME/.claude" ]]; then
                claude_candidate="$(run_as_target find "$TARGET_HOME/.claude" -maxdepth 4 -type f -name claude -perm -111 -print -quit 2>/dev/null || true)"
            fi

            if [[ -n "$claude_candidate" ]] && [[ -x "$claude_candidate" ]]; then
                try_step "Linking Claude Code into $GTBI_BIN_DIR" gtbi_link_primary_bin_command "$claude_candidate" "claude" || true
            fi
        fi

        log_success "Coding agents installed"
        return 0
    fi
    log_warn "Generated agent installers not found; skipping"
    return 0
}

# ============================================================
# Phase 8: Gastown stack
# ============================================================

# Resolve binaries only from target-owned or stable system locations.
# Do not trust arbitrary inherited PATH entries here: they can point at tools from
# the caller's shell instead of the target installation we are managing.
binary_path() {
    local name="${1:-}"
    local primary_bin=""
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    primary_bin="${GTBI_BIN_DIR:-$TARGET_HOME/.local/bin}"

    for candidate in \
        "$primary_bin/$name" \
        "$TARGET_HOME/.local/bin/$name" \
        "$TARGET_HOME/.gtbi/bin/$name" \
        "$TARGET_HOME/.cargo/bin/$name" \
        "$TARGET_HOME/.bun/bin/$name" \
        "$TARGET_HOME/.atuin/bin/$name" \
        "$TARGET_HOME/go/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/snap/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

binary_installed() {
    local path=""
    path="$(binary_path "$1" 2>/dev/null || true)"
    [[ -n "$path" ]]
}

install_stack_phase() {
    set_phase "stack" "Gastown Stack"
    log_step "7/8" "Installing Gastown stack..."

    # Install any tools-category modules at phase 9 (e.g. utils.*)
    if gtbi_use_generated_category "tools"; then
        log_detail "Using generated installers for tools (phase 9)"
        gtbi_run_generated_category_phase "tools" "9" || return 1
    fi

    if gtbi_use_generated_category "stack"; then
        log_detail "Using generated installers for stack (phase 9)"
        gtbi_run_generated_category_phase "stack" "9" || return 1
        log_success "Gastown stack installed"
        return 0
    fi

    log_warn "Generated stack installers not found; skipping Gastown stack"
    return 0
}

# ============================================================
# Phase 9: Final wiring
# ============================================================
# ============================================================
# Post-install smoke test
# Runs quick, automatic verification at the end of install.sh
# ============================================================
_smoke_target_path() {
    local user_home="${TARGET_HOME:-}"
    if [[ -z "$user_home" ]]; then
        user_home="$(gtbi_home_for_user "$TARGET_USER" || true)"
    fi
    if [[ -z "$user_home" ]] || [[ "$user_home" != /* ]]; then
        return 1
    fi

    printf '%s\n' "${GTBI_BIN_DIR:-$user_home/.local/bin}:$user_home/.local/bin:$user_home/.gtbi/bin:$user_home/.cargo/bin:$user_home/.bun/bin:$user_home/.atuin/bin:$user_home/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
}


_smoke_run_as_target() {
    local cmd="$1"
    local smoke_path=""

    smoke_path="$(_smoke_target_path)" || return 1
    run_as_target env "PATH=$smoke_path" bash -c "set -euo pipefail; $cmd"
}

gtbi_smoke_install_fix_command() {
    local install_url="https://agent-flywheel.com/install"
    local install_url_q=""
    local flags=""
    local module_id=""
    local -a fix_args=(--yes --force-reinstall)

    for module_id in "$@"; do
        [[ -n "$module_id" ]] || continue
        fix_args+=(--only "$module_id")
    done

    if [[ -n "${GTBI_COMMIT_SHA_FULL:-}" ]]; then
        install_url="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_COMMIT_SHA_FULL}/install.sh"
        fix_args+=(--ref "$GTBI_COMMIT_SHA_FULL")
    elif [[ -n "${GTBI_REF_INPUT:-}" && "${GTBI_REF_INPUT}" != "main" ]]; then
        install_url="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_REF_INPUT}/install.sh"
        fix_args+=(--ref "$GTBI_REF_INPUT")
    fi

    printf -v install_url_q '%q' "$install_url"
    printf -v flags '%q ' "${fix_args[@]}"
    flags="${flags% }"

    printf 'curl -fsSL %s | bash -s -- %s\n' "$install_url_q" "$flags"
}

run_smoke_test() {
    local critical_total=8
    local critical_passed=0
    local critical_failed=0
    local warnings=0

    echo "" >&2
    echo "[Smoke Test]" >&2

    # 1) Target user exists
    local smoke_id_bin=""
    local target_shell=""
    local target_shell_entry=""
    smoke_id_bin="$(gtbi_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$smoke_id_bin" ]] && "$smoke_id_bin" "$TARGET_USER" &>/dev/null; then
        echo "✅ User: $TARGET_USER" >&2
        ((critical_passed += 1))
    else
        echo "✖ User: missing (TARGET_USER=$TARGET_USER)" >&2
        echo "    Fix: set TARGET_USER=<user> and ensure the user exists" >&2
        ((critical_failed += 1))
    fi

    # 2) Shell is zsh
    target_shell_entry="$(gtbi_early_getent_passwd_entry "$TARGET_USER" 2>/dev/null || true)"
    if [[ -n "$target_shell_entry" ]]; then
        IFS=: read -r _ _ _ _ _ _ target_shell <<< "$target_shell_entry"
    fi
    if [[ "$target_shell" == *"zsh"* ]]; then
        echo "✅ Shell: zsh" >&2
        ((critical_passed += 1))
    elif gtbi_is_externally_managed_user "$TARGET_USER"; then
        if gtbi_external_shell_handoff_configured "$TARGET_HOME"; then
            echo "✅ Shell: externally managed login hands off to zsh" >&2
            ((critical_passed += 1))
        else
            echo "⚠ Shell: externally managed account reports ${target_shell:-unknown}" >&2
            echo "    Note: local chsh is not valid here; configure the identity provider shell or add the GTBI bash-to-zsh handoff." >&2
            ((warnings += 1))
        fi
    else
        echo "✖ Shell: zsh (found: ${target_shell:-unknown})" >&2
        echo "    Fix: sudo chsh -s \"\$(command -v zsh)\" \"$TARGET_USER\"" >&2
        ((critical_failed += 1))
    fi

    # 3) Sudo configuration
    # - vibe mode: passwordless sudo is required
    # - safe mode: sudo must exist, but may require a password
    if [[ "$MODE" == "vibe" ]]; then
        if _smoke_run_as_target "sudo -n true" &>/dev/null; then
            echo "✅ Sudo: passwordless (vibe mode)" >&2
            ((critical_passed += 1))
        else
            echo "✖ Sudo: passwordless (vibe mode)" >&2
            echo "    Fix: re-run installer with --mode vibe (or configure NOPASSWD for $TARGET_USER)" >&2
            ((critical_failed += 1))
        fi
    else
        if _smoke_run_as_target "command -v sudo >/dev/null" &>/dev/null && \
            _smoke_run_as_target "id -nG | grep -qw sudo" &>/dev/null; then
            echo "✅ Sudo: available (safe mode)" >&2
            ((critical_passed += 1))
        else
            echo "✖ Sudo: available (safe mode)" >&2
            echo "    Fix: ensure sudo is installed and $TARGET_USER is in the sudo group" >&2
            ((critical_failed += 1))
        fi
    fi

    # 4) /data/projects exists
    if _smoke_run_as_target "[[ -d /data/projects && -w /data/projects ]]" &>/dev/null; then
        echo "✅ Workspace: /data/projects exists" >&2
        ((critical_passed += 1))
    else
        echo "✖ Workspace: /data/projects exists" >&2
        echo "    Fix: sudo mkdir -p /data/projects && sudo chown -R \"$TARGET_USER:$TARGET_USER\" /data/projects" >&2
        ((critical_failed += 1))
    fi

    # 5) bun, uv, cargo, go available
    local missing_lang=()
    [[ -x "$TARGET_HOME/.bun/bin/bun" ]] || missing_lang+=("bun")
    [[ -x "$GTBI_BIN_DIR/uv" || -x "$TARGET_HOME/.cargo/bin/uv" ]] || missing_lang+=("uv")
    [[ -x "$TARGET_HOME/.cargo/bin/cargo" ]] || missing_lang+=("cargo")
    binary_installed "go" || missing_lang+=("go")
    if [[ ${#missing_lang[@]} -eq 0 ]]; then
        echo "✅ Languages: bun, uv, cargo, go available" >&2
        ((critical_passed += 1))
    else
        echo "✖ Languages: missing ${missing_lang[*]}" >&2
        echo "    Fix: $(gtbi_smoke_install_fix_command lang.bun lang.uv lang.rust lang.go)" >&2
        ((critical_failed += 1))
    fi

    # 6) claude, codex, gemini commands exist
    local missing_agents=()
    [[ -x "$GTBI_BIN_DIR/claude" || -x "$TARGET_HOME/.bun/bin/claude" ]] || missing_agents+=("claude")
    [[ -x "$TARGET_HOME/.bun/bin/codex" || -x "$GTBI_BIN_DIR/codex" ]] || missing_agents+=("codex")
    [[ -x "$TARGET_HOME/.bun/bin/gemini" || -x "$GTBI_BIN_DIR/gemini" ]] || missing_agents+=("gemini")
    if [[ ${#missing_agents[@]} -eq 0 ]]; then
        echo "✅ Agents: claude, codex, gemini" >&2
        ((critical_passed += 1))
    else
        echo "✖ Agents: missing ${missing_agents[*]}" >&2
        echo "    Fix: $(gtbi_smoke_install_fix_command agents.claude agents.codex agents.gemini)" >&2
        ((critical_failed += 1))
    fi

    # 7) dolt command works
    if _smoke_run_as_target "command -v dolt >/dev/null && dolt version >/dev/null 2>&1"; then
        echo "✅ Dolt: working" >&2
        ((critical_passed += 1))
    else
        echo "✖ Dolt: not working" >&2
        echo "    Fix: $(gtbi_smoke_install_fix_command stack.dolt)" >&2
        ((critical_failed += 1))
    fi

    # 8) onboard command exists
    if [[ -x "$GTBI_BIN_DIR/onboard" ]]; then
        echo "✅ Onboard: installed" >&2
        ((critical_passed += 1))
    else
        echo "✖ Onboard: missing" >&2
        echo "    Fix: $(gtbi_smoke_install_fix_command gtbi.onboard)" >&2
        ((critical_failed += 1))
    fi

    # Non-critical: bd (beads) responds to version check
    if _smoke_run_as_target "command -v bd >/dev/null && bd --version >/dev/null 2>&1"; then
        echo "✅ beads (bd): working" >&2
    else
        echo "⚠️ beads (bd): not working (re-run: $(gtbi_smoke_install_fix_command stack.bd))" >&2
        ((warnings += 1))
    fi

    echo "" >&2
    if [[ $critical_failed -eq 0 ]]; then
        echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${warnings} warnings" >&2
        return 0
    fi

    echo "Smoke test: ${critical_passed}/${critical_total} critical passed, ${critical_failed} critical failed, ${warnings} warnings" >&2
    return 1
}

# ============================================================
# Print summary
# ============================================================
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        {
            if [[ "$HAS_GUM" == "true" ]]; then
                echo ""
                gum style \
                    --border double \
                    --border-foreground "$GTBI_WARNING" \
                    --padding "1 3" \
                    --margin "1 0" \
                    --align left \
                    "$(gum style --foreground "$GTBI_WARNING" --bold '🧪 GTBI Dry Run Complete (no changes made)')

Version: $GTBI_VERSION
Mode:    $MODE

No commands were executed. To actually install, re-run without --dry-run.
Tip: use --print to see upstream install scripts that will be fetched."
            else
                echo ""
                echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║          🧪 GTBI Dry Run Complete (no changes made)        ║${NC}"
                echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
                echo ""
                echo -e "Version: ${BLUE}$GTBI_VERSION${NC}"
                echo -e "Mode:    ${BLUE}$MODE${NC}"
                echo ""
                echo -e "${GRAY}No commands were executed. Re-run without --dry-run to install.${NC}"
                echo -e "${GRAY}Tip: use --print to see upstream install scripts.${NC}"
                echo ""
                echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
            fi
        } >&2
        return 0
    fi

    # Build dynamic Tailscale status
    local tailscale_section=""
    if command -v tailscale &>/dev/null; then
        if check_tailscale_auth 2>/dev/null; then
            local ts_ip
            ts_ip=$(tailscale ip -4 2>/dev/null || echo "connected")
            tailscale_section="  ✓ Tailscale: connected ($ts_ip)"
        else
            tailscale_section="  🔐 Tailscale (Secure Remote Access):
     sudo tailscale up
     → Log in with your Google account
     → Then access this VPS from anywhere!"
        fi
    fi

    local target_ssh_command="ssh -i ~/.ssh/gtbi_ed25519 ${TARGET_USER}@YOUR_SERVER_IP"
    local target_ssh_copy_command="ssh-copy-id -i ~/.ssh/gtbi_ed25519.pub ${TARGET_USER}@YOUR_SERVER_IP"
    local target_user_ssh_repair_command="cat ~/.ssh/gtbi_ed25519.pub | ssh ${TARGET_USER}@YOUR_SERVER_IP \"read -r gtbi_pubkey && test ! -L ~/.ssh && install -d -m 700 ~/.ssh && chmod 700 ~/.ssh && test ! -L ~/.ssh/authorized_keys && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && { [ ! -s ~/.ssh/authorized_keys ] || tail -c 1 ~/.ssh/authorized_keys | od -An -t u1 | grep -qw 10 || printf '\\n' >> ~/.ssh/authorized_keys; } && if ! grep -qxF \\\"\\\$gtbi_pubkey\\\" ~/.ssh/authorized_keys; then printf '%s\\n' \\\"\\\$gtbi_pubkey\\\" >> ~/.ssh/authorized_keys; fi\""
    local target_home_for_summary="${TARGET_HOME:-/home/$TARGET_USER}"
    local target_ssh_dir_for_summary="$target_home_for_summary/.ssh"
    local target_authorized_keys_for_summary="$target_home_for_summary/.ssh/authorized_keys"
    local target_owner_for_summary="$TARGET_USER:$TARGET_USER"
    local target_ssh_dir_for_summary_q=""
    local target_authorized_keys_for_summary_q=""
    local target_user_for_summary_q=""
    local target_owner_for_summary_q=""
    printf -v target_ssh_dir_for_summary_q '%q' "$target_ssh_dir_for_summary"
    printf -v target_authorized_keys_for_summary_q '%q' "$target_authorized_keys_for_summary"
    printf -v target_user_for_summary_q '%q' "$TARGET_USER"
    printf -v target_owner_for_summary_q '%q' "$target_owner_for_summary"
    local target_ssh_remote_command="read -r gtbi_pubkey && test ! -L $target_ssh_dir_for_summary_q && install -d -m 700 -o $target_user_for_summary_q -g $target_user_for_summary_q $target_ssh_dir_for_summary_q && test ! -L $target_authorized_keys_for_summary_q && touch $target_authorized_keys_for_summary_q && { [ ! -s $target_authorized_keys_for_summary_q ] || tail -c 1 $target_authorized_keys_for_summary_q | od -An -t u1 | grep -qw 10 || printf \"\\n\" >> $target_authorized_keys_for_summary_q; } && if ! grep -qxF \"\$gtbi_pubkey\" $target_authorized_keys_for_summary_q; then printf \"%s\\n\" \"\$gtbi_pubkey\" >> $target_authorized_keys_for_summary_q; fi && chown $target_owner_for_summary_q $target_authorized_keys_for_summary_q && chmod 600 $target_authorized_keys_for_summary_q"
    local target_ssh_remote_command_q="$target_ssh_remote_command"
    target_ssh_remote_command_q=${target_ssh_remote_command_q//\'/\'\\\'\'}
    printf -v target_ssh_remote_command_q "'%s'" "$target_ssh_remote_command_q"
    local target_ssh_repair_command="cat ~/.ssh/gtbi_ed25519.pub | ssh root@YOUR_SERVER_IP $target_ssh_remote_command_q"

    local ssh_key_warning_section=""
    if [[ "${GTBI_SSH_KEY_WARNING:-false}" == "true" ]]; then
        ssh_key_warning_section="SSH key setup required for $TARGET_USER:

  You connected with a password, so no SSH key was copied to $TARGET_USER.
  Passwordless sudo for $TARGET_USER is not a login password.

  From your local machine, first try this only if you can already sign in as $TARGET_USER:
     $target_user_ssh_repair_command

  This uses the $TARGET_USER account and does not ask for the VPS root password.

  If you only have the VPS root password or that cannot connect, use the root fallback:
     $target_ssh_repair_command

  This asks for the VPS root password once, then installs your local key for $TARGET_USER.

  ssh-copy-id is optional and only works if you know the $TARGET_USER Linux account password:
     $target_ssh_copy_command

"
    fi

    local next_steps_content=""
    if [[ "${GTBI_SSH_KEY_WARNING:-false}" == "true" ]]; then
        next_steps_content="Next steps:

  1. Set up SSH key access for $TARGET_USER using the command above.

  2. Then reconnect as $TARGET_USER:
     exit
     $target_ssh_command

  3. Run the onboarding tutorial:
     onboard

  4. Check everything is working:
     gtbi doctor

  5. Start an agent session:
     bd ready  # find work to do"
    else
        next_steps_content="Next steps:

  1. If you logged in as root, reconnect as $TARGET_USER:
     exit
     $target_ssh_command

  2. Run the onboarding tutorial:
     onboard

  3. Check everything is working:
     gtbi doctor

  4. Start an agent session:
     bd ready  # find work to do"
    fi

    local summary_content="Version: $GTBI_VERSION
Mode:    $MODE

${tailscale_section:+Service Authentication:

$tailscale_section

}$ssh_key_warning_section$next_steps_content"

    {
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border double \
                --border-foreground "$GTBI_SUCCESS" \
                --padding "1 3" \
                --margin "1 0" \
                --align left \
                "$(gum style --foreground "$GTBI_SUCCESS" --bold '🎉 GTBI Installation Complete!')

$summary_content"
        else
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║            🎉 GTBI Installation Complete!                   ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
            echo ""
            echo -e "Version: ${BLUE}$GTBI_VERSION${NC}"
            echo -e "Mode:    ${BLUE}$MODE${NC}"
            echo ""
            # Show Tailscale auth section if applicable
            if [[ -n "$tailscale_section" ]]; then
                echo -e "${YELLOW}Service Authentication:${NC}"
                echo ""
                if command -v tailscale &>/dev/null && check_tailscale_auth 2>/dev/null; then
                    local ts_ip_display
                    ts_ip_display=$(tailscale ip -4 2>/dev/null || echo "connected")
                    echo -e "  ${GREEN}✓${NC} Tailscale: connected (${BLUE}$ts_ip_display${NC})"
                else
                    echo -e "  ${YELLOW}🔐${NC} Tailscale (Secure Remote Access):"
                    echo -e "     ${BLUE}sudo tailscale up${NC}"
                    echo -e "     ${GRAY}→ Log in with your Google account${NC}"
                    echo -e "     ${GRAY}→ Then access this VPS from anywhere!${NC}"
                fi
                echo ""
            fi
            # Show SSH key warning if password-only connection was detected
            if [[ "${GTBI_SSH_KEY_WARNING:-false}" == "true" ]]; then
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo -e "${RED}  ⚠  SSH KEY SETUP REQUIRED FOR TARGET USER${NC}"
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo ""
                echo -e "  You connected with a password, so no SSH key was copied"
                echo -e "  to the $TARGET_USER user. You won't be able to SSH as $TARGET_USER"
                echo -e "  until you set up SSH key access."
                echo ""
                echo -e "  ${GRAY}Passwordless sudo for $TARGET_USER is not a login password.${NC}"
                echo ""
                echo -e "  ${YELLOW}FROM YOUR LOCAL MACHINE, first try this only if you can already sign in as $TARGET_USER:${NC}"
                echo ""
                echo -e "    ${BLUE}$target_user_ssh_repair_command${NC}"
                echo ""
                echo -e "  ${GRAY}This uses the $TARGET_USER account and does not ask for the VPS root password.${NC}"
                echo ""
                echo -e "  ${YELLOW}If you only have the VPS root password or that cannot connect, use the root fallback:${NC}"
                echo ""
                echo -e "    ${BLUE}$target_ssh_repair_command${NC}"
                echo ""
                echo -e "  This asks for the VPS root password once, then installs your local"
                echo -e "  GTBI public key for $TARGET_USER."
                echo ""
                echo -e "  ${YELLOW}ssh-copy-id is optional and only works if you know the $TARGET_USER Linux account password:${NC}"
                echo ""
                echo -e "    ${BLUE}$target_ssh_copy_command${NC}"
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo ""
            fi
            echo -e "${YELLOW}Next steps:${NC}"
            echo ""
            if [[ "${GTBI_SSH_KEY_WARNING:-false}" == "true" ]]; then
                echo "  1. Set up SSH key for $TARGET_USER user (see warning above)"
                echo ""
                echo "  2. Then reconnect as $TARGET_USER:"
            else
                echo "  1. If you logged in as root, reconnect as $TARGET_USER:"
            fi
            echo -e "     ${GRAY}exit${NC}"
            echo -e "     ${GRAY}$target_ssh_command${NC}"
            echo ""
            local step_num=2
            if [[ "${GTBI_SSH_KEY_WARNING:-false}" == "true" ]]; then
                step_num=3
            fi
            echo "  $step_num. Run the onboarding tutorial:"
            echo -e "     ${BLUE}onboard${NC}"
            echo ""
            ((step_num++))
            echo "  $step_num. Check everything is working:"
            echo -e "     ${BLUE}gtbi doctor${NC}"
            echo ""
            ((step_num++))
            echo "  $step_num. Start an agent session:"
            echo -e "     ${BLUE}bd ready${NC}  # find work to do"
            echo ""
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
            echo ""
        fi
    } >&2
}

# ============================================================
# Main
# ============================================================
main() {
    parse_args "$@"
    gtbi_require_ref_arg_value "GTBI_REF" "${GTBI_REF:-}" "main"
    gtbi_require_ref_arg_value "GTBI_CHECKSUMS_REF" "${GTBI_CHECKSUMS_REF:-}" "main"
    normalize_read_only_modes

    # --yes should always behave non-interactively (skip prompts), regardless of flag order.
    if [[ "$YES_MODE" == "true" ]]; then
        export GTBI_INTERACTIVE=false
    fi

    # Handle --pin-ref early (before any heavy setup) - just resolve SHA and exit
    if [[ "$PIN_REF_MODE" == "true" ]]; then
        fetch_commit_sha
        print_pinned_ref
        exit 0
    fi

    gtbi_normalize_offline_pack_configuration

    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        # Resolve GTBI_REF to a specific commit SHA early to prevent mixed-ref installs.
        # Without this, we could download a tarball for one commit and later fetch commit metadata
        # (or resume scripts) from a newer commit if the branch/tag moves mid-install.
        fetch_commit_sha
        if [[ -n "${GTBI_COMMIT_SHA_FULL:-}" ]]; then
            GTBI_REF="$GTBI_COMMIT_SHA_FULL"
            GTBI_RAW="https://raw.githubusercontent.com/${GTBI_REPO_OWNER}/${GTBI_REPO_NAME}/${GTBI_REF}"
            export GTBI_REF GTBI_RAW
        fi
        # Download and extract the repo archive for curl-pipe mode.
        # This sets GTBI_BOOTSTRAP_DIR and related paths. If it fails, we cannot continue
        # because the library files (install_helpers.sh, etc.) won't be available.
        if ! bootstrap_repo_archive; then
            log_error "Bootstrap failed. Cannot continue without library files."
            log_error "Try again, or run from a local checkout instead of curl|bash."
            exit 1
        fi
        # Verify bootstrap succeeded - GTBI_BOOTSTRAP_DIR must be set for curl-pipe mode
        if [[ -z "${GTBI_BOOTSTRAP_DIR:-}" ]]; then
            log_error "Bootstrap did not set GTBI_BOOTSTRAP_DIR. This is a bug."
            exit 1
        fi
    fi

    # Detect environment and source manifest index (mjt.5.3)
    # This must happen BEFORE any handlers that need module data
    detect_environment

    # Acquire install-wide flock to prevent concurrent install.sh processes.
    # Uses FD 199 (autofix.sh already uses FD 200 for its own lock).
    # Read-only modes (--list-modules, --print-plan, --dry-run, --print) skip locking.
    if [[ "$LIST_MODULES" != "true" ]] && [[ "$PRINT_PLAN_MODE" != "true" ]] \
       && [[ "$DRY_RUN" != "true" ]] && [[ "$PRINT_MODE" != "true" ]]; then
        local _gtbi_lock_home="${TARGET_HOME:-}"
        if [[ -z "$_gtbi_lock_home" ]]; then
            _gtbi_lock_home="$(gtbi_home_for_user "${TARGET_USER:-ubuntu}" || true)"
        fi
        if [[ -z "$_gtbi_lock_home" ]] && [[ $EUID -eq 0 ]] && ! id "${TARGET_USER:-ubuntu}" &>/dev/null; then
            _gtbi_lock_home="$(gtbi_default_home_for_new_user "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
        fi
        if [[ -z "$_gtbi_lock_home" ]] || [[ "$_gtbi_lock_home" != /* ]]; then
            log_error "Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly"
            exit 1
        fi
        local _gtbi_lock_dir="${GTBI_HOME:-${_gtbi_lock_home}/.gtbi}"
        if ! mkdir -p "$_gtbi_lock_dir" 2>/dev/null; then
            log_error "Unable to create GTBI install lock directory: $_gtbi_lock_dir"
            exit 1
        fi
        local _gtbi_lock_file="$_gtbi_lock_dir/.install.lock"
        # NOTE: On bash 5.3+, `exec N>file` under set -e exits the script
        # before `if` can catch the failure. We test in a subshell first,
        # then only exec in the main shell if the subshell succeeded.
        local _gtbi_lock_fd=""
        if (exec 199>"$_gtbi_lock_file") 2>/dev/null; then
            exec 199>"$_gtbi_lock_file"
            _gtbi_lock_fd=199
        elif (exec 198>"$_gtbi_lock_file") 2>/dev/null; then
            exec 198>"$_gtbi_lock_file"
            _gtbi_lock_fd=198
        fi
        if [[ -n "$_gtbi_lock_fd" ]]; then
            if ! flock -n "$_gtbi_lock_fd"; then
                log_error "Another GTBI installer is already running."
                log_error "Wait for it to finish, then retry. Lock file: $_gtbi_lock_file"
                exit 1
            fi
            gtbi_remember_install_lock "$_gtbi_lock_fd" "$_gtbi_lock_file"
        else
            log_error "Unable to open GTBI install lock file: $_gtbi_lock_file"
            exit 1
        fi
    fi

    # Source generated installers for manifest-driven execution (mjt.5.6)
    # Skip when we're only listing/printing plan or running dry-run/print-only modes.
    if [[ "$LIST_MODULES" != "true" ]] && [[ "$PRINT_PLAN_MODE" != "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ "$PRINT_MODE" != "true" ]]; then
        source_generated_installers
    fi

    # Resolve module selection (mjt.5.4)
    # Computes GTBI_EFFECTIVE_PLAN and GTBI_EFFECTIVE_RUN based on:
    # - CLI flags (--only, --skip, --no-deps, --only-phase)
    # - Legacy flags mapped above
    # - Manifest defaults and dependency graph
    if ! gtbi_resolve_selection; then
        exit 1
    fi

    # Handle --list-modules: print available modules and exit (mjt.5.3)
    if [[ "$LIST_MODULES" == "true" ]]; then
        list_modules
        exit 0
    fi

    # Handle --print-plan: print execution plan and exit (mjt.5.3/5.4)
    if [[ "$PRINT_PLAN_MODE" == "true" ]]; then
        print_execution_plan
        exit 0
    fi

    # Handle --reset-state: move state file aside and exit
    if [[ "$RESET_STATE_ONLY" == "true" ]]; then
        echo "Resetting GTBI state..." >&2
        local state_file=""
        if [[ -n "${GTBI_HOME:-}" ]]; then
            state_file="${GTBI_HOME}/state.json"
        else
            local base_home=""
            if [[ -n "${TARGET_HOME:-}" ]]; then
                base_home="$TARGET_HOME"
            else
                base_home="$(gtbi_home_for_user "${TARGET_USER:-ubuntu}" || true)"
            fi

            if [[ -z "$base_home" ]]; then
                echo "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly" >&2
                exit 1
            fi

            if [[ -z "$base_home" ]] || [[ "$base_home" == "/" ]]; then
                echo "ERROR: Invalid TARGET_HOME: '${base_home:-<empty>}'" >&2
                exit 1
            fi
            if [[ "$base_home" != /* ]]; then
                echo "ERROR: TARGET_HOME must be an absolute path (got: $base_home)" >&2
                exit 1
            fi

            state_file="${base_home}/.gtbi/state.json"
        fi
        if [[ -f "$state_file" ]]; then
            if type -t state_backup_and_remove &>/dev/null; then
                local state_dir
                state_dir="$(dirname "$state_file")"
                if ! GTBI_HOME="$state_dir" GTBI_STATE_FILE="$state_file" state_backup_and_remove; then
                    echo "ERROR: Failed to move state file out of the way: $state_file" >&2
                    exit 1
                fi
            else
                local backup_file
                backup_file="${state_file}.backup.$(date +%Y%m%d_%H%M%S)"
                if mv "$state_file" "$backup_file" 2>/dev/null; then
                    echo "Moved state file aside: $backup_file" >&2
                else
                    echo "ERROR: Failed to move state file out of the way: $state_file" >&2
                    exit 1
                fi
            fi
        else
            echo "No state file found at: $state_file" >&2
        fi
        exit 0
    fi

    # Install gum FIRST so the entire script looks amazing
    install_gum_early

    # Fetch commit SHA for version display
    fetch_commit_sha

    # Print beautiful ASCII banner (now with gum if available!)
    print_banner

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        echo ""
    fi

    # Run auto-fix checks before preflight (bd-19y9.3.4)
    if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
        run_autofix_checks
    fi

    # Run pre-flight validation (Phase 0)
    if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
        run_preflight_checks
    fi

    # Dry-run mode should be truly non-destructive. Print the plan/summary and exit
    # before any system-modifying steps (apt/user/upgrade) can run.
    if [[ "$DRY_RUN" == "true" ]]; then
        print_execution_plan || true
        print_summary
        exit 0
    fi

    if [[ "$PRINT_MODE" == "true" ]]; then
        echo "The following tools will be installed from upstream:"
        echo ""
        echo "  - Oh My Zsh: https://ohmyz.sh"
        echo "  - Powerlevel10k: https://github.com/romkatv/powerlevel10k"
        echo "  - Bun: https://bun.sh"
        echo "  - Rust: https://rustup.rs"
        echo "  - uv: https://astral.sh/uv"
        echo "  - Claude Code (native): https://claude.ai/install.sh"
        echo "  - Dolt: https://github.com/dolthub/dolt"
        echo "  - beads (bd): https://github.com/gastownhall/beads"
        echo ""
        exit 0
    fi

    ensure_root

    # Early dependency bootstrap (issue #152, #180): on a truly fresh Ubuntu,
    # jq and curl may be missing. Install them before anything else so that
    # later phases (state management, JSON parsing, gum install) don't fail.
    # Also covers the case where sudo is available but $SUDO isn't set yet.
    if [[ $EUID -eq 0 ]] || [[ -n "${SUDO:-}" ]] || gtbi_early_sudo_binary_path &>/dev/null; then
        local _need_early_apt=false
        gtbi_early_system_binary_path curl &>/dev/null || _need_early_apt=true
        gtbi_early_system_binary_path jq &>/dev/null   || _need_early_apt=true
        gtbi_early_system_binary_path git &>/dev/null   || _need_early_apt=true
        if [[ "$_need_early_apt" == "true" ]]; then
            echo -e "${YELLOW}Installing minimal bootstrap dependencies (curl, jq, git)...${NC}" >&2
            local -a _sudo_cmd=()
            local apt_get_bin=""
            apt_get_bin="$(gtbi_early_system_binary_path apt-get 2>/dev/null || true)"
            if [[ -z "$apt_get_bin" ]]; then
                log_warn "apt-get not found; cannot install bootstrap dependencies"
            else
                if [[ $EUID -ne 0 ]]; then
                    local sudo_bin=""
                    sudo_bin="$(gtbi_early_sudo_binary_path 2>/dev/null || true)"
                    [[ -n "$sudo_bin" ]] && _sudo_cmd=("$sudo_bin")
                fi
                if [[ $EUID -eq 0 || ${#_sudo_cmd[@]} -gt 0 ]]; then
                    "${_sudo_cmd[@]}" "$apt_get_bin" update -qq 2>/dev/null || true
                    "${_sudo_cmd[@]}" "$apt_get_bin" install -y -qq curl jq git 2>/dev/null || true
                fi
            fi
        fi
    fi

    disable_needrestart_apt_hook  # Prevent apt hangs on Ubuntu 22.04+ (issue #70)
    validate_target_user
    init_target_paths
    gtbi_log_init   # Start capturing stderr to log file (uses GTBI_HOME/logs)
    ensure_ubuntu

    # Ensure base dependencies (like jq) are installed before upgrade logic
    # This is safe to run on old Ubuntu versions and ensures jq is available
    # for state management during the upgrade process.
    ensure_base_deps

    # ============================================================
    # Ubuntu Auto-Upgrade Phase (nb4)
    # ============================================================
    # Run as "Phase -1" before all other phases.
    # This may trigger a reboot and exit. After final reboot,
    # the resume service will call install.sh again to continue.
    # Skip when --only or --only-phase is specified, since the user
    # is targeting a specific module on an already-installed system.
    if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
        run_ubuntu_upgrade_phase "$@"
    else
        log_debug "Skipping Ubuntu auto-upgrade (--only/--only-phase mode)"
    fi

    # ============================================================
    # State Management and Resume Logic (mjt.5.8)
    # ============================================================
    # Initialize state file location (uses TARGET_USER's home)
    GTBI_HOME="${GTBI_HOME:-$TARGET_HOME/.gtbi}"
    GTBI_STATE_FILE="${GTBI_STATE_FILE:-$GTBI_HOME/state.json}"
    export GTBI_HOME GTBI_STATE_FILE

    # Validate and handle existing state file
    if type -t state_ensure_valid &>/dev/null; then
        if ! state_ensure_valid; then
            log_error "State validation failed. Aborting."
            exit 1
        fi
    fi

    # Check for resume scenario (if state functions available)
    if type -t confirm_resume &>/dev/null; then
        # Use || to capture non-zero exit codes without triggering set -e
        # confirm_resume returns: 0=resume, 1=fresh install, 2=abort
        local resume_result=0
        confirm_resume || resume_result=$?
        case $resume_result in
            0) # Resume - state functions will skip completed phases
                log_info "Resuming installation from last checkpoint..."
                ;;
            1) # Fresh install - confirm before proceeding, then initialize state
                confirm_or_exit
                if type -t state_init &>/dev/null; then
                    state_init
                fi
                ;;
            2) # Abort
                log_info "Installation aborted by user."
                exit 0
                ;;
        esac
    else
        # Fallback: use original confirm_or_exit
        confirm_or_exit
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        # Execute phases with state tracking (mjt.5.8)
        # Each run_phase call checks if phase is already completed and skips if so

        # Track installation timing for report_success
        local installation_start_time
        installation_start_time=$(date +%s)

        # Helper: Run phase with structured error reporting (mjt.5.8)
        _run_phase_with_report() {
            local phase_id="$1"
            local phase_display="$2"
            local phase_func="$3"
            local phase_num="${phase_display%%/*}"
            # Extract name after the leading "X/Y " prefix (robust to multi-digit totals).
            local phase_name="${phase_display#* }"

            # Show progress header before running phase
            if type -t show_progress_header &>/dev/null; then
                show_progress_header "$phase_num" 8 "$phase_name" "$installation_start_time" "$phase_id"
            fi

            if type -t run_phase &>/dev/null; then
                if ! run_phase "$phase_id" "$phase_display" "$phase_func"; then
                    # Use structured error reporting
                    if type -t report_failure &>/dev/null; then
                        report_failure "$phase_num" 8
                    else
                        log_error "Phase $phase_display failed"
                    fi
                    # Print precise resume hint (bd-31ps.9.1)
                    print_resume_hint "$phase_id" ""
                    exit 1
                fi
            else
                # Fallback: direct call with basic error handling
                if ! "$phase_func"; then
                    log_error "Phase $phase_display failed"
                    print_resume_hint "$phase_id" ""
                    exit 1
                fi
            fi
        }

        _run_phase_with_report "user_setup" "1/8 User Setup" normalize_user
        _run_phase_with_report "filesystem" "2/8 Filesystem" setup_filesystem
        _run_phase_with_report "shell_setup" "3/8 Shell Setup" setup_shell
        _run_phase_with_report "cli_tools" "4/8 CLI Tools" install_cli_tools
        _run_phase_with_report "languages" "5/8 Languages" install_languages
        _run_phase_with_report "agents" "6/8 Coding Agents" install_agents_phase
        _run_phase_with_report "stack" "7/8 Stack" install_stack_phase
        _run_phase_with_report "finalize" "8/8 Finalize" finalize

        # Always update checksums.yaml and VERSION after all phases complete
        # This ensures resume installs get fresh metadata even if finalize was previously completed
        # Related: PR #44 - fix checksums.yaml becoming stale on resume installs
        if [[ -n "${GTBI_BOOTSTRAP_DIR:-}" ]] && [[ -d "$GTBI_BOOTSTRAP_DIR" ]]; then
            if [[ -f "$GTBI_BOOTSTRAP_DIR/checksums.yaml" ]]; then
                if [[ -n "${GTBI_CHECKSUMS_REF:-}" && -n "${GTBI_REF_INPUT:-}" && "$GTBI_CHECKSUMS_REF" != "$GTBI_REF_INPUT" ]]; then
                    log_detail "Refreshing checksums.yaml from ref '${GTBI_CHECKSUMS_REF}'"
                    install_checksums_yaml "$GTBI_HOME/checksums.yaml" || true
                    $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/checksums.yaml" 2>/dev/null || true
                else
                    log_detail "Ensuring checksums.yaml is up to date"
                    $SUDO cp -f "$GTBI_BOOTSTRAP_DIR/checksums.yaml" "$GTBI_HOME/checksums.yaml" 2>/dev/null || true
                    $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/checksums.yaml" 2>/dev/null || true
                fi
            fi
            if [[ -f "$GTBI_BOOTSTRAP_DIR/VERSION" ]]; then
                log_detail "Ensuring VERSION is up to date"
                $SUDO cp -f "$GTBI_BOOTSTRAP_DIR/VERSION" "$GTBI_HOME/VERSION" 2>/dev/null || true
                $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/VERSION" 2>/dev/null || true
            fi
        fi

        # Calculate installation time for success report
        local installation_end_time total_seconds
        installation_end_time=$(date +%s)
        total_seconds=$((installation_end_time - installation_start_time))

        # Show completion message with progress display
        if type -t show_completion &>/dev/null; then
            show_completion 9 "$total_seconds"
        fi

        # Report success with timing (mjt.5.8)
        if type -t report_success &>/dev/null; then
            report_success 9 "$total_seconds"
        fi

        # Emit install summary JSON (bd-31ps.3.2)
        gtbi_summary_emit "success" "$total_seconds" 2>/dev/null || true

        # Send webhook notification if configured (bd-2zqr)
        if type -t webhook_notify &>/dev/null; then
            webhook_notify "success" "${GTBI_SUMMARY_FILE:-}" 2>/dev/null || true
        fi
        # Send ntfy.sh notification if configured (bd-2igt6)
        if type -t gtbi_notify_install_success &>/dev/null; then
            gtbi_notify_install_success 2>/dev/null || true
        fi

        # Skip the post-install smoke test when --only / --only-phase was
        # used: the user asked for a targeted subset, so the full-stack
        # checks (agents, ntm, onboard, languages, …) will fail by design.
        # They can still run `gtbi doctor` if they want a broader health check.
        SMOKE_TEST_FAILED=false
        if [[ ${#ONLY_MODULES[@]} -eq 0 ]] && [[ ${#ONLY_PHASES[@]} -eq 0 ]]; then
            if ! run_smoke_test; then
                SMOKE_TEST_FAILED=true
            fi
        else
            log_debug "Skipping post-install smoke test (--only/--only-phase mode)"
        fi
    fi

    print_summary

    if [[ "${SMOKE_TEST_FAILED:-false}" == "true" ]]; then
        exit 1
    fi
}

main "$@"
