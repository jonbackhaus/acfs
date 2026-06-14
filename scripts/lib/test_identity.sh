#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for Git/Dolt identity configuration (gtbi-90i)
# Covers:
#   - skip when both git + dolt already configured (no writes, no prompt)
#   - copy Git -> Dolt when only Git is set
#   - copy Dolt -> Git when only Dolt is set
#   - env override (GTBI_GIT_NAME / GTBI_GIT_EMAIL) configures both
#   - --yes / no-TTY skip: returns cleanly without hanging or writing
#   - invalid email from env is rejected (skipped, not applied)
# Hermetic: git/dolt config state lives in in-memory mock associative arrays.
# Run: bash scripts/lib/test_identity.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/identity.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "\033[32m[PASS]\033[0m $1"
    ((++TESTS_PASSED))
}
test_fail() {
    echo -e "\033[31m[FAIL]\033[0m $1"
    [[ -n "${2:-}" ]] && echo "       Reason: $2"
    ((++TESTS_FAILED))
}

# ------------------------------------------------------------
# Mock store: emulate git/dolt --global config as the target user.
# run_as_target_shell is overridden to operate on these arrays so the
# test never shells out to a real user / real git / real dolt.
# ------------------------------------------------------------
declare -A MOCK_CFG=()

reset_store() {
    MOCK_CFG=()
    unset GTBI_GIT_NAME GTBI_GIT_EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL YES_MODE 2>/dev/null || true
}

# Override the target-user shell runner used by identity.sh.
# Parses the handful of git/dolt config commands identity.sh issues.
run_as_target_shell() {
    local cmd="$1"
    # git config --global --get <key>
    if [[ "$cmd" =~ ^git\ config\ --global\ --get\ ([^ ]+) ]]; then
        printf '%s\n' "${MOCK_CFG[git.${BASH_REMATCH[1]}]:-}"
        return 0
    fi
    # dolt config --global --get <key>
    if [[ "$cmd" =~ ^dolt\ config\ --global\ --get\ ([^ ]+) ]]; then
        printf '%s\n' "${MOCK_CFG[dolt.${BASH_REMATCH[1]}]:-}"
        return 0
    fi
    # git config --global <key> '<value>'
    if [[ "$cmd" =~ ^git\ config\ --global\ ([^ ]+)\ \'(.*)\'$ ]]; then
        MOCK_CFG[git.${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
        return 0
    fi
    # dolt config --global --add <key> '<value>'
    if [[ "$cmd" =~ ^dolt\ config\ --global\ --add\ ([^ ]+)\ \'(.*)\'$ ]]; then
        MOCK_CFG[dolt.${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
        return 0
    fi
    echo "UNHANDLED MOCK CMD: $cmd" >&2
    return 1
}

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------

test_skip_when_both_set() {
    local name="skip when git + dolt already configured"
    reset_store
    MOCK_CFG[git.user.name]="Jane Doe"
    MOCK_CFG[git.user.email]="jane@example.com"
    MOCK_CFG[dolt.user.name]="Jane Doe"
    MOCK_CFG[dolt.user.email]="jane@example.com"
    YES_MODE=true

    configure_user_identity >/dev/null 2>&1
    # Values unchanged.
    if [[ "${MOCK_CFG[git.user.name]}" == "Jane Doe" && "${MOCK_CFG[dolt.user.email]}" == "jane@example.com" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "config was modified"
    fi
}

test_copy_git_to_dolt() {
    local name="copy Git -> Dolt when only Git set"
    reset_store
    MOCK_CFG[git.user.name]="Git User"
    MOCK_CFG[git.user.email]="git@example.com"
    YES_MODE=true

    configure_user_identity >/dev/null 2>&1
    if [[ "${MOCK_CFG[dolt.user.name]:-}" == "Git User" && "${MOCK_CFG[dolt.user.email]:-}" == "git@example.com" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "dolt not populated from git (name=${MOCK_CFG[dolt.user.name]:-} email=${MOCK_CFG[dolt.user.email]:-})"
    fi
}

test_copy_dolt_to_git() {
    local name="copy Dolt -> Git when only Dolt set"
    reset_store
    MOCK_CFG[dolt.user.name]="Dolt User"
    MOCK_CFG[dolt.user.email]="dolt@example.com"
    YES_MODE=true

    configure_user_identity >/dev/null 2>&1
    if [[ "${MOCK_CFG[git.user.name]:-}" == "Dolt User" && "${MOCK_CFG[git.user.email]:-}" == "dolt@example.com" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "git not populated from dolt (name=${MOCK_CFG[git.user.name]:-} email=${MOCK_CFG[git.user.email]:-})"
    fi
}

test_env_override_configures_both() {
    local name="env GTBI_GIT_NAME/EMAIL configures both"
    reset_store
    GTBI_GIT_NAME="Env User"
    GTBI_GIT_EMAIL="env@example.com"
    YES_MODE=true   # ensure env path, not prompt

    configure_user_identity >/dev/null 2>&1
    if [[ "${MOCK_CFG[git.user.name]:-}" == "Env User" && "${MOCK_CFG[git.user.email]:-}" == "env@example.com" \
       && "${MOCK_CFG[dolt.user.name]:-}" == "Env User" && "${MOCK_CFG[dolt.user.email]:-}" == "env@example.com" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "both not configured from env"
    fi
}

test_git_author_env_fallback() {
    local name="GIT_AUTHOR_NAME/EMAIL fallback configures both"
    reset_store
    GIT_AUTHOR_NAME="Author User"
    GIT_AUTHOR_EMAIL="author@example.com"
    YES_MODE=true

    configure_user_identity >/dev/null 2>&1
    if [[ "${MOCK_CFG[git.user.name]:-}" == "Author User" && "${MOCK_CFG[dolt.user.email]:-}" == "author@example.com" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "GIT_AUTHOR fallback not applied"
    fi
}

test_noninteractive_skip_no_hang() {
    local name="--yes / no-TTY skips without hang or writes"
    reset_store
    YES_MODE=true
    # No env, no config -> must skip cleanly. timeout guards against hang.
    local rc=0
    timeout 10 bash -c '
        set -euo pipefail
        SCRIPT_DIR="'"$SCRIPT_DIR"'"
        source "$SCRIPT_DIR/logging.sh"
        source "$SCRIPT_DIR/identity.sh"
        declare -A MOCK_CFG=()
        run_as_target_shell() {
            local cmd="$1"
            if [[ "$cmd" =~ --get\ ([^ ]+) ]]; then printf "\n"; return 0; fi
            echo "WROTE: $cmd" >&2; return 0
        }
        YES_MODE=true
        configure_user_identity </dev/null >/dev/null 2>/tmp/gtbi_identity_skip.$$ || exit 3
        # Ensure nothing was written.
        if grep -q "^WROTE:" /tmp/gtbi_identity_skip.$$; then exit 4; fi
        rm -f /tmp/gtbi_identity_skip.$$
    ' || rc=$?

    if [[ "$rc" -eq 0 ]]; then
        test_pass "$name"
    elif [[ "$rc" -eq 124 ]]; then
        test_fail "$name" "TIMED OUT (hung waiting for input)"
    elif [[ "$rc" -eq 4 ]]; then
        test_fail "$name" "wrote config in non-interactive mode"
    else
        test_fail "$name" "unexpected rc=$rc"
    fi
}

test_invalid_email_rejected() {
    local name="invalid env email rejected (not applied)"
    reset_store
    GTBI_GIT_NAME="Bad User"
    GTBI_GIT_EMAIL="not-an-email"   # no '@'
    YES_MODE=true

    configure_user_identity >/dev/null 2>&1
    if [[ -z "${MOCK_CFG[git.user.name]:-}" && -z "${MOCK_CFG[dolt.user.name]:-}" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "invalid identity was applied"
    fi
}

echo "=== Identity configuration tests (gtbi-90i) ==="
test_skip_when_both_set
test_copy_git_to_dolt
test_copy_dolt_to_git
test_env_override_configures_both
test_git_author_env_fallback
test_noninteractive_skip_no_hang
test_invalid_email_rejected

echo ""
echo "Passed: $TESTS_PASSED  Failed: $TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
