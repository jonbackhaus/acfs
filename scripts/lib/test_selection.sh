#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for module selection logic (install_helpers.sh)
# Run: bash scripts/lib/test_selection.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
GTBI_MANIFEST_INDEX_LOADED=true  # Required by install_helpers.sh
# The selection logic is in install_helpers.sh (gtbi_resolve_selection, should_run_module)
source "$SCRIPT_DIR/install_helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    local name="$1"
    echo -e "\033[32m[PASS]\033[0m $name"
    ((++TESTS_PASSED))  # Use ++X to avoid exit on zero under set -e
}

test_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "\033[31m[FAIL]\033[0m $name"
    [[ -n "$reason" ]] && echo "       Reason: $reason"
    ((++TESTS_FAILED))  # Use ++X to avoid exit on zero under set -e
}

# Reset selection state for each test
reset_selection() {
    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false
    PRINT_PLAN=false
    GTBI_EFFECTIVE_PLAN=()
    GTBI_EFFECTIVE_RUN=()
    # Legacy flags
    SKIP_VAULT=false
    SKIP_POSTGRES=false
    SKIP_CLOUD=false
}

# ============================================================
# Test Cases
# ============================================================

test_default_selection() {
    local name="Default selection includes enabled_by_default modules"
    reset_selection

    if gtbi_resolve_selection; then
        # Check that default modules are included
        if should_run_module "lang.bun" && should_run_module "agents.claude"; then
            # Check that non-default modules are excluded
            if ! should_run_module "db.postgres18" && ! should_run_module "tools.vault"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_only_modules() {
    local name="--only selects specific modules with deps"
    reset_selection
    ONLY_MODULES=("agents.codex")

    if gtbi_resolve_selection; then
        # Should include agents.codex and its deps (lang.bun -> base.system)
        if should_run_module "agents.codex" && should_run_module "lang.bun" && should_run_module "base.system"; then
            # Should NOT include unrelated modules
            if ! should_run_module "lang.rust" && ! should_run_module "agents.claude"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_only_modules_no_deps() {
    local name="--only with --no-deps excludes dependencies"
    reset_selection
    ONLY_MODULES=("agents.codex")
    NO_DEPS=true

    if gtbi_resolve_selection 2>/dev/null; then
        # Should include only agents.codex
        if should_run_module "agents.codex"; then
            # Should NOT include deps
            if ! should_run_module "lang.bun" && ! should_run_module "base.system"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_skip_modules() {
    local name="--skip removes modules from plan"
    reset_selection
    SKIP_MODULES=("tools.atuin" "tools.zoxide")

    if gtbi_resolve_selection; then
        # Should not include skipped modules
        if ! should_run_module "tools.atuin" && ! should_run_module "tools.zoxide"; then
            # Should still include other default modules
            if should_run_module "lang.bun"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_skip_safety_violation() {
    local name="--skip fails when breaking dependencies"
    reset_selection
    ONLY_MODULES=("agents.codex")
    SKIP_MODULES=("lang.bun")  # agents.codex depends on lang.bun

    # This should fail because skipping lang.bun breaks agents.codex
    if ! gtbi_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should have failed due to dependency violation"
    fi
}

test_phase_selection() {
    local name="--only-phase selects all modules in phase"
    reset_selection
    ONLY_PHASES=("6")  # Phase 6: lang.*, tools.atuin, tools.zoxide, tools.ast_grep

    if gtbi_resolve_selection; then
        # Should include phase 6 modules
        if should_run_module "lang.bun" && should_run_module "lang.rust" && should_run_module "tools.atuin"; then
            # Should also include dependencies (base.system is phase 1)
            if should_run_module "base.system"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_phase_name_selection() {
    local name="--only-phase accepts named phase ids (agents)"
    reset_selection
    ONLY_PHASES=("agents")

    if gtbi_resolve_selection; then
        if should_run_module "agents.claude" && should_run_module "agents.codex"; then
            if should_run_module "lang.bun"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_unknown_module_error() {
    local name="Unknown module in --only returns error"
    reset_selection
    ONLY_MODULES=("nonexistent.module")

    if ! gtbi_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should have failed for unknown module"
    fi
}

test_unknown_skip_error() {
    local name="Unknown module in --skip returns error"
    reset_selection
    SKIP_MODULES=("nonexistent.module")

    if ! gtbi_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should have failed for unknown module"
    fi
}

test_plan_order() {
    local name="Plan follows manifest order (deps before dependents)"
    reset_selection
    ONLY_MODULES=("agents.codex")  # deps: lang.bun -> base.system

    if gtbi_resolve_selection; then
        # Find positions in plan
        local base_pos=-1 bun_pos=-1 codex_pos=-1
        local i=0
        for module_id in "${GTBI_EFFECTIVE_PLAN[@]}"; do
            case "$module_id" in
                "base.system") base_pos=$i ;;
                "lang.bun") bun_pos=$i ;;
                "agents.codex") codex_pos=$i ;;
            esac
            ((++i))  # Use ++i to avoid exit on zero under set -e
        done

        # Verify order: base < bun < codex
        if [[ $base_pos -lt $bun_pos && $bun_pos -lt $codex_pos ]]; then
            test_pass "$name"
            return
        fi
    fi
    test_fail "$name"
}

test_should_run_module() {
    local name="should_run_module returns correct results"
    reset_selection
    ONLY_MODULES=("lang.bun")

    if gtbi_resolve_selection; then
        if should_run_module "lang.bun" && should_run_module "base.system"; then
            if ! should_run_module "lang.rust"; then
                test_pass "$name"
                return
            fi
        fi
    fi
    test_fail "$name"
}

test_unknown_phase_error() {
    local name="Unknown phase in --only-phase returns error"
    reset_selection
    ONLY_PHASES=("99")  # Non-existent phase

    if ! gtbi_resolve_selection 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should have failed for unknown phase"
    fi
}

test_print_plan_deterministic() {
    local name="--print-plan produces deterministic output"
    reset_selection
    ONLY_MODULES=("agents.claude")
    PRINT_PLAN=true

    # Run selection twice and compare plans
    if gtbi_resolve_selection 2>/dev/null; then
        local plan1
        plan1="${GTBI_EFFECTIVE_PLAN[*]}"

        # Reset and run again
        GTBI_EFFECTIVE_PLAN=()
        GTBI_EFFECTIVE_RUN=()

        if gtbi_resolve_selection 2>/dev/null; then
            local plan2
            plan2="${GTBI_EFFECTIVE_PLAN[*]}"

            if [[ "$plan1" == "$plan2" ]]; then
                test_pass "$name"
                return
            else
                test_fail "$name" "Plans differ: '$plan1' vs '$plan2'"
                return
            fi
        fi
    fi
    test_fail "$name" "Failed to resolve selection"
}

# ============================================================
# Feature Flag Tests (mjt.5.6)
# ============================================================

test_feature_flag_default_unmigrated() {
    local name="Default: unmigrated categories use legacy"
    reset_selection

    unset GTBI_GENERATED_MIGRATED_CATEGORIES
    unset GTBI_USE_GENERATED_LANG
    unset GTBI_USE_GENERATED

    # Re-source to pick up default flag behavior
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/install_helpers.sh"

    if ! gtbi_use_generated_for_category "legacy_only"; then
        test_pass "$name"
    else
        test_fail "$name" "Expected legacy for unmigrated category"
    fi
}

test_feature_flag_migrated_default() {
    local name="Default: migrated categories use generated"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang,cli"
    unset GTBI_USE_GENERATED
    unset GTBI_USE_GENERATED_LANG

    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/install_helpers.sh"

    if gtbi_use_generated_for_category "lang" && gtbi_use_generated_for_category "cli"; then
        if ! gtbi_use_generated_for_category "agents"; then
            test_pass "$name"
            return
        fi
    fi

    test_fail "$name"
}

test_feature_flag_global_disable() {
    local name="Global=0 forces legacy (even for migrated categories)"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang"
    GTBI_USE_GENERATED=0
    unset GTBI_USE_GENERATED_LANG

    if ! gtbi_use_generated_for_category "lang"; then
        test_pass "$name"
    else
        test_fail "$name" "Expected legacy when global=0"
    fi
}

test_feature_flag_per_category_override_enable() {
    local name="Per-category=1 overrides global=0"
    reset_selection

    unset GTBI_GENERATED_MIGRATED_CATEGORIES
    GTBI_USE_GENERATED=0
    GTBI_USE_GENERATED_LANG=1

    if gtbi_use_generated_for_category "lang"; then
        test_pass "$name"
    else
        test_fail "$name" "Expected generated when per-category=1 even if global=0"
    fi

    unset GTBI_USE_GENERATED_LANG
}

test_feature_flag_per_category_override_disable() {
    local name="Per-category=0 overrides migrated default"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang"
    GTBI_USE_GENERATED=1
    GTBI_USE_GENERATED_LANG=0

    if ! gtbi_use_generated_for_category "lang"; then
        test_pass "$name"
    else
        test_fail "$name" "Expected legacy when per-category=0"
    fi

    unset GTBI_USE_GENERATED_LANG
}

test_feature_flag_module_extraction() {
    local name="gtbi_use_generated_for_module derives category from module id"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang"
    GTBI_USE_GENERATED=1
    unset GTBI_USE_GENERATED_LANG

    if ! gtbi_use_generated_for_module "agents.claude"; then
        if gtbi_use_generated_for_module "lang.bun"; then
            test_pass "$name"
            return
        fi
    fi

    test_fail "$name"
}

test_feature_flag_get_installer() {
    local name="gtbi_get_module_installer returns function name when enabled"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang"
    GTBI_USE_GENERATED=1
    unset GTBI_USE_GENERATED_LANG

    local func
    func="$(gtbi_get_module_installer "lang.bun")"

    if [[ "$func" == "install_lang_bun" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected install_lang_bun, got '$func'"
    fi
}

test_feature_flag_get_installer_disabled() {
    local name="gtbi_get_module_installer returns empty when disabled"
    reset_selection

    GTBI_GENERATED_MIGRATED_CATEGORIES="lang"
    GTBI_USE_GENERATED=1
    GTBI_USE_GENERATED_LANG=0

    local func
    func="$(gtbi_get_module_installer "lang.bun")"

    if [[ -z "$func" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected empty string, got '$func'"
    fi

    unset GTBI_USE_GENERATED_LANG
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "GTBI Selection Tests"
echo "===================="
echo ""

test_default_selection
test_only_modules
test_only_modules_no_deps
test_skip_modules
test_skip_safety_violation
test_phase_selection
test_phase_name_selection
test_unknown_module_error
test_unknown_skip_error
test_unknown_phase_error
test_plan_order
test_should_run_module
test_print_plan_deterministic
test_feature_flag_default_unmigrated
test_feature_flag_migrated_default
test_feature_flag_global_disable
test_feature_flag_per_category_override_enable
test_feature_flag_per_category_override_disable
test_feature_flag_module_extraction
test_feature_flag_get_installer
test_feature_flag_get_installer_disabled

echo ""
echo "===================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
