#!/usr/bin/env bash
# ============================================================
# GTBI Landing Plane - read-only closeout checklist
#
# Builds an auditable end-of-session checklist for Beads, quality gates,
# exact-file staging, and handoff.
# ============================================================

set -euo pipefail

LANDING_JSON=false
LANDING_GATES_PASSED="${GTBI_LAND_GATES_PASSED:-false}"
LANDING_THREAD_ID="${GTBI_LAND_THREAD_ID:-}"
LANDING_COMMIT_MESSAGE="${GTBI_LAND_COMMIT_MESSAGE:-close out session work}"

LANDING_CHANGED_FILES=()
LANDING_SHELL_FILES=()
LANDING_ZSH_FILES=()
LANDING_RUST_FILES=()
LANDING_BEADS_DB_DIRTY=false
LANDING_BEADS_JSONL_DIRTY=false
LANDING_BEADS_SYNC_STATUS="unknown"
LANDING_BEADS_IN_PROGRESS_IDS=()
LANDING_NEXT_COMMANDS=()
LANDING_WARNINGS=()

LANDING_GATES_STATUS="pass"
LANDING_BEADS_STATUS="pass"
LANDING_STATUS="pass"

declare -gA LANDING_CHANGED_SEEN=()
declare -gA LANDING_COMMAND_SEEN=()

landing_usage() {
    cat <<'EOF'
Usage: gtbi landing-plane [OPTIONS]

Read-only closeout assistant for agent work sessions.

Options:
  --json              Emit machine-readable JSON
  --gates-passed      Mark quality gates as already completed
  --thread-id ID      Beads issue id for completion handoff
  --commit-message M  Commit message placeholder for the suggested commit
  --help, -h          Show this help

Environment for tests or nonstandard shells:
  GTBI_LAND_GIT_STATUS_FILE       File containing git status --porcelain=v1 output
  GTBI_LAND_IN_PROGRESS_JSON      br list --status in_progress --json payload or file path
  GTBI_LAND_GATES_PASSED=true     Same as --gates-passed
EOF
}

landing_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                LANDING_JSON=true
                shift
                ;;
            --gates-passed)
                LANDING_GATES_PASSED=true
                shift
                ;;
            --thread-id)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --thread-id requires an id" >&2
                    return 2
                fi
                LANDING_THREAD_ID="$2"
                shift 2
                ;;
            --commit-message)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --commit-message requires a message" >&2
                    return 2
                fi
                LANDING_COMMIT_MESSAGE="$2"
                shift 2
                ;;
            --help|-h)
                landing_usage
                exit 0
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'gtbi landing-plane --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

landing_binary_path() {
    local name="${1:-}"
    local path_value=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$path_value" && -x "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

landing_bool_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

landing_read_payload() {
    local value="${1:-}"

    if [[ -n "$value" && -f "$value" ]]; then
        cat "$value"
    else
        printf '%s\n' "$value"
    fi
}

landing_add_warning() {
    LANDING_WARNINGS+=("$1")
}

landing_add_command() {
    local command_text="$1"

    [[ -n "$command_text" ]] || return 0
    if [[ -z "${LANDING_COMMAND_SEEN[$command_text]+x}" ]]; then
        LANDING_NEXT_COMMANDS+=("$command_text")
        LANDING_COMMAND_SEEN[$command_text]=1
    fi
}

landing_quote_args() {
    local quoted=""
    local arg=""
    local piece=""

    for arg in "$@"; do
        printf -v piece '%q' "$arg"
        quoted+="${quoted:+ }$piece"
    done
    printf '%s\n' "$quoted"
}

landing_git_status_output() {
    local git_bin=""
    local output=""
    local exit_status=0

    if [[ -n "${GTBI_LAND_GIT_STATUS_FILE:-}" ]]; then
        cat "$GTBI_LAND_GIT_STATUS_FILE"
        return 0
    fi

    git_bin="$(landing_binary_path git 2>/dev/null || true)"
    if [[ -z "$git_bin" ]]; then
        landing_add_warning "git not found; changed-file detection is unavailable"
        return 0
    fi

    set +e
    output="$("$git_bin" status --porcelain=v1 2>/dev/null)"
    exit_status=$?
    set -e
    if [[ $exit_status -ne 0 ]]; then
        landing_add_warning "git status failed; run inside a git worktree for exact-file closeout"
        return 0
    fi

    printf '%s\n' "$output"
}

landing_add_changed_file() {
    local path="$1"

    [[ -n "$path" ]] || return 0
    if [[ -z "${LANDING_CHANGED_SEEN[$path]+x}" ]]; then
        LANDING_CHANGED_FILES+=("$path")
        LANDING_CHANGED_SEEN[$path]=1
    fi
}

landing_classify_changed_file() {
    local path="$1"

    case "$path" in
        .beads/beads.db) LANDING_BEADS_DB_DIRTY=true ;;
        .beads/issues.jsonl) LANDING_BEADS_JSONL_DIRTY=true ;;
    esac

    case "$path" in
        install.sh|*.sh|scripts/gtbi-*)
            LANDING_SHELL_FILES+=("$path")
            ;;
    esac

    case "$path" in
        *.zsh|*.zshrc|gtbi/zsh/*)
            LANDING_ZSH_FILES+=("$path")
            ;;
    esac

    case "$path" in
        *.rs|Cargo.toml|Cargo.lock|*/Cargo.toml|*/Cargo.lock)
            LANDING_RUST_FILES+=("$path")
            ;;
    esac
}

landing_collect_changed_files() {
    local status_output=""
    local line=""
    local path=""

    status_output="$(landing_git_status_output)"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        path="${line:3}"
        if [[ "$path" == *" -> "* ]]; then
            path="${path##* -> }"
        fi
        landing_add_changed_file "$path"
        landing_classify_changed_file "$path"
    done <<<"$status_output"

    if [[ "$LANDING_BEADS_DB_DIRTY" == true && "$LANDING_BEADS_JSONL_DIRTY" != true ]]; then
        LANDING_BEADS_SYNC_STATUS="needs_sync"
    elif [[ "$LANDING_BEADS_JSONL_DIRTY" == true ]]; then
        LANDING_BEADS_SYNC_STATUS="export_changed"
    else
        LANDING_BEADS_SYNC_STATUS="clean"
    fi
}

landing_collect_beads() {
    local jq_bin="$1"
    local br_bin=""
    local payload=""
    local id=""

    if [[ -n "${GTBI_LAND_IN_PROGRESS_JSON:-}" ]]; then
        payload="$(landing_read_payload "$GTBI_LAND_IN_PROGRESS_JSON")"
    else
        br_bin="$(landing_binary_path br 2>/dev/null || true)"
        if [[ -n "$br_bin" ]]; then
            payload="$("$br_bin" list --status in_progress --json 2>/dev/null || true)"
        else
            landing_add_warning "br not found; Beads in-progress detection is unavailable"
        fi
    fi

    if [[ -n "$payload" ]] && printf '%s' "$payload" | "$jq_bin" . >/dev/null 2>&1; then
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            LANDING_BEADS_IN_PROGRESS_IDS+=("$id")
        done < <(printf '%s' "$payload" | "$jq_bin" -r '
            (if type == "array" then .
             else (.issues // .result // [])
             end)
            | .[]
            | .id? // empty
        ')
    elif [[ -n "$payload" ]]; then
        landing_add_warning "Beads in-progress payload was not valid JSON"
    fi

    if [[ -z "$LANDING_THREAD_ID" && ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -eq 1 ]]; then
        LANDING_THREAD_ID="${LANDING_BEADS_IN_PROGRESS_IDS[0]}"
    fi
}

landing_set_statuses_and_commands() {
    local quoted=""
    local id=""

    if [[ ${#LANDING_CHANGED_FILES[@]} -gt 0 ]]; then
        if landing_bool_true "$LANDING_GATES_PASSED"; then
            LANDING_GATES_STATUS="pass"
        else
            LANDING_GATES_STATUS="warn"
            landing_add_warning "quality gates are not marked complete for the changed files"
        fi

        landing_add_command "git diff --check"
        landing_add_command "git diff --cached --check"

        quoted="$(landing_quote_args "${LANDING_CHANGED_FILES[@]}")"
        landing_add_command "ubs $quoted"
        landing_add_command "git add -- $quoted"
    else
        LANDING_GATES_STATUS="pass"
    fi

    if [[ ${#LANDING_SHELL_FILES[@]} -gt 0 ]]; then
        quoted="$(landing_quote_args "${LANDING_SHELL_FILES[@]}")"
        landing_add_command "shellcheck $quoted"
        landing_add_command "shellcheck install.sh scripts/**/*.sh"
    fi

    if [[ ${#LANDING_ZSH_FILES[@]} -gt 0 ]]; then
        quoted="$(landing_quote_args "${LANDING_ZSH_FILES[@]}")"
        landing_add_command "zsh -n $quoted"
    fi

    if [[ ${#LANDING_RUST_FILES[@]} -gt 0 ]]; then
        landing_add_command "rch exec -- cargo test"
    fi

    if [[ "$LANDING_BEADS_SYNC_STATUS" == "needs_sync" ]]; then
        LANDING_BEADS_STATUS="warn"
        landing_add_warning "Beads database changed but .beads/issues.jsonl is not exported"
    elif [[ "$LANDING_BEADS_SYNC_STATUS" == "unknown" ]]; then
        LANDING_BEADS_STATUS="warn"
    fi

    if [[ ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -gt 0 ]]; then
        LANDING_BEADS_STATUS="warn"
        for id in "${LANDING_BEADS_IN_PROGRESS_IDS[@]}"; do
            landing_add_command "br close $id --reason \"Completed\""
        done
    fi

    if [[ ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -gt 0 || "$LANDING_BEADS_SYNC_STATUS" != "clean" ]]; then
        landing_add_command "br sync --flush-only"
    fi

    if [[ ${#LANDING_CHANGED_FILES[@]} -gt 0 ]]; then
        landing_add_command "git commit -m \"$LANDING_COMMIT_MESSAGE\""
        landing_add_command "git push origin main"
    fi

    LANDING_STATUS="pass"
    if [[ "$LANDING_GATES_STATUS" != "pass" || "$LANDING_BEADS_STATUS" != "pass" ]]; then
        LANDING_STATUS="warn"
    fi
}

landing_json_array() {
    local jq_bin="$1"
    shift

    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    printf '%s\n' "$@" | "$jq_bin" -R . | "$jq_bin" -s .
}

landing_build_report() {
    local jq_bin="$1"
    local changed_json=""
    local shell_json=""
    local zsh_json=""
    local rust_json=""
    local in_progress_json=""
    local commands_json=""
    local warnings_json=""

    changed_json="$(landing_json_array "$jq_bin" "${LANDING_CHANGED_FILES[@]}")"
    shell_json="$(landing_json_array "$jq_bin" "${LANDING_SHELL_FILES[@]}")"
    zsh_json="$(landing_json_array "$jq_bin" "${LANDING_ZSH_FILES[@]}")"
    rust_json="$(landing_json_array "$jq_bin" "${LANDING_RUST_FILES[@]}")"
    in_progress_json="$(landing_json_array "$jq_bin" "${LANDING_BEADS_IN_PROGRESS_IDS[@]}")"
    commands_json="$(landing_json_array "$jq_bin" "${LANDING_NEXT_COMMANDS[@]}")"
    warnings_json="$(landing_json_array "$jq_bin" "${LANDING_WARNINGS[@]}")"

    "$jq_bin" -n \
        --arg status "$LANDING_STATUS" \
        --arg gates_status "$LANDING_GATES_STATUS" \
        --arg beads_status "$LANDING_BEADS_STATUS" \
        --arg beads_sync_status "$LANDING_BEADS_SYNC_STATUS" \
        --arg thread_id "$LANDING_THREAD_ID" \
        --argjson changed_files "$changed_json" \
        --argjson shell_files "$shell_json" \
        --argjson zsh_files "$zsh_json" \
        --argjson rust_files "$rust_json" \
        --argjson in_progress_ids "$in_progress_json" \
        --argjson next_commands "$commands_json" \
        --argjson warnings "$warnings_json" \
        '{
            schema_version: 1,
            status: $status,
            warnings: $warnings,
            changed_files: $changed_files,
            quality_gates: {
                status: $gates_status,
                shell_files: $shell_files,
                zsh_files: $zsh_files,
                rust_files: $rust_files
            },
            beads: {
                status: $beads_status,
                sync_status: $beads_sync_status,
                in_progress_ids: $in_progress_ids,
                thread_id: $thread_id
            },
            next_commands: $next_commands
        }'
}

landing_emit_human() {
    local report="$1"
    local jq_bin="$2"

    echo "GTBI Landing Plane"
    echo "Status: $("${jq_bin}" -r '.status' <<<"$report")"
    echo ""

    echo "Changed files:"
    if [[ "$("${jq_bin}" -r '.changed_files | length' <<<"$report")" == "0" ]]; then
        echo "  none"
    else
        "${jq_bin}" -r '.changed_files[] | "  " + .' <<<"$report"
    fi

    echo ""
    echo "Checks:"
    "${jq_bin}" -r '"  quality_gates: " + .quality_gates.status' <<<"$report"
    "${jq_bin}" -r '"  beads:        " + .beads.status + " (sync=" + .beads.sync_status + ", thread=" + (.beads.thread_id // "") + ")"' <<<"$report"

    if [[ "$("${jq_bin}" -r '.warnings | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Warnings:"
        "${jq_bin}" -r '.warnings[] | "  " + .' <<<"$report"
    fi

    if [[ "$("${jq_bin}" -r '.next_commands | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Copyable closeout commands:"
        "${jq_bin}" -r '.next_commands[] | "  " + .' <<<"$report"
    fi

    echo ""
    echo "Handoff summary template:"
    echo "  Summary: <what changed>"
    echo "  Verification: <commands and results>"
    echo "  Remaining work: <none, or exact follow-up issue ids>"
}

landing_main() {
    landing_parse_args "$@"

    local jq_bin=""
    local report=""

    jq_bin="$(landing_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for gtbi landing-plane" >&2
        return 2
    fi

    landing_collect_changed_files
    landing_collect_beads "$jq_bin"
    landing_set_statuses_and_commands
    report="$(landing_build_report "$jq_bin")"

    if [[ "$LANDING_JSON" == true ]]; then
        printf '%s\n' "$report"
    else
        landing_emit_human "$report" "$jq_bin"
    fi
}

landing_main "$@"
