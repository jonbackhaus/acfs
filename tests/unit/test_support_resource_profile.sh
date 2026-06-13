#!/usr/bin/env bash
# ============================================================
# Unit tests for support-bundle sanitized evidence
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${GTBI_SUPPORT_RESOURCE_PROFILE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/gtbi-support-resource-profile-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

test_support_capture_resource_profile_sanitizes_paths() {
    local home_dir bundle_dir profile_home output token_like
    home_dir="$ARTIFACT_DIR/home"
    bundle_dir="$ARTIFACT_DIR/bundle"
    token_like="ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD"
    profile_home="$ARTIFACT_DIR/profile-$token_like"
    mkdir -p "$home_dir" "$bundle_dir"

    output="$(env \
        HOME="$home_dir" \
        GTBI_RESOURCE_PROFILE_HOME="$profile_home" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_GTBI_HOME=""
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            RESOURCE_PROFILE_TIMEOUT=5
            BUNDLE_FILES=()
            capture_resource_profile_json "$BUNDLE_DIR"
            write_manifest "$BUNDLE_DIR"
            printf "%s\n" "${BUNDLE_FILES[*]}"
        ')"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/resource-profile.files"

    [[ -f "$bundle_dir/resource_profile.json" ]] || return 1
    [[ -f "$bundle_dir/manifest.json" ]] || return 1
    grep -qw "resource_profile.json" <<<"$output" || return 1

    jq -e '
      .schema_version == 1 and
      .mode == "dry-run" and
      .status == "pass" and
      .capture.status == "pass" and
      .safety.limited_to_gtbi_owned_files == true and
      .redaction.paths_redacted == true and
      .redaction.raw_paths_collected == false and
      .redaction.secrets_collected == false and
      (.managed_file_count | type == "number") and
      (.wrappers[] | select(.name == "gtbi-scope" and .command_present == false)) and
      (.wrappers[] | select(.name == "ccs" and .command_present == true))
    ' "$bundle_dir/resource_profile.json" >/dev/null || return 1

    ! grep -Fq "$profile_home" "$bundle_dir/resource_profile.json" || return 1
    ! grep -Fq "$token_like" "$bundle_dir/resource_profile.json" || return 1

    jq -e '
      .diagnostics.resource_profile.included == true and
      .diagnostics.resource_profile.summary.status == "pass" and
      .diagnostics.resource_profile.summary.mode == "dry-run" and
      .diagnostics.resource_profile.summary.paths_redacted == true and
      .diagnostics.resource_profile.summary.raw_paths_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1
    ! grep -Fq "$profile_home" "$bundle_dir/manifest.json" || return 1
    ! grep -Fq "$token_like" "$bundle_dir/manifest.json" || return 1

    pass "support_capture_resource_profile_sanitizes_paths"
}

run_test() {
    local name="$1"
    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required for support resource profile tests" >&2
        exit 1
    }

    run_test test_support_capture_resource_profile_sanitizes_paths

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
