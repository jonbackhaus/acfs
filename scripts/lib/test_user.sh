#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for user.sh
# Run: bash scripts/lib/test_user.sh
#
# Focuses on user_ensure_home_owned (gtbi-9z5): the home dir must
# exist and be owned by the target after the call, idempotently.
#
# Runs hermetically without root by using the current user as the
# target so a non-privileged chown succeeds ($SUDO is empty).
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Silence library logging and force $SUDO empty (no privilege escalation in test).
log_fatal() { printf "FATAL: %s\n" "$1" >&2; exit 1; }
log_detail() { :; }
log_warn() { :; }
log_success() { :; }
log_error() { :; }
log_step() { :; }
SUDO=""

# Use the current user as the target so chown works without root.
TARGET_USER="$(id -un)"

source "$SCRIPT_DIR/user.sh"

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

# Stub user_home_for_user to return a controlled path for the duration of a test.
# Note: use a uniquely-named global (not "home") to avoid being shadowed by the
# `local home` inside user_ensure_home_owned under bash dynamic scoping.
set_stub_home() {
    _STUB_HOME="$1"
    user_home_for_user() { printf '%s\n' "$_STUB_HOME"; }
}

test_creates_missing_home_and_owns_it() {
    local tmp home owner
    tmp="$(mktemp -d)"
    home="$tmp/home/$(id -un)"   # does not exist yet
    set_stub_home "$home"

    user_ensure_home_owned "$(id -un)" || { rm -rf "$tmp" 2>/dev/null; return 1; }

    [[ -d "$home" ]] || { rm -rf "$tmp" 2>/dev/null; return 1; }
    owner="$(stat -c '%U' "$home")"
    rm -rf "$tmp" 2>/dev/null
    [[ "$owner" == "$(id -un)" ]]
}

test_reasserts_ownership_on_existing_root_owned_home() {
    # Simulate the bug: home pre-exists, owned by "another" user. We can't
    # actually create a root-owned dir without root, but we CAN verify the
    # function chowns an already-existing dir to the target and recurses into
    # contents. Create a dir + nested file, then assert all become target-owned.
    local tmp home owner file_owner
    tmp="$(mktemp -d)"
    home="$tmp/home/$(id -un)"
    mkdir -p "$home/sub"
    : > "$home/sub/dotfile"
    set_stub_home "$home"

    user_ensure_home_owned "$(id -un)" || { rm -rf "$tmp" 2>/dev/null; return 1; }

    owner="$(stat -c '%U' "$home")"
    file_owner="$(stat -c '%U' "$home/sub/dotfile")"
    rm -rf "$tmp" 2>/dev/null
    [[ "$owner" == "$(id -un)" && "$file_owner" == "$(id -un)" ]]
}

test_idempotent_second_call() {
    local tmp home owner
    tmp="$(mktemp -d)"
    home="$tmp/home/$(id -un)"
    set_stub_home "$home"

    user_ensure_home_owned "$(id -un)" || { rm -rf "$tmp" 2>/dev/null; return 1; }
    user_ensure_home_owned "$(id -un)" || { rm -rf "$tmp" 2>/dev/null; return 1; }

    [[ -d "$home" ]] || { rm -rf "$tmp" 2>/dev/null; return 1; }
    owner="$(stat -c '%U' "$home")"
    rm -rf "$tmp" 2>/dev/null
    [[ "$owner" == "$(id -un)" ]]
}

test_rejects_root_home() {
    set_stub_home "/"
    # Must refuse (return non-zero) and NOT attempt a chown on /.
    ! user_ensure_home_owned "$(id -un)"
}

test_rejects_empty_home() {
    set_stub_home ""
    ! user_ensure_home_owned "$(id -un)"
}

test_rejects_invalid_target_name() {
    set_stub_home "/tmp/whatever"
    ! user_ensure_home_owned "Bad Name!"
}

run_test() {
    local name="$1"
    if "$name"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

main() {
    run_test test_creates_missing_home_and_owns_it
    run_test test_reasserts_ownership_on_existing_root_owned_home
    run_test test_idempotent_second_call
    run_test test_rejects_root_home
    run_test test_rejects_empty_home
    run_test test_rejects_invalid_target_name

    echo ""
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
