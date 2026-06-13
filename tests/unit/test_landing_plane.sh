#!/usr/bin/env bash
# ============================================================
# Unit tests for gtbi landing-plane closeout assistant
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANDING_PLANE_SH="$REPO_ROOT/scripts/lib/landing_plane.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${GTBI_LANDING_PLANE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/gtbi-landing-plane-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
    return 0
}

write_status_file() {
    local name="$1"
    local body="$2"
    local path="$ARTIFACT_DIR/$name.status"

    printf '%s\n' "$body" > "$path"
    printf '%s\n' "$path"
}

run_landing_json() {
    local status_file="$1"
    local in_progress_json="$2"
    local gates_passed="$3"

    env \
        GTBI_LAND_GIT_STATUS_FILE="$status_file" \
        GTBI_LAND_IN_PROGRESS_JSON="$in_progress_json" \
        GTBI_LAND_GATES_PASSED="$gates_passed" \
        bash "$LANDING_PLANE_SH" --json
}

assert_no_forbidden_copy() {
    local output="$1"

    if grep -Eq '(^|[[:space:]])bv($|[[:space:]])|(^|[[:space:]])bd($|[[:space:]])|git reset|git clean|rm -rf|(^|[[:space:]])cargo (build|test|clippy)' <<<"$output"; then
        printf '%s\n' "$output" > "$ARTIFACT_DIR/forbidden-output.json"
        return 1
    fi
}

test_clean_session_passes() {
    local status_file output
    status_file="$(write_status_file clean "")"
    output="$(run_landing_json "$status_file" '{"issues":[]}' true)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/clean.json"

    jq -e '
      .status == "pass" and
      (.changed_files | length) == 0 and
      .quality_gates.status == "pass" and
      .beads.status == "pass" and
      .beads.sync_status == "clean" and
      (has("agent_mail") | not) and
      (has("reservations") | not) and
      (.next_commands | length) == 0
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "clean_session_passes"
}

test_dirty_session_prints_exact_gates_and_staging() {
    local status_file output
    status_file="$(write_status_file dirty $' M scripts/lib/foo.sh\n?? tests/unit/test_foo.sh\n M .beads/beads.db')"
    output="$(run_landing_json "$status_file" '{"issues":[{"id":"bd-r86ef"}]}' false)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/dirty.json"

    jq -e '
      .status == "warn" and
      (.changed_files | index("scripts/lib/foo.sh")) != null and
      (.changed_files | index("tests/unit/test_foo.sh")) != null and
      .quality_gates.status == "warn" and
      .beads.sync_status == "needs_sync" and
      (.beads.in_progress_ids | index("bd-r86ef")) != null and
      any(.next_commands[]; startswith("shellcheck ") and contains("scripts/lib/foo.sh") and contains("tests/unit/test_foo.sh")) and
      any(.next_commands[]; . == "shellcheck install.sh scripts/**/*.sh") and
      any(.next_commands[]; startswith("ubs ")) and
      any(.next_commands[]; startswith("git add -- ")) and
      any(.next_commands[]; . == "br sync --flush-only") and
      any(.next_commands[]; . == "git commit -m \"close out session work\"") and
      any(.next_commands[]; . == "git push origin main")
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "dirty_session_prints_exact_gates_and_staging"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    run_test test_clean_session_passes
    run_test test_dirty_session_prints_exact_gates_and_staging

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
