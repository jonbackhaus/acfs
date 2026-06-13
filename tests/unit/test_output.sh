#!/usr/bin/env bash
# ============================================================
# Unit tests for GTBI output formatting library (output.sh)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the output library
source "$PROJECT_ROOT/scripts/lib/output.sh"

TESTS_PASSED=0
TESTS_FAILED=0

pass() { ((TESTS_PASSED++)); echo "✅ PASS: $1"; }
fail() { ((TESTS_FAILED++)); echo "❌ FAIL: $1"; }

echo "=== GTBI Output Module Unit Tests ==="
echo ""

# Test 1: gtbi_resolve_format always resolves to json
echo "Test 1: gtbi_resolve_format resolves to json"
unset GTBI_OUTPUT_FORMAT

result=$(gtbi_resolve_format "json")
[[ "$result" == "json" ]] && pass "CLI json" || fail "CLI json (got: $result)"

result=$(gtbi_resolve_format "")
[[ "$result" == "json" ]] && pass "default json" || fail "default (got: $result)"

export GTBI_OUTPUT_FORMAT=json
result=$(gtbi_resolve_format "")
[[ "$result" == "json" ]] && pass "GTBI_OUTPUT_FORMAT=json" || fail "env (got: $result)"
unset GTBI_OUTPUT_FORMAT

# Test 2: gtbi_format_output passes JSON through unchanged
echo ""
echo "Test 2: gtbi_format_output JSON passthrough"
test_json='{"config": {"env": "test"}}'
result=$(gtbi_format_output "$test_json" "json")
[[ "$result" == "$test_json" ]] && pass "JSON passthrough" || fail "JSON passthrough (got: $result)"

# Format argument is ignored; output is always JSON
result=$(gtbi_format_output "$test_json")
[[ "$result" == "$test_json" ]] && pass "JSON passthrough (no format arg)" || fail "JSON passthrough no-arg (got: $result)"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]]
