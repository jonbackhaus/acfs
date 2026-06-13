#!/usr/bin/env bash
# ============================================================
# GTBI Selection E2E Tests
#
# Tests selection semantics end-to-end by invoking install.sh
# with various flags and verifying outputs without running
# actual installations.
#
# Usage:
#   bash tests/vm/selection_e2e.sh
#
# These tests validate:
#   - --print-plan output format and stability
#   - --list-modules output format
#   - Selection error cases (unknown module, broken deps, etc.)
#   - Legacy flag mapping
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "\033[32m[PASS]\033[0m $1"
    ((++TESTS_PASSED))
}

fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "\033[31m[FAIL]\033[0m $name"
    [[ -n "$reason" ]] && echo "       Reason: $reason"
    ((++TESTS_FAILED))
}

# ============================================================
# Test Cases: --print-plan Output
# ============================================================

test_print_plan_exits_zero() {
    local name="--print-plan exits with code 0"
    if bash "$REPO_ROOT/install.sh" --print-plan >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name" "install.sh --print-plan exited with non-zero"
    fi
}

test_print_plan_shows_modules() {
    local name="--print-plan output lists module IDs"
    local output
    output=$(bash "$REPO_ROOT/install.sh" --print-plan 2>&1) || true

    # Should contain at least base.system and lang.bun (always in default plan)
    if echo "$output" | grep -q "base.system" && echo "$output" | grep -q "lang.bun"; then
        pass "$name"
    else
        fail "$name" "Expected base.system and lang.bun in output"
    fi
}

test_print_plan_is_deterministic() {
    local name="--print-plan output is deterministic (stable ordering)"
    local output1 output2

    output1=$(bash "$REPO_ROOT/install.sh" --print-plan 2>&1 | grep -E '^\s*[a-z]' | head -20) || true
    output2=$(bash "$REPO_ROOT/install.sh" --print-plan 2>&1 | grep -E '^\s*[a-z]' | head -20) || true

    if [[ "$output1" == "$output2" ]]; then
        pass "$name"
    else
        fail "$name" "Two runs produced different output"
    fi
}

test_print_plan_does_not_mutate_state() {
    local name="--print-plan does not create state file"
    local temp_home
    temp_home=$(mktemp -d)

    # GTBI_HOME points to the ~/.gtbi directory (not $HOME), so keep the path consistent
    # with install.sh behavior when overriding it for tests.
    GTBI_HOME="$temp_home/.gtbi" bash "$REPO_ROOT/install.sh" --print-plan >/dev/null 2>&1 || true

    if [[ ! -f "$temp_home/.gtbi/state.json" ]]; then
        pass "$name"
    else
        fail "$name" "State file was created"
    fi

    rm -rf "$temp_home"
}

test_print_plan_with_only() {
    local name="--print-plan --only lang.bun shows limited plan"
    local output
    output=$(bash "$REPO_ROOT/install.sh" --print-plan --only lang.bun 2>&1) || true

    # Should include lang.bun and base.system (dependency)
    local has_bun has_base has_rust
    has_bun=$(echo "$output" | grep -c "lang.bun" || true)
    has_base=$(echo "$output" | grep -c "base.system" || true)
    has_rust=$(echo "$output" | grep -c "lang.rust" || true)

    if [[ "$has_bun" -gt 0 && "$has_base" -gt 0 && "$has_rust" -eq 0 ]]; then
        pass "$name"
    else
        fail "$name" "Expected lang.bun+base.system, no lang.rust"
    fi
}

# ============================================================
# Test Cases: --list-modules Output
# ============================================================

test_list_modules_exits_zero() {
    local name="--list-modules exits with code 0"
    if bash "$REPO_ROOT/install.sh" --list-modules >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name" "install.sh --list-modules exited with non-zero"
    fi
}

test_list_modules_shows_all() {
    local name="--list-modules output includes expected modules"
    local output
    output=$(bash "$REPO_ROOT/install.sh" --list-modules 2>&1) || true

    # Check for a variety of modules across categories
    local missing=""
    for mod in "base.system" "lang.bun" "lang.rust" "agents.claude" "tools.atuin"; do
        if ! echo "$output" | grep -q "$mod"; then
            missing="$missing $mod"
        fi
    done

    if [[ -z "$missing" ]]; then
        pass "$name"
    else
        fail "$name" "Missing modules:$missing"
    fi
}

# ============================================================
# Test Cases: Selection Error Handling
# ============================================================

test_unknown_module_fails() {
    local name="--only with unknown module fails"
    if bash "$REPO_ROOT/install.sh" --print-plan --only nonexistent.module 2>&1; then
        fail "$name" "Should have failed for unknown module"
    else
        pass "$name"
    fi
}

test_unknown_skip_module_fails() {
    local name="--skip with unknown module fails"
    if bash "$REPO_ROOT/install.sh" --print-plan --skip nonexistent.module 2>&1; then
        fail "$name" "Should have failed for unknown module"
    else
        pass "$name"
    fi
}

test_broken_dependency_fails() {
    local name="--skip breaking dependency fails with message"
    local output rc

    # Run with set +e to capture exit code
    set +e
    output=$(bash "$REPO_ROOT/install.sh" --print-plan --only agents.codex --skip lang.bun 2>&1)
    rc=$?
    set -e

    # Should fail (non-zero exit) and mention dependency
    if [[ $rc -ne 0 ]] && echo "$output" | grep -qiE "depend|skip"; then
        pass "$name"
    else
        fail "$name" "Expected failure with dependency error message (rc=$rc)"
    fi
}

test_no_deps_prints_warning() {
    local name="--no-deps prints warning message"
    local output
    output=$(bash "$REPO_ROOT/install.sh" --print-plan --only agents.codex --no-deps 2>&1) || true

    if echo "$output" | grep -qi "warning"; then
        pass "$name"
    else
        fail "$name" "Expected warning about --no-deps"
    fi
}

# ============================================================
# Test Cases: Phase Selection
# ============================================================

test_only_phase_limits_selection() {
    local name="--only-phase limits to specific phase"
    local output
    output=$(bash "$REPO_ROOT/install.sh" --print-plan --only-phase 1 2>&1) || true

    # Phase 1 is base system, shouldn't include agents (phase 8+)
    local has_base has_agents
    has_base=$(echo "$output" | grep -c "base.system" || true)
    has_agents=$(echo "$output" | grep -c "agents.claude" || true)

    if [[ "$has_base" -gt 0 && "$has_agents" -eq 0 ]]; then
        pass "$name"
    else
        fail "$name" "Expected only phase 1 modules"
    fi
}

# ============================================================
# Run Tests
# ============================================================

main() {
    echo ""
    echo "GTBI Selection E2E Tests"
    echo "========================"
    echo ""

    # --print-plan tests
    test_print_plan_exits_zero
    test_print_plan_shows_modules
    test_print_plan_is_deterministic
    test_print_plan_does_not_mutate_state
    test_print_plan_with_only

    # --list-modules tests
    test_list_modules_exits_zero
    test_list_modules_shows_all

    # Error handling tests
    test_unknown_module_fails
    test_unknown_skip_module_fails
    test_broken_dependency_fails
    test_no_deps_prints_warning

    # Phase selection tests
    test_only_phase_limits_selection

    echo ""
    echo "========================"
    echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
    echo ""

    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
