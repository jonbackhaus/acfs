#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for module-level install idempotency (gtbi-d8b)
# Covers:
#   - state_should_skip_phase re-entering a completed phase that is
#     missing a module (Change 2, scripts/lib/state.sh)
#   - the generated per-module install guard via gtbi_should_skip_module
#     (Change 1, packages/manifest/src/generate.ts -> install_helpers.sh)
# Run: bash scripts/lib/test_idempotency.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/install_helpers.sh"
source "$SCRIPT_DIR/state.sh"

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

# Isolate state_should_skip_phase to its completed-phase branch:
# pretend the phase is completed and that no --only selection is active.
state_is_phase_completed() { [[ "$1" == "stack" ]]; }
state_has_module_selection() { return 1; }

reset_maps() {
    unset GTBI_MODULE_PHASE GTBI_MODULE_INSTALLED_CHECK 2>/dev/null || true
    declare -gA GTBI_MODULE_PHASE=()
    declare -gA GTBI_MODULE_INSTALLED_CHECK=()
    ONLY_MODULES=()
    ONLY_PHASES=()
    : "${GTBI_FORCE_REINSTALL:=false}"
    export GTBI_FORCE_REINSTALL=false
}

# ------------------------------------------------------------
# Change 2: state_should_skip_phase re-entry
# ------------------------------------------------------------

test_completed_phase_reruns_when_module_missing() {
    local name="completed phase re-runs when a module is missing"
    reset_maps
    GTBI_MODULE_PHASE=( [stack.bd]="9" [stack.gastown]="9" )
    GTBI_MODULE_INSTALLED_CHECK=( [stack.bd]="command -v bd" [stack.gastown]="command -v gt" )
    gtbi_module_is_installed() { [[ "$1" == "stack.bd" ]]; }  # gastown absent

    if state_should_skip_phase "stack"; then
        test_fail "$name" "phase was skipped but gastown is missing"
    else
        test_pass "$name"
    fi
}

test_completed_phase_skips_when_all_present() {
    local name="completed phase stays skipped when all modules present"
    reset_maps
    GTBI_MODULE_PHASE=( [stack.bd]="9" [stack.gastown]="9" )
    GTBI_MODULE_INSTALLED_CHECK=( [stack.bd]="command -v bd" [stack.gastown]="command -v gt" )
    gtbi_module_is_installed() { return 0; }  # all present

    if state_should_skip_phase "stack"; then
        test_pass "$name"
    else
        test_fail "$name" "phase re-ran even though all modules present"
    fi
}

test_completed_phase_ignores_uncheckable_module() {
    local name="completed phase ignores module without installed_check"
    reset_maps
    GTBI_MODULE_PHASE=( [stack.bd]="9" [stack.gastown]="9" )
    GTBI_MODULE_INSTALLED_CHECK=( [stack.bd]="command -v bd" )  # gastown has no check
    gtbi_module_is_installed() { [[ "$1" == "stack.bd" ]]; }

    if state_should_skip_phase "stack"; then
        test_pass "$name"
    else
        test_fail "$name" "phase re-ran on account of an uncheckable module"
    fi
}

test_completed_phase_skips_when_maps_unavailable() {
    local name="completed phase skipped when index maps unavailable"
    reset_maps
    unset GTBI_MODULE_PHASE 2>/dev/null || true
    # Drop the real runner to simulate an environment without install_helpers;
    # restore it afterward so later tests still see it.
    unset -f gtbi_module_is_installed 2>/dev/null || true

    if state_should_skip_phase "stack"; then
        test_pass "$name"
    else
        test_fail "$name" "fallback fast-resume did not skip"
    fi

    # Restore the real gtbi_module_is_installed for the guard tests below.
    source "$SCRIPT_DIR/install_helpers.sh"
}

# ------------------------------------------------------------
# Change 1: gtbi_should_skip_module guard semantics
# ------------------------------------------------------------

test_guard_skips_present_module() {
    local name="gtbi_should_skip_module skips a present module"
    reset_maps
    GTBI_MANIFEST_INDEX_LOADED=true
    GTBI_MODULE_INSTALLED_CHECK=( [demo.tool]="true" )      # check passes -> present
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( [demo.tool]="current" )

    if gtbi_should_skip_module "demo.tool"; then
        test_pass "$name"
    else
        test_fail "$name" "present module was not skipped"
    fi
}

test_guard_runs_missing_module() {
    local name="gtbi_should_skip_module installs a missing module"
    reset_maps
    GTBI_MANIFEST_INDEX_LOADED=true
    GTBI_MODULE_INSTALLED_CHECK=( [demo.tool]="false" )     # check fails -> missing
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( [demo.tool]="current" )

    if gtbi_should_skip_module "demo.tool"; then
        test_fail "$name" "missing module was skipped"
    else
        test_pass "$name"
    fi
}

test_guard_bypassed_under_force_reinstall() {
    local name="gtbi_should_skip_module bypassed under --force-reinstall"
    reset_maps
    GTBI_MANIFEST_INDEX_LOADED=true
    GTBI_MODULE_INSTALLED_CHECK=( [demo.tool]="true" )      # present
    declare -gA GTBI_MODULE_INSTALLED_CHECK_RUN_AS=( [demo.tool]="current" )
    export GTBI_FORCE_REINSTALL=true

    if gtbi_should_skip_module "demo.tool"; then
        test_fail "$name" "force-reinstall did not bypass the skip guard"
    else
        test_pass "$name"
    fi
    export GTBI_FORCE_REINSTALL=false
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "GTBI Idempotency Tests (gtbi-d8b)"
echo "================================="
echo ""

test_completed_phase_reruns_when_module_missing
test_completed_phase_skips_when_all_present
test_completed_phase_ignores_uncheckable_module
test_completed_phase_skips_when_maps_unavailable
test_guard_skips_present_module
test_guard_runs_missing_module
test_guard_bypassed_under_force_reinstall

echo ""
echo "================================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
