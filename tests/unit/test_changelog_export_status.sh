#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# Targeted regression tests for changelog, export-config, and
# status output handling.
# Usage: bash tests/unit/test_changelog_export_status.sh
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANGELOG_SH="$REPO_ROOT/scripts/lib/changelog.sh"
EXPORT_CONFIG_SH="$REPO_ROOT/scripts/lib/export-config.sh"
STATUS_SH="$REPO_ROOT/scripts/lib/status.sh"
INFO_SH="$REPO_ROOT/scripts/lib/info.sh"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"
CHEATSHEET_SH="$REPO_ROOT/scripts/lib/cheatsheet.sh"
DASHBOARD_SH="$REPO_ROOT/scripts/lib/dashboard.sh"
DOCTOR_SH="$REPO_ROOT/scripts/lib/doctor.sh"
CONTINUE_SH="$REPO_ROOT/scripts/lib/continue.sh"
STATE_SH="$REPO_ROOT/scripts/lib/state.sh"
SMOKE_TEST_SH="$REPO_ROOT/scripts/lib/smoke_test.sh"
ONBOARD_SH="$REPO_ROOT/packages/onboard/onboard.sh"
PREFLIGHT_SH="$REPO_ROOT/scripts/preflight.sh"
NOTIFY_SH="$REPO_ROOT/scripts/lib/notify.sh"
WEBHOOK_SH="$REPO_ROOT/scripts/lib/webhook.sh"
NOTIFICATIONS_SH="$REPO_ROOT/scripts/lib/notifications.sh"
AUTOFIX_SH="$REPO_ROOT/scripts/lib/autofix.sh"
AUTOFIX_EXISTING_SH="$REPO_ROOT/scripts/lib/autofix_existing.sh"
UBUNTU_UPGRADE_SH="$REPO_ROOT/scripts/lib/ubuntu_upgrade.sh"
STACK_SH="$REPO_ROOT/scripts/lib/stack.sh"
CLI_TOOLS_SH="$REPO_ROOT/scripts/lib/cli_tools.sh"
AGENTS_SH="$REPO_ROOT/scripts/lib/agents.sh"
LANGUAGES_SH="$REPO_ROOT/scripts/lib/languages.sh"
GITHUB_API_SH="$REPO_ROOT/scripts/lib/github_api.sh"
NIGHTLY_UPDATE_SH="$REPO_ROOT/scripts/lib/nightly_update.sh"
OS_DETECT_SH="$REPO_ROOT/scripts/lib/os_detect.sh"
TEST_INSTALL_ARTIFACTS_SH="$REPO_ROOT/tests/vm/test_install_artifacts.sh"

source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

TEST_HOME=""
TEST_GTBI=""
TEST_REPO=""
TEST_INSTALL_HELPERS=""
TEST_MANIFEST_INDEX=""
TEST_ROOT_HOME=""
TEST_INSTALLED_GTBI=""
TEST_TARGET_HOME=""
TEST_FAKE_BIN=""
TEST_INSTALLED_HELPERS=""
TEST_INSTALLED_MANIFEST_INDEX=""
TEST_SYSTEM_STATE_FILE=""
TEST_DEV_REPO=""
RELATIVE_HOME=""
STALE_HOME=""
TEST_POISONED_GTBI_HOME=""

setup_mock_env() {
    TEST_HOME="$(mktemp -d)"
    TEST_GTBI="$TEST_HOME/.gtbi"
    TEST_REPO="$TEST_HOME/mock-repo"
    mkdir -p "$TEST_GTBI" "$TEST_REPO"

    cat > "$TEST_GTBI/state.json" <<'JSON'
{
  "mode": "vibe \"quoted\"",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON

    printf '1.2.3 "beta"\n' > "$TEST_GTBI/VERSION"

    cat > "$TEST_REPO/CHANGELOG.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-03-10

### Fixed
- Fixed "quoted" Windows path C:\temp
  Continued detail with	tab data

## [1.2.2] - 2026-03-01

### Added
- Legacy entry that should be filtered by the current state timestamp
EOF

    TEST_INSTALL_HELPERS="$TEST_HOME/mock_install_helpers.sh"
    TEST_MANIFEST_INDEX="$TEST_HOME/mock_manifest_index.sh"

    cat > "$TEST_INSTALL_HELPERS" <<EOF
#!/usr/bin/env bash
gtbi_module_is_installed() {
    [[ "\${TARGET_USER:-}" == "tester" ]] || return 1
    [[ "\${TARGET_HOME:-}" == "$TEST_HOME" ]] || return 1

    case "\$1" in
        alpha|'module "beta" \\\\ path') return 0 ;;
        *) return 1 ;;
    esac
}
EOF
    chmod +x "$TEST_INSTALL_HELPERS"

    cat > "$TEST_MANIFEST_INDEX" <<'EOF'
#!/usr/bin/env bash
GTBI_MODULES_IN_ORDER=(
  "alpha"
  "module \"beta\" \\\\ path"
  "gamma"
)
GTBI_MANIFEST_INDEX_LOADED=true
EOF
    chmod +x "$TEST_MANIFEST_INDEX"
}

write_fake_command() {
    local path="$1"
    local output="$2"
    cat > "$path" <<EOF
#!/usr/bin/env bash
echo '$output'
EOF
    chmod +x "$path"
}

setup_installed_layout_env() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_INSTALLED_GTBI="$TEST_HOME/installed/.gtbi"
    TEST_TARGET_HOME="$TEST_HOME/users/tester"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    TEST_INSTALLED_HELPERS="$TEST_HOME/installed_helpers.sh"
    TEST_INSTALLED_MANIFEST_INDEX="$TEST_HOME/installed_manifest_index.sh"

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_INSTALLED_GTBI/bin" \
        "$TEST_INSTALLED_GTBI/scripts/lib" \
        "$TEST_INSTALLED_GTBI/scripts/generated" \
        "$TEST_INSTALLED_GTBI/onboard/lessons" \
        "$TEST_TARGET_HOME/.oh-my-zsh" \
        "$TEST_TARGET_HOME/.local/bin" \
        "$TEST_TARGET_HOME/.bun/bin" \
        "$TEST_TARGET_HOME/.cargo/bin" \
        "$TEST_TARGET_HOME/go/bin" \
        "$TEST_TARGET_HOME/.atuin/bin" \
        "$TEST_FAKE_BIN"

    cp "$DOCTOR_SH" "$TEST_INSTALLED_GTBI/bin/gtbi"
    cp "$STATUS_SH" "$TEST_INSTALLED_GTBI/scripts/lib/status.sh"
    cp "$CHANGELOG_SH" "$TEST_INSTALLED_GTBI/scripts/lib/changelog.sh"
    cp "$EXPORT_CONFIG_SH" "$TEST_INSTALLED_GTBI/scripts/lib/export-config.sh"
    cp "$INFO_SH" "$TEST_INSTALLED_GTBI/scripts/lib/info.sh"
    cp "$SUPPORT_SH" "$TEST_INSTALLED_GTBI/scripts/lib/support.sh"
    cp "$CONTINUE_SH" "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
    printf '2.0.0\n' > "$TEST_INSTALLED_GTBI/VERSION"

    cat > "$TEST_INSTALLED_GTBI/CHANGELOG.md" <<'EOF'
# Changelog

## [2.0.0] - 2026-03-10

### Fixed
- Installed-layout root discovery now works correctly

## [1.9.0] - 2026-02-01

### Added
- Older entry that should be filtered out by last_updated
EOF
    printf '# Installed Lesson\n' > "$TEST_INSTALLED_GTBI/onboard/lessons/01_intro.md"

    cat > "$TEST_INSTALLED_HELPERS" <<EOF
#!/usr/bin/env bash
gtbi_module_is_installed() {
    [[ "\${TARGET_USER:-}" == "tester" ]] || return 1
    [[ "\${TARGET_HOME:-}" == "$TEST_TARGET_HOME" ]] || return 1

    case "\$1" in
        alpha|'module "beta" \\\\ path') return 0 ;;
        *) return 1 ;;
    esac
}
EOF
    chmod +x "$TEST_INSTALLED_HELPERS"

    cat > "$TEST_INSTALLED_MANIFEST_INDEX" <<'EOF'
#!/usr/bin/env bash
GTBI_MODULES_IN_ORDER=(
  "alpha"
  "module \"beta\" \\\\ path"
  "gamma"
)
GTBI_MANIFEST_INDEX_LOADED=true
EOF
    chmod +x "$TEST_INSTALLED_MANIFEST_INDEX"

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    cat > "$TEST_FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/systemctl"

    write_fake_command "$TEST_TARGET_HOME/.local/bin/zsh" "zsh 5.9"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/git" "git version 2.43.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/tmux" "tmux 3.4"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rg" "ripgrep 14.1.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/uv" "uv 0.8.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rustc" "rustc 1.85.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/ntm" "ntm 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.bun/bin/bun" "1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.cargo/bin/cargo" "cargo 1.85.0"
    write_fake_command "$TEST_TARGET_HOME/go/bin/go" "go version go1.24.0 linux/amd64"
}

setup_cross_home_bin_dir_env() {
    setup_installed_layout_env

    STALE_HOME="$TEST_HOME/users/staleuser"
    mkdir -p "$STALE_HOME/.local/bin"

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\$#" -eq 1 ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    echo "staleuser:x:1001:1001::${STALE_HOME}:/bin/bash"
    exit 0
fi
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "staleuser" ]]; then
    echo "staleuser:x:1001:1001::${STALE_HOME}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"
}

setup_poisoned_gtbi_home() {
    TEST_POISONED_GTBI_HOME="$TEST_HOME/poisoned/.gtbi"
    mkdir -p "$TEST_POISONED_GTBI_HOME/onboard/lessons" "$TEST_POISONED_GTBI_HOME/zsh" "$TEST_POISONED_GTBI_HOME/logs"

    cat > "$TEST_POISONED_GTBI_HOME/state.json" <<'JSON'
{
  "mode": "poison",
  "target_user": "tester",
  "target_home": "/poison/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z",
  "current_phase": { "id": "poison" },
  "current_step": "Poisoned state"
}
JSON
    printf '9.9.9\n' > "$TEST_POISONED_GTBI_HOME/VERSION"

    cat > "$TEST_POISONED_GTBI_HOME/CHANGELOG.md" <<'EOF'
# Changelog

## [9.9.9] - 2030-01-01

### Added
- Poisoned entry
EOF
    printf '# Poison Lesson\n' > "$TEST_POISONED_GTBI_HOME/onboard/lessons/01_poison.md"
    cat > "$TEST_POISONED_GTBI_HOME/zsh/gtbi.zshrc" <<'EOF'
alias poisoned='trap'
EOF
    printf 'poison install log\n' > "$TEST_POISONED_GTBI_HOME/logs/install-poison.log"
}

setup_system_state_only_env() {
    setup_installed_layout_env

    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    mkdir -p "$(dirname "$TEST_SYSTEM_STATE_FILE")"
    mv "$TEST_INSTALLED_GTBI/state.json" "$TEST_INSTALLED_GTBI/state.user.bak"

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools",
  "skipped_tools": ["ntm", "bv"]
}
EOF
}

setup_system_state_target_home_env() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_TARGET_HOME="$TEST_HOME/custom-home"
    TEST_INSTALLED_GTBI="$TEST_TARGET_HOME/.gtbi"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    TEST_INSTALLED_HELPERS="$TEST_HOME/installed_helpers.sh"
    TEST_INSTALLED_MANIFEST_INDEX="$TEST_HOME/installed_manifest_index.sh"

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_INSTALLED_GTBI/onboard/lessons" \
        "$TEST_TARGET_HOME/.oh-my-zsh" \
        "$TEST_TARGET_HOME/.local/bin" \
        "$TEST_TARGET_HOME/.bun/bin" \
        "$TEST_TARGET_HOME/.cargo/bin" \
        "$TEST_TARGET_HOME/go/bin" \
        "$TEST_TARGET_HOME/.atuin/bin" \
        "$TEST_FAKE_BIN" \
        "$(dirname "$TEST_SYSTEM_STATE_FILE")"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "/placeholder/overridden/by/system/state",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
JSON
    printf '2.0.0\n' > "$TEST_INSTALLED_GTBI/VERSION"

    cat > "$TEST_INSTALLED_GTBI/CHANGELOG.md" <<'EOF'
# Changelog

## [2.0.0] - 2026-03-10

### Fixed
- System-state target_home fallback now finds the real install
EOF

    printf '# Installed Lesson\n' > "$TEST_INSTALLED_GTBI/onboard/lessons/01_intro.md"

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_INSTALLED_HELPERS" <<EOF
#!/usr/bin/env bash
gtbi_module_is_installed() {
    [[ "\${TARGET_USER:-}" == "tester" ]] || return 1
    [[ "\${TARGET_HOME:-}" == "$TEST_TARGET_HOME" ]] || return 1

    case "\$1" in
        alpha|'module "beta" \\\\ path') return 0 ;;
        *) return 1 ;;
    esac
}
EOF
    chmod +x "$TEST_INSTALLED_HELPERS"

    cat > "$TEST_INSTALLED_MANIFEST_INDEX" <<'EOF'
#!/usr/bin/env bash
GTBI_MODULES_IN_ORDER=(
  "alpha"
  "module \"beta\" \\\\ path"
  "gamma"
)
GTBI_MANIFEST_INDEX_LOADED=true
EOF
    chmod +x "$TEST_INSTALLED_MANIFEST_INDEX"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    cat > "$TEST_FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/systemctl"

    write_fake_command "$TEST_TARGET_HOME/.local/bin/zsh" "zsh 5.9"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/git" "git version 2.43.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/tmux" "tmux 3.4"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rg" "ripgrep 14.1.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/uv" "uv 0.8.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rustc" "rustc 1.85.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/ntm" "ntm 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.bun/bin/bun" "1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.cargo/bin/cargo" "cargo 1.85.0"
    write_fake_command "$TEST_TARGET_HOME/go/bin/go" "go version go1.24.0 linux/amd64"
}

setup_system_state_target_home_only_env() {
    setup_system_state_target_home_env

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_home": "$TEST_TARGET_HOME",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
}

poison_installed_target_user() {
    local stale_user="${1:-stale-user}"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "$stale_user",
  "target_home": "/placeholder/overridden/by/system/state",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
}

setup_relative_home_trap() {
    RELATIVE_HOME="relative-home"
    STALE_HOME="$TEST_HOME/$RELATIVE_HOME"
    mkdir -p "$STALE_HOME/.gtbi"
}

cleanup_mock_env() {
    if [[ -n "$TEST_HOME" ]] && [[ -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME"
    fi
}

test_changelog_json_is_valid() {
    setup_mock_env

    local output
    output=$(GTBI_HOME="$TEST_GTBI" GTBI_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --all --json)

    if printf '%s\n' "$output" | jq -e '.changes | length == 2' >/dev/null 2>&1; then
        harness_pass "changelog JSON stays valid with quotes, backslashes, and tabs"
    else
        harness_fail "changelog JSON stays valid with quotes, backslashes, and tabs"
    fi

    cleanup_mock_env
}

test_changelog_rejects_invalid_duration() {
    setup_mock_env

    local output=""
    local exit_code=0
    output=$(GTBI_HOME="$TEST_GTBI" GTBI_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --since nonsense 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"invalid duration"* ]]; then
        harness_pass "changelog rejects malformed --since values"
    else
        harness_fail "changelog rejects malformed --since values" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_stack_is_installed_handles_unknown_tool_under_set_u() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
export TARGET_USER="ubuntu"
export TARGET_HOME="/tmp/gtbi-stack-test-home"
# shellcheck source=/dev/null
source "$STACK_SH"

if _stack_is_installed "does_not_exist"; then
    printf 'rc=0\n'
else
    printf 'rc=%s\n' "$?"
fi
EOF
    ); then
        if [[ "$output" == "rc=1" ]]; then
            harness_pass "stack helper returns false for unknown tool under set -u"
        else
            harness_fail "stack helper returns false for unknown tool under set -u" "$output"
        fi
    else
        harness_fail "stack helper returns false for unknown tool under set -u"
    fi
}

test_stack_is_installed_ignores_current_shell_only_path_entries() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
global_bin="$tmp_dir/global-bin"
mkdir -p "$target_home/.local/bin" "$global_bin"
cat > "$global_bin/current-shell-only-tool" <<'SCRIPT'
#!/usr/bin/env bash
echo current-shell-only-tool
SCRIPT
chmod +x "$global_bin/current-shell-only-tool"
export PATH="$global_bin:${PATH:-/usr/bin:/bin}"
export TARGET_USER="ubuntu"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$target_home/.local/bin"
# shellcheck source=/dev/null
source "$STACK_SH"
STACK_COMMANDS[ntm]="current-shell-only-tool"

if _stack_is_installed "ntm"; then
    printf 'rc=0\n'
else
    printf 'rc=%s\n' "$?"
fi
EOF
    ); then
        if [[ "$output" == "rc=1" ]]; then
            harness_pass "stack helper ignores current-shell-only PATH entries"
        else
            harness_fail "stack helper ignores current-shell-only PATH entries" "$output"
        fi
    else
        harness_fail "stack helper ignores current-shell-only PATH entries"
    fi
}

test_stack_target_has_command_finds_target_user_local_claude() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
mkdir -p "$target_home/.local/bin"
cat > "$target_home/.local/bin/claude" <<'SCRIPT'
#!/usr/bin/env bash
echo claude
SCRIPT
chmod +x "$target_home/.local/bin/claude"
export PATH="/usr/bin:/bin"
export TARGET_USER="ubuntu"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$target_home/.local/bin"
export GTBI_STACK_TRUST_TARGET_HOME=true
# shellcheck source=/dev/null
source "$STACK_SH"

resolved="$(_stack_target_command_path "claude" 2>/dev/null || true)"
if [[ "$resolved" == "$target_home/.local/bin/claude" ]] && _stack_target_has_command "claude"; then
    printf 'rc=0 path=%s\n' "$resolved"
else
    printf 'rc=%s path=%s\n' "$?" "$resolved"
fi
EOF
    ); then
        if [[ "$output" == "rc=0 path="*"/target-home/.local/bin/claude" ]]; then
            harness_pass "stack helper finds target-user local claude binary"
        else
            harness_fail "stack helper finds target-user local claude binary" "$output"
        fi
    else
        harness_fail "stack helper finds target-user local claude binary"
    fi
}

test_stack_target_home_ignores_invalid_explicit_target_home_before_passwd_fallback() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
stale_home="$tmp_dir/missing-target-home"
missing_current_home="$tmp_dir/missing-current-home"
target_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
resolved_home="$(getent passwd "$target_user" 2>/dev/null | awk -F: 'NR == 1 { print $6 }')"
if [[ -z "$resolved_home" && -r /etc/passwd ]]; then
    resolved_home="$(awk -F: -v user="$target_user" '$1 == user { print $6; exit }' /etc/passwd)"
fi
export PATH="/usr/bin:/bin"
export HOME="$missing_current_home"
export TARGET_USER="$target_user"
export TARGET_HOME="$stale_home"
# shellcheck source=/dev/null
source "$STACK_SH"

if [[ -z "$target_user" || -z "$resolved_home" || ! -d "$resolved_home" ]]; then
    printf 'rc=skip missing-current-passwd-context\n'
elif resolved="$(_stack_target_home 2>/dev/null)"; then
    if [[ "$resolved" == "$resolved_home" ]]; then
        printf 'rc=0 path=%s\n' "$resolved"
    else
        printf 'rc=mismatch path=%s expected=%s\n' "$resolved" "$resolved_home"
    fi
else
    printf 'rc=%s\n' "$?"
fi
EOF
    ); then
        if [[ "$output" == "rc=0 path="* ]]; then
            harness_pass "stack target_home ignores invalid explicit TARGET_HOME before passwd fallback"
        else
            harness_fail "stack target_home ignores invalid explicit TARGET_HOME before passwd fallback" "$output"
        fi
    else
        harness_fail "stack target_home ignores invalid explicit TARGET_HOME before passwd fallback"
    fi
}

test_stack_target_command_path_ignores_other_user_home_bin_dir_override() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
stale_home="$tmp_dir/stale-home"
fake_bin="$tmp_dir/fake-bin"
mkdir -p "$target_home/.local/bin" "$stale_home/.local/bin" "$fake_bin"
cat > "$fake_bin/getent" <<GETENT
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\$#" -eq 1 ]]; then
    printf '%s\n' "tester:x:1000:1000::${target_home}:/bin/bash"
    printf '%s\n' "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "tester" ]]; then
    printf '%s\n' "tester:x:1000:1000::${target_home}:/bin/bash"
    exit 0
fi
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "staleuser" ]]; then
    printf '%s\n' "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
exit 2
GETENT
cat > "$target_home/.local/bin/claude" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
cat > "$stale_home/.local/bin/claude" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$fake_bin/getent" "$target_home/.local/bin/claude" "$stale_home/.local/bin/claude"
export PATH="$fake_bin:/usr/bin:/bin"
export TARGET_USER="tester"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$stale_home/.local/bin"
# shellcheck source=/dev/null
source "$STACK_SH"

resolved="$(_stack_target_command_path claude 2>/dev/null || true)"
if [[ "$resolved" == "$target_home/.local/bin/claude" ]]; then
    printf 'source=live\n'
else
    printf 'path=%s\n' "$resolved"
fi
EOF
    ); then
        if [[ "$output" == "source=live" ]]; then
            harness_pass "stack target command path ignores other-user home bin-dir override"
        else
            harness_fail "stack target command path ignores other-user home bin-dir override" "$output"
        fi
    else
        harness_fail "stack target command path ignores other-user home bin-dir override"
    fi
}

test_stack_target_home_prefers_current_home_over_current_shell_only_getent() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
current_home="$tmp_dir/current-home"
stale_home="$tmp_dir/stale-home"
fake_bin="$tmp_dir/fake-bin"
mkdir -p "$current_home" "$stale_home" "$fake_bin"
cat > "$fake_bin/getent" <<GETENT
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s\n' "$current_user:x:1000:1000::${stale_home}:/bin/bash"
    exit 0
fi
exit 2
GETENT
chmod +x "$fake_bin/getent"
export PATH="$fake_bin:/usr/bin:/bin"
export TARGET_USER="$current_user"
unset TARGET_HOME || true
export HOME="$current_home"
# shellcheck source=/dev/null
source "$STACK_SH"

resolved="$(_stack_target_home "$current_user" 2>/dev/null || true)"
if [[ "$resolved" == "$current_home" ]]; then
    printf 'source=current-home\n'
else
    printf 'path=%s\n' "$resolved"
fi
EOF
    ); then
        if [[ "$output" == "source=current-home" ]]; then
            harness_pass "stack target_home prefers current HOME over current-shell-only getent"
        else
            harness_fail "stack target_home prefers current HOME over current-shell-only getent" "$output"
        fi
    else
        harness_fail "stack target_home prefers current HOME over current-shell-only getent"
    fi
}

test_stack_agent_mail_cli_path_ignores_current_shell_only_am() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
global_bin="$tmp_dir/global-bin"
mkdir -p "$target_home/.local/bin" "$global_bin"
cat > "$global_bin/am" <<'SCRIPT'
#!/usr/bin/env bash
echo am
SCRIPT
chmod +x "$global_bin/am"
export PATH="$global_bin:/usr/bin:/bin"
export TARGET_USER="ubuntu"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$target_home/.local/bin"
export GTBI_STACK_TRUST_TARGET_HOME=true
# shellcheck source=/dev/null
source "$STACK_SH"

if cli_path="$(_stack_agent_mail_cli_path 2>/dev/null)"; then
    printf 'rc=0 path=%s\n' "$cli_path"
else
    printf 'rc=%s\n' "$?"
fi
EOF
    ); then
        if [[ "$output" == "rc=1" ]]; then
            harness_pass "stack agent mail cli path ignores current-shell-only am"
        else
            harness_fail "stack agent mail cli path ignores current-shell-only am" "$output"
        fi
    else
        harness_fail "stack agent mail cli path ignores current-shell-only am"
    fi
}

test_stack_agent_mail_ready_ignores_current_shell_only_am() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
global_bin="$tmp_dir/global-bin"
mkdir -p "$target_home/.local/bin" "$global_bin"
cat > "$global_bin/am" <<'SCRIPT'
#!/usr/bin/env bash
echo am
SCRIPT
chmod +x "$global_bin/am"
cat > "$target_home/.local/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
case "$*" in
    *"/health")
        printf '%s\n' '{"status":"ready"}'
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT
chmod +x "$target_home/.local/bin/curl"
cat > "$target_home/.local/bin/systemctl" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$target_home/.local/bin/systemctl"
export PATH="$global_bin:/usr/bin:/bin"
export HOME="$target_home"
export TARGET_USER="ubuntu"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$target_home/.local/bin"
export GTBI_STACK_TRUST_TARGET_HOME=true
# shellcheck source=/dev/null
source "$STACK_SH"
_stack_run_as_user() {
    HOME="$TARGET_HOME" \
    GTBI_BIN_DIR="$GTBI_BIN_DIR" \
    PATH="$GTBI_BIN_DIR:${PATH:-/usr/bin:/bin}" \
    bash -c "$1"
}

if _stack_agent_mail_ready; then
    printf 'rc=0\n'
else
    printf 'rc=%s\n' "$?"
fi
EOF
    ); then
        if [[ "$output" == "rc=1" ]]; then
            harness_pass "stack agent mail ready ignores current-shell-only am"
        else
            harness_fail "stack agent mail ready ignores current-shell-only am" "$output"
        fi
    else
        harness_fail "stack agent mail ready ignores current-shell-only am"
    fi
}

test_stack_run_as_user_prefers_system_bins_over_current_shell_path() {
    local output=""

    if output=$(STACK_SH="$STACK_SH" bash <<'EOF'
set -u
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
target_home="$tmp_dir/target-home"
global_bin="$tmp_dir/global-bin"
current_user="$(id -un)"
mkdir -p "$target_home/.local/bin" "$global_bin"
cat > "$global_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
echo POISONED_CURL
SCRIPT
chmod +x "$global_bin/curl"
export PATH="$global_bin:/usr/bin:/bin"
export TARGET_USER="$current_user"
export TARGET_HOME="$target_home"
export GTBI_BIN_DIR="$target_home/.local/bin"
# shellcheck source=/dev/null
source "$STACK_SH"
resolved_curl="$(_stack_run_as_user 'command -v curl' 2>/dev/null || true)"
curl_banner="$(_stack_run_as_user 'curl --version 2>&1 | head -n1' 2>/dev/null || true)"
pwd_output="$(_stack_run_as_user pwd 2>/dev/null || true)"
printf 'curl=%s\nbanner=%s\npwd=%s\n' "$resolved_curl" "$curl_banner" "$pwd_output"
EOF
    ); then
        if [[ "$output" == *$'curl='* ]] \
            && [[ "$output" != *"banner=POISONED_CURL"* ]] \
            && [[ "$output" != *"/global-bin/curl"* ]] \
            && [[ "$output" == *$'pwd='* ]] \
            && [[ "$output" == *"pwd="*"/target-home"* ]]; then
            harness_pass "stack run-as-user prefers system bins over current-shell PATH"
        else
            harness_fail "stack run-as-user prefers system bins over current-shell PATH" "$output"
        fi
    else
        harness_fail "stack run-as-user prefers system bins over current-shell PATH"
    fi
}

test_notify_uses_target_home_for_config_and_state_when_home_is_relative() {
    setup_mock_env

    local target_home="$TEST_HOME/notify-target"
    mkdir -p "$target_home/.config/gtbi"

    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
ntfy_topic: target-topic
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_NOTIFY_SH_LOADED
            source "$1"
            printf "topic=%s\n" "$(_gtbi_notify_config_read ntfy_topic)"
            printf "state=%s\n" "${_GTBI_NOTIFY_STATE_DIR:-}"
        ' _ "$NOTIFY_SH" 2>&1)

    if [[ "$output" == *"topic=target-topic"* ]] \
        && [[ "$output" == *"state=$target_home/.cache/gtbi/notify"* ]]; then
        harness_pass "notify uses target_home for config and state when HOME is relative"
    else
        harness_fail "notify uses target_home for config and state when HOME is relative" "$output"
    fi

    cleanup_mock_env
}

test_notify_header_helpers_sanitize_control_characters() {
    setup_mock_env

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_NOTIFY_SH_LOADED
            source "$1"
            printf "title=<%s>\n" "$(_gtbi_notify_header_value "$2" "")"
            printf "priority=<%s>\n" "$(_gtbi_notify_priority_value "$3")"
            printf "tags=<%s>\n" "$(_gtbi_notify_header_value "$4" "computer,gtbi")"
        ' _ "$NOTIFY_SH" $'Agent\nDone' $'urgent\nTitle: hacked' $'computer\ngtbi' 2>&1)

    if [[ "$output" == *"title=<Agent Done>"* ]] \
        && [[ "$output" == *"priority=<default>"* ]] \
        && [[ "$output" == *"tags=<computer gtbi>"* ]] \
        && [[ "$output" != *"Title: hacked"* ]]; then
        harness_pass "notify header helpers sanitize control characters"
    else
        harness_fail "notify header helpers sanitize control characters" "$output"
    fi

    cleanup_mock_env
}

test_webhook_reads_config_from_target_home_when_home_is_relative() {
    setup_mock_env

    local target_home="$TEST_HOME/webhook-target"
    mkdir -p "$target_home/.config/gtbi"

    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
webhook_url: "https://example.com/hook"
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_WEBHOOK_SH_LOADED GTBI_WEBHOOK_URL
            source "$1"
            webhook_read_config
            printf "%s\n" "${GTBI_WEBHOOK_URL:-}"
        ' _ "$WEBHOOK_SH" 2>&1)

    if [[ "$output" == "https://example.com/hook" ]]; then
        harness_pass "webhook reads config from target_home when HOME is relative"
    else
        harness_fail "webhook reads config from target_home when HOME is relative" "$output"
    fi

    cleanup_mock_env
}

test_webhook_payload_rejects_non_ip_public_ip_response() {
    if ! command -v jq >/dev/null 2>&1; then
        harness_warn "jq not available — skipping webhook payload IP sanitization test"
        return 0
    fi

    setup_mock_env

    local fake_bin="$TEST_HOME/fake-bin"
    local output=""
    mkdir -p "$fake_bin"

    cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${GTBI_FAKE_CURL_RESPONSE:-}"
EOF
    chmod +x "$fake_bin/curl"

    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" GTBI_WEBHOOK_URL="https://example.com/hook" \
        GTBI_FAKE_CURL_RESPONSE="<html>temporarily unavailable</html>" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_WEBHOOK_SH_LOADED
            source "$1"
            fake_bin="$2"
            webhook_system_binary_path() {
                case "${1:-}" in
                    curl) printf "%s/curl\n" "$fake_bin" ;;
                    jq) command -v jq ;;
                    *) command -v "${1:-}" ;;
                esac
            }
            curl() { printf "%s\n" "198.51.100.77"; }
            webhook_format_payload success "" | jq -r ".ip"
        ' _ "$WEBHOOK_SH" "$fake_bin" 2>&1)

    if [[ "$output" == "unknown" ]]; then
        harness_pass "webhook payload rejects non-IP public IP response"
    else
        harness_fail "webhook payload rejects non-IP public IP response" "$output"
    fi

    cleanup_mock_env
}

test_webhook_public_ip_accepts_valid_ips_only() {
    setup_mock_env

    local fake_bin="$TEST_HOME/fake-bin"
    local output=""
    mkdir -p "$fake_bin"

    cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${GTBI_FAKE_CURL_RESPONSE:-}"
EOF
    chmod +x "$fake_bin/curl"

    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_WEBHOOK_SH_LOADED
            source "$1"
            fake_bin="$2"
            webhook_system_binary_path() {
                case "${1:-}" in
                    curl) printf "%s/curl\n" "$fake_bin" ;;
                    jq) command -v jq ;;
                    *) command -v "${1:-}" ;;
                esac
            }
            curl() { printf "%s\n" "bad-function-curl"; }
            export GTBI_FAKE_CURL_RESPONSE="203.0.113.9"
            printf "ipv4=%s\n" "$(webhook_public_ip)"
            export GTBI_FAKE_CURL_RESPONSE="2001:db8::1"
            printf "ipv6=%s\n" "$(webhook_public_ip)"
            export GTBI_FAKE_CURL_RESPONSE="bad:feed"
            printf "hex_words=%s\n" "$(webhook_public_ip)"
        ' _ "$WEBHOOK_SH" "$fake_bin" 2>&1)

    if [[ "$output" == *"ipv4=203.0.113.9"* ]] \
        && [[ "$output" == *"ipv6=2001:db8::1"* ]] \
        && [[ "$output" == *"hex_words=unknown"* ]]; then
        harness_pass "webhook public IP accepts valid IPs only"
    else
        harness_fail "webhook public IP accepts valid IPs only" "$output"
    fi

    cleanup_mock_env
}

test_webhook_payload_defaults_missing_summary_timestamp() {
    if ! command -v jq >/dev/null 2>&1; then
        harness_warn "jq not available — skipping webhook timestamp fallback test"
        return 0
    fi

    setup_mock_env

    local fake_bin="$TEST_HOME/fake-bin"
    local summary="$TEST_HOME/summary.json"
    local output=""
    mkdir -p "$fake_bin"

    cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "203.0.113.9"
EOF
    chmod +x "$fake_bin/curl"

    cat > "$summary" <<'EOF'
{
  "total_seconds": 7,
  "phases": [],
  "environment": {
    "gtbi_version": "test"
  }
}
EOF

    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" GTBI_WEBHOOK_URL="https://example.com/hook" \
        bash -c '
            log_warn() { :; }
            log_detail() { :; }
            unset _GTBI_WEBHOOK_SH_LOADED
            source "$1"
            fake_bin="$2"
            webhook_system_binary_path() {
                case "${1:-}" in
                    curl) printf "%s/curl\n" "$fake_bin" ;;
                    jq) command -v jq ;;
                    *) command -v "${1:-}" ;;
                esac
            }
            webhook_format_payload success "$3" | jq -r ".timestamp"
        ' _ "$WEBHOOK_SH" "$fake_bin" "$summary" 2>&1)

    if [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        harness_pass "webhook payload defaults missing summary timestamp"
    else
        harness_fail "webhook payload defaults missing summary timestamp" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_notify_uses_resolved_curl_path() {
    setup_mock_env

    local fake_bin="$TEST_HOME/fake-bin"
    local capture="$TEST_HOME/notify-curl-args"
    local poisoned="$TEST_HOME/poisoned-curl-used"
    local output=""

    mkdir -p "$fake_bin"

    cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
: > "$GTBI_CURL_CAPTURE"
while [[ $# -gt 0 ]]; do
    printf '<%s>\n' "$1" >> "$GTBI_CURL_CAPTURE"
    shift
done
EOF
    chmod +x "$fake_bin/curl"

    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" GTBI_NTFY_ENABLED=true \
        GTBI_NTFY_TOPIC=cli-topic GTBI_NTFY_SERVER=https://ntfy.example \
        GTBI_CURL_CAPTURE="$capture" GTBI_POISONED_CURL="$poisoned" \
        bash -c '
            unset _GTBI_NOTIFY_SH_LOADED
            source "$1"
            fake_bin="$2"
            _gtbi_notify_system_binary_path() {
                if [[ "${1:-}" == "curl" ]]; then
                    printf "%s/curl\n" "$fake_bin"
                    return 0
                fi
                command -v "${1:-}"
            }
            curl() { printf "poisoned\n" > "$GTBI_POISONED_CURL"; }
            gtbi_notify "Build Done" "" default
            for _ in {1..20}; do
                [[ -s "$GTBI_CURL_CAPTURE" ]] && break
                sleep 0.1
            done
            printf "capture=%s\npoisoned=%s\n" "$(cat "$GTBI_CURL_CAPTURE" 2>/dev/null || true)" "$(cat "$GTBI_POISONED_CURL" 2>/dev/null || true)"
        ' _ "$NOTIFY_SH" "$fake_bin" 2>&1)

    if [[ "$output" == *"<Title: Build Done>"* ]] \
        && [[ "$output" != *"poisoned=poisoned"* ]]; then
        harness_pass "gtbi_notify uses resolved curl path"
    else
        harness_fail "gtbi_notify uses resolved curl path" "$output"
    fi

    cleanup_mock_env
}

test_notifications_cli_uses_target_home_when_home_is_relative() {
    setup_mock_env

    local target_home="$TEST_HOME/notifications-target"
    mkdir -p "$target_home/.config/gtbi"

    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
ntfy_enabled: true
ntfy_topic: cli-topic
ntfy_server: https://ntfy.example
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        bash "$NOTIFICATIONS_SH" status 2>&1)

    if [[ "$output" == *"Topic:         cli-topic"* ]] \
        && [[ "$output" == *"Server:        https://ntfy.example"* ]] \
        && [[ "$output" == *"Config file:   $target_home/.config/gtbi/config.yaml"* ]]; then
        harness_pass "notifications CLI uses target_home when HOME is relative"
    else
        harness_fail "notifications CLI uses target_home when HOME is relative" "$output"
    fi

    cleanup_mock_env
}

test_notifications_cli_source_preserves_shell_options() {
    setup_mock_env

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$TEST_HOME" \
        bash -c '
            set +e +u +o pipefail
            source "$1"
            case "$-" in
                *e*) errexit=on ;;
                *) errexit=off ;;
            esac
            case "$-" in
                *u*) nounset=on ;;
                *) nounset=off ;;
            esac
            if [[ -o pipefail ]]; then
                pipefail=on
            else
                pipefail=off
            fi
            printf "errexit=%s nounset=%s pipefail=%s\n" "$errexit" "$nounset" "$pipefail"
        ' _ "$NOTIFICATIONS_SH" 2>&1)

    if [[ "$output" == "errexit=off nounset=off pipefail=off" ]]; then
        harness_pass "notifications CLI source preserves shell options"
    else
        harness_fail "notifications CLI source preserves shell options" "$output"
    fi

    cleanup_mock_env
}

test_notifications_cli_sanitizes_headers_before_curl() {
    setup_mock_env

    local target_home="$TEST_HOME/notifications-target"
    local fake_bin="$TEST_HOME/fake-bin"
    local capture="$TEST_HOME/curl-args"
    local output=""
    local invalid_output=""
    local invalid_status=0
    local headers=""

    mkdir -p "$target_home/.config/gtbi" "$fake_bin"

    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
ntfy_enabled: true
ntfy_topic: cli-topic
ntfy_server: https://ntfy.example
EOF

    cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
: > "$GTBI_CURL_CAPTURE"
while [[ $# -gt 0 ]]; do
    printf '<%s>\n' "$1" >> "$GTBI_CURL_CAPTURE"
    shift
done
printf '200'
EOF
    chmod +x "$fake_bin/curl"

    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        PATH="$fake_bin:/usr/bin:/bin" GTBI_CURL_CAPTURE="$capture" \
        bash -c '
            source "$1"
            fake_bin="$2"
            notifications_system_binary_path() {
                if [[ "${1:-}" == "curl" ]]; then
                    printf "%s/curl\n" "$fake_bin"
                    return 0
                fi
                command -v "${1:-}"
            }
            cmd_send "$3" "$4" "$5"
        ' _ "$NOTIFICATIONS_SH" "$fake_bin" $'Build\nDone' "" default 2>&1)
    headers="$(cat "$capture" 2>/dev/null || true)"
    : > "$capture"

    invalid_output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        PATH="$fake_bin:/usr/bin:/bin" GTBI_CURL_CAPTURE="$capture" \
        bash -c '
            source "$1"
            fake_bin="$2"
            notifications_system_binary_path() {
                if [[ "${1:-}" == "curl" ]]; then
                    printf "%s/curl\n" "$fake_bin"
                    return 0
                fi
                command -v "${1:-}"
            }
            cmd_send "$3" "$4" "$5"
        ' _ "$NOTIFICATIONS_SH" "$fake_bin" "Build" "" $'urgent\nTitle: hacked' 2>&1) || invalid_status=$?

    if [[ "$output" == *"Notification sent (HTTP 200)."* ]] \
        && [[ "$headers" == *"<Title: Build Done>"* ]] \
        && [[ "$headers" != *"<Title: hacked>"* ]] \
        && [[ $invalid_status -eq 1 ]] \
        && [[ "$invalid_output" == *"Error: Invalid priority 'urgent Title: hacked'"* ]] \
        && [[ ! -s "$capture" ]]; then
        harness_pass "notifications CLI sanitizes headers before curl"
    else
        harness_fail "notifications CLI sanitizes headers before curl" \
            "output=$output headers=$headers invalid_status=$invalid_status invalid_output=$invalid_output capture=$(cat "$capture" 2>/dev/null || true)"
    fi

    cleanup_mock_env
}

test_notifications_cli_reports_config_write_failure_when_sourced() {
    setup_mock_env

    local target_home="$TEST_HOME/notifications-target"
    local output=""

    mkdir -p "$target_home/.config/gtbi"
    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
ntfy_enabled: true
ntfy_topic: cli-topic
EOF

    output=$(cd "$TEST_HOME" && HOME="$target_home" TARGET_HOME="$target_home" \
        TMPDIR="$TEST_HOME/missing-tmp" bash -c '
            source "$1"
            status=0
            cmd_disable || status=$?
            printf "status=%s\n" "$status"
            cat "$GTBI_CONFIG_FILE"
        ' _ "$NOTIFICATIONS_SH" 2>&1)

    if [[ "$output" == *"Error: Unable to create temporary notification config file."* ]] \
        && [[ "$output" == *"status=1"* ]] \
        && [[ "$output" == *"ntfy_enabled: true"* ]] \
        && [[ "$output" != *"Notifications disabled."* ]]; then
        harness_pass "notifications CLI reports config write failure when sourced"
    else
        harness_fail "notifications CLI reports config write failure when sourced" "$output"
    fi

    cleanup_mock_env
}

test_notifications_cli_rejects_unsafe_topic_and_server_values() {
    setup_mock_env

    local target_home="$TEST_HOME/notifications-target"
    local output=""

    mkdir -p "$target_home/.config/gtbi"
    cat > "$target_home/.config/gtbi/config.yaml" <<'EOF'
ntfy_enabled: true
ntfy_topic: cli-topic
ntfy_server: https://ntfy.example
EOF

    output=$(cd "$TEST_HOME" && HOME="$target_home" TARGET_HOME="$target_home" \
        bash -c '
            source "$1"
            topic_status=0
            cmd_set_topic "$2" || topic_status=$?
            server_status=0
            cmd_set_server "$3" || server_status=$?
            printf "topic_status=%s\nserver_status=%s\n" "$topic_status" "$server_status"
            cat "$GTBI_CONFIG_FILE"
        ' _ "$NOTIFICATIONS_SH" $'bad\nntfy_enabled: false' $'https://ntfy.example\nntfy_enabled: false' 2>&1)

    if [[ "$output" == *"Error: Topic must be 1-128 characters"* ]] \
        && [[ "$output" == *"Error: Server URL must be an http(s) base URL"* ]] \
        && [[ "$output" == *"topic_status=1"* ]] \
        && [[ "$output" == *"server_status=1"* ]] \
        && [[ "$output" == *"ntfy_enabled: true"* ]] \
        && [[ "$output" == *"ntfy_topic: cli-topic"* ]] \
        && [[ "$output" == *"ntfy_server: https://ntfy.example"* ]] \
        && [[ "$output" != *"ntfy_enabled: false"* ]]; then
        harness_pass "notifications CLI rejects unsafe topic and server values"
    else
        harness_fail "notifications CLI rejects unsafe topic and server values" "$output"
    fi

    cleanup_mock_env
}

test_autofix_uses_target_home_for_state_dir_when_home_is_relative() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-target"
    mkdir -p "$target_home"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED
            source "$1"
            printf "%s\n" "$GTBI_STATE_DIR"
        ' _ "$AUTOFIX_SH" 2>&1)

    if [[ "$output" == "$target_home/.gtbi/autofix" ]]; then
        harness_pass "autofix uses target_home for state dir when HOME is relative"
    else
        harness_fail "autofix uses target_home for state dir when HOME is relative" "$output"
    fi

    cleanup_mock_env
}

test_autofix_repairs_stale_target_home_for_state_dir_from_passwd() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local stale_home="$TEST_HOME/autofix-stale-target"
    local output=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    if [[ -n "$current_user" ]]; then
        passwd_home="$(command getent passwd "$current_user" 2>/dev/null | cut -d: -f6)"
        passwd_home="${passwd_home%/}"
    fi
    if [[ -z "$current_user" || -z "$passwd_home" || "$passwd_home" != /* || ! -d "$passwd_home" ]]; then
        harness_skip "autofix repairs stale target_home for state dir from passwd" "could not resolve current user home"
        cleanup_mock_env
        return 0
    fi

    mkdir -p "$stale_home"

    output=$(HOME="$stale_home" TARGET_HOME="$stale_home" TARGET_USER="$current_user" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED
            source "$1"
            printf "%s\n" "$GTBI_STATE_DIR"
        ' _ "$AUTOFIX_SH" 2>&1)

    if [[ "$output" == "$passwd_home/.gtbi/autofix" ]]; then
        harness_pass "autofix repairs stale target_home for state dir from passwd"
    else
        harness_fail "autofix repairs stale target_home for state dir from passwd" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_detects_target_home_install_when_home_is_relative() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-target"
    mkdir -p "$target_home/.gtbi"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="relative-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            detect_existing_gtbi
        ' _ "$AUTOFIX_EXISTING_SH" 2>&1)

    if [[ "$output" == *"$target_home/.gtbi"* ]] && [[ "$output" != *"relative-home/.gtbi"* ]]; then
        harness_pass "autofix_existing detects target_home install when HOME is relative"
    else
        harness_fail "autofix_existing detects target_home install when HOME is relative" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_reads_target_home_version_under_root_home() {
    setup_mock_env

    local root_home="$TEST_HOME/root-home"
    local target_home="$TEST_HOME/autofix-existing-version-target"
    mkdir -p "$root_home/.gtbi" "$target_home/.gtbi"
    printf '0.0.1\n' > "$root_home/.gtbi/version"
    printf '9.9.9\n' > "$target_home/.gtbi/version"

    local output=""
    output=$(HOME="$root_home" TARGET_HOME="$target_home" PATH="/usr/bin:/bin" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            get_installed_version
        ' _ "$AUTOFIX_EXISTING_SH" 2>&1)

    if [[ "$output" == "9.9.9" ]]; then
        harness_pass "autofix_existing reads target_home version under root home"
    else
        harness_fail "autofix_existing reads target_home version under root home" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_prefers_target_home_over_poisoned_gtbi_home() {
    setup_mock_env

    local root_home="$TEST_HOME/root-home"
    local target_home="$TEST_HOME/autofix-existing-poison-target"
    local poisoned_gtbi_home="$TEST_HOME/poisoned/.gtbi"
    mkdir -p "$root_home" "$target_home/.gtbi" "$poisoned_gtbi_home"
    printf '8.8.8\n' > "$poisoned_gtbi_home/version"
    printf '9.9.9\n' > "$target_home/.gtbi/version"

    local output=""
    output=$(HOME="$root_home" TARGET_HOME="$target_home" GTBI_HOME="$poisoned_gtbi_home" PATH="/usr/bin:/bin" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            get_installed_version
        ' _ "$AUTOFIX_EXISTING_SH" 2>&1)

    if [[ "$output" == "9.9.9" ]]; then
        harness_pass "autofix_existing prefers target_home over poisoned GTBI_HOME"
    else
        harness_fail "autofix_existing prefers target_home over poisoned GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_preserves_distinct_relative_paths() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-backup-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local backup_dir=""
    backup_dir=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            create_installation_backup
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if [[ -d "$backup_dir/.config/gtbi" ]] && [[ -f "$backup_dir/.local/bin/gtbi" ]]; then
        harness_pass "autofix_existing backup preserves distinct relative paths"
    else
        harness_fail "autofix_existing backup preserves distinct relative paths" "$backup_dir"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_records_manifest_backups() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-target"
    mkdir -p "$target_home/.gtbi/bin" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf '#!/usr/bin/env bash\n' > "$target_home/.gtbi/bin/gtbi-real"
    chmod +x "$target_home/.gtbi/bin/gtbi-real"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    ln -s "$target_home/.gtbi/bin/gtbi-real" "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            clean_reinstall >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -c "{reversible: .reversible, backups: .backups}" "$GTBI_CHANGES_FILE"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .reversible == false
        and (.backups | type == "array")
        and (.backups | length > 0)
        and all(.backups[]; (.backup? != null) and (.original? != null))
        and all(.backups[]; ((.checksum // "") | length) > 0)
        and all(.backups[]; ((.path_type // "") | length) > 0)
        and any(.backups[]; .original == "'"$target_home"'/.local/bin/gtbi" and .path_type == "symlink")
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall records manifest backups"
    else
        harness_fail "autofix_existing clean reinstall records manifest backups" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_aborts_when_recording_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-record-fail-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            record_change() { return 1; }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                "{result: \$result, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall aborts before deletion when recording fails"
    else
        harness_fail "autofix_existing clean reinstall aborts before deletion when recording fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_aborts_when_backup_root_creation_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-backup-root-fail-target"
    local fake_bin="$TEST_HOME/fake-bin"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin" "$fake_bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    cat > "$fake_bin/mkdir" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    if [[ "\$arg" == "$target_home/.gtbi-backup-"* ]]; then
        exit 1
    fi
done
exec /bin/mkdir "\$@"
EOF
    chmod +x "$fake_bin/mkdir"

    local output=""
    output=$(PATH="$fake_bin:$PATH" HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                "{result: \$result, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall aborts when backup root creation fails"
    else
        harness_fail "autofix_existing clean reinstall aborts when backup root creation fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_aborts_when_state_relocation_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-relocate-fail-target"
    local fake_bin="$TEST_HOME/fake-bin"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin" "$fake_bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    cat > "$fake_bin/mv" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "$target_home/.gtbi/autofix" ]]; then
    exit 1
fi
exec /bin/mv "\$@"
EOF
    chmod +x "$fake_bin/mv"

    local output=""
    output=$(PATH="$fake_bin:$PATH" HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            change_count=$(jq -s "length" "$GTBI_CHANGES_FILE" 2>/dev/null || echo 0)
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg change_count "$change_count" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                "{result: \$result, change_count: \$change_count, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .change_count == "0"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall aborts when state relocation fails"
    else
        harness_fail "autofix_existing clean reinstall aborts when state relocation fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_restores_backup_after_artifact_removal_failure() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-restore-artifact-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f remove_gtbi_artifacts | sed '\''1s/remove_gtbi_artifacts/original_remove_gtbi_artifacts/'\'')"
            remove_gtbi_artifacts() {
                original_remove_gtbi_artifacts "$@" || return 1
                return 1
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
        and (.changes | length == 0)
        and (.undos | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall restores backup after artifact removal failure"
    else
        harness_fail "autofix_existing clean reinstall restores backup after artifact removal failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_preserves_journal_when_artifact_recovery_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-preserve-artifact-journal-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f remove_gtbi_artifacts | sed '\''1s/remove_gtbi_artifacts/original_remove_gtbi_artifacts/'\'')"
            remove_gtbi_artifacts() {
                original_remove_gtbi_artifacts "$@" || return 1
                return 1
            }
            autofix_existing_restore_installation_backup() { return 1; }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
        and (.changes | length > 0)
        and any(.changes[]; .description == "Clean reinstall - removed existing GTBI installation")
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall preserves journal when artifact recovery fails"
    else
        harness_fail "autofix_existing clean reinstall preserves journal when artifact recovery fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_recovery_preserves_preexisting_journal() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-preserve-journal-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f remove_gtbi_artifacts | sed '\''1s/remove_gtbi_artifacts/original_remove_gtbi_artifacts/'\'')"
            remove_gtbi_artifacts() {
                original_remove_gtbi_artifacts "$@" || return 1
                return 1
            }

            start_autofix_session >/dev/null 2>&1 || exit 1
            preexisting_change_id="$(record_change \
                "gtbi" \
                "Preexisting change" \
                ":" \
                false \
                "info" \
                "[]" \
                "[]" \
                "[]")" || exit 1
            undo_change "$preexisting_change_id" true true >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true

            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true

            jq -nc \
                --arg result "$result" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.changes[0].id) as $id
        | .result == "failure"
        and (.changes | length == 1)
        and (.changes[0].description == "Preexisting change")
        and (.undos | length == 2)
        and (([.undos[].status] | sort) == ["applied", "pending"])
        and (([.undos[].undone] | unique) == [$id])
        and ((reduce .undos[] as $undo ({}; .[$undo.undone] = ($undo.status // "applied")) | .[$id]) == "applied")
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall recovery preserves preexisting journal"
    else
        harness_fail "autofix_existing clean reinstall recovery preserves preexisting journal" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_drop_changes_since_restores_original_journals_on_late_replace_failure() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-drop-journal-target"
    mkdir -p "$target_home/.gtbi/autofix"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"

            start_autofix_session >/dev/null 2>&1 || exit 1
            record_change "gtbi" "Keep change" ":" false "info" "[]" "[]" "[]" > "$GTBI_STATE_DIR/keep.id" || exit 1
            record_change "gtbi" "Drop change" ":" false "info" "[]" "[]" "[]" > "$GTBI_STATE_DIR/drop.id" || exit 1
            keep_id="$(cat "$GTBI_STATE_DIR/keep.id")"
            drop_id="$(cat "$GTBI_STATE_DIR/drop.id")"
            undo_change "$drop_id" true true >/dev/null 2>&1 || exit 1

            before_changes="$(jq -sc . "$GTBI_CHANGES_FILE")"
            before_undos="$(jq -sc . "$GTBI_UNDOS_FILE")"
            before_order="$(printf "%s\n" "${GTBI_CHANGE_ORDER[@]}" | awk "NF" | jq -R . | jq -sc .)"

            real_mv="$(command -v mv)"
            mv() {
                local dest="${@: -1}"
                if [[ "$dest" == "$GTBI_UNDOS_FILE" ]]; then
                    return 1
                fi
                "$real_mv" "$@"
            }

            if autofix_existing_drop_changes_since 1 >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi

            after_changes="$(jq -sc . "$GTBI_CHANGES_FILE")"
            after_undos="$(jq -sc . "$GTBI_UNDOS_FILE")"
            after_order="$(printf "%s\n" "${GTBI_CHANGE_ORDER[@]}" | awk "NF" | jq -R . | jq -sc .)"
            end_autofix_session >/dev/null 2>&1 || true

            jq -nc \
                --arg result "$result" \
                --argjson before_changes "$before_changes" \
                --argjson after_changes "$after_changes" \
                --argjson before_undos "$before_undos" \
                --argjson after_undos "$after_undos" \
                --argjson before_order "$before_order" \
                --argjson after_order "$after_order" \
                "{result: \$result, before_changes: \$before_changes, after_changes: \$after_changes, before_undos: \$before_undos, after_undos: \$after_undos, before_order: \$before_order, after_order: \$after_order}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and (.before_changes == .after_changes)
        and (.before_undos == .after_undos)
        and (.before_order == .after_order)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing drop_changes_since restores original journals on late replace failure"
    else
        harness_fail "autofix_existing drop_changes_since restores original journals on late replace failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_uses_unique_dir_when_timestamp_collides() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-backup-collision-target"
    local fake_bin="$TEST_HOME/fake-bin"
    local fixed_stamp="20260415_000000"
    local stale_backup_dir="$target_home/.gtbi-backup-$fixed_stamp"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin" "$fake_bin" "$stale_backup_dir"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"
    printf 'stale\n' > "$stale_backup_dir/stale-marker"

    cat > "$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "+%Y%m%d_%H%M%S" ]]; then
    printf '20260415_000000\n'
    exit 0
fi
if [[ "${1:-}" == "-Iseconds" ]]; then
    printf '2026-04-15T00:00:00+00:00\n'
    exit 0
fi
exec /bin/date "$@"
EOF
    chmod +x "$fake_bin/date"

    local output=""
    output=$(PATH="$fake_bin:$PATH" HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            backup_dir=$(create_installation_backup) || exit 1
            jq -nc \
                --arg backup_dir "$backup_dir" \
                --arg stale_exists "$(test -f "$2/stale-marker" && echo yes || echo no)" \
                --arg stale_reused "$(if [[ "$backup_dir" == "$2" ]]; then echo yes; else echo no; fi)" \
                --arg manifest_exists "$(test -f "$backup_dir/manifest.json" && echo yes || echo no)" \
                "{backup_dir: \$backup_dir, stale_exists: \$stale_exists, stale_reused: \$stale_reused, manifest_exists: \$manifest_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" "$stale_backup_dir" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .stale_exists == "yes"
        and .stale_reused == "no"
        and .manifest_exists == "yes"
        and (.backup_dir | startswith("'"$target_home"'/.gtbi-backup-20260415_000000"))
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing backup uses unique dir when timestamp collides"
    else
        harness_fail "autofix_existing backup uses unique dir when timestamp collides" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_avoids_broken_symlink_collision() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-backup-broken-symlink-target"
    local fake_bin="$TEST_HOME/fake-bin"
    local fixed_stamp="20260415_000001"
    local stale_backup_dir="$target_home/.gtbi-backup-$fixed_stamp"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin" "$fake_bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"
    ln -s "$target_home/missing-backup-dir" "$stale_backup_dir"

    cat > "$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "+%Y%m%d_%H%M%S" ]]; then
    printf '20260415_000001\n'
    exit 0
fi
if [[ "${1:-}" == "-Iseconds" ]]; then
    printf '2026-04-15T00:00:01+00:00\n'
    exit 0
fi
exec /bin/date "$@"
EOF
    chmod +x "$fake_bin/date"

    local output=""
    output=$(PATH="$fake_bin:$PATH" HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            backup_dir=$(create_installation_backup) || exit 1
            jq -nc \
                --arg backup_dir "$backup_dir" \
                --arg stale_is_symlink "$(test -L "$2" && echo yes || echo no)" \
                --arg stale_reused "$(if [[ "$backup_dir" == "$2" ]]; then echo yes; else echo no; fi)" \
                --arg manifest_exists "$(test -f "$backup_dir/manifest.json" && echo yes || echo no)" \
                "{backup_dir: \$backup_dir, stale_is_symlink: \$stale_is_symlink, stale_reused: \$stale_reused, manifest_exists: \$manifest_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" "$stale_backup_dir" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .stale_is_symlink == "yes"
        and .stale_reused == "no"
        and .manifest_exists == "yes"
        and (.backup_dir | startswith("'"$target_home"'/.gtbi-backup-20260415_000001"))
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing backup avoids broken symlink collision"
    else
        harness_fail "autofix_existing backup avoids broken symlink collision" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_fsyncs_manifest_and_parent_dir() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-backup-fsync-target"
    local fsync_log="$TEST_HOME/fsync.log"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            FSYNC_LOG_PATH="$2"
            fsync_file() { printf "file:%s\n" "$1" >> "$FSYNC_LOG_PATH"; return 0; }
            fsync_directory() { printf "dir:%s\n" "$1" >> "$FSYNC_LOG_PATH"; return 0; }
            backup_dir=$(create_installation_backup) || exit 1
            manifest="$backup_dir/manifest.json"
            artifact_backup=$(jq -r --arg original "$TARGET_HOME/.config/gtbi" \
                ".backed_up_items[] | select(.original == \$original) | .backup" \
                "$manifest")
            jq -nc \
                --arg parent_synced "$(grep -Fx "dir:$(dirname "$backup_dir")" "$FSYNC_LOG_PATH" >/dev/null 2>&1 && echo yes || echo no)" \
                --arg artifact_synced "$(grep -Fx "dir:$artifact_backup" "$FSYNC_LOG_PATH" >/dev/null 2>&1 && echo yes || echo no)" \
                --arg manifest_synced "$(grep -Fx "file:$manifest" "$FSYNC_LOG_PATH" >/dev/null 2>&1 && echo yes || echo no)" \
                "{parent_synced: \$parent_synced, artifact_synced: \$artifact_synced, manifest_synced: \$manifest_synced}"
        ' _ "$AUTOFIX_EXISTING_SH" "$fsync_log" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .parent_synced == "yes"
        and .artifact_synced == "yes"
        and .manifest_synced == "yes"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing backup fsyncs manifest and parent dir"
    else
        harness_fail "autofix_existing backup fsyncs manifest and parent dir" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_restore_from_backup_fsyncs_restored_path() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-restore-sync-target"
    mkdir -p "$target_home"
    printf 'old\n' > "$target_home/config.toml"
    printf 'restored\n' > "$target_home/config.toml.backup"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            fsync_log="$TARGET_HOME/fsync.log"
            autofix_sync_backup_path() {
                printf "%s\n" "$1" >> "$fsync_log"
                return 0
            }
            backup_json=$(jq -cn \
                --arg original "$TARGET_HOME/config.toml" \
                --arg backup "$TARGET_HOME/config.toml.backup" \
                "{original: \$original, backup: \$backup}")
            if autofix_existing_restore_from_backup "$backup_json" "$TARGET_HOME/config.toml" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg contents "$(cat "$TARGET_HOME/config.toml" 2>/dev/null || true)" \
                --arg fsync_log "$(cat "$fsync_log" 2>/dev/null || true)" \
                "{result: \$result, contents: \$contents, fsync_log: \$fsync_log}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "success"
        and .contents == "restored"
        and (.fsync_log | contains("/config.toml"))
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing restore from backup fsyncs restored path"
    else
        harness_fail "autofix_existing restore from backup fsyncs restored path" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_cleans_partial_dir_after_copy_failure() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-backup-copy-fail-target"
    local fsync_log="$TEST_HOME/fsync.log"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            FSYNC_LOG_PATH="$2"
            cp() {
                local last="${@: -1}"
                if [[ "$last" == "$TARGET_HOME/.gtbi-backup-"* ]]; then
                    mkdir -p "$last"
                    return 1
                fi
                command cp "$@"
            }
            fsync_directory() { printf "dir:%s\n" "$1" >> "$FSYNC_LOG_PATH"; return 0; }
            if create_installation_backup >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg leftover_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-backup-*" | wc -l | tr -d " ")" \
                --arg parent_synced "$(grep -Fx "dir:$TARGET_HOME" "$FSYNC_LOG_PATH" >/dev/null 2>&1 && echo yes || echo no)" \
                "{result: \$result, leftover_count: \$leftover_count, parent_synced: \$parent_synced}"
        ' _ "$AUTOFIX_EXISTING_SH" "$fsync_log" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .leftover_count == "0"
        and .parent_synced == "yes"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing backup cleans partial dir after copy failure"
    else
        harness_fail "autofix_existing backup cleans partial dir after copy failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_artifacts_include_global_wrapper() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-artifacts-target"
    mkdir -p "$target_home"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            autofix_existing_artifacts | jq -R . | jq -s .
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        index("/usr/local/bin/gtbi") != null
        and index("'"$target_home"'/.gtbi") != null
        and index("'"$target_home"'/.local/bin/gtbi") != null
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing artifacts include global wrapper"
    else
        harness_fail "autofix_existing artifacts include global wrapper" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_backup_preserves_symlink_artifacts() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-symlink-backup-target"
    mkdir -p "$target_home/.gtbi/bin" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf '#!/usr/bin/env bash\n' > "$target_home/.gtbi/bin/gtbi-real"
    chmod +x "$target_home/.gtbi/bin/gtbi-real"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    ln -s "$target_home/.gtbi/bin/gtbi-real" "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            backup_dir=$(create_installation_backup) || exit 1
            original="$TARGET_HOME/.local/bin/gtbi"
            backup_path=$(jq -r --arg original "$original" \
                ".backed_up_items[] | select(.original == \$original) | .backup" \
                "$backup_dir/manifest.json")
            path_type=$(jq -r --arg original "$original" \
                ".backed_up_items[] | select(.original == \$original) | .path_type" \
                "$backup_dir/manifest.json")
            jq -nc \
                --arg path_type "$path_type" \
                --arg is_symlink "$(test -L "$backup_path" && echo yes || echo no)" \
                "{path_type: \$path_type, is_symlink: \$is_symlink}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .path_type == "symlink"
        and .is_symlink == "yes"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing backup preserves symlink artifacts"
    else
        harness_fail "autofix_existing backup preserves symlink artifacts" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_handles_broken_symlink_artifacts() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-broken-symlink-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    ln -s "$target_home/.gtbi/bin/missing-gtbi" "$target_home/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            markers=$(detect_existing_gtbi | tr " " "\n" | jq -R . | jq -s .)
            if remove_gtbi_artifacts >/dev/null 2>&1; then
                remove_result="success"
            else
                remove_result="failure"
            fi
            jq -nc \
                --argjson markers "$markers" \
                --arg remove_result "$remove_result" \
                --arg symlink_exists "$(test -L "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                "{markers: \$markers, remove_result: \$remove_result, symlink_exists: \$symlink_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.markers | index("'"$target_home"'/.local/bin/gtbi")) != null
        and .remove_result == "success"
        and .symlink_exists == "no"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing handles broken symlink artifacts"
    else
        harness_fail "autofix_existing handles broken symlink artifacts" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_shell_configs_records_changes() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-shell-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zshrc" <<'EOF'
# shell config
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_me=1
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            clean_shell_configs >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.file_contents | contains("keep_me=1"))
        and (.file_contents | contains(".gtbi") | not)
        and (.changes | length == 1)
        and (.changes[0].description | contains("Cleaned GTBI entries from"))
        and (.changes[0].reversible == true)
        and (.changes[0].backups | length == 1)
        and (.changes[0].backups[0].backup != null)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean shell configs records changes"
    else
        harness_fail "autofix_existing clean shell configs records changes" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_shell_configs_preserves_symlinked_config() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-shell-symlink-target"
    local dotfiles_home="$TEST_HOME/dotfiles"
    local real_config="$dotfiles_home/zshrc"
    mkdir -p "$target_home" "$dotfiles_home"
    cat > "$real_config" <<'EOF'
# shell config
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_me=1
EOF
    ln -s "$real_config" "$target_home/.zshrc"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            clean_shell_configs >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg symlink_exists "$(test -L "$TARGET_HOME/.zshrc" && echo yes || echo no)" \
                --arg symlink_target "$(readlink "$TARGET_HOME/.zshrc" 2>/dev/null || true)" \
                --arg file_contents "$(cat "$2")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{symlink_exists: \$symlink_exists, symlink_target: \$symlink_target, file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" "$real_config" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .symlink_exists == "yes"
        and .symlink_target == "'"$real_config"'"
        and (.file_contents | contains("keep_me=1"))
        and (.file_contents | contains(".gtbi") | not)
        and (.changes | length == 1)
        and any(.changes[0].files_affected[]; . == "'"$target_home"'/.zshrc")
        and any(.changes[0].files_affected[]; . == "'"$real_config"'")
        and (.changes[0].backups | length == 1)
        and (.changes[0].backups[0].original == "'"$real_config"'")
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean shell configs preserve symlinked config"
    else
        harness_fail "autofix_existing clean shell configs preserve symlinked config" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_shell_configs_preserves_owner_before_move() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-shell-owner-target"
    local fake_bin="$TEST_HOME/fake-bin"
    local chown_log="$TEST_HOME/chown.log"
    mkdir -p "$target_home" "$fake_bin"
    cat > "$target_home/.zshrc" <<'EOF'
# shell config
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_me=1
EOF

    cat > "$fake_bin/stat" <<EOF
#!/usr/bin/env bash
fmt="\$2"
path="\$3"
if [[ "\$fmt" == "%u:%g" ]]; then
    if [[ "\$path" == "$target_home/.zshrc" ]]; then
        printf '2001:3002\\n'
        exit 0
    fi
    if [[ "\$path" == "$target_home"/.gtbi-clean.* ]]; then
        printf '1000:1000\\n'
        exit 0
    fi
fi
exec /usr/bin/stat "\$@"
EOF
    chmod +x "$fake_bin/stat"

    cat > "$fake_bin/chown" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" > "$chown_log"
exit 0
EOF
    chmod +x "$fake_bin/chown"

    local output=""
    output=$(PATH="$fake_bin:$PATH" HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            clean_shell_configs >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg chown_args "$(cat "$2")" \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                "{chown_args: \$chown_args, file_contents: \$file_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" "$chown_log" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.chown_args | startswith("2001:3002 "))
        and (.chown_args | contains(".gtbi-clean."))
        and (.file_contents | contains("keep_me=1"))
        and (.file_contents | contains(".gtbi") | not)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean shell configs preserves owner before move"
    else
        harness_fail "autofix_existing clean shell configs preserves owner before move" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_shell_configs_restores_file_when_recording_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-shell-record-fail-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zshrc" <<'EOF'
# shell config
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_me=1
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            record_change() { return 1; }
            if clean_shell_configs >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{result: \$result, file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and (.file_contents == "# shell config\n# GTBI PATH\nsource ~/.gtbi/zsh/gtbi.zshrc\nkeep_me=1")
        and (.changes | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean shell configs restores file when recording fails"
    else
        harness_fail "autofix_existing clean shell configs restores file when recording fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_update_path_entries_restores_file_when_recording_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-path-record-fail-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zshrc" <<'EOF'
# shell config
export PATH="$HOME/bin:$PATH"
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            record_change() { return 1; }
            if update_path_entries >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                "{result: \$result, file_contents: \$file_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and (.file_contents == "# shell config\nexport PATH=\"$HOME/bin:$PATH\"")
        and (.file_contents | contains("# GTBI PATH") | not)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing update_path_entries restores file when recording fails"
    else
        harness_fail "autofix_existing update_path_entries restores file when recording fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_update_path_entries_restores_symlink_target_when_recording_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-path-symlink-record-fail-target"
    local dotfiles_home="$TEST_HOME/dotfiles"
    local real_config="$dotfiles_home/zshrc"
    mkdir -p "$target_home" "$dotfiles_home"
    cat > "$real_config" <<'EOF'
# shell config
export PATH="$HOME/bin:$PATH"
EOF
    ln -s "$real_config" "$target_home/.zshrc"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            record_change() { return 1; }
            if update_path_entries >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg symlink_exists "$(test -L "$TARGET_HOME/.zshrc" && echo yes || echo no)" \
                --arg symlink_target "$(readlink "$TARGET_HOME/.zshrc" 2>/dev/null || true)" \
                --arg file_contents "$(cat "$2")" \
                "{result: \$result, symlink_exists: \$symlink_exists, symlink_target: \$symlink_target, file_contents: \$file_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" "$real_config" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .symlink_exists == "yes"
        and .symlink_target == "'"$real_config"'"
        and (.file_contents == "# shell config\nexport PATH=\"$HOME/bin:$PATH\"")
        and (.file_contents | contains("# GTBI PATH") | not)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing update path entries restore symlink target on journaling failure"
    else
        harness_fail "autofix_existing update path entries restore symlink target on journaling failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_update_path_entries_repairs_legacy_gtbi_marker_missing_atuin() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-path-stale-marker-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zshrc" <<'EOF'
# shell config
# GTBI PATH
export PATH="$HOME/.local/bin:$PATH" # GTBI
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            update_path_entries >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.file_contents | contains(".atuin/bin"))
        and (.file_contents | contains(".cargo/bin"))
        and (.file_contents | contains("# GTBI PATH"))
        and (.changes | length == 1)
        and (.changes[0].description == "Added PATH entry to '"$target_home"'/.zshrc")
        and (.changes[0].backups | length == 1)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing update_path_entries repairs stale GTBI marker missing Atuin"
    else
        harness_fail "autofix_existing update_path_entries repairs stale GTBI marker missing Atuin" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_update_path_entries_repairs_zprofile_and_ignores_commented_atuin() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-path-zprofile-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zprofile" <<'EOF'
# .atuin/bin appears in this comment but not in the active PATH
# export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            update_path_entries >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg file_contents "$(cat "$TARGET_HOME/.zprofile")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.file_contents | contains("# .atuin/bin appears in this comment"))
        and (.file_contents | contains("# export PATH=\"$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH\""))
        and (.file_contents | contains("export PATH=\"$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH\" # GTBI"))
        and (.changes | length == 1)
        and (.changes[0].description == "Added PATH entry to '"$target_home"'/.zprofile")
        and (.changes[0].backups | length == 1)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing update_path_entries repairs zprofile and ignores commented Atuin"
    else
        harness_fail "autofix_existing update_path_entries repairs zprofile and ignores commented Atuin" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_legacy_config_migration_undo_handles_quoted_paths() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-quote-target-'legacy"
    mkdir -p "$target_home/.gtbi"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            run_migrations "0.9.0" "1.0.0" >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            if gtbi_undo_command --all >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg legacy_contents "$(cat "$TARGET_HOME/.gtbi_config" 2>/dev/null || true)" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, legacy_contents: \$legacy_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "success"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .legacy_contents == "legacy-config"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing legacy config migration undo handles quoted paths"
    else
        harness_fail "autofix_existing legacy config migration undo handles quoted paths" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_legacy_config_migration_undo_cleans_created_dirs() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-undo-clean-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            run_migrations "0.9.0" "1.0.0" >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            if gtbi_undo_command --all >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg config_dir_exists "$(test -d "$TARGET_HOME/.gtbi/config" && echo yes || echo no)" \
                --arg local_dir_exists "$(test -d "$TARGET_HOME/.local" && echo yes || echo no)" \
                --arg local_bin_exists "$(test -d "$TARGET_HOME/.local/bin" && echo yes || echo no)" \
                --arg legacy_contents "$(cat "$TARGET_HOME/.gtbi_config" 2>/dev/null || true)" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, gtbi_home_exists: \$gtbi_home_exists, config_dir_exists: \$config_dir_exists, local_dir_exists: \$local_dir_exists, local_bin_exists: \$local_bin_exists, legacy_contents: \$legacy_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "success"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .gtbi_home_exists == "no"
        and .config_dir_exists == "no"
        and .local_dir_exists == "no"
        and .local_bin_exists == "no"
        and .legacy_contents == "legacy-config"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing legacy config migration undo cleans created dirs"
    else
        harness_fail "autofix_existing legacy config migration undo cleans created dirs" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_legacy_json_migration_undo_handles_quoted_paths() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-quote-target-'json"
    mkdir -p "$target_home/.gtbi"
    printf '{\"legacy\":true}\n' > "$target_home/.gtbi/config.json"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            run_migrations "0.9.0" "1.0.0" >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            if gtbi_undo_command --all >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            jq -nc \
                --arg result "$result" \
                --arg json_exists "$(test -f "$TARGET_HOME/.gtbi/config.json" && echo yes || echo no)" \
                --arg migrated_exists "$(test -f "$TARGET_HOME/.gtbi/config.json.migrated" && echo yes || echo no)" \
                --arg json_contents "$(cat "$TARGET_HOME/.gtbi/config.json" 2>/dev/null || true)" \
                "{result: \$result, json_exists: \$json_exists, migrated_exists: \$migrated_exists, json_contents: \$json_contents}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "success"
        and .json_exists == "yes"
        and .migrated_exists == "no"
        and .json_contents == "{\"legacy\":true}"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing legacy json migration undo handles quoted paths"
    else
        harness_fail "autofix_existing legacy json migration undo handles quoted paths" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_legacy_config_migration_record_failure_cleans_created_dirs() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-migration-clean-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            record_change() { return 1; }
            if run_migrations "0.9.0" "1.0.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg config_dir_exists "$(test -d "$TARGET_HOME/.gtbi/config" && echo yes || echo no)" \
                "{result: \$result, legacy_exists: \$legacy_exists, gtbi_home_exists: \$gtbi_home_exists, config_dir_exists: \$config_dir_exists}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .legacy_exists == "yes"
        and .gtbi_home_exists == "no"
        and .config_dir_exists == "no"
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing legacy config migration failure cleans created dirs"
    else
        harness_fail "autofix_existing legacy config migration failure cleans created dirs" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_run_migrations_rolls_back_earlier_steps_on_late_failure() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-migration-rollback-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home/.gtbi"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"
    printf '{"legacy":true}\n' > "$target_home/.gtbi/config.json"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed "1s/^record_change/original_record_change/")"
            start_autofix_session >/dev/null 2>&1 || exit 1
            record_attempt=0
            record_change() {
                record_attempt=$((record_attempt + 1))
                if [[ $record_attempt -eq 3 ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            if run_migrations "0.9.0" "1.0.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg config_dir_exists "$(test -d "$TARGET_HOME/.gtbi/config" && echo yes || echo no)" \
                --arg json_exists "$(test -f "$TARGET_HOME/.gtbi/config.json" && echo yes || echo no)" \
                --arg migrated_exists "$(test -f "$TARGET_HOME/.gtbi/config.json.migrated" && echo yes || echo no)" \
                --arg local_dir_exists "$(test -d "$TARGET_HOME/.local" && echo yes || echo no)" \
                --arg local_bin_exists "$(test -d "$TARGET_HOME/.local/bin" && echo yes || echo no)" \
                --arg legacy_contents "$(cat "$TARGET_HOME/.gtbi_config" 2>/dev/null || true)" \
                --arg json_contents "$(cat "$TARGET_HOME/.gtbi/config.json" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, gtbi_home_exists: \$gtbi_home_exists, config_dir_exists: \$config_dir_exists, json_exists: \$json_exists, migrated_exists: \$migrated_exists, local_dir_exists: \$local_dir_exists, local_bin_exists: \$local_bin_exists, legacy_contents: \$legacy_contents, json_contents: \$json_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .gtbi_home_exists == "yes"
        and .config_dir_exists == "no"
        and .json_exists == "yes"
        and .migrated_exists == "no"
        and .local_dir_exists == "no"
        and .local_bin_exists == "no"
        and .legacy_contents == "legacy-config"
        and .json_contents == "{\"legacy\":true}"
        and (.changes | length == 0)
        and (.undos | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing run migrations rolls back earlier steps on late failure"
    else
        harness_fail "autofix_existing run migrations rolls back earlier steps on late failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_restores_version_when_path_repair_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-path-fail-target"
    mkdir -p "$target_home/.gtbi"
    printf '1.0.0\n' > "$target_home/.gtbi/version"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            update_path_entries() { return 1; }
            if upgrade_existing_installation "1.0.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_contents "$(cat "$TARGET_HOME/.gtbi/version" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{result: \$result, version_contents: \$version_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_contents == "1.0.0"
        and (.changes | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade restores version when path repair fails"
    else
        harness_fail "autofix_existing upgrade restores version when path repair fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_preserves_journal_when_path_recovery_is_incomplete() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-path-incomplete-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home/.gtbi"
    printf '0.9.0\n' > "$target_home/.gtbi/version"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"
    printf '# shell config\n' > "$target_home/.bashrc"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed '\''1s/record_change/original_record_change/'\'')"
            eval "$(declare -f autofix_existing_restore_from_backup | sed '\''1s/autofix_existing_restore_from_backup/original_autofix_existing_restore_from_backup/'\'')"
            record_change() {
                if [[ "${2:-}" == "Added PATH entry to $TARGET_HOME/.bashrc" ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            autofix_existing_restore_from_backup() {
                if [[ "${2:-}" == "$TARGET_HOME/.bashrc" ]]; then
                    return 1
                fi
                original_autofix_existing_restore_from_backup "$@"
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if upgrade_existing_installation "0.9.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg version_contents "$(cat "$TARGET_HOME/.gtbi/version" 2>/dev/null || true)" \
                --arg bashrc_contents "$(cat "$TARGET_HOME/.bashrc" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, version_contents: \$version_contents, bashrc_contents: \$bashrc_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .version_contents == "0.9.0"
        and (.bashrc_contents | contains("# GTBI PATH"))
        and (.changes | length == 2)
        and any(.changes[]; .description == "Migrated legacy config file to new location")
        and any(.changes[]; .description == "Created ~/.local/bin directory for GTBI PATH support")
        and (.undos | length > 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade preserves journal when path recovery is incomplete"
    else
        harness_fail "autofix_existing upgrade preserves journal when path recovery is incomplete" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_write_failure_cleans_new_gtbi_home() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-write-fail-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            printf() {
                if [[ "${1:-}" == "%s\n" && "${2:-}" == "1.1.0" ]]; then
                    builtin printf "$@"
                    return 1
                fi
                builtin printf "$@"
            }
            if upgrade_existing_installation "1.0.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg version_exists "$(test -e "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{result: \$result, gtbi_home_exists: \$gtbi_home_exists, version_exists: \$version_exists, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .gtbi_home_exists == "no"
        and .version_exists == "no"
        and (.changes | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade write failure cleans new gtbi home"
    else
        harness_fail "autofix_existing upgrade write failure cleans new gtbi home" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_version_backup_failure_rolls_back_migrations() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-version-backup-fail-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home/.gtbi"
    printf '0.9.0\n' > "$target_home/.gtbi/version"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f create_backup | sed '\''1s/^create_backup/original_create_backup/'\'')"
            create_backup() {
                if [[ "${1:-}" == "$TARGET_HOME/.gtbi/version" ]]; then
                    return 1
                fi
                original_create_backup "$@"
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if upgrade_existing_installation "0.9.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg local_dir_exists "$(test -d "$TARGET_HOME/.local" && echo yes || echo no)" \
                --arg local_bin_exists "$(test -d "$TARGET_HOME/.local/bin" && echo yes || echo no)" \
                --arg version_contents "$(cat "$TARGET_HOME/.gtbi/version" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, local_dir_exists: \$local_dir_exists, local_bin_exists: \$local_bin_exists, version_contents: \$version_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .local_dir_exists == "no"
        and .local_bin_exists == "no"
        and .version_contents == "0.9.0"
        and (.changes | length == 0)
        and (.undos | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade version backup failure rolls back migrations"
    else
        harness_fail "autofix_existing upgrade version backup failure rolls back migrations" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_record_failure_rolls_back_migrations_and_path_updates() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-rollback-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home"
    printf 'legacy-config\n' > "$target_home/.gtbi_config"
    printf '# shell config\n' > "$target_home/.bashrc"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed '\''1s/record_change/original_record_change/'\'')"
            record_change() {
                if [[ "${2:-}" == "Upgraded GTBI from 0.9.0 to 1.1.0" ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if upgrade_existing_installation "0.9.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg legacy_exists "$(test -f "$TARGET_HOME/.gtbi_config" && echo yes || echo no)" \
                --arg settings_exists "$(test -f "$TARGET_HOME/.gtbi/config/settings.toml" && echo yes || echo no)" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg local_dir_exists "$(test -d "$TARGET_HOME/.local" && echo yes || echo no)" \
                --arg local_bin_exists "$(test -d "$TARGET_HOME/.local/bin" && echo yes || echo no)" \
                --arg bashrc_contents "$(cat "$TARGET_HOME/.bashrc" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, legacy_exists: \$legacy_exists, settings_exists: \$settings_exists, gtbi_home_exists: \$gtbi_home_exists, local_dir_exists: \$local_dir_exists, local_bin_exists: \$local_bin_exists, bashrc_contents: \$bashrc_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .legacy_exists == "yes"
        and .settings_exists == "no"
        and .gtbi_home_exists == "no"
        and .local_dir_exists == "no"
        and .local_bin_exists == "no"
        and (.bashrc_contents | contains("# GTBI PATH") | not)
        and (.changes | length == 0)
        and (.undos | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade record failure rolls back migrations and path updates"
    else
        harness_fail "autofix_existing upgrade record failure rolls back migrations and path updates" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_record_failure_cleans_new_gtbi_home() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-clean-home-target"
    local state_dir="$TEST_HOME/autofix-state"
    mkdir -p "$target_home"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$state_dir" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            record_change() { return 1; }
            if upgrade_existing_installation "1.0.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg gtbi_home_exists "$(test -d "$TARGET_HOME/.gtbi" && echo yes || echo no)" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{result: \$result, gtbi_home_exists: \$gtbi_home_exists, version_exists: \$version_exists, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .gtbi_home_exists == "no"
        and .version_exists == "no"
        and (.changes | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade record failure cleans new gtbi home"
    else
        harness_fail "autofix_existing upgrade record failure cleans new gtbi home" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_upgrade_restores_version_when_recording_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-upgrade-record-fail-target"
    mkdir -p "$target_home/.gtbi"
    printf '1.0.0\n' > "$target_home/.gtbi/version"

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            record_change() { return 1; }
            if upgrade_existing_installation "1.0.0" "1.1.0" >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_contents "$(cat "$TARGET_HOME/.gtbi/version" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{result: \$result, version_contents: \$version_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_contents == "1.0.0"
        and (.changes | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing upgrade restores version when recording fails"
    else
        harness_fail "autofix_existing upgrade restores version when recording fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_shell_configs_allows_empty_result() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-shell-empty-target"
    mkdir -p "$target_home"
    cat > "$target_home/.zshrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            start_autofix_session >/dev/null 2>&1 || exit 1
            clean_shell_configs >/dev/null 2>&1 || exit 1
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg file_contents "$(cat "$TARGET_HOME/.zshrc")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                "{file_contents: \$file_contents, changes: \$changes}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        (.file_contents == "")
        and (.changes | length == 1)
        and (.changes[0].backups | length == 1)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean shell configs allows empty result"
    else
        harness_fail "autofix_existing clean shell configs allows empty result" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_restores_backup_after_shell_cleanup_failure() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-restore-shell-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"
    cat > "$target_home/.bashrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_bash=1
EOF
    cat > "$target_home/.zshrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_zsh=1
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed '\''1s/record_change/original_record_change/'\'')"
            record_change() {
                if [[ "${2:-}" == "Cleaned GTBI entries from $TARGET_HOME/.zshrc" ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                --arg bashrc_contents "$(cat "$TARGET_HOME/.bashrc" 2>/dev/null || true)" \
                --arg zshrc_contents "$(cat "$TARGET_HOME/.zshrc" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count, bashrc_contents: \$bashrc_contents, zshrc_contents: \$zshrc_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
        and (.bashrc_contents | contains("# GTBI PATH"))
        and (.zshrc_contents | contains("# GTBI PATH"))
        and (.changes | length == 0)
        and (.undos | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall restores backup after shell cleanup failure"
    else
        harness_fail "autofix_existing clean reinstall restores backup after shell cleanup failure" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_preserves_journal_when_shell_cleanup_recovery_fails() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-preserve-shell-journal-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    cat > "$target_home/.bashrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_bash=1
EOF
    cat > "$target_home/.zshrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_zsh=1
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed '\''1s/record_change/original_record_change/'\'')"
            record_change() {
                if [[ "${2:-}" == "Cleaned GTBI entries from $TARGET_HOME/.zshrc" ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            autofix_existing_restore_installation_backup() { return 1; }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
        and (.changes | length > 0)
        and any(.changes[]; .description == "Clean reinstall - removed existing GTBI installation")
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall preserves journal when shell cleanup recovery fails"
    else
        harness_fail "autofix_existing clean reinstall preserves journal when shell cleanup recovery fails" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_clean_reinstall_preserves_journal_when_shell_file_recovery_is_incomplete() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-clean-preserve-shell-file-target"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin"
    printf 'installed\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    cat > "$target_home/.bashrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_bash=1
EOF
    cat > "$target_home/.zshrc" <<'EOF'
# GTBI PATH
source ~/.gtbi/zsh/gtbi.zshrc
keep_zsh=1
EOF

    local output=""
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" GTBI_STATE_DIR="$target_home/.gtbi/autofix" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            eval "$(declare -f record_change | sed '\''1s/record_change/original_record_change/'\'')"
            eval "$(declare -f autofix_existing_restore_from_backup | sed '\''1s/autofix_existing_restore_from_backup/original_autofix_existing_restore_from_backup/'\'')"
            record_change() {
                if [[ "${2:-}" == "Cleaned GTBI entries from $TARGET_HOME/.zshrc" ]]; then
                    return 1
                fi
                original_record_change "$@"
            }
            autofix_existing_restore_from_backup() {
                if [[ "${2:-}" == "$TARGET_HOME/.zshrc" ]]; then
                    return 1
                fi
                original_autofix_existing_restore_from_backup "$@"
            }
            start_autofix_session >/dev/null 2>&1 || exit 1
            if clean_reinstall >/dev/null 2>&1; then
                result="success"
            else
                result="failure"
            fi
            end_autofix_session >/dev/null 2>&1 || true
            jq -nc \
                --arg result "$result" \
                --arg version_exists "$(test -f "$TARGET_HOME/.gtbi/version" && echo yes || echo no)" \
                --arg config_exists "$(test -f "$TARGET_HOME/.config/gtbi/settings.toml" && echo yes || echo no)" \
                --arg binary_exists "$(test -f "$TARGET_HOME/.local/bin/gtbi" && echo yes || echo no)" \
                --arg state_dir_exists "$(test -d "$TARGET_HOME/.gtbi/autofix" && echo yes || echo no)" \
                --arg relocated_state_count "$(find "$TARGET_HOME" -maxdepth 1 -type d -name ".gtbi-autofix-clean.*" | wc -l | tr -d " ")" \
                --arg bashrc_contents "$(cat "$TARGET_HOME/.bashrc" 2>/dev/null || true)" \
                --arg zshrc_contents "$(cat "$TARGET_HOME/.zshrc" 2>/dev/null || true)" \
                --slurpfile changes "$GTBI_CHANGES_FILE" \
                --slurpfile undos "$GTBI_UNDOS_FILE" \
                "{result: \$result, version_exists: \$version_exists, config_exists: \$config_exists, binary_exists: \$binary_exists, state_dir_exists: \$state_dir_exists, relocated_state_count: \$relocated_state_count, bashrc_contents: \$bashrc_contents, zshrc_contents: \$zshrc_contents, changes: \$changes, undos: \$undos}"
        ' _ "$AUTOFIX_EXISTING_SH" 2>/dev/null)

    if printf '%s\n' "$output" | jq -e '
        .result == "failure"
        and .version_exists == "yes"
        and .config_exists == "yes"
        and .binary_exists == "yes"
        and .state_dir_exists == "yes"
        and .relocated_state_count == "0"
        and (.bashrc_contents | contains("# GTBI PATH"))
        and (.zshrc_contents | contains("# GTBI PATH") | not)
        and (.changes | length > 0)
        and any(.changes[]; .description == "Clean reinstall - removed existing GTBI installation")
        and (.undos | length > 0)
    ' >/dev/null 2>&1; then
        harness_pass "autofix_existing clean reinstall preserves journal when shell file recovery is incomplete"
    else
        harness_fail "autofix_existing clean reinstall preserves journal when shell file recovery is incomplete" "$output"
    fi

    cleanup_mock_env
}

test_autofix_existing_remove_artifacts_propagates_rm_failures() {
    setup_mock_env

    local target_home="$TEST_HOME/autofix-existing-rm-target"
    local fake_bin="$TEST_HOME/fake-bin"
    mkdir -p "$target_home/.gtbi" "$target_home/.config/gtbi" "$target_home/.local/bin" "$fake_bin"
    printf 'version\n' > "$target_home/.gtbi/version"
    printf 'config\n' > "$target_home/.config/gtbi/settings.toml"
    printf '#!/usr/bin/env bash\n' > "$target_home/.local/bin/gtbi"
    chmod +x "$target_home/.local/bin/gtbi"

    cat > "$fake_bin/rm" <<EOF
#!/usr/bin/env bash
last="\${@: -1}"
if [[ "\$last" == "$target_home/.config/gtbi" ]]; then
    exit 1
fi
exec /bin/rm "\$@"
EOF
    chmod +x "$fake_bin/rm"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME/root-home" TARGET_HOME="$target_home" PATH="$fake_bin:/usr/bin:/bin" \
        bash -c '
            unset _GTBI_AUTOFIX_SOURCED _GTBI_AUTOFIX_EXISTING_SOURCED
            source "$1"
            remove_gtbi_artifacts
        ' _ "$AUTOFIX_EXISTING_SH" 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"Failed to remove artifact"* ]]; then
        harness_pass "autofix_existing remove artifacts propagates rm failures"
    else
        harness_fail "autofix_existing remove artifacts propagates rm failures" "$output"
    fi

    cleanup_mock_env
}

test_changelog_defaults_to_last_updated() {
    setup_mock_env

    local output
    output=$(GTBI_HOME="$TEST_GTBI" GTBI_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "1.2.3")' >/dev/null 2>&1; then
        harness_pass "changelog defaults to the current state last_updated timestamp"
    else
        harness_fail "changelog defaults to the current state last_updated timestamp"
    fi

    cleanup_mock_env
}

test_export_config_json_is_valid() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALL_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_MANIFEST_INDEX" \
        bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.settings.mode == "vibe \"quoted\"" and .modules[0] == "alpha" and .modules[1] == "module \"beta\" \\\\ path" and .metadata.gtbi_version == "1.2.3 \"beta\""' >/dev/null 2>&1; then
        harness_pass "export-config JSON escapes state, version, and detected module strings correctly"
    else
        harness_fail "export-config JSON escapes state, version, and detected module strings correctly"
    fi

    cleanup_mock_env
}

test_status_rejects_unknown_flags() {
    setup_mock_env

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$STATUS_SH" --bogus 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"Unknown option"* ]]; then
        harness_pass "status rejects unknown flags"
    else
        harness_fail "status rejects unknown flags" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_status_plain_output_avoids_ansi_when_not_tty() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$STATUS_SH")

    if [[ "$output" == *$'\033['* ]]; then
        harness_fail "status suppresses ANSI codes when stdout is not a TTY" "$output"
    else
        harness_pass "status suppresses ANSI codes when stdout is not a TTY"
    fi

    cleanup_mock_env
}

test_status_reports_last_updated_timestamp() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$STATUS_SH" --json)

    if printf '%s\n' "$output" | jq -e '.last_update == "2026-03-10T12:34:56Z"' >/dev/null 2>&1; then
        harness_pass "status reports last_updated from the current state schema"
    else
        harness_fail "status reports last_updated from the current state schema"
    fi

    cleanup_mock_env
}

test_status_errors_on_malformed_state_json() {
    setup_mock_env
    printf '{ invalid json\n' > "$TEST_GTBI/state.json"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$STATUS_SH" --json 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 2 ]] && printf '%s\n' "$output" | jq -e '.errors | index("state file invalid JSON")' >/dev/null 2>&1; then
        harness_pass "status marks malformed state.json as an error"
    else
        harness_fail "status marks malformed state.json as an error" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_dashboard_generation_is_atomic_on_failure() {
    setup_mock_env
    TEST_DEV_REPO="$TEST_HOME/dev-repo-failing-dashboard"
    mkdir -p "$TEST_GTBI/dashboard" "$TEST_DEV_REPO/scripts/lib"
    printf 'existing dashboard\n' > "$TEST_GTBI/dashboard/index.html"
    cp "$DASHBOARD_SH" "$TEST_DEV_REPO/scripts/lib/dashboard.sh"
    cat > "$TEST_DEV_REPO/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_DEV_REPO/scripts/lib/info.sh"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$TEST_DEV_REPO/scripts/lib/dashboard.sh" generate --force 2>&1) || exit_code=$?
    local current_contents
    current_contents=$(cat "$TEST_GTBI/dashboard/index.html")
    local leftover_tmp
    leftover_tmp=$(find "$TEST_GTBI/dashboard" -maxdepth 1 -name 'index.html.tmp.*' -print -quit 2>/dev/null || true)

    if [[ "$exit_code" -ne 0 ]] && [[ "$current_contents" == "existing dashboard" ]] && [[ -z "$leftover_tmp" ]]; then
        harness_pass "dashboard generation preserves the previous file on failure"
    else
        harness_fail "dashboard generation preserves the previous file on failure" "exit=$exit_code output=$output contents=$current_contents leftover_tmp=$leftover_tmp"
    fi

    cleanup_mock_env
}

test_dashboard_rejects_invalid_ports_before_serving() {
    setup_mock_env
    mkdir -p "$TEST_GTBI/dashboard"
    printf 'existing dashboard\n' > "$TEST_GTBI/dashboard/index.html"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$DASHBOARD_SH" serve --port not-a-number 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] \
        && [[ "$output" == *"port must be an integer between 1 and 65535"* ]] \
        && [[ "$output" != *"http://localhost:not-a-number"* ]]; then
        harness_pass "dashboard serve rejects invalid ports before printing URLs"
    else
        harness_fail "dashboard serve rejects invalid ports before printing URLs" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_dashboard_help_does_not_require_target_context() {
    setup_installed_layout_env

    local mode=""
    local output=""
    local exit_code=0
    local failures=""
    local -a dashboard_args=()

    for mode in generate serve; do
        dashboard_args=("$mode" "--help")
        exit_code=0
        output=$(HOME="$TEST_ROOT_HOME" \
            TARGET_USER="ghost" \
            TARGET_HOME="$TEST_HOME/missing-target-home" \
            GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" \
            PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
            bash "$DASHBOARD_SH" "${dashboard_args[@]}" 2>&1) || exit_code=$?

        if [[ "$exit_code" -ne 0 ]] || [[ "$output" != *"Usage:"* ]] || [[ "$output" == *"refusing to fall back to current HOME"* ]]; then
            printf -v failures '%s%s: exit=%s output=%s\n' "$failures" "$mode" "$exit_code" "$output"
        fi
    done

    if [[ -z "$failures" ]]; then
        harness_pass "dashboard help does not require target context"
    else
        harness_fail "dashboard help does not require target context" "$failures"
    fi

    cleanup_mock_env
}

test_dashboard_prefers_repo_local_info_script() {
    setup_installed_layout_env

    TEST_DEV_REPO="$TEST_HOME/dev-repo"
    mkdir -p "$TEST_DEV_REPO/scripts/lib" "$TEST_INSTALLED_GTBI/scripts/lib"
    cp "$DASHBOARD_SH" "$TEST_DEV_REPO/scripts/lib/dashboard.sh"

    cat > "$TEST_DEV_REPO/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>repo-local-info</html>\n'
EOF
    chmod +x "$TEST_DEV_REPO/scripts/lib/info.sh"

    cat > "$TEST_INSTALLED_GTBI/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>installed-info</html>\n'
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/info.sh"

    local output
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" \
        bash "$TEST_DEV_REPO/scripts/lib/dashboard.sh" generate --force)

    if [[ "$output" == *"Dashboard generated:"* ]] \
        && grep -q 'repo-local-info' "$TEST_INSTALLED_GTBI/dashboard/index.html" \
        && ! grep -q 'installed-info' "$TEST_INSTALLED_GTBI/dashboard/index.html"; then
        harness_pass "dashboard prefers repo-local info.sh over installed copy"
    else
        harness_fail "dashboard prefers repo-local info.sh over installed copy" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home
    cp "$DASHBOARD_SH" "$TEST_INSTALLED_GTBI/scripts/lib/dashboard.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/dashboard.sh" generate --force)

    if [[ "$output" == *"$TEST_INSTALLED_GTBI/dashboard/index.html"* ]] \
        && [[ -f "$TEST_INSTALLED_GTBI/dashboard/index.html" ]] \
        && [[ ! -e "$TEST_ROOT_HOME/.gtbi/dashboard/index.html" ]]; then
        harness_pass "dashboard writes to installed layout under root home"
    else
        harness_fail "dashboard writes to installed layout under root home" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_serve_uses_target_user_in_ssh_hint() {
    setup_installed_layout_env
    cp "$DASHBOARD_SH" "$TEST_INSTALLED_GTBI/scripts/lib/dashboard.sh"
    mkdir -p "$TEST_INSTALLED_GTBI/dashboard"
    printf 'existing dashboard\n' > "$TEST_INSTALLED_GTBI/dashboard/index.html"

    cat > "$TEST_FAKE_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_FAKE_BIN/python3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -s -- "$TEST_INSTALLED_GTBI/scripts/lib/dashboard.sh" "$TEST_FAKE_BIN/python3" <<'EOF_DASHBOARD_SERVE_HINT'
script="$1"
fake_python="$2"
source "$script"
dashboard_system_binary_path() {
    case "${1:-}" in
        python3|python)
            printf '%s\n' "$fake_python"
            ;;
        jq)
            [[ -x /usr/bin/jq ]] || return 1
            printf '%s\n' /usr/bin/jq
            ;;
        sed)
            printf '%s\n' /usr/bin/sed
            ;;
        head)
            printf '%s\n' /usr/bin/head
            ;;
        *)
            return 1
            ;;
    esac
}
dashboard_serve --port 9099
EOF_DASHBOARD_SERVE_HINT
    )

    if [[ "$output" == *"ssh -L 9099:localhost:9099 tester@"* ]] \
        && [[ "$output" != *"ssh -L 9099:localhost:9099 $(whoami 2>/dev/null || echo unknown)@"* ]]; then
        harness_pass "dashboard serve uses target user in SSH hint"
    else
        harness_fail "dashboard serve uses target user in SSH hint" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_copy_install_uses_target_home_only_system_state() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$TEST_INSTALLED_GTBI/scripts/lib"
    cp "$DASHBOARD_SH" "$TEST_ROOT_HOME/.local/bin/dashboard"
    chmod +x "$TEST_ROOT_HOME/.local/bin/dashboard"

    cat > "$TEST_INSTALLED_GTBI/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>copied-dashboard-info</html>\n'
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/info.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        dashboard generate --force 2>&1)

    if [[ "$output" == *"$TEST_INSTALLED_GTBI/dashboard/index.html"* ]] \
        && [[ -f "$TEST_INSTALLED_GTBI/dashboard/index.html" ]] \
        && [[ ! -e "$TEST_ROOT_HOME/.gtbi/dashboard/index.html" ]]; then
        harness_pass "copied dashboard uses target_home-only system state"
    else
        harness_fail "copied dashboard uses target_home-only system state" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH" \
        bash -lc '
            source "$TEST_DASHBOARD_SCRIPT"
            dashboard_prepare_context
            printf "home=%s\nstate=%s\ntarget=%s\n" "${_DASHBOARD_GTBI_HOME:-}" "$(dashboard_resolve_state_file)" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"home=$TEST_INSTALLED_GTBI"* ]] \
        && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]] \
        && [[ "$output" == *"target=$TEST_TARGET_HOME"* ]]; then
        harness_pass "dashboard repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "dashboard repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_uses_installed_layout_and_target_path_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home
    cp "$CHEATSHEET_SH" "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh"

    mkdir -p "$TEST_INSTALLED_GTBI/zsh"
    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
if command -v claude >/dev/null 2>&1; then
  alias cc='claude'
fi
alias cod='codex'
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh" --json)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" \
        '.source == $zshrc and ([.entries[].name] | index("cc")) != null and ([.entries[].name] | index("cod")) != null' \
        >/dev/null 2>&1; then
        harness_pass "cheatsheet uses installed layout and target-user PATH under root home"
    else
        harness_fail "cheatsheet uses installed layout and target-user PATH under root home" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_copy_install_uses_target_home_only_system_state() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$TEST_INSTALLED_GTBI/zsh"
    cp "$CHEATSHEET_SH" "$TEST_ROOT_HOME/.local/bin/cheatsheet"
    chmod +x "$TEST_ROOT_HOME/.local/bin/cheatsheet"

    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
if command -v codex >/dev/null 2>&1; then
  alias cod='codex'
fi
EOF
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        cheatsheet --json 2>&1)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" \
        '.source == $zshrc and ([.entries[].name] | index("cod")) != null' >/dev/null 2>&1; then
        harness_pass "copied cheatsheet uses target_home-only system state"
    else
        harness_fail "copied cheatsheet uses target_home-only system state" "$output"
    fi

    cleanup_mock_env
}


test_cheatsheet_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env
    cp "$CHEATSHEET_SH" "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh"

    mkdir -p "$TEST_INSTALLED_GTBI/zsh"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
if command -v claude >/dev/null 2>&1; then
  alias cc='claude'
fi
alias cod='codex'
EOF

    rm -f "$TEST_TARGET_HOME/.local/bin/claude"
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh" --json)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" '
        .source == $zshrc and
        ([.entries[].name] | index("cod")) != null and
        ([.entries[].name] | index("cc")) == null
    ' >/dev/null 2>&1; then
        harness_pass "cheatsheet ignores other-user home bin_dir from state"
    else
        harness_fail "cheatsheet ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    mkdir -p "$TEST_INSTALLED_GTBI/zsh"
    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
alias cod='codex'
EOF
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$CHEATSHEET_SH" --json)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" \
        '.source == $zshrc and ([.entries[].name] | index("cod")) != null and ([.entries[].name] | index("poisoned")) == null' \
        >/dev/null 2>&1; then
        harness_pass "cheatsheet repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "cheatsheet repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_CHEATSHEET_SCRIPT="$CHEATSHEET_SH" \
        bash -lc '
            source "$TEST_CHEATSHEET_SCRIPT"
            cheatsheet_prepare_context
            printf "user=%s\nhome=%s\n" "${_CHEATSHEET_RESOLVED_TARGET_USER:-}" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] \
        && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "cheatsheet repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "cheatsheet repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_cli_tools_ignore_other_user_home_bin_dir_override() {
    setup_cross_home_bin_dir_env

    local tool_name="cli-cross-home-tool"
    write_fake_command "$STALE_HOME/.local/bin/$tool_name" "stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="$(id -un 2>/dev/null || whoami 2>/dev/null)" \
        GTBI_BIN_DIR="$STALE_HOME/.local/bin" TEST_CLI_TOOLS_SCRIPT="$CLI_TOOLS_SH" TEST_TOOL_NAME="$tool_name" \
        bash <<'EOF'
set -u
source "$TEST_CLI_TOOLS_SCRIPT"
if _cli_target_has_command "$TEST_TOOL_NAME"; then
    printf 'has=0\n'
else
    printf 'has=%s\n' "$?"
fi
_cli_run_as_user 'printf "%s\n" "${GTBI_BIN_DIR:-}"'
EOF
)

    if [[ "$output" == $'has=1\n'"$TEST_TARGET_HOME/.local/bin" ]]; then
        harness_pass "cli_tools ignore other-user home bin_dir override"
    else
        harness_fail "cli_tools ignore other-user home bin_dir override" "$output"
    fi

    cleanup_mock_env
}

test_agents_ignore_other_user_home_bin_dir_override() {
    setup_cross_home_bin_dir_env

    cat > "$STALE_HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
printf 'stale am\n'
EOF
    chmod +x "$STALE_HOME/.local/bin/am"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="$(id -un 2>/dev/null || whoami 2>/dev/null)" \
        GTBI_BIN_DIR="$STALE_HOME/.local/bin" TEST_AGENTS_SCRIPT="$AGENTS_SH" \
        bash <<'EOF'
set -u
source "$TEST_AGENTS_SCRIPT"
if out="$(_agent_find_am_bin "$TARGET_HOME" 2>/dev/null)"; then
    printf 'find=%s\n' "$out"
else
    printf 'find=rc%s\n' "$?"
fi
_agent_run_as_user 'printf "%s\n" "${GTBI_BIN_DIR:-}"'
EOF
)

    if [[ "$output" == $'find=rc1\n'"$TEST_TARGET_HOME/.local/bin" ]]; then
        harness_pass "agents ignore other-user home bin_dir override"
    else
        harness_fail "agents ignore other-user home bin_dir override" "$output"
    fi

    cleanup_mock_env
}

test_language_cloud_ignore_other_user_home_bin_dir_override() {
    setup_mock_env

    local target_user="gtbitestuser"
    local target_home="$TEST_HOME/users/$target_user"
    local stale_home="$TEST_HOME/users/staleuser"

    mkdir -p "$target_home" "$stale_home/.local/bin"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$target_home" TARGET_USER="$target_user" \
        GTBI_BIN_DIR="$stale_home/.local/bin" TEST_LANGUAGES_SCRIPT="$LANGUAGES_SH" \
        TEST_TARGET_USER="$target_user" TEST_TARGET_HOME="$target_home" TEST_STALE_HOME="$stale_home" \
        bash <<'EOF'
set -u
emit_test_passwd_entry() {
    local user="${1-}"

    case "$user" in
        "$TEST_TARGET_USER")
            printf '%s:x:1001:1001::%s:/bin/bash\n' "$TEST_TARGET_USER" "$TEST_TARGET_HOME"
            ;;
        staleuser)
            printf 'staleuser:x:1002:1002::%s:/bin/bash\n' "$TEST_STALE_HOME"
            ;;
        "")
            printf '%s:x:1001:1001::%s:/bin/bash\n' "$TEST_TARGET_USER" "$TEST_TARGET_HOME"
            printf 'staleuser:x:1002:1002::%s:/bin/bash\n' "$TEST_STALE_HOME"
            ;;
        *)
            return 1
            ;;
    esac
}
source "$TEST_LANGUAGES_SCRIPT"
_lang_resolve_current_user() { printf '%s\n' "$TEST_TARGET_USER"; }
_lang_getent_passwd_entry() { emit_test_passwd_entry "${1-}"; }
_lang_run_as_user 'printf "lang=%s\n" "${GTBI_BIN_DIR:-}"'
EOF
)

    if [[ "$output" == "lang=$target_home/.local/bin" ]]; then
        harness_pass "language run_as_user ignores other-user home bin_dir override"
    else
        harness_fail "language run_as_user ignores other-user home bin_dir override" "$output"
    fi

    cleanup_mock_env
}

test_github_api_binary_path_ignores_other_user_home_bin_dir_override() {
    setup_cross_home_bin_dir_env

    local tool_name="github-api-cross-home-tool"
    write_fake_command "$STALE_HOME/.local/bin/$tool_name" "stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" GTBI_BIN_DIR="$STALE_HOME/.local/bin" \
        TEST_GITHUB_API_SCRIPT="$GITHUB_API_SH" TEST_TOOL_NAME="$tool_name" \
        bash <<'EOF'
set -u
source "$TEST_GITHUB_API_SCRIPT"
if out="$(_github_api_binary_path "$TEST_TOOL_NAME" 2>/dev/null)"; then
    printf 'path=%s\n' "$out"
else
    printf 'rc=%s\n' "$?"
fi
EOF
)

    if [[ "$output" == "rc=1" ]]; then
        harness_pass "github_api binary path ignores other-user home bin_dir override"
    else
        harness_fail "github_api binary path ignores other-user home bin_dir override" "$output"
    fi

    cleanup_mock_env
}

test_export_config_augment_path_ignores_other_user_home_bin_dir() {
    setup_cross_home_bin_dir_env

    local tool_name="export-cross-home-tool"
    write_fake_command "$STALE_HOME/.local/bin/$tool_name" "stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="tester" GTBI_BIN_DIR="$STALE_HOME/.local/bin" \
        TEST_EXPORT_SCRIPT="$EXPORT_CONFIG_SH" TEST_TOOL_NAME="$tool_name" \
        bash <<'EOF'
set -u
PATH=/usr/bin:/bin
source "$TEST_EXPORT_SCRIPT"
augment_path_for_target_user
if out="$(command -v "$TEST_TOOL_NAME" 2>/dev/null)"; then
    printf 'path=%s\n' "$out"
else
    printf 'rc=%s\n' "$?"
fi
EOF
)

    if [[ "$output" == "rc=1" ]]; then
        harness_pass "export-config augment_path ignores other-user home bin_dir"
    else
        harness_fail "export-config augment_path ignores other-user home bin_dir" "$output"
    fi

    cleanup_mock_env
}

test_nightly_update_ignores_other_user_home_bin_dir_before_preflight_path() {
    setup_cross_home_bin_dir_env

    local system_state="$TEST_ROOT_HOME/system-state.json"
    mkdir -p \
        "$TEST_ROOT_HOME/.gtbi/scripts/lib" \
        "$TEST_TARGET_HOME/.gtbi/bin" \
        "$TEST_TARGET_HOME/.gtbi/scripts/lib" \
        "$TEST_TARGET_HOME/.gtbi/logs/updates"

    cat > "$TEST_ROOT_HOME/.gtbi/scripts/lib/notify.sh" <<'EOF'
gtbi_notify_update_success() { :; }
gtbi_notify_update_failure() { :; }
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/notify.sh" <<'EOF'
gtbi_notify_update_success() { :; }
gtbi_notify_update_failure() { :; }
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin"
}
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/bin/gtbi-update" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_HOME=%s TARGET_HOME=%s GTBI_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}"
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/bin/nproc" <<'EOF'
#!/usr/bin/env bash
printf '999999\n'
EOF
    cat > "$STALE_HOME/.local/bin/df" <<'EOF'
#!/usr/bin/env bash
echo 'STALE_DF_USED' >&2
exit 99
EOF
    chmod +x \
        "$TEST_TARGET_HOME/.gtbi/bin/gtbi-update" \
        "$TEST_TARGET_HOME/.gtbi/bin/nproc" \
        "$STALE_HOME/.local/bin/df"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$system_state" PATH="/usr/bin:/bin" \
        bash "$NIGHTLY_UPDATE_SH" 2>&1 || true)

    if [[ "$output" == *"Running: $TEST_TARGET_HOME/.gtbi/bin/gtbi-update --yes --quiet --no-self-update"* ]] \
        && [[ "$output" == *"LIVE_HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_TARGET_HOME/.gtbi"* ]] \
        && [[ "$output" != *"STALE_DF_USED"* ]]; then
        harness_pass "nightly update ignores other-user home bin_dir before preflight PATH"
    else
        harness_fail "nightly update ignores other-user home bin_dir before preflight PATH" "$output"
    fi

    cleanup_mock_env
}

test_nightly_update_ignores_stale_explicit_target_home_before_preflight_path() {
    setup_cross_home_bin_dir_env

    mkdir -p \
        "$TEST_TARGET_HOME/.gtbi/bin" \
        "$TEST_TARGET_HOME/.gtbi/scripts/lib" \
        "$TEST_TARGET_HOME/.gtbi/logs/updates"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/notify.sh" <<'EOF'
gtbi_notify_update_success() { :; }
gtbi_notify_update_failure() { :; }
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/bin/gtbi-update" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_HOME=%s TARGET_HOME=%s GTBI_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}"
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/bin/nproc" <<'EOF'
#!/usr/bin/env bash
printf '999999\n'
EOF
    cat > "$STALE_HOME/.local/bin/df" <<'EOF'
#!/usr/bin/env bash
echo 'STALE_DF_USED' >&2
exit 99
EOF
    chmod +x \
        "$TEST_TARGET_HOME/.gtbi/bin/gtbi-update" \
        "$TEST_TARGET_HOME/.gtbi/bin/nproc" \
        "$STALE_HOME/.local/bin/df"

    local output=""
    output=$(HOME="$TEST_TARGET_HOME" TARGET_HOME="$STALE_HOME" GTBI_BIN_DIR="$STALE_HOME/.local/bin" PATH="/usr/bin:/bin" \
        bash "$NIGHTLY_UPDATE_SH" 2>&1 || true)

    if [[ "$output" == *"Running: $TEST_TARGET_HOME/.gtbi/bin/gtbi-update --yes --quiet --no-self-update"* ]] \
        && [[ "$output" == *"LIVE_HOME=$TEST_TARGET_HOME TARGET_HOME=$STALE_HOME"* ]] \
        && [[ "$output" != *"STALE_DF_USED"* ]]; then
        harness_pass "nightly update ignores stale explicit TARGET_HOME before preflight PATH"
    else
        harness_fail "nightly update ignores stale explicit TARGET_HOME before preflight PATH" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_can_be_sourced_without_running_main() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME"         TEST_CHEATSHEET_SCRIPT="$CHEATSHEET_SH"         bash -lc '
            set +e +u
            set +o pipefail
            HOME=relative-home
            set -- --bogus keep
            source "$TEST_CHEATSHEET_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            gtbi_home_set=unset
            script_dir_set=unset
            gtbi_version_set=unset
            has_gum_set=unset
            [[ -v GTBI_HOME ]] && gtbi_home_set=set
            [[ -v SCRIPT_DIR ]] && script_dir_set=set
            [[ -v GTBI_VERSION ]] && gtbi_version_set=set
            [[ -v HAS_GUM ]] && has_gum_set=set
            printf "%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$gtbi_home_set" "$script_dir_set" "$gtbi_version_set" "$has_gum_set"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|unset|unset|unset|unset" ]]; then
        harness_pass "cheatsheet can be sourced without leaking install context"
    else
        harness_fail "cheatsheet can be sourced without leaking install context" "$output"
    fi

    cleanup_mock_env
}

test_doctor_entrypoint_dispatches_helper_commands() {
    setup_mock_env

    local status_output
    status_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" bash "$DOCTOR_SH" status --short)

    local changelog_output
    changelog_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_REPO="$TEST_REPO" bash "$DOCTOR_SH" changelog --all --json)

    local export_output
    export_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALL_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_MANIFEST_INDEX" \
        bash "$DOCTOR_SH" export-config --json)

    if [[ -n "$status_output" ]] \
        && printf '%s\n' "$changelog_output" | jq -e '.changes | length == 2' >/dev/null 2>&1 \
        && printf '%s\n' "$export_output" | jq -e '.modules | length == 2' >/dev/null 2>&1; then
        harness_pass "doctor entrypoint dispatches status, changelog, and export-config"
    else
        harness_fail "doctor entrypoint dispatches status, changelog, and export-config"
    fi

    cleanup_mock_env
}

test_status_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/status.sh" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status resolves installed layout and target-user PATH under root home"
    else
        harness_fail "status resolves installed layout and target-user PATH under root home" "$output"
    fi

    cleanup_mock_env
}

test_status_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_STATUS_SCRIPT="$STATUS_SH"         bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_GTBI_HOME:-}"
        ' 2>/dev/null)
    expected=$'user=tester
home='"$TEST_TARGET_HOME"$'
gtbi='"$TEST_INSTALLED_GTBI"

    if [[ "$output" == "$expected" ]]; then
        harness_pass "status uses explicit target home when state is missing"
    else
        harness_fail "status uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_status_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"

    local missing_target_home="$TEST_HOME/missing-target-home"
    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$missing_target_home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_STATUS_SCRIPT="$STATUS_SH"         bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_GTBI_HOME:-}"
        ' 2>/dev/null)
    expected=$'user=ghost
home='"$missing_target_home"$'
gtbi='

    if [[ "$output" == "$expected" ]]; then
        harness_pass "status does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "status does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_status_ignores_current_shell_only_binaries() {
    setup_installed_layout_env

    rm -f \
        "$TEST_TARGET_HOME/.local/bin/claude" \
        "$TEST_TARGET_HOME/.local/bin/codex" \
        "$TEST_TARGET_HOME/.local/bin/gemini" \
        "$TEST_TARGET_HOME/.local/bin/ntm"

    write_fake_command "$TEST_FAKE_BIN/claude" "claude 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/codex" "codex 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/gemini" "gemini 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/ntm" "ntm 9.9.9"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_STATUS_SCRIPT="$STATUS_SH" bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_prepare_context
            printf "claude=%s\ncodex=%s\ngemini=%s\nntm=%s\n" \
                "$(_status_binary_path claude 2>/dev/null || true)" \
                "$(_status_binary_path codex 2>/dev/null || true)" \
                "$(_status_binary_path gemini 2>/dev/null || true)" \
                "$(_status_binary_path ntm 2>/dev/null || true)"
        ' 2>/dev/null)

    if [[ "$output" != *"$TEST_FAKE_BIN/claude"* ]] \
        && [[ "$output" != *"$TEST_FAKE_BIN/codex"* ]] \
        && [[ "$output" != *"$TEST_FAKE_BIN/gemini"* ]] \
        && [[ "$output" != *"$TEST_FAKE_BIN/ntm"* ]]; then
        harness_pass "status ignores current-shell-only binaries"
    else
        harness_fail "status ignores current-shell-only binaries" "$output"
    fi

    cleanup_mock_env
}

test_status_binary_path_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" TEST_STATUS_SCRIPT="$STATUS_SH" bash -lc 'source "$TEST_STATUS_SCRIPT"; _status_prepare_context; _status_binary_path claude' 2>/dev/null)

    if [[ "$output" == "$TEST_TARGET_HOME/.local/bin/claude" ]]; then
        harness_pass "status binary path ignores other-user home bin_dir from state"
    else
        harness_fail "status binary path ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_status_uses_persisted_bin_dir_over_poisoned_env_bin_dir() {
    setup_installed_layout_env

    local custom_bin="$TEST_HOME/custom-bin"
    mkdir -p "$custom_bin"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    rm -f "$TEST_TARGET_HOME/.local/bin/claude"
    rm -f "$TEST_TARGET_HOME/.local/bin/codex"
    rm -f "$TEST_TARGET_HOME/.local/bin/gemini"
    rm -f "$TEST_TARGET_HOME/.local/bin/ntm"
    write_fake_command "$custom_bin/claude" "claude 1.2.3"
    write_fake_command "$custom_bin/codex" "codex 1.2.3"
    write_fake_command "$custom_bin/gemini" "gemini 1.2.3"
    write_fake_command "$custom_bin/ntm" "ntm 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_BIN_DIR="$TEST_FAKE_BIN" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash "$TEST_INSTALLED_GTBI/scripts/lib/status.sh" --json)

    if printf '%s\n' "$output" | jq -e '
        .status == "ok" and
        ((.warnings | index("missing: claude")) == null)
    ' >/dev/null 2>&1; then
        harness_pass "status prefers persisted bin_dir over poisoned env bin_dir"
    else
        harness_fail "status prefers persisted bin_dir over poisoned env bin_dir" "$output"
    fi

    cleanup_mock_env
}

test_status_prefers_resolved_install_state_over_stale_system_state_for_target_context() {
    setup_installed_layout_env

    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    mkdir -p "$(dirname "$TEST_SYSTEM_STATE_FILE")"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$TEST_TARGET_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$TEST_HOME/users/stale",
  "bin_dir": "$TEST_HOME/stale-bin",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" TEST_STATUS_SCRIPT="$TEST_INSTALLED_GTBI/scripts/lib/status.sh" bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_prepare_context
            printf "user=%s\nhome=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "$(_status_resolve_state_file)"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "status prefers resolved install state over stale system state for target context"
    else
        harness_fail "status prefers resolved install state over stale system state for target context" "$output"
    fi

    cleanup_mock_env
}

test_status_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    mkdir -p "$stale_home"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$#" -eq 1 ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    echo "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "staleuser" ]]; then
    echo "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_STATUS_SCRIPT="$STATUS_SH"         bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_prepare_context
            printf "user=%s\nhome=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "$(_status_resolve_state_file)"
        ' 2>/dev/null)

    if [[ "$output" != *"user=staleuser"* ]] && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "status prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "status prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_status_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/status.sh" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status falls back to system state when user state is missing"
    else
        harness_fail "status falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_status_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$STATUS_SH" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status uses target_home from system state when getent is unavailable"
    else
        harness_fail "status uses target_home from system state when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_status_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$STATUS_SH" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "status repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_status_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" TEST_TARGET_HOME="$TEST_TARGET_HOME" \
        TEST_STATUS_SCRIPT="$STATUS_SH" PATH="/usr/bin:/bin" \
        bash -lc '
            source "$TEST_STATUS_SCRIPT"
            _status_getent_passwd_entry() {
                if [[ "${1:-}" == "tester" ]]; then
                    printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
                    return 0
                fi
                return 2
            }
            status_main --json || true
        ')

    if printf '%s\n' "$output" | jq -e '
        .status == "warn" and
        .tools == 12 and
        (.warnings | sort) == ["missing: bun", "missing: cargo", "missing: claude"] and
        (.errors | length == 0)
    ' >/dev/null 2>&1; then
        harness_pass "status repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "status repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_status_can_be_sourced_without_running_main() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME"         TEST_STATUS_SCRIPT="$STATUS_SH"         bash -lc '
            set +e +u
            set +o pipefail
            HOME=relative-home
            set -- --bogus keep
            source "$TEST_STATUS_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            script_dir_set=unset
            [[ -v SCRIPT_DIR ]] && script_dir_set=set
            declare -F status_main >/dev/null
            printf "%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$script_dir_set"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|unset" ]]; then
        harness_pass "status can be sourced without leaking script path state"
    else
        harness_fail "status can be sourced without leaking script path state" "$output"
    fi

    cleanup_mock_env
}
test_status_ignores_relative_home_state_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    cat > "$STALE_HOME/.gtbi/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "/trap/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
JSON
    printf '9.9.9\n' > "$STALE_HOME/.gtbi/VERSION"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash "$STATUS_SH" --json)

    if printf '%s\n' "$output" | jq -e '.last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status ignores relative HOME state trap"
    else
        harness_fail "status ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_changelog_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/changelog.sh" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog uses installed-layout state under root home"
    else
        harness_fail "changelog uses installed-layout state under root home" "$output"
    fi

    cleanup_mock_env
}

test_changelog_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/changelog.sh" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog falls back to system state when user state is missing"
    else
        harness_fail "changelog falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_changelog_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$CHANGELOG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog uses target_home from system state when getent is unavailable"
    else
        harness_fail "changelog uses target_home from system state when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}


test_changelog_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_SYSTEM_STATE_FILE"

    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="tester" TARGET_HOME="$TEST_TARGET_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CHANGELOG_SCRIPT="$CHANGELOG_SH" \
        bash -lc '
            source "$TEST_CHANGELOG_SCRIPT"
            refresh_changelog_paths
            printf "gtbi=%s\nstate=%s\nfile=%s\n" "${_CHANGELOG_GTBI_HOME:-}" "$(resolve_changelog_state_file 2>/dev/null || true)" "$(find_changelog 2>/dev/null || true)"
        ' 2>/dev/null)
    expected=$'gtbi='"$TEST_TARGET_HOME"$'/.gtbi\nstate='"$TEST_TARGET_HOME"$'/.gtbi/state.json\nfile='"$TEST_TARGET_HOME"$'/.gtbi/CHANGELOG.md'

    if [[ "$output" == "$expected" ]]; then
        harness_pass "changelog uses explicit target home when state is missing"
    else
        harness_fail "changelog uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_changelog_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env

    mkdir -p "$TEST_ROOT_HOME/.gtbi"
    cat > "$TEST_ROOT_HOME/.gtbi/state.json" <<'JSON'
{
  "target_user": "root",
  "target_home": "/trap/root-home"
}
JSON
    cat > "$TEST_ROOT_HOME/.gtbi/CHANGELOG.md" <<'EOF'
# Changelog

## [9.9.9] - 2030-01-01

### Added
- Trap entry
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="ghost" TARGET_HOME="$TEST_HOME/missing-target-home" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CHANGELOG_SCRIPT="$CHANGELOG_SH" \
        bash -lc '
            source "$TEST_CHANGELOG_SCRIPT"
            refresh_changelog_paths
            printf "gtbi=%s\nstate=%s\nfile=%s\n" "${_CHANGELOG_GTBI_HOME:-}" "$(resolve_changelog_state_file 2>/dev/null || true)" "$(find_changelog 2>/dev/null || true)"
        ' 2>/dev/null)

    if [[ "$output" == $'gtbi=\nstate=\nfile=' ]]; then
        harness_pass "changelog does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "changelog does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_changelog_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$CHANGELOG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "changelog repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_changelog_ignores_relative_home_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    cat > "$STALE_HOME/.gtbi/CHANGELOG.md" <<'EOF'
# Changelog

## [9.9.9] - 2030-01-01

### Added
- Trap entry
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash "$CHANGELOG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog ignores relative HOME trap"
    else
        harness_fail "changelog ignores relative HOME trap" "$output"
    fi

    cleanup_mock_env
}

test_changelog_can_be_sourced_without_leaking_install_context() {
    local output=""

    output=$(HOME='relative-home' bash -c '
        set +e +u
        set +o pipefail
        set -- --bogus keep
        source "'$CHANGELOG_SH'" >/dev/null 2>&1
        errexit=off
        nounset=off
        pipefail_state=off
        gtbi_home_set=unset
        gtbi_repo_set=unset
        color_set=unset
        [[ $- == *e* ]] && errexit=on
        [[ $- == *u* ]] && nounset=on
        if shopt -qo pipefail 2>/dev/null; then
            pipefail_state=on
        fi
        [[ -v GTBI_HOME ]] && gtbi_home_set=set
        [[ -v GTBI_REPO ]] && gtbi_repo_set=set
        [[ -v C_RESET ]] && color_set=set
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$errexit" "$nounset" "$pipefail_state" "$#" "$1" "$2" "$gtbi_home_set" "$gtbi_repo_set" "$color_set"
    ' 2>/dev/null)

    if [[ "$output" == "relative-home|off|off|off|2|--bogus|keep|unset|unset|unset" ]]; then
        harness_pass "changelog can be sourced without leaking install context"
    else
        harness_fail "changelog can be sourced without leaking install context" "$output"
    fi
}

test_changelog_sourced_helper_uses_cached_current_home_when_runtime_home_is_poisoned() {
    setup_mock_env

    local current_user=""
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    local output=""
    output=$(HOME="$TEST_HOME" CURRENT_USER="$current_user" TEST_CHANGELOG_SCRIPT="$CHANGELOG_SH"         bash -c '
            source "$TEST_CHANGELOG_SCRIPT" >/dev/null 2>&1
            HOME=relative-home
            getent() { return 127; }
            printf "%s\n" "$(changelog_home_for_user "$CURRENT_USER" 2>/dev/null || true)"
        ' 2>/dev/null)

    if [[ "$output" == "$TEST_HOME" ]]; then
        harness_pass "changelog sourced helper uses cached current home when runtime HOME is poisoned"
    else
        harness_fail "changelog sourced helper uses cached current home when runtime HOME is poisoned" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/export-config.sh" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.gtbi_version == "2.0.0" and .settings.mode == "safe" and .tools.bun.version == "1.2.3" and .agents.claude.version == "1.2.3" and (.modules | length == 2)' >/dev/null 2>&1; then
        harness_pass "export-config uses installed-layout state and target-user PATH under root home"
    else
        harness_fail "export-config uses installed-layout state and target-user PATH under root home" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_EXPORT_SCRIPT="$EXPORT_CONFIG_SH"         bash -lc '
            source "$TEST_EXPORT_SCRIPT"
            prepare_target_context
            printf "user=%s\nhome=%s\ngtbi=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_EXPORT_GTBI_HOME:-}" "${_EXPORT_STATE_FILE:-}"
        ' 2>/dev/null)
    expected=$'user=tester
home='"$TEST_TARGET_HOME"$'
gtbi='"$TEST_INSTALLED_GTBI"$'
state='"$TEST_INSTALLED_GTBI/state.json"

    if [[ "$output" == "$expected" ]]; then
        harness_pass "export-config uses explicit target home when state is missing"
    else
        harness_fail "export-config uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_export_config_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"

    local missing_target_home="$TEST_HOME/missing-target-home"
    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$missing_target_home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_EXPORT_SCRIPT="$EXPORT_CONFIG_SH"         bash -lc '
            source "$TEST_EXPORT_SCRIPT"
            prepare_target_context
            printf "user=%s\nhome=%s\ngtbi=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_EXPORT_GTBI_HOME:-}" "${_EXPORT_STATE_FILE:-}"
        ' 2>/dev/null)
    expected=$'user=ghost
home='"$missing_target_home"$'
gtbi=
state='

    if [[ "$output" == "$expected" ]]; then
        harness_pass "export-config does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "export-config does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_export_config_installed_script_ignores_poisoned_explicit_gtbi_home() {
    setup_installed_layout_env

    local poisoned_gtbi_home="$TEST_HOME/poisoned/.gtbi"
    mkdir -p "$poisoned_gtbi_home"

    cat > "$poisoned_gtbi_home/state.json" <<'JSON'
{
  "mode": "poison",
  "target_user": "tester",
  "target_home": "/poison/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
JSON
    printf '9.9.9\n' > "$poisoned_gtbi_home/VERSION"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$poisoned_gtbi_home" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/export-config.sh" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.gtbi_version == "2.0.0" and .settings.mode == "safe" and .tools.bun.version == "1.2.3" and .agents.claude.version == "1.2.3" and (.modules | length == 2)' >/dev/null 2>&1; then
        harness_pass "export-config installed script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "export-config installed script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/export-config.sh" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.gtbi_version == "2.0.0" and .settings.mode == "safe" and .tools.bun.version == "1.2.3" and .agents.claude.version == "1.2.3" and (.modules | length == 2)' >/dev/null 2>&1; then
        harness_pass "export-config falls back to system state when user state is missing"
    else
        harness_fail "export-config falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '
        .metadata.gtbi_version == "2.0.0" and
        (.modules | length) == 2 and
        .modules == ["alpha", "module \"beta\" \\\\ path"] and
        .tools.bun.version == "1.2.3" and
        .agents.claude.version == "1.2.3"
    ' >/dev/null 2>&1; then
        harness_pass "export-config uses target_home from system state when getent is unavailable"
    else
        harness_fail "export-config uses target_home from system state when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_export_config_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '
        .metadata.gtbi_version == "2.0.0" and
        .settings.mode == "safe" and
        (.modules | length) == 2 and
        .modules == ["alpha", "module \"beta\" \\\\ path"] and
        .tools.bun.version == "1.2.3" and
        .agents.claude.version == "1.2.3"
    ' >/dev/null 2>&1; then
        harness_pass "export-config repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "export-config repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_export_config_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '
        (.modules | length) == 2 and
        .modules == ["alpha", "module \"beta\" \\\\ path"] and
        .settings.mode == "safe"
    ' >/dev/null 2>&1; then
        harness_pass "export-config repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "export-config repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_export_config_can_be_sourced_without_mutating_caller_env() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME"         TEST_EXPORT_CONFIG_SCRIPT="$EXPORT_CONFIG_SH"         bash -lc '
            set +e +u
            set +o pipefail
            HOME=relative-home
            PATH=/usr/bin:/bin
            unset TARGET_HOME TARGET_USER
            set -- --bogus keep
            source "$TEST_EXPORT_CONFIG_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            target_home_set=unset
            target_user_set=unset
            gtbi_home_set=unset
            script_dir_set=unset
            output_format_set=unset
            output_file_set=unset
            state_file_set=unset
            version_file_set=unset
            helpers_file_set=unset
            manifest_file_set=unset
            [[ -v TARGET_HOME ]] && target_home_set=set
            [[ -v TARGET_USER ]] && target_user_set=set
            [[ -v GTBI_HOME ]] && gtbi_home_set=set
            [[ -v SCRIPT_DIR ]] && script_dir_set=set
            [[ -v OUTPUT_FORMAT ]] && output_format_set=set
            [[ -v OUTPUT_FILE ]] && output_file_set=set
            [[ -v STATE_FILE ]] && state_file_set=set
            [[ -v VERSION_FILE ]] && version_file_set=set
            [[ -v INSTALL_HELPERS_FILE ]] && helpers_file_set=set
            [[ -v MANIFEST_INDEX_FILE ]] && manifest_file_set=set
            declare -F export_config_main >/dev/null
            printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$PATH" "$target_home_set" "$target_user_set" "$gtbi_home_set" "$script_dir_set" "$output_format_set" "$output_file_set" "$state_file_set" "$version_file_set" "$helpers_file_set" "$manifest_file_set"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|/usr/bin:/bin|unset|unset|unset|unset|unset|unset|unset|unset|unset|unset" ]]; then
        harness_pass "export-config can be sourced without leaking install context"
    else
        harness_fail "export-config can be sourced without leaking install context" "$output"
    fi

    cleanup_mock_env
}
test_export_config_ignores_relative_home_state_trap() {

    setup_system_state_target_home_only_env
    setup_relative_home_trap

    cat > "$STALE_HOME/.gtbi/state.json" <<'JSON'
{
  "mode": "trap",
  "target_user": "tester",
  "target_home": "/trap/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
JSON
    printf '9.9.9\n' > "$STALE_HOME/.gtbi/VERSION"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" GTBI_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.gtbi_version == "2.0.0" and .settings.mode == "safe"' >/dev/null 2>&1; then
        harness_pass "export-config ignores relative HOME state trap"
    else
        harness_fail "export-config ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_export_config_does_not_infer_target_home_from_markerless_gtbi_home() {
    setup_mock_env

    local bogus_gtbi_home="$TEST_HOME/bogus/.gtbi"
    mkdir -p "$bogus_gtbi_home"

    cat > "$TEST_INSTALL_HELPERS" <<EOF
#!/usr/bin/env bash
gtbi_module_is_installed() {
    [[ "\${TARGET_HOME:-}" == "$TEST_HOME/bogus" ]] || return 1
    [[ "\$1" == "alpha" ]]
}
EOF
    chmod +x "$TEST_INSTALL_HELPERS"

    local output=""
    output=$(HOME="relative-home" GTBI_HOME="$bogus_gtbi_home" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" \
        GTBI_INSTALL_HELPERS_SH="$TEST_INSTALL_HELPERS" GTBI_MANIFEST_INDEX_SH="$TEST_MANIFEST_INDEX" \
        PATH="/usr/bin:/bin" bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '(.modules | length) == 0' >/dev/null 2>&1; then
        harness_pass "export-config ignores markerless GTBI_HOME target-home inference"
    else
        harness_fail "export-config ignores markerless GTBI_HOME target-home inference" "$output"
    fi

    cleanup_mock_env
}

test_continue_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"Installation in progress"* ]] && [[ "$output" == *"Phase:"*bootstrap* ]]; then
        harness_pass "continue discovers installed-layout state under root home"
    else
        harness_fail "continue discovers installed-layout state under root home" "$output"
    fi

    cleanup_mock_env
}

test_continue_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CONTINUE_SCRIPT="$CONTINUE_SH" \
        bash -lc '
            source "$TEST_CONTINUE_SCRIPT"
            get_install_state_file
        ' 2>&1)

    if [[ "$output" == "$TEST_TARGET_HOME/.gtbi/state.json" ]]; then
        harness_pass "continue uses target_home from system state when getent is unavailable"
    else
        harness_fail "continue uses target_home from system state when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}


test_continue_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_SYSTEM_STATE_FILE"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="tester" TARGET_HOME="$TEST_TARGET_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CONTINUE_SCRIPT="$CONTINUE_SH" \
        bash -lc '
            source "$TEST_CONTINUE_SCRIPT"
            get_install_state_file
        ' 2>&1)

    if [[ "$output" == "$TEST_TARGET_HOME/.gtbi/state.json" ]]; then
        harness_pass "continue uses explicit target home when state is missing"
    else
        harness_fail "continue uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_continue_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"

    mkdir -p "$TEST_ROOT_HOME/.gtbi"
    cat > "$TEST_ROOT_HOME/.gtbi/state.json" <<'JSON'
{
  "target_user": "root",
  "target_home": "/trap/root-home"
}
JSON

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="ghost" TARGET_HOME="$TEST_HOME/missing-target-home" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CONTINUE_SCRIPT="$CONTINUE_SH" \
        bash -lc '
            source "$TEST_CONTINUE_SCRIPT"
            printf "%s\n" "$(get_install_state_file 2>/dev/null || true)"
        ' 2>&1)

    if [[ -z "$output" ]]; then
        harness_pass "continue does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "continue does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_continue_ignores_relative_home_state_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    cat > "$STALE_HOME/.gtbi/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "/trap/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
JSON

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" TEST_CONTINUE_SCRIPT="$CONTINUE_SH" \
        bash -lc '
            source "$TEST_CONTINUE_SCRIPT"
            get_install_state_file
        ' 2>&1)

    if [[ "$output" == "$TEST_TARGET_HOME/.gtbi/state.json" ]]; then
        harness_pass "continue ignores relative HOME state trap"
    else
        harness_fail "continue ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_continue_ignores_generic_install_process_matches() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    cat > "$TEST_INSTALLED_GTBI/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"bash.*install.sh.*--mode"*|*"bash.*install.sh.*--yes"*|*"bash.*install.sh.*--resume"*|*"bash -s -- .*--resume"*)
    exit 0
    ;;
esac
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"No active installation"* ]] && [[ "$output" != *"Installation in progress"* ]]; then
        harness_pass "continue ignores generic install.sh process matches"
    else
        harness_fail "continue ignores generic install.sh process matches" "$output"
    fi

    cleanup_mock_env
}

test_continue_failed_state_beats_runtime_probe() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    cat > "$TEST_INSTALLED_GTBI/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "failed_phase": "agents",
  "failed_step": "install codex"
}
JSON

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"Installation failed"* ]] && \
       [[ "$output" == *"install codex"* ]] && \
       [[ "$output" != *"Installation in progress"* ]]; then
        harness_pass "continue failure status beats loose runtime probes"
    else
        harness_fail "continue failure status beats loose runtime probes" "$output"
    fi

    cleanup_mock_env
}

test_continue_failed_state_prints_resume_hint() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local resume_cmd="curl -fsSL https://raw.githubusercontent.com/jonbackhaus/gtbi/2463b6a6e4338d74502c7bb34cb02ab8ca8e2ad4/install.sh | bash -s -- --resume --ref 2463b6a6e4338d74502c7bb34cb02ab8ca8e2ad4 --yes"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<JSON
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "failed_phase": "stack",
  "failed_step": "MCP Agent Mail",
  "resume_hint": "$resume_cmd"
}
JSON

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"To resume:"* ]] && \
       [[ "$output" == *"$resume_cmd"* ]] && \
       [[ "$output" != *"rerun the installer with --resume"* ]]; then
        harness_pass "continue failed state prints persisted resume hint"
    else
        harness_fail "continue failed state prints persisted resume hint" "$output"
    fi

    cleanup_mock_env
}

test_continue_reports_installed_layout_log_locations() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home
    mkdir -p "$TEST_INSTALLED_GTBI/logs"
    printf 'install log\n' > "$TEST_INSTALLED_GTBI/logs/install-20260310.log"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"$TEST_INSTALLED_GTBI/logs/install-20260310.log"* ]]; then
        harness_pass "continue reports installed-layout log paths"
    else
        harness_fail "continue reports installed-layout log paths" "$output"
    fi

    cleanup_mock_env
}

test_continue_live_log_hint_uses_installed_layout_log_dir() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash -c '
            source "'"$TEST_INSTALLED_GTBI"'/scripts/lib/continue.sh"
            get_log_root_hint
        ' 2>&1)

    if [[ "$output" == "$TEST_INSTALLED_GTBI/logs" ]]; then
        harness_pass "continue live-log hint uses installed-layout log dir"
    else
        harness_fail "continue live-log hint uses installed-layout log dir" "$output"
    fi

    cleanup_mock_env
}

test_continue_can_be_sourced_without_leaking_install_context() {
    local output=""

    output=$(HOME='relative-home' bash -c '
        set +e +u
        set +o pipefail
        set -- --bogus keep
        source "'$CONTINUE_SH'" >/dev/null 2>&1
        errexit=off
        nounset=off
        pipefail_state=off
        script_dir_set=unset
        log_dir_set=unset
        color_set=unset
        [[ $- == *e* ]] && errexit=on
        [[ $- == *u* ]] && nounset=on
        if shopt -qo pipefail 2>/dev/null; then
            pipefail_state=on
        fi
        [[ -v SCRIPT_DIR ]] && script_dir_set=set
        [[ -v GTBI_LOG_DIR ]] && log_dir_set=set
        [[ -v RED ]] && color_set=set
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$errexit" "$nounset" "$pipefail_state" "$#" "$1" "$2" "$script_dir_set" "$log_dir_set" "$color_set"
    ' 2>/dev/null)

    if [[ "$output" == "relative-home|off|off|off|2|--bogus|keep|unset|unset|unset" ]]; then
        harness_pass "continue can be sourced without leaking install context"
    else
        harness_fail "continue can be sourced without leaking install context" "$output"
    fi
}

test_continue_sourced_helper_uses_cached_current_home_when_runtime_home_is_poisoned() {
    setup_mock_env

    local current_user=""
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    local output=""
    output=$(HOME="$TEST_HOME" CURRENT_USER="$current_user" TEST_CONTINUE_SCRIPT="$CONTINUE_SH"         bash -c '
            source "$TEST_CONTINUE_SCRIPT" >/dev/null 2>&1
            HOME=relative-home
            getent() { return 127; }
            printf "%s\n" "$(home_for_user "$CURRENT_USER" 2>/dev/null || true)"
        ' 2>/dev/null)

    if [[ "$output" == "$TEST_HOME" ]]; then
        harness_pass "continue sourced helper uses cached current home when runtime HOME is poisoned"
    else
        harness_fail "continue sourced helper uses cached current home when runtime HOME is poisoned" "$output"
    fi

    cleanup_mock_env
}

test_other_sourced_helpers_use_cached_current_home_when_runtime_home_is_poisoned() {
    setup_mock_env

    local current_user=""
    local failures=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0

        output=$(HOME="$TEST_HOME" CURRENT_USER="$current_user" \
            bash -c '
                script="$1"
                func="$2"
                label="$3"
                shift 3
                set --
                source "$script" >/dev/null 2>&1
                HOME=relative-home
                case "$label" in
                    dashboard)
                        dashboard_getent_passwd_entry() { return 127; }
                        ;;
                    info)
                        info_getent_passwd_entry() { return 127; }
                        ;;
                    support)
                        support_getent_passwd_entry() { return 127; }
                        ;;
                    status)
                        _status_getent_passwd_entry() { return 127; }
                        ;;
                    export)
                        export_getent_passwd_entry() { return 127; }
                        ;;
                    cheatsheet)
                        cheatsheet_getent_passwd_entry() { return 127; }
                        ;;
                    onboard)
                        onboard_lookup_passwd_home() { return 1; }
                        ;;
                    smoke)
                        _smoke_getent_passwd_entry() { return 1; }
                        ;;
                esac
                "$func" "$CURRENT_USER"
            ' _ "$script" "$func" "$label" 2>&1) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$TEST_HOME" ]]; then
            printf -v failures '%s%s\n' "$failures" "${label}: status=${status} output=${output}"
        fi
    done <<EOF

dashboard|$DASHBOARD_SH|dashboard_home_for_user
info|$INFO_SH|info_home_for_user
support|$SUPPORT_SH|support_home_for_user
status|$STATUS_SH|_status_home_for_user
export|$EXPORT_CONFIG_SH|home_for_user
cheatsheet|$CHEATSHEET_SH|cheatsheet_home_for_user
onboard|$ONBOARD_SH|onboard_home_for_user
smoke|$SMOKE_TEST_SH|_smoke_home_for_user
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "other sourced helpers use cached current home when runtime HOME is poisoned"
    else
        harness_fail "other sourced helpers use cached current home when runtime HOME is poisoned" "$failures"
    fi

    cleanup_mock_env
}

test_continue_scans_nonstandard_homes_via_getent() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.gtbi"
    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TEST_CONTINUE_SCRIPT="$CONTINUE_SH" TEST_TARGET_HOME="$TEST_TARGET_HOME" \
        bash -lc '
            source "$TEST_CONTINUE_SCRIPT"
            continue_getent_passwd_entry() {
                if [[ "${1:-}" == "tester" ]]; then
                    printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
                    return 0
                fi
                if [[ $# -eq 0 ]]; then
                    printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
                    return 0
                fi
                return 1
            }
            get_install_state_file
        ' 2>&1)

    if [[ "$output" == "$TEST_TARGET_HOME/.gtbi/state.json" ]]; then
        harness_pass "continue scans nonstandard homes via getent"
    else
        harness_fail "continue scans nonstandard homes via getent" "$output"
    fi

    cleanup_mock_env
}

test_info_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/info.sh" --json)

    if printf '%s\n' "$output" | jq -e \
        '.installation.date == "2026-03-09" and .onboard.total_lessons == 1 and .onboard.next_lesson == "Lesson 1 - Installed Lesson"' \
        >/dev/null 2>&1; then
        harness_pass "info uses installed-layout state and lessons under root home"
    else
        harness_fail "info uses installed-layout state and lessons under root home" "$output"
    fi

    cleanup_mock_env
}

test_info_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_INFO_SCRIPT="$INFO_SH"         bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_INFO_RESOLVED_GTBI_HOME:-}"
        ' 2>/dev/null)
    expected=$'user=tester
home='"$TEST_TARGET_HOME"$'
gtbi='"$TEST_INSTALLED_GTBI"

    if [[ "$output" == "$expected" ]]; then
        harness_pass "info uses explicit target home when state is missing"
    else
        harness_fail "info uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_info_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"

    local missing_target_home="$TEST_HOME/missing-target-home"
    local output=""
    local expected=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$missing_target_home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_INFO_SCRIPT="$INFO_SH"         bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_INFO_RESOLVED_GTBI_HOME:-}"
        ' 2>/dev/null)
    expected=$'user=ghost
home='"$missing_target_home"$'
gtbi='

    if [[ "$output" == "$expected" ]]; then
        harness_pass "info does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "info does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_info_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_TARGET_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$INFO_SH" --json)

    if printf '%s\n' "$output" | jq -e \
        '.installation.date == "2026-03-09" and .onboard.total_lessons == 1 and .onboard.next_lesson == "Lesson 1 - Installed Lesson"' \
        >/dev/null 2>&1; then
        harness_pass "info uses target_home from system state when getent is unavailable"
    else
        harness_fail "info uses target_home from system state when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_info_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_TARGET_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$INFO_SH" --json)

    if printf '%s\n' "$output" | jq -e \
        '.installation.date == "2026-03-09" and .onboard.total_lessons == 1 and .onboard.next_lesson == "Lesson 1 - Installed Lesson"' \
        >/dev/null 2>&1; then
        harness_pass "info repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "info repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_info_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_INFO_SCRIPT="$INFO_SH" \
        bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            printf "user=%s\nhome=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] \
        && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "info repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "info repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}


test_info_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    mkdir -p "$stale_home"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$#" -eq 1 ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    echo "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "staleuser" ]]; then
    echo "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_INFO_SCRIPT="$INFO_SH"         bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            printf "user=%s\nhome=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" != *"user=staleuser"* ]] && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "info prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "info prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_info_prefers_resolved_install_state_over_stale_system_state_for_target_context() {
    setup_installed_layout_env

    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    mkdir -p "$(dirname "$TEST_SYSTEM_STATE_FILE")"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$TEST_TARGET_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$TEST_HOME/users/stale",
  "bin_dir": "$TEST_HOME/stale-bin",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" TEST_INFO_SCRIPT="$TEST_INSTALLED_GTBI/scripts/lib/info.sh" bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            printf "user=%s\nhome=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "$(info_get_install_state_file)"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "info prefers resolved install state over stale system state for target context"
    else
        harness_fail "info prefers resolved install state over stale system state for target context" "$output"
    fi

    cleanup_mock_env
}

test_info_can_be_sourced_without_mutating_caller_home() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME" \
        TEST_INFO_SCRIPT="$INFO_SH" \
        bash -lc '
            HOME=relative-home
            source "$TEST_INFO_SCRIPT"
            declare -F info_prepare_context >/dev/null
            printf "%s|%s\n" "$HOME" "${GTBI_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|" ]]; then
        harness_pass "info can be sourced without leaking GTBI_HOME"
    else
        harness_fail "info can be sourced without leaking GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_info_ignores_relative_home_state_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    mkdir -p "$STALE_HOME/.gtbi/onboard/lessons"
    cat > "$STALE_HOME/.gtbi/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "/trap/home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
JSON
    cat > "$STALE_HOME/.gtbi/onboard/lessons/01-trap.md" <<'EOF'
# Trap Lesson
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_TARGET_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" bash "$INFO_SH" --json)

    if printf '%s\n' "$output" | jq -e \
        '.installation.date == "2026-03-09" and .onboard.next_lesson == "Lesson 1 - Installed Lesson"' \
        >/dev/null 2>&1; then
        harness_pass "info ignores relative HOME state trap"
    else
        harness_fail "info ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_info_uses_target_user_path_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        TEST_INFO_SCRIPT="$TEST_INSTALLED_GTBI/scripts/lib/info.sh" \
        bash -lc '
            source "$TEST_INFO_SCRIPT"
            info_prepare_context
            info_get_installed_tools_summary
        ' 2>/dev/null)

    if [[ "$output" == "shell:✓|lang:✓|agents:✓|stack:✓" ]]; then
        harness_pass "info augments PATH from target-user install under root home"
    else
        harness_fail "info augments PATH from target-user install under root home" "$output"
    fi

    cleanup_mock_env
}

test_info_summary_ignores_current_shell_only_binaries() {
    setup_mock_env

    local target_home="$TEST_HOME/target-home"
    local runtime_home="$TEST_HOME/runtime-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p \
        "$runtime_home" \
        "$TEST_FAKE_BIN" \
        "$target_home/.oh-my-zsh" \
        "$target_home/.local/bin" \
        "$target_home/.bun/bin" \
        "$target_home/.cargo/bin" \
        "$target_home/go/bin"

    write_fake_command "$target_home/.local/bin/zsh" "zsh 5.9"
    write_fake_command "$target_home/.bun/bin/bun" "1.2.3"
    write_fake_command "$target_home/.local/bin/uv" "uv 0.8.0"
    write_fake_command "$target_home/.cargo/bin/rustc" "rustc 1.85.0"
    write_fake_command "$target_home/go/bin/go" "go version go1.24.0 linux/amd64"

    write_fake_command "$TEST_FAKE_BIN/claude" "claude 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/codex" "codex 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/gemini" "gemini 9.9.9"
    write_fake_command "$TEST_FAKE_BIN/ntm" "ntm 9.9.9"

    local output=""
    output=$(HOME="$runtime_home" TARGET_HOME="$target_home" GTBI_BIN_DIR="$target_home/.local/bin" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" TEST_INFO_SCRIPT="$INFO_SH" \
        bash -lc 'source "$TEST_INFO_SCRIPT"; info_get_installed_tools_summary' 2>/dev/null)

    if [[ "$output" == shell:✓\|lang:✓\|agents:○\|stack:* ]]; then
        harness_pass "info summary ignores current-shell-only agent binaries"
    else
        harness_fail "info summary ignores current-shell-only agent binaries" "$output"
    fi

    cleanup_mock_env
}

test_info_binary_path_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" TEST_INFO_SCRIPT="$INFO_SH" bash -lc 'source "$TEST_INFO_SCRIPT"; info_prepare_context; info_binary_path claude' 2>/dev/null)

    if [[ "$output" == "$TEST_TARGET_HOME/.local/bin/claude" ]]; then
        harness_pass "info binary path ignores other-user home bin_dir from state"
    else
        harness_fail "info binary path ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_info_binary_path_prefers_persisted_bin_dir_over_poisoned_env_bin_dir() {
    setup_installed_layout_env

    local custom_bin="$TEST_HOME/custom-bin"
    mkdir -p "$custom_bin"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    rm -f "$TEST_TARGET_HOME/.local/bin/claude"
    write_fake_command "$custom_bin/claude" "claude 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_BIN_DIR="$TEST_FAKE_BIN" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" TEST_INFO_SCRIPT="$INFO_SH" bash -lc 'source "$TEST_INFO_SCRIPT"; info_prepare_context; info_binary_path claude' 2>/dev/null)

    if [[ "$output" == "$custom_bin/claude" ]]; then
        harness_pass "info binary path prefers persisted bin_dir over poisoned env bin_dir"
    else
        harness_fail "info binary path prefers persisted bin_dir over poisoned env bin_dir" "$output"
    fi

    cleanup_mock_env
}

test_support_bundle_uses_installed_layout_under_root_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home

    local output_dir="$TEST_HOME/support-out"
    mkdir -p "$output_dir"

    local archive_path=""
    archive_path=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        bash "$TEST_INSTALLED_GTBI/scripts/lib/support.sh" --output "$output_dir")

    local bundle_dir="$archive_path"
    if [[ "$bundle_dir" == *.tar.gz ]]; then
        bundle_dir="${bundle_dir%.tar.gz}"
    fi

    if [[ -f "$bundle_dir/environment.json" ]] \
        && [[ -f "$bundle_dir/state.json" ]] \
        && jq -e --arg gtbi_home "$TEST_INSTALLED_GTBI" --arg target_home "$TEST_TARGET_HOME" \
            '.gtbi_home == $gtbi_home and .home == $target_home and .user == "tester"' \
            "$bundle_dir/environment.json" >/dev/null 2>&1; then
        harness_pass "support bundle uses installed-layout home and target user under root home"
    else
        harness_fail "support bundle uses installed-layout home and target user under root home" "$archive_path"
    fi

    cleanup_mock_env
}

test_support_bundle_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_env

    local output_dir="$TEST_HOME/support-out"
    mkdir -p "$output_dir"

    local archive_path=""
    archive_path=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=1 PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$SUPPORT_SH" --output "$output_dir")

    local bundle_dir="$archive_path"
    if [[ "$bundle_dir" == *.tar.gz ]]; then
        bundle_dir="${bundle_dir%.tar.gz}"
    fi

    if [[ -f "$bundle_dir/environment.json" ]] \
        && [[ -f "$bundle_dir/state.json" ]] \
        && jq -e --arg gtbi_home "$TEST_INSTALLED_GTBI" --arg target_home "$TEST_TARGET_HOME" \
            '.gtbi_home == $gtbi_home and .home == $target_home and .user == "tester"' \
            "$bundle_dir/environment.json" >/dev/null 2>&1; then
        harness_pass "support bundle uses target_home from system state when getent is unavailable"
    else
        harness_fail "support bundle uses target_home from system state when getent is unavailable" "$archive_path"
    fi

    cleanup_mock_env
}

test_support_bundle_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    local output_dir="$TEST_HOME/support-out"
    mkdir -p "$output_dir"

    local archive_path=""
    archive_path=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        SUPPORT_BUNDLE_DOCTOR_TIMEOUT=1 \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$SUPPORT_SH" --output "$output_dir")

    local bundle_dir="$archive_path"
    if [[ "$bundle_dir" == *.tar.gz ]]; then
        bundle_dir="${bundle_dir%.tar.gz}"
    fi

    if [[ -f "$bundle_dir/environment.json" ]] \
        && jq -e --arg target_home "$TEST_TARGET_HOME" \
            '.user == "tester" and .home == $target_home' \
            "$bundle_dir/environment.json" >/dev/null 2>&1; then
        harness_pass "support bundle repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "support bundle repo-local prefers system-state target_user over stale installed state" "$archive_path"
    fi

    cleanup_mock_env
}

test_support_can_be_sourced_without_running_main() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME"         TEST_SUPPORT_SCRIPT="$SUPPORT_SH"         bash -lc '
            set +e +u
            set +o pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            HOME=relative-home
            set -- --bogus keep
            source "$TEST_SUPPORT_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            gtbi_home_set=unset
            script_dir_set=unset
            [[ -v GTBI_HOME ]] && gtbi_home_set=set
            [[ -v SCRIPT_DIR ]] && script_dir_set=set
            declare -F redact_file >/dev/null
            declare -F redact_bundle >/dev/null
            printf "%s|%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$gtbi_home_set" "$script_dir_set"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|unset|unset" ]]; then
        harness_pass "support can be sourced without leaking install context"
    else
        harness_fail "support can be sourced without leaking install context" "$output"
    fi

    cleanup_mock_env
}

test_support_bundle_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output_dir="$TEST_HOME/support-out"
    mkdir -p "$output_dir"

    local archive_path=""
    archive_path=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        SUPPORT_BUNDLE_DOCTOR_TIMEOUT=1 \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$SUPPORT_SH" --output "$output_dir")

    local bundle_dir="$archive_path"
    if [[ "$bundle_dir" == *.tar.gz ]]; then
        bundle_dir="${bundle_dir%.tar.gz}"
    fi

    if [[ -f "$bundle_dir/environment.json" ]] \
        && [[ -f "$bundle_dir/state.json" ]] \
        && jq -e --arg gtbi_home "$TEST_INSTALLED_GTBI" --arg target_home "$TEST_TARGET_HOME" \
            '.gtbi_home == $gtbi_home and .home == $target_home and .user == "tester"' \
            "$bundle_dir/environment.json" >/dev/null 2>&1; then
        harness_pass "support bundle repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "support bundle repo-local script ignores poisoned explicit GTBI_HOME" "$archive_path"
    fi

    cleanup_mock_env
}

test_dashboard_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH" \
        bash -lc '
            source "$TEST_DASHBOARD_SCRIPT"
            dashboard_prepare_context
            printf "user=%s\nhome=%s\n" "${_DASHBOARD_RESOLVED_TARGET_USER:-}" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] \
        && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "dashboard repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "dashboard repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_can_be_sourced_without_mutating_caller_env() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME" \
        TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH" \
        bash -lc '
            set +e +u
            set +o pipefail
            HOME=relative-home
            set -- --bogus keep
            source "$TEST_DASHBOARD_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            declare -F dashboard_prepare_context >/dev/null
            printf "%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "${GTBI_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|" ]]; then
        harness_pass "dashboard can be sourced without leaking GTBI_HOME"
    else
        harness_fail "dashboard can be sourced without leaking GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_copy_install_ignores_relative_home_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$TEST_INSTALLED_GTBI/scripts/lib" "$STALE_HOME/.gtbi/scripts/lib"
    cp "$DASHBOARD_SH" "$TEST_ROOT_HOME/.local/bin/dashboard"
    chmod +x "$TEST_ROOT_HOME/.local/bin/dashboard"

    cat > "$TEST_INSTALLED_GTBI/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>copied-dashboard-info</html>\n'
EOF
    cat > "$STALE_HOME/.gtbi/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>trap-dashboard-info</html>\n'
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/info.sh" "$STALE_HOME/.gtbi/scripts/lib/info.sh"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" dashboard generate --force 2>&1)

    if [[ "$output" == *"$TEST_INSTALLED_GTBI/dashboard/index.html"* ]] \
        && [[ -f "$TEST_INSTALLED_GTBI/dashboard/index.html" ]] \
        && [[ ! -e "$STALE_HOME/.gtbi/dashboard/index.html" ]]; then
        harness_pass "copied dashboard ignores relative HOME trap"
    else
        harness_fail "copied dashboard ignores relative HOME trap" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_copy_install_ignores_relative_home_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$TEST_INSTALLED_GTBI/zsh" "$STALE_HOME/.gtbi/zsh"
    cp "$CHEATSHEET_SH" "$TEST_ROOT_HOME/.local/bin/cheatsheet"
    chmod +x "$TEST_ROOT_HOME/.local/bin/cheatsheet"

    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
alias cod='codex'
EOF
    cat > "$STALE_HOME/.gtbi/zsh/gtbi.zshrc" <<'EOF'
alias trapcmd='echo trap'
EOF
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" cheatsheet --json 2>&1)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" \
        '.source == $zshrc and ([.entries[].name] | index("cod")) != null and ([.entries[].name] | index("trapcmd")) == null' \
        >/dev/null 2>&1; then
        harness_pass "copied cheatsheet ignores relative HOME trap"
    else
        harness_fail "copied cheatsheet ignores relative HOME trap" "$output"
    fi

    cleanup_mock_env
}

test_state_library_ignores_relative_home_target_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"
    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="relative-home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -c 'source "$1"; unset TARGET_HOME; TARGET_USER="$(id -un 2>/dev/null || whoami 2>/dev/null)"; printf "home=%s\n" "$(state_resolve_target_home)"; printf "state=%s\n" "$(state_get_file)"' _ \
        "$STATE_SH")

    local resolved_home=""
    local state_file=""
    resolved_home="$(printf '%s\n' "$output" | sed -n 's/^home=//p' | head -n 1)"
    state_file="$(printf '%s\n' "$output" | sed -n 's/^state=//p' | head -n 1)"

    if [[ "$resolved_home" == /* ]] && [[ "$resolved_home" != "/" ]] \
        && [[ "$resolved_home" != "relative-home" ]] \
        && [[ "$state_file" == "$resolved_home/.gtbi/state.json" ]]; then
        harness_pass "state library ignores relative HOME during target resolution"
    else
        harness_fail "state library ignores relative HOME during target resolution" "$output"
    fi

    cleanup_mock_env
}

test_smoke_test_ignores_relative_home_target_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"
    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="relative-home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -c 'source "$1"; printf "target_home=%s\n" "${_SMOKE_TARGET_HOME:-}"' _ \
        "$SMOKE_TEST_SH")

    local resolved_home=""
    resolved_home="$(printf '%s\n' "$output" | sed -n 's/^target_home=//p' | head -n 1)"

    if [[ -z "$resolved_home" ]]; then
        harness_pass "smoke test ignores relative HOME during target resolution"
    elif [[ "$resolved_home" == /* ]] && [[ "$resolved_home" != "/" ]] && [[ "$resolved_home" != "relative-home" ]]; then
        harness_pass "smoke test ignores relative HOME during target resolution"
    else
        harness_fail "smoke test ignores relative HOME during target resolution" "$output"
    fi

    cleanup_mock_env
}

test_smoke_test_does_not_guess_target_home_from_username() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"
    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="relative-home" TARGET_USER="ghostuser" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -c 'source "$1"; echo "target_home=${_SMOKE_TARGET_HOME:-}"' _ \
        "$SMOKE_TEST_SH")

    if [[ "$output" == "target_home=" ]]; then
        harness_pass "smoke test does not guess target home from username"
    else
        harness_fail "smoke test does not guess target home from username" "$output"
    fi

    cleanup_mock_env
}

test_smoke_test_can_be_sourced_without_leaking_install_context() {
    local output=""

    output=$(HOME='relative-home' PATH='/usr/bin:/bin' bash -c '
        set +e +u
        set -- --bogus keep
        source "'$SMOKE_TEST_SH'" >/dev/null 2>&1
        target_user_set=unset
        target_home_set=unset
        script_dir_set=unset
        counter_set=unset
        [[ -v TARGET_USER ]] && target_user_set=set
        [[ -v TARGET_HOME ]] && target_home_set=set
        [[ -v SCRIPT_DIR ]] && script_dir_set=set
        [[ -v CRITICAL_PASS ]] && counter_set=set
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$PATH" "$target_user_set" "$target_home_set" "$script_dir_set" "$counter_set"
    ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|/usr/bin:/bin|unset|unset|unset|unset" ]]; then
        harness_pass "smoke test can be sourced without leaking install context"
    else
        harness_fail "smoke test can be sourced without leaking install context" "$output"
    fi
}

test_smoke_test_run_preserves_caller_path_when_sourced() {
    setup_installed_layout_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="tester" PATH="/usr/bin:/bin"         bash -c 'source "$1" >/dev/null 2>&1; old_path="$PATH"; run_smoke_test >/dev/null 2>&1 || true; printf "%s\n" "$PATH"' _         "$SMOKE_TEST_SH")

    if [[ "$output" == "/usr/bin:/bin" ]]; then
        harness_pass "smoke test run preserves caller PATH when sourced"
    else
        harness_fail "smoke test run preserves caller PATH when sourced" "$output"
    fi

    cleanup_mock_env
}

test_smoke_binary_path_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="tester" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash -c 'source "$1"; _smoke_binary_path claude' _ "$SMOKE_TEST_SH")

    if [[ "$output" == "$TEST_TARGET_HOME/.local/bin/claude" ]]; then
        harness_pass "smoke binary path ignores other-user home bin_dir from state"
    else
        harness_fail "smoke binary path ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_smoke_binary_path_prefers_persisted_bin_dir_over_poisoned_env_bin_dir() {
    setup_installed_layout_env

    local custom_bin="$TEST_HOME/custom-bin"
    local stale_state_file="$TEST_HOME/stale-smoke-state.json"
    mkdir -p "$custom_bin"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
    cat > "$stale_state_file" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_ROOT_HOME",
  "bin_dir": "$TEST_FAKE_BIN",
  "started_at": "2026-03-01T00:00:00Z",
  "last_updated": "2026-03-02T00:00:00Z"
}
EOF

    rm -f "$TEST_TARGET_HOME/.local/bin/claude"
    write_fake_command "$custom_bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_FAKE_BIN/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$TEST_TARGET_HOME" TARGET_USER="tester" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_STATE_FILE="$stale_state_file" GTBI_BIN_DIR="$TEST_FAKE_BIN" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash -c 'source "$1"; _smoke_binary_path claude' _ "$SMOKE_TEST_SH")

    if [[ "$output" == "$custom_bin/claude" ]]; then
        harness_pass "smoke binary path prefers persisted bin_dir over poisoned env bin_dir"
    else
        harness_fail "smoke binary path prefers persisted bin_dir over poisoned env bin_dir" "$output"
    fi

    cleanup_mock_env
}

test_smoke_installed_script_ignores_poisoned_explicit_gtbi_home() {
    setup_installed_layout_env
    setup_poisoned_gtbi_home
    cp "$SMOKE_TEST_SH" "$TEST_INSTALLED_GTBI/scripts/lib/smoke_test.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_POISONED_GTBI_HOME" GTBI_BLUE=1 bash -c 'source "$1"; printf "bootstrap=%s\nstate=%s\n" "$(_smoke_resolve_bootstrap_state_file)" "$(_smoke_resolve_state_file)"' _ "$TEST_INSTALLED_GTBI/scripts/lib/smoke_test.sh")

    if [[ "$output" == *"bootstrap=$TEST_INSTALLED_GTBI/state.json"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "smoke installed script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "smoke installed script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_smoke_repo_local_ignores_poisoned_explicit_gtbi_home() {
    setup_system_state_target_home_env
    setup_poisoned_gtbi_home

    local output=""
    output=$(
        HOME="$TEST_ROOT_HOME" \
            GTBI_HOME="$TEST_POISONED_GTBI_HOME" \
            GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
            PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
            bash -c 'source "$1"; printf "bootstrap=%s\nstate=%s\ntarget_user=%s\ntarget_home=%s\nbin=%s\n" "$(_smoke_resolve_bootstrap_state_file)" "$(_smoke_resolve_state_file)" "${_SMOKE_TARGET_USER:-}" "${_SMOKE_TARGET_HOME:-}" "$(_smoke_binary_path claude 2>/dev/null || true)"' \
            _ "$SMOKE_TEST_SH"
    )

    if [[ "$output" == *"bootstrap=$TEST_SYSTEM_STATE_FILE"* ]] \
        && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]] \
        && [[ "$output" == *"target_user=tester"* ]] \
        && [[ "$output" == *"target_home=$TEST_TARGET_HOME"* ]] \
        && [[ "$output" == *"bin=$TEST_TARGET_HOME/.local/bin/claude"* ]]; then
        harness_pass "smoke repo-local script ignores poisoned explicit GTBI_HOME"
    else
        harness_fail "smoke repo-local script ignores poisoned explicit GTBI_HOME" "$output"
    fi

    cleanup_mock_env
}

test_smoke_prefers_explicit_gtbi_home_over_stale_system_state_for_target_context() {
    setup_installed_layout_env

    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    mkdir -p "$(dirname "$TEST_SYSTEM_STATE_FILE")"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$TEST_TARGET_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$TEST_HOME/users/stale",
  "bin_dir": "$TEST_HOME/stale-bin",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" TEST_SMOKE_SCRIPT="$SMOKE_TEST_SH" bash -lc '
            source "$TEST_SMOKE_SCRIPT"
            printf "user=%s\nhome=%s\nstate=%s\n" "${_SMOKE_TARGET_USER:-}" "${_SMOKE_TARGET_HOME:-}" "$(_smoke_resolve_state_file)"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]] && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "smoke prefers explicit GTBI_HOME over stale system state for target context"
    else
        harness_fail "smoke prefers explicit GTBI_HOME over stale system state for target context" "$output"
    fi

    cleanup_mock_env
}

test_smoke_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    mkdir -p "$stale_home"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "bin_dir": "$stale_home/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$stale_home",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
EOF

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "staleuser" ]]; then
    echo "staleuser:x:1001:1001::${stale_home}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_SMOKE_SCRIPT="$SMOKE_TEST_SH"         bash -lc '
            source "$TEST_SMOKE_SCRIPT"
            printf "home=%s\nstate=%s\n" "${_SMOKE_TARGET_HOME:-}" "$(_smoke_resolve_state_file)"
        ' 2>/dev/null)

    if [[ "$output" == *"home=$TEST_TARGET_HOME"* ]] && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "smoke prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "smoke prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_smoke_bootstrap_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_only_env

    local current_user=""
    local output=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    output=$(
        HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
            PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
            bash -c 'source "$1"; printf "target_user=%s\ntarget_home=%s\nbinary=%s\n" "${_SMOKE_TARGET_USER:-}" "${_SMOKE_TARGET_HOME:-}" "$(_smoke_binary_path claude 2>/dev/null || true)"' \
            _ "$SMOKE_TEST_SH"
    )

    if [[ "$output" == *"target_user=$current_user"* ]] \
        && [[ "$output" == *"target_home=$TEST_TARGET_HOME"* ]] \
        && [[ "$output" == *"binary=$TEST_TARGET_HOME/.local/bin/claude"* ]]; then
        harness_pass "smoke bootstrap uses system state target_home when getent is unavailable"
    else
        harness_fail "smoke bootstrap uses system state target_home when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_smoke_bootstrap_reads_state_with_poisoned_path() {
    setup_system_state_target_home_env

    local output=""

    output=$(
        HOME="relative-home" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" PATH="/nonexistent" \
            /bin/bash -c 'source "$1" >/dev/null 2>&1; printf "target_user=%s\ntarget_home=%s\n" "${_SMOKE_TARGET_USER:-}" "${_SMOKE_TARGET_HOME:-}"' \
            _ "$SMOKE_TEST_SH"
    )

    if [[ "$output" == *"target_user=tester"* ]] && [[ "$output" == *"target_home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "smoke bootstrap reads state with poisoned path"
    else
        harness_fail "smoke bootstrap reads state with poisoned path" "$output"
    fi

    cleanup_mock_env
}

test_smoke_bootstrap_recovers_local_passwd_when_getent_is_broken() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local output=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    passwd_home="$(awk -F: -v user="$current_user" '$1 == user { print $6; exit }' /etc/passwd 2>/dev/null || true)"
    passwd_home="${passwd_home%/}"

    if [[ -z "$current_user" ]] || [[ -z "$passwd_home" ]] || [[ "$passwd_home" != /* ]]; then
        harness_fail "smoke bootstrap recovers local passwd when getent is broken" "user=$current_user home=$passwd_home"
        cleanup_mock_env
        return
    fi

    output=$(
        HOME="relative-home" TARGET_USER="$current_user" PATH="/nonexistent" \
            /bin/bash -c 'getent() { return 127; }; source "$1" >/dev/null 2>&1; printf "current=%s\ntarget=%s\n" "${_SMOKE_CURRENT_HOME:-}" "${_SMOKE_TARGET_HOME:-}"' \
            _ "$SMOKE_TEST_SH"
    )

    if [[ "$output" == *"current=$passwd_home"* ]] && [[ "$output" == *"target=$passwd_home"* ]]; then
        harness_pass "smoke bootstrap recovers local passwd when getent is broken"
    else
        harness_fail "smoke bootstrap recovers local passwd when getent is broken" "$output"
    fi

    cleanup_mock_env
}

test_smoke_bootstrap_ignores_poisoned_current_user_env_and_path_tools() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local output=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    passwd_home="$(awk -F: -v user="$current_user" '$1 == user { print $6; exit }' /etc/passwd 2>/dev/null || true)"
    passwd_home="${passwd_home%/}"

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"

    if [[ -z "$current_user" ]] || [[ -z "$passwd_home" ]] || [[ "$passwd_home" != /* ]]; then
        harness_fail "smoke bootstrap ignores poisoned current user env and path tools" "user=$current_user home=$passwd_home"
        cleanup_mock_env
        return
    fi

    cat > "$TEST_FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
printf 'evil\n'
EOF
    cat > "$TEST_FAKE_BIN/whoami" <<'EOF'
#!/usr/bin/env bash
printf 'evil\n'
EOF
    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
printf 'evil:x:9999:9999::/tmp/evil:/bin/false\n'
EOF
    chmod +x "$TEST_FAKE_BIN/id" "$TEST_FAKE_BIN/whoami" "$TEST_FAKE_BIN/getent"

    output=$(
        USER="evil" LOGNAME="evil" HOME="relative-home" TARGET_USER="$current_user" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
            /bin/bash -c 'source "$1" >/dev/null 2>&1; printf "user=%s\ncurrent=%s\ntarget=%s\n" "${_SMOKE_CURRENT_USER:-}" "${_SMOKE_CURRENT_HOME:-}" "${_SMOKE_TARGET_HOME:-}"' \
            _ "$SMOKE_TEST_SH"
    )

    if [[ "$output" == *"user=$current_user"* ]] && [[ "$output" == *"current=$passwd_home"* ]] && [[ "$output" == *"target=$passwd_home"* ]]; then
        harness_pass "smoke bootstrap ignores poisoned current user env and path tools"
    else
        harness_fail "smoke bootstrap ignores poisoned current user env and path tools" "$output"
    fi

    cleanup_mock_env
}

test_runtime_helpers_resolve_current_home_from_passwd_when_home_invalid() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local failures=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    passwd_home="$TEST_HOME/passwd-home"
    mkdir -p "$passwd_home"

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0
        output=$(HOME="relative-home" CURRENT_USER="$current_user" PASSWD_HOME="$passwd_home" \
            bash -c '
                script="$1"
                func="$2"
                label="$3"
                shift 3
                set --
                source "$script"
                case "$label" in
                    continue)
                        continue_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                        ;;
                    dashboard)
                        dashboard_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                        ;;
                    info)
                        info_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                        ;;
                    changelog)
                        changelog_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                        ;;
                    onboard)
                        onboard_lookup_passwd_home() {
                            if [[ "${1:-}" == "$CURRENT_USER" ]]; then
                                printf "%s\n" "$PASSWD_HOME"
                                return 0
                            fi
                            return 1
                        }
                        ;;
                esac
                "$func"
            ' _ "$script" "$func" "$label" 2>&1) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            failures+="${label}: status=${status} output=${output}"$'\n'
        fi
    done <<EOF
continue|$CONTINUE_SH|continue_resolve_current_home
dashboard|$DASHBOARD_SH|dashboard_resolve_current_home
info|$INFO_SH|info_resolve_current_home
changelog|$CHANGELOG_SH|changelog_resolve_current_home
onboard|$ONBOARD_SH|onboard_resolve_current_home
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "runtime helpers recover current home from passwd when HOME is invalid"
    else
        harness_fail "runtime helpers recover current home from passwd when HOME is invalid" "$failures"
    fi

    cleanup_mock_env
}

test_runtime_helpers_prefer_passwd_home_over_mismatched_absolute_home() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local poisoned_home=""
    local failures=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    passwd_home="$TEST_HOME/passwd-home"
    poisoned_home="$TEST_HOME/poisoned-home"
    mkdir -p "$passwd_home" "$poisoned_home"

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0
        output=$(
            HOME="$poisoned_home" CURRENT_USER="$current_user" PASSWD_HOME="$passwd_home" \
                bash -c '
                    script="$1"
                    func="$2"
                    label="$3"
                    shift 3
                    set --
                    source "$script"
                    case "$label" in
                        continue)
                            continue_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        dashboard)
                            dashboard_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        info)
                            info_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        changelog)
                            changelog_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        support)
                            support_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        status)
                            _status_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        export)
                            export_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        cheatsheet)
                            cheatsheet_getent_passwd_entry() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$CURRENT_USER" "$PASSWD_HOME"; }
                            ;;
                        onboard)
                            onboard_lookup_passwd_home() {
                                if [[ "${1:-}" == "$CURRENT_USER" ]]; then
                                    printf "%s\n" "$PASSWD_HOME"
                                    return 0
                                fi
                                return 1
                            }
                            ;;
                    esac
                    "$func"
                ' _ "$script" "$func" "$label" 2>&1
        ) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            printf -v failures '%s%s\n' "$failures" "${label}: status=${status} output=${output}"
        fi
    done <<EOF
continue|$CONTINUE_SH|continue_resolve_current_home
dashboard|$DASHBOARD_SH|dashboard_resolve_current_home
info|$INFO_SH|info_resolve_current_home
changelog|$CHANGELOG_SH|changelog_resolve_current_home
support|$SUPPORT_SH|support_resolve_current_home
status|$STATUS_SH|_status_resolve_current_home
export|$EXPORT_CONFIG_SH|export_resolve_current_home
cheatsheet|$CHEATSHEET_SH|cheatsheet_resolve_current_home
onboard|$ONBOARD_SH|onboard_resolve_current_home
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "runtime helpers prefer passwd home over mismatched absolute HOME"
    else
        harness_fail "runtime helpers prefer passwd home over mismatched absolute HOME" "$failures"
    fi

    cleanup_mock_env
}

test_runtime_helpers_ignore_poisoned_current_user_path_tools() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local getent_bin=""
    local failures=""

    if [[ -x /usr/bin/id ]]; then
        current_user="$(/usr/bin/id -un 2>/dev/null || true)"
    elif [[ -x /bin/id ]]; then
        current_user="$(/bin/id -un 2>/dev/null || true)"
    else
        current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    fi

    if [[ -x /usr/bin/getent ]]; then
        getent_bin=/usr/bin/getent
    elif [[ -x /bin/getent ]]; then
        getent_bin=/bin/getent
    else
        getent_bin="$(command -v getent 2>/dev/null || true)"
    fi

    if [[ -n "$getent_bin" ]] && [[ -n "$current_user" ]]; then
        passwd_home="$("$getent_bin" passwd "$current_user" 2>/dev/null | cut -d: -f6)"
    fi
    if [[ -z "$passwd_home" ]] && [[ -n "$current_user" ]] && [[ -r /etc/passwd ]]; then
        passwd_home="$(awk -F: -v u="$current_user" '$1==u{print $6; exit}' /etc/passwd 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]] || [[ -z "$passwd_home" ]]; then
        harness_fail "runtime helpers ignore poisoned current user path tools" "unable to determine current user/passwd home"
        cleanup_mock_env
        return
    fi

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"

    while IFS= read -r tool; do
        [[ -n "$tool" ]] || continue
        cat > "$TEST_FAKE_BIN/$tool" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done <<'EOF'
id
whoami
getent
EOF

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0

        output=$(HOME="relative-home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"             bash -c 'script="$1"; func="$2"; shift 2; set --; source "$script"; "$func"' _             "$script" "$func" 2>&1) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            printf -v failures '%s%s\n' "$failures" "${label}: status=${status} output=${output}"
        fi
    done <<EOF
continue|$CONTINUE_SH|continue_resolve_current_home
dashboard|$DASHBOARD_SH|dashboard_resolve_current_home
info|$INFO_SH|info_resolve_current_home
changelog|$CHANGELOG_SH|changelog_resolve_current_home
support|$SUPPORT_SH|support_resolve_current_home
status|$STATUS_SH|_status_resolve_current_home
export|$EXPORT_CONFIG_SH|export_resolve_current_home
cheatsheet|$CHEATSHEET_SH|cheatsheet_resolve_current_home
onboard|$ONBOARD_SH|onboard_resolve_current_home
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "runtime helpers ignore poisoned current user path tools"
    else
        harness_fail "runtime helpers ignore poisoned current user path tools" "$failures"
    fi

    cleanup_mock_env
}

test_runtime_helpers_fail_closed_when_current_home_unresolved() {
    setup_mock_env

    local failures=""

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0
        output=$(HOME="relative-home" PATH="/usr/bin:/bin" \
            bash -c '
                script="$1"
                func="$2"
                label="$3"
                shift 3
                set --
                source "$script"
                case "$label" in
                    continue)
                        continue_getent_passwd_entry() { return 1; }
                        ;;
                    dashboard)
                        dashboard_getent_passwd_entry() { return 1; }
                        ;;
                    info)
                        info_getent_passwd_entry() { return 1; }
                        ;;
                    changelog)
                        changelog_getent_passwd_entry() { return 1; }
                        ;;
                    onboard)
                        onboard_lookup_passwd_home() { return 1; }
                        ;;
                esac
                "$func"
            ' _ "$script" "$func" "$label" 2>&1) || status=$?

        if [[ $status -eq 0 ]] || [[ -n "$output" ]]; then
            failures+="${label}: status=${status} output=${output}"$'\n'
        fi
    done <<EOF
continue|$CONTINUE_SH|continue_resolve_current_home
dashboard|$DASHBOARD_SH|dashboard_resolve_current_home
info|$INFO_SH|info_resolve_current_home
changelog|$CHANGELOG_SH|changelog_resolve_current_home
onboard|$ONBOARD_SH|onboard_resolve_current_home
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "runtime helpers fail closed when current home is unresolved"
    else
        harness_fail "runtime helpers fail closed when current home is unresolved" "$failures"
    fi

    cleanup_mock_env
}

test_runtime_helpers_fail_closed_on_invalid_passwd_home_for_target_user() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "passwd" ]] && [[ "${2:-}" == "tester" ]]; then
    echo 'tester:x:1000:1000::relative-home:/bin/bash'
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local failures=""

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        local output=""
        local status=0
        output=$(HOME="$TEST_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
            bash -c 'script="$1"; func="$2"; shift 2; set --; source "$script"; "$func" tester' _ \
            "$script" "$func" 2>&1) || status=$?

        if [[ $status -eq 0 ]] || [[ -n "$output" ]]; then
            failures+="${label}: status=${status} output=${output}"$'\n'
        fi
    done <<EOF
continue|$CONTINUE_SH|home_for_user
dashboard|$DASHBOARD_SH|dashboard_home_for_user
info|$INFO_SH|info_home_for_user
changelog|$CHANGELOG_SH|changelog_home_for_user
onboard|$ONBOARD_SH|onboard_home_for_user
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "runtime helpers fail closed on invalid passwd homes for target users"
    else
        harness_fail "runtime helpers fail closed on invalid passwd homes for target users" "$failures"
    fi

    cleanup_mock_env
}

test_doctor_dispatches_installed_layout_under_root_home() {

    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" version)

    if [[ "$output" == "2.0.0" ]]; then
        harness_pass "installed gtbi dispatcher finds VERSION and helper tree under root home"
    else
        harness_fail "installed gtbi dispatcher finds VERSION and helper tree under root home" "$output"
    fi

    cleanup_mock_env
}

test_doctor_ignores_relative_home_state_trap() {
    setup_installed_layout_env
    setup_relative_home_trap

    mkdir -p "$STALE_HOME/.local/bin"
    cat > "$STALE_HOME/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$STALE_HOME"
}
EOF
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json)

    if printf '%s\n' "$output" | jq -e --arg live_path "$TEST_TARGET_HOME/.local/bin/claude" --arg stale_path "$STALE_HOME/.local/bin/claude" '
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) == ("native (" + $live_path + ")") and
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) != ("native (" + $stale_path + ")")
    ' >/dev/null 2>&1; then
        harness_pass "doctor ignores relative HOME state trap"
    else
        harness_fail "doctor ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_doctor_uses_system_state_target_home_when_installed_state_is_stale() {
    setup_system_state_target_home_env

    mkdir -p "$TEST_INSTALLED_GTBI/bin"
    cp "$DOCTOR_SH" "$TEST_INSTALLED_GTBI/bin/gtbi"
    chmod +x "$TEST_INSTALLED_GTBI/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json)

    if printf '%s\n' "$output" | jq -e --arg live_path "$TEST_TARGET_HOME/.local/bin/claude" '
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) == ("native (" + $live_path + ")") and
        ([.checks[] | select(.id == "agent.claude") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor prefers system-state target_home over stale installed state"
    else
        harness_fail "doctor prefers system-state target_home over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_doctor_prefers_target_home_over_poisoned_gtbi_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_ROOT_HOME/.gtbi"
    cat > "$TEST_ROOT_HOME/.gtbi/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "other",
  "target_home": "$TEST_ROOT_HOME/.gtbi"
}
EOF

    local probe_file="$TEST_HOME/doctor-fix-source.env"
    cat > "$TEST_INSTALLED_GTBI/scripts/lib/doctor_fix.sh" <<EOF
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s\n' "\$HOME" "\${TARGET_HOME:-}" "\${GTBI_HOME:-}" > "$probe_file"
return 0 2>/dev/null || exit 0
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/doctor_fix.sh"

    HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_ROOT_HOME/.gtbi"         TARGET_HOME="$TEST_ROOT_HOME"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json >/dev/null 2>&1 || true

    local expected="HOME=$TEST_ROOT_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI"
    local output=""
    output="$(cat "$probe_file" 2>/dev/null || true)"

    if [[ "$output" == "$expected" ]]; then
        harness_pass "doctor sources doctor_fix with resolved target install context"
    else
        harness_fail "doctor sources doctor_fix with resolved target install context" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_wrappers_prefer_passwd_home_over_mismatched_absolute_home() {
    setup_mock_env

    local passwd_home="$TEST_HOME/passwd-home"
    local poisoned_home="$TEST_HOME/poisoned-home"
    local failures=""

    mkdir -p "$passwd_home" "$poisoned_home" "$TEST_HOME/probe"

    while IFS='|' read -r label script_path; do
        [[ -n "$label" ]] || continue
        local sourceable_wrapper="$TEST_HOME/probe/${label}-sourceable.sh"
        local output=""
        local status=0

        sed '$d' "$script_path" > "$sourceable_wrapper"
        chmod +x "$sourceable_wrapper"

        output=$(
            HOME="$poisoned_home" PASSWD_HOME="$passwd_home" SOURCEABLE_WRAPPER="$sourceable_wrapper"                 bash -lc '
set -euo pipefail
source "$SOURCEABLE_WRAPPER"
resolve_current_user() { printf "tester\n"; }
resolve_home_for_user() { printf "%s\n" "$PASSWD_HOME"; }
resolve_current_home
' 2>&1
        ) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            printf -v failures '%s%s\n' "$failures" "${label}: status=${status} output=${output}"
        fi
    done <<EOF
gtbi-update|$REPO_ROOT/scripts/gtbi-update
gtbi-global|$REPO_ROOT/scripts/gtbi-global
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "gtbi wrappers prefer passwd home over mismatched absolute HOME"
    else
        harness_fail "gtbi wrappers prefer passwd home over mismatched absolute HOME" "$failures"
    fi

    cleanup_mock_env
}


test_gtbi_wrappers_ignore_poisoned_current_user_path_tools() {
    setup_mock_env

    local current_user=""
    local passwd_home=""
    local getent_bin=""
    local failures=""

    if [[ -x /usr/bin/id ]]; then
        current_user="$(/usr/bin/id -un 2>/dev/null || true)"
    elif [[ -x /bin/id ]]; then
        current_user="$(/bin/id -un 2>/dev/null || true)"
    else
        current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    fi

    if [[ -x /usr/bin/getent ]]; then
        getent_bin=/usr/bin/getent
    elif [[ -x /bin/getent ]]; then
        getent_bin=/bin/getent
    else
        getent_bin="$(command -v getent 2>/dev/null || true)"
    fi

    if [[ -n "$getent_bin" ]] && [[ -n "$current_user" ]]; then
        passwd_home="$("$getent_bin" passwd "$current_user" 2>/dev/null | cut -d: -f6)"
    fi
    if [[ -z "$passwd_home" ]] && [[ -n "$current_user" ]] && [[ -r /etc/passwd ]]; then
        passwd_home="$(awk -F: -v u="$current_user" '$1==u{print $6; exit}' /etc/passwd 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]] || [[ -z "$passwd_home" ]]; then
        harness_fail "gtbi wrappers ignore poisoned current user path tools" "unable to determine current user/passwd home"
        cleanup_mock_env
        return
    fi

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    mkdir -p "$TEST_FAKE_BIN" "$TEST_HOME/probe"

    while IFS= read -r tool; do
        [[ -n "$tool" ]] || continue
        cat > "$TEST_FAKE_BIN/$tool" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done <<'EOF'
id
whoami
getent
EOF

    while IFS='|' read -r label script_path; do
        [[ -n "$label" ]] || continue
        local sourceable_wrapper="$TEST_HOME/probe/${label}-sourceable.sh"
        local output=""
        local status=0

        sed '$d' "$script_path" > "$sourceable_wrapper"
        chmod +x "$sourceable_wrapper"

        output=$(
            HOME="relative-home" SOURCEABLE_WRAPPER="$sourceable_wrapper" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"                 bash -lc '
set -euo pipefail
source "$SOURCEABLE_WRAPPER"
resolve_current_home
' 2>&1
        ) || status=$?

        if [[ $status -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            printf -v failures '%s%s\n' "$failures" "${label}: status=${status} output=${output}"
        fi
    done <<EOF
gtbi-update|$REPO_ROOT/scripts/gtbi-update
gtbi-global|$REPO_ROOT/scripts/gtbi-global
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "gtbi wrappers ignore poisoned current user path tools"
    else
        harness_fail "gtbi wrappers ignore poisoned current user path tools" "$failures"
    fi

    cleanup_mock_env
}

test_gtbi_system_binary_resolvers_cover_usr_local() {
    local failures=""

    while IFS='|' read -r label script_path function_name variable_name; do
        [[ -n "$label" ]] || continue
        local function_body=""
        function_body="$(
            awk -v fn="$function_name" '
                $0 ~ "^[[:space:]]*" fn "\\(\\)[[:space:]]*\\{" { in_function = 1 }
                in_function { print }
                in_function && $0 ~ "^[[:space:]]*}[[:space:]]*$" { exit }
            ' "$script_path"
        )"
        if [[ -z "$function_body" ]]; then
            printf -v failures '%s%s missing function %s\n' "$failures" "$label" "$function_name"
            continue
        fi
        if ! grep -Fq "\"/usr/local/bin/\$$variable_name\"" <<< "$function_body" \
            || ! grep -Fq "\"/usr/local/sbin/\$$variable_name\"" <<< "$function_body"; then
            printf -v failures '%s%s missing /usr/local system binary candidates in %s\n' "$failures" "$label" "$function_name"
        fi
    done <<EOF
install|$REPO_ROOT/install.sh|gtbi_early_system_binary_path|name
preflight|$REPO_ROOT/scripts/preflight.sh|preflight_system_binary_path|name
install-workflow|$REPO_ROOT/scripts/install-gtbi-workflow.sh|workflow_system_binary_path|name
gtbi-update|$REPO_ROOT/scripts/gtbi-update|system_binary_path|name
gtbi-global|$REPO_ROOT/scripts/gtbi-global|system_binary_path|name
onboard|$REPO_ROOT/packages/onboard/onboard.sh|onboard_system_binary_path|name
install-helpers|$REPO_ROOT/scripts/lib/install_helpers.sh|_gtbi_system_binary_path|name
update-early-lib|$REPO_ROOT/scripts/lib/update.sh|_update_early_system_binary_path|name
update-system-lib|$REPO_ROOT/scripts/lib/update.sh|update_system_binary_path|name
cli-tools-lib|$REPO_ROOT/scripts/lib/cli_tools.sh|_cli_system_binary_path|name
agents-lib|$REPO_ROOT/scripts/lib/agents.sh|_agent_system_binary_path|name
languages-lib|$REPO_ROOT/scripts/lib/languages.sh|_lang_system_binary_path|name
stack-lib|$REPO_ROOT/scripts/lib/stack.sh|_stack_system_binary_path|name
autofix-lib|$REPO_ROOT/scripts/lib/autofix.sh|autofix_system_binary_path|name
changelog-lib|$REPO_ROOT/scripts/lib/changelog.sh|changelog_system_binary_path|name
cheatsheet-lib|$REPO_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_system_binary_path|name
continue-lib|$REPO_ROOT/scripts/lib/continue.sh|continue_system_binary_path|name
dashboard-lib|$REPO_ROOT/scripts/lib/dashboard.sh|dashboard_system_binary_path|name
doctor-lib|$REPO_ROOT/scripts/lib/doctor.sh|_gtbi_doctor_system_binary_path|name
doctor-fix-lib|$REPO_ROOT/scripts/lib/doctor_fix.sh|doctor_fix_system_binary_path|name
export-config-lib|$REPO_ROOT/scripts/lib/export-config.sh|export_system_binary_path|name
github-api-lib|$REPO_ROOT/scripts/lib/github_api.sh|_github_api_system_binary_path|name
info-lib|$REPO_ROOT/scripts/lib/info.sh|info_system_binary_path|name
nightly-update-lib|$REPO_ROOT/scripts/lib/nightly_update.sh|system_binary_path|name
notifications-lib|$REPO_ROOT/scripts/lib/notifications.sh|notifications_system_binary_path|name
notify-lib|$REPO_ROOT/scripts/lib/notify.sh|_gtbi_notify_system_binary_path|name
os-detect-lib|$REPO_ROOT/scripts/lib/os_detect.sh|os_detect_system_binary_path|name
smoke-test-lib|$REPO_ROOT/scripts/lib/smoke_test.sh|_smoke_system_binary_path|name
state-lib|$REPO_ROOT/scripts/lib/state.sh|state_system_binary_path|name
status-lib|$REPO_ROOT/scripts/lib/status.sh|_status_system_binary_path|name
support-lib|$REPO_ROOT/scripts/lib/support.sh|support_system_binary_path|name
user-lib|$REPO_ROOT/scripts/lib/user.sh|user_system_binary_path|name
webhook-lib|$REPO_ROOT/scripts/lib/webhook.sh|webhook_system_binary_path|name
ubuntu-upgrade-lib|$REPO_ROOT/scripts/lib/ubuntu_upgrade.sh|ubuntu_system_binary_path|name
zsh-lib|$REPO_ROOT/scripts/lib/zsh.sh|zsh_system_binary_path|name
generated-install-all|$REPO_ROOT/scripts/generated/install_all.sh|gtbi_generated_system_binary_path|name
generated-doctor-checks|$REPO_ROOT/scripts/generated/doctor_checks.sh|gtbi_generated_system_binary_path|name
EOF

    while IFS='|' read -r label script_path function_name variable_name; do
        [[ -n "$label" ]] || continue
        local function_body=""
        function_body="$(
            awk -v fn="$function_name" '
                $0 ~ "^[[:space:]]*" fn "\\(\\)[[:space:]]*\\{" { in_function = 1 }
                in_function { print }
                in_function && $0 ~ "^[[:space:]]*}[[:space:]]*$" { exit }
            ' "$script_path"
        )"
        if [[ -z "$function_body" ]]; then
            printf -v failures '%s%s missing function %s\n' "$failures" "$label" "$function_name"
            continue
        fi
        if ! grep -Fq "\"/usr/local/bin/\$$variable_name\"" <<< "$function_body" \
            || ! grep -Fq "\"/usr/local/sbin/\$$variable_name\"" <<< "$function_body"; then
            printf -v failures '%s%s missing /usr/local command fallback in %s\n' "$failures" "$label" "$function_name"
        fi
    done <<EOF
install-target-lookup|$REPO_ROOT/install.sh|binary_path|name
preflight-target-lookup|$REPO_ROOT/scripts/preflight.sh|preflight_binary_path|name
cli-tools-target-lookup|$REPO_ROOT/scripts/lib/cli_tools.sh|_cli_target_has_command|cmd
stack-target-lookup|$REPO_ROOT/scripts/lib/stack.sh|_stack_target_command_path|cmd
update-target-lookup|$REPO_ROOT/scripts/lib/update.sh|update_binary_path|tool
doctor-target-lookup|$REPO_ROOT/scripts/lib/doctor.sh|doctor_binary_path|name
github-api-target-lookup|$REPO_ROOT/scripts/lib/github_api.sh|_github_api_binary_path|name
info-target-lookup|$REPO_ROOT/scripts/lib/info.sh|info_binary_path|name
smoke-target-lookup|$REPO_ROOT/scripts/lib/smoke_test.sh|_smoke_binary_path|name
status-target-lookup|$REPO_ROOT/scripts/lib/status.sh|_status_binary_path|name
onboard-target-lookup|$REPO_ROOT/packages/onboard/onboard.sh|onboard_runtime_binary_path|name
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "gtbi system binary resolvers cover /usr/local"
    else
        harness_fail "gtbi system binary resolvers cover /usr/local" "$failures"
    fi
}

test_selected_system_binary_resolvers_reject_pathlike_names() {
    local failures=""

    while IFS='|' read -r label script_path function_name; do
        [[ -n "$label" ]] || continue
        local function_body=""
        local resolver_output=""
        function_body="$(
            awk -v fn="$function_name" '
                $0 ~ "^[[:space:]]*" fn "\\(\\)[[:space:]]*\\{" { in_function = 1 }
                in_function { print }
                in_function && $0 ~ "^[[:space:]]*}[[:space:]]*$" { exit }
            ' "$script_path"
        )"
        if [[ -z "$function_body" ]]; then
            printf -v failures '%s%s missing function %s\n' "$failures" "$label" "$function_name"
            continue
        fi

        if ! resolver_output="$(
            FUNCTION_BODY="$function_body" FUNCTION_NAME="$function_name" bash -c '
                set -euo pipefail
                eval "$FUNCTION_BODY"
                for unsafe_name in "." ".." "../bash" "/bin/bash" "bash/../sh" "bash name"; do
                    if "$FUNCTION_NAME" "$unsafe_name" >/dev/null 2>&1; then
                        printf "%s accepted unsafe name: %s\n" "$FUNCTION_NAME" "$unsafe_name" >&2
                        exit 1
                    fi
                done
            ' 2>&1
        )"; then
            printf -v failures '%s%s accepted pathlike system binary names: %s\n' "$failures" "$label" "$resolver_output"
        fi
    done <<EOF
gtbi-update|$REPO_ROOT/scripts/gtbi-update|system_binary_path
gtbi-global|$REPO_ROOT/scripts/gtbi-global|system_binary_path
install-helpers|$REPO_ROOT/scripts/lib/install_helpers.sh|_gtbi_system_binary_path
update-early-lib|$REPO_ROOT/scripts/lib/update.sh|_update_early_system_binary_path
update-system-lib|$REPO_ROOT/scripts/lib/update.sh|update_system_binary_path
stack-lib|$REPO_ROOT/scripts/lib/stack.sh|_stack_system_binary_path
agents-lib|$REPO_ROOT/scripts/lib/agents.sh|_agent_system_binary_path
notify-lib|$REPO_ROOT/scripts/lib/notify.sh|_gtbi_notify_system_binary_path
notifications-lib|$REPO_ROOT/scripts/lib/notifications.sh|notifications_system_binary_path
webhook-lib|$REPO_ROOT/scripts/lib/webhook.sh|webhook_system_binary_path
ubuntu-upgrade-lib|$REPO_ROOT/scripts/lib/ubuntu_upgrade.sh|ubuntu_system_binary_path
generated-install-all|$REPO_ROOT/scripts/generated/install_all.sh|gtbi_generated_system_binary_path
generated-doctor-checks|$REPO_ROOT/scripts/generated/doctor_checks.sh|gtbi_generated_system_binary_path
EOF

    if [[ -z "$failures" ]]; then
        harness_pass "selected system binary resolvers reject pathlike names"
    else
        harness_fail "selected system binary resolvers reject pathlike names" "$failures"
    fi
}

test_gtbi_update_wrapper_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib" "$TEST_FAKE_BIN"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s SYSTEM_STATE=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${GTBI_SYSTEM_STATE_FILE:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local tool=""
    for tool in id whoami getent stat jq sed head env bash sudo runuser dirname; do
        cat > "$TEST_FAKE_BIN/$tool" <<EOF
#!/usr/bin/env bash
printf 'poisoned-$tool\n' >&2
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" USER="evil" LOGNAME="evil" PATH="$TEST_FAKE_BIN" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI SYSTEM_STATE=$TEST_SYSTEM_STATE_FILE ARG1=--dry-run" ]]; then
        harness_pass "gtbi-update wrapper uses system-state target_home when getent is unavailable"
    else
        harness_fail "gtbi-update wrapper uses system-state target_home when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_repairs_runtime_home_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=--dry-run" ]]; then
        harness_pass "gtbi-update wrapper repairs runtime home on direct exec"
    else
        harness_fail "gtbi-update wrapper repairs runtime home on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    local sourceable_wrapper="$TEST_HOME/probe/gtbi-update-sourceable.sh"
    local output=""

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib" "$stale_home"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"
    sed '$d' "$TEST_HOME/probe/gtbi-update" > "$sourceable_wrapper"
    chmod +x "$sourceable_wrapper"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$stale_home"
}
EOF
    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    output=$(env         HOME="$TEST_ROOT_HOME"         GTBI_STATE_FILE="$TEST_TARGET_HOME/.gtbi/state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_TARGET_HOME="$TEST_TARGET_HOME"         SOURCEABLE_WRAPPER="$sourceable_wrapper"         bash -lc '
set -euo pipefail
source "$SOURCEABLE_WRAPPER"
getent_passwd_entry() {
    if [[ $# -eq 0 ]]; then
        printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
        return 0
    fi
    if [[ "$1" == "tester" ]]; then
        printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
        return 0
    fi
    return 2
}
resolve_current_user() { printf "tester\n"; }
main --help
' 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper prefers live home-adjacent gtbi path over stale state target_home"
    else
        harness_fail "gtbi-update wrapper prefers live home-adjacent gtbi path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_repo_local_prefers_system_state_target_home_over_stale_explicit_env() {
    setup_system_state_target_home_only_env

    local repo_home="$TEST_HOME/repo-local"
    local stale_home="$TEST_HOME/stale-home"

    mkdir -p \
        "$repo_home/scripts/lib" \
        "$stale_home/.gtbi"

    cp "$REPO_ROOT/scripts/gtbi-update" "$repo_home/scripts/gtbi-update"
    chmod +x "$repo_home/scripts/gtbi-update"
    : > "$repo_home/gtbi.manifest.yaml"

    cat > "$repo_home/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$repo_home/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_HOME="$stale_home" GTBI_HOME="$stale_home/.gtbi" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$repo_home/scripts/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=--dry-run" ]]; then
        harness_pass "gtbi-update repo-local wrapper prefers system-state target_home over stale explicit env"
    else
        harness_fail "gtbi-update repo-local wrapper prefers system-state target_home over stale explicit env" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_passes_bin_dir_from_state() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local custom_bin="$TEST_HOME/custom-bin"
    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin"
}
EOF

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR=$custom_bin TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "gtbi-update wrapper passes persisted bin_dir from state"
    else
        harness_fail "gtbi-update wrapper passes persisted bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_prefers_state_bin_dir_over_poisoned_env() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local persisted_bin="$TEST_TARGET_HOME/.local/bin"
    local poisoned_bin="$TEST_HOME/poisoned-bin"
    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$persisted_bin"
}
EOF

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" GTBI_BIN_DIR="$poisoned_bin" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR=$persisted_bin TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "gtbi-update wrapper prefers persisted bin_dir over poisoned env"
    else
        harness_fail "gtbi-update wrapper prefers persisted bin_dir over poisoned env" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    mkdir -p "$TEST_HOME/probe" "$TEST_INSTALLED_GTBI/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s ARG1=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores other-user home bin_dir from state"
    else
        harness_fail "gtbi-update wrapper ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_other_user_home_env_bin_dir_after_runtime_resolution() {
    setup_cross_home_bin_dir_env

    mkdir -p "$TEST_HOME/probe" "$TEST_INSTALLED_GTBI/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s ARG1=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        GTBI_BIN_DIR="$STALE_HOME/.local/bin" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores other-user home env bin_dir after runtime resolution"
    else
        harness_fail "gtbi-update wrapper ignores other-user home env bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_discards_invalid_env_bin_dir_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" GTBI_BIN_DIR="relative/bin" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "gtbi-update wrapper discards invalid env bin_dir on direct exec"
    else
        harness_fail "gtbi-update wrapper discards invalid env bin_dir on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_discards_invalid_env_state_file_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="relative-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=--dry-run" ]]; then
        harness_pass "gtbi-update wrapper discards invalid env state file on direct exec"
    else
        harness_fail "gtbi-update wrapper discards invalid env state file on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_relative_home_state_trap() {
    setup_system_state_target_home_only_env

    local relative_home="relative-home"
    local stale_home="$TEST_HOME/$relative_home"

    mkdir -p \
        "$TEST_HOME/probe" \
        "$TEST_TARGET_HOME/.gtbi/scripts/lib" \
        "$stale_home/.gtbi/scripts/lib"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live\n' "${TARGET_HOME:-}"
EOF
    cat > "$stale_home/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$stale_home"
}
EOF
    cat > "$stale_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale\n' "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" "$stale_home/.gtbi/scripts/lib/update.sh"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$relative_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1)

    if [[ "$output" == "TARGET_HOME=$TEST_TARGET_HOME SOURCE=live" ]]; then
        harness_pass "gtbi-update wrapper ignores relative HOME state trap"
    else
        harness_fail "gtbi-update wrapper ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_does_not_guess_current_home_when_target_home_is_unresolved() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"

    mkdir -p "$TEST_ROOT_HOME" "$TEST_FAKE_BIN" "$TEST_HOME/probe"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local custom_state="$TEST_HOME/system-state.json"
    cat > "$custom_state" <<'JSON'
{
  "target_user": "ubuntu"
}
JSON

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$custom_state" \
        bash "$TEST_HOME/probe/gtbi-update" --dry-run 2>&1 || true)

    if [[ "$output" == *"Error: update.sh not found."* ]] \
        && [[ "$output" == *"Run from the repo or install GTBI first."* ]]; then
        harness_pass "gtbi-update wrapper does not guess current HOME when target_home is unresolved"
    else
        harness_fail "gtbi-update wrapper does not guess current HOME when target_home is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_stale_explicit_gtbi_home_when_system_state_points_to_live_install() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local live_home="$TEST_HOME/live-home"
    local stale_home="$TEST_HOME/stale-home"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_FAKE_BIN" \
        "$live_home/.gtbi/scripts/lib" \
        "$stale_home/.gtbi/scripts/lib" \
        "$TEST_HOME/probe"

    cat > "$live_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$stale_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$live_home/.gtbi/scripts/lib/update.sh" "$stale_home/.gtbi/scripts/lib/update.sh"

    cat > "$stale_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home"
}
EOF
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$stale_home/.gtbi" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "TARGET_HOME=$live_home SOURCE=live ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores stale explicit GTBI_HOME when system state points to live install"
    else
        harness_fail "gtbi-update wrapper ignores stale explicit GTBI_HOME when system state points to live install" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_prefers_explicit_gtbi_home_over_current_home_when_system_state_is_missing() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local explicit_home="$TEST_HOME/explicit-home"
    local current_user=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi/scripts/lib" \
        "$explicit_home/.gtbi/scripts/lib" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home"
}
EOF
    cat > "$explicit_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$explicit_home"
}
EOF
    cat > "$current_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=current ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$explicit_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=explicit ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$current_home/.gtbi/scripts/lib/update.sh" "$explicit_home/.gtbi/scripts/lib/update.sh"

    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$explicit_home/.gtbi" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "TARGET_HOME=$explicit_home SOURCE=explicit ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper prefers explicit GTBI_HOME over current home when system state is missing"
    else
        harness_fail "gtbi-update wrapper prefers explicit GTBI_HOME over current home when system state is missing" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_poisoned_bin_dir_after_runtime_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local live_home="$TEST_HOME/live-home"
    local stale_bin="$TEST_HOME/stale-bin"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi" \
        "$live_home/.gtbi/scripts/lib" \
        "$stale_bin" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home",
  "bin_dir": "$stale_bin"
}
EOF
    cat > "$live_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF
    cat > "$live_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s GTBI_BIN_DIR=%s ARG1=%s\n' "${TARGET_HOME:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$live_home/.gtbi/scripts/lib/update.sh"
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_BIN_DIR="$stale_bin" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "TARGET_HOME=$live_home GTBI_BIN_DIR= ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores poisoned bin_dir after runtime resolution"
    else
        harness_fail "gtbi-update wrapper ignores poisoned bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_stale_system_state_bin_dir_after_runtime_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local stale_home="$TEST_HOME/stale-home"
    local stale_bin="$TEST_HOME/stale-bin"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi/scripts/lib" \
        "$stale_bin" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home"
}
EOF
    cat > "$current_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s GTBI_BIN_DIR=%s ARG1=%s\n' "${TARGET_HOME:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$current_home/.gtbi/scripts/lib/update.sh"
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home",
  "bin_dir": "$stale_bin"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "TARGET_HOME=$current_home GTBI_BIN_DIR= ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores stale system-state bin_dir after runtime resolution"
    else
        harness_fail "gtbi-update wrapper ignores stale system-state bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_ignores_stale_home_adjacent_target_user() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_TARGET_HOME="$TEST_HOME/custom-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local other_home="$TEST_HOME/other-home"
    local tool=""

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_TARGET_HOME/.gtbi/scripts/lib" \
        "$other_home/.gtbi/scripts/lib" \
        "$TEST_HOME/probe" \
        "$TEST_FAKE_BIN"

    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<'JSON'
{
  "target_user": "otheruser"
}
JSON
    cat > "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$other_home/.gtbi/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/scripts/lib/update.sh" "$other_home/.gtbi/scripts/lib/update.sh"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    for tool in id whoami getent stat jq sed head env bash sudo runuser dirname; do
        cat > "$TEST_FAKE_BIN/$tool" <<EOF
#!/usr/bin/env bash
printf 'poisoned-$tool\n' >&2
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" USER="evil" LOGNAME="evil" PATH="$TEST_FAKE_BIN" \
        GTBI_STATE_FILE="$TEST_TARGET_HOME/.gtbi/state.json" \
        /bin/bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "TARGET_HOME=$TEST_TARGET_HOME SOURCE=live ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper ignores stale home-adjacent target_user"
    else
        harness_fail "gtbi-update wrapper ignores stale home-adjacent target_user" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_update_wrapper_uses_installed_layout_state_context() {
    setup_installed_layout_env

    local current_user=""
    local custom_bin="$TEST_HOME/custom-bin"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$TEST_HOME/probe" "$custom_bin"
    cp "$REPO_ROOT/scripts/gtbi-update" "$TEST_HOME/probe/gtbi-update"
    chmod +x "$TEST_HOME/probe/gtbi-update"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s STATE=%s BIN=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${GTBI_STATE_FILE:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/scripts/lib/update.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         bash "$TEST_HOME/probe/gtbi-update" --help 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI STATE=$TEST_INSTALLED_GTBI/state.json BIN=$custom_bin ARG1=--help" ]]; then
        harness_pass "gtbi-update wrapper uses installed-layout state context"
    else
        harness_fail "gtbi-update wrapper uses installed-layout state context" "$output"
    fi

    cleanup_mock_env
}


test_gtbi_global_wrapper_uses_system_state_target_home_when_getent_unavailable() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin" "$TEST_FAKE_BIN"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s SYSTEM_STATE=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${GTBI_SYSTEM_STATE_FILE:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi"

    local tool=""
    for tool in id whoami getent stat jq sed head env bash sudo runuser dirname; do
        cat > "$TEST_FAKE_BIN/$tool" <<EOF
#!/usr/bin/env bash
printf 'poisoned-$tool\n' >&2
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" USER="evil" LOGNAME="evil" PATH="$TEST_FAKE_BIN" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI SYSTEM_STATE=$TEST_SYSTEM_STATE_FILE ARG1=version" ]]; then
        harness_pass "global gtbi wrapper uses system-state target_home when getent is unavailable"
    else
        harness_fail "global gtbi wrapper uses system-state target_home when getent is unavailable" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_repairs_runtime_home_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=version" ]]; then
        harness_pass "global gtbi wrapper repairs runtime home on direct exec"
    else
        harness_fail "global gtbi wrapper repairs runtime home on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    local sourceable_wrapper="$TEST_HOME/probe/gtbi-sourceable.sh"
    local output=""

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin" "$stale_home"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"
    sed '$d' "$TEST_HOME/probe/gtbi" > "$sourceable_wrapper"
    chmod +x "$sourceable_wrapper"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$stale_home"
}
EOF
    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi"

    output=$(env         HOME="$TEST_ROOT_HOME"         GTBI_STATE_FILE="$TEST_TARGET_HOME/.gtbi/state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_TARGET_HOME="$TEST_TARGET_HOME"         SOURCEABLE_WRAPPER="$sourceable_wrapper"         bash -lc '
set -euo pipefail
source "$SOURCEABLE_WRAPPER"
getent_passwd_entry() {
    if [[ $# -eq 0 ]]; then
        printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
        return 0
    fi
    if [[ "$1" == "tester" ]]; then
        printf "tester:x:1000:1000::%s:/bin/bash\n" "$TEST_TARGET_HOME"
        return 0
    fi
    return 2
}
resolve_current_user() { printf "tester\n"; }
main version
' 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=version" ]]; then
        harness_pass "global gtbi wrapper prefers live home-adjacent gtbi path over stale state target_home"
    else
        harness_fail "global gtbi wrapper prefers live home-adjacent gtbi path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_runs_direct_when_owner_unknown_but_target_home_known() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    cat > "$TEST_FAKE_BIN/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]] && [[ "$2" == "%U" ]]; then
    printf 'UNKNOWN\n'
    exit 0
fi
exec /usr/bin/stat "$@"
EOF
    cat > "$TEST_FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo-called=%s\n' "$*"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi" "$TEST_FAKE_BIN/stat" "$TEST_FAKE_BIN/sudo"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=version" ]]; then
        harness_pass "global gtbi wrapper runs direct when owner is unknown but target_home is known"
    else
        harness_fail "global gtbi wrapper runs direct when owner is unknown but target_home is known" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_passes_bin_dir_from_state() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local custom_bin="$TEST_HOME/custom-bin"
    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin"
}
EOF

    cat > "$TEST_TARGET_HOME/.gtbi/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR=$custom_bin TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "global gtbi wrapper passes persisted bin_dir from state"
    else
        harness_fail "global gtbi wrapper passes persisted bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_prefers_state_bin_dir_over_poisoned_env() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.gtbi/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local persisted_bin="$TEST_TARGET_HOME/.local/bin"
    local poisoned_bin="$TEST_HOME/poisoned-bin"
    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$persisted_bin"
}
EOF

    cat > "$TEST_TARGET_HOME/.gtbi/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.gtbi/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" GTBI_BIN_DIR="$poisoned_bin" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR=$persisted_bin TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "global gtbi wrapper prefers persisted bin_dir over poisoned env"
    else
        harness_fail "global gtbi wrapper prefers persisted bin_dir over poisoned env" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    mkdir -p "$TEST_HOME/probe" "$TEST_INSTALLED_GTBI/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s ARG1=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores other-user home bin_dir from state"
    else
        harness_fail "global gtbi wrapper ignores other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_other_user_home_env_bin_dir_after_runtime_resolution() {
    setup_cross_home_bin_dir_env

    mkdir -p "$TEST_HOME/probe" "$TEST_INSTALLED_GTBI/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s ARG1=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        GTBI_BIN_DIR="$STALE_HOME/.local/bin" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores other-user home env bin_dir after runtime resolution"
    else
        harness_fail "global gtbi wrapper ignores other-user home env bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_discards_invalid_env_bin_dir_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'GTBI_BIN_DIR=%s TARGET_HOME=%s\n' "${GTBI_BIN_DIR:-}" "${TARGET_HOME:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="$TEST_ROOT_HOME/.gtbi/state.json" GTBI_BIN_DIR="relative/bin" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "GTBI_BIN_DIR= TARGET_HOME=$TEST_TARGET_HOME" ]]; then
        harness_pass "global gtbi wrapper discards invalid env bin_dir on direct exec"
    else
        harness_fail "global gtbi wrapper discards invalid env bin_dir on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_discards_invalid_env_state_file_on_direct_exec() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_HOME/probe" "$TEST_TARGET_HOME/.local/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_ROOT_HOME/.gtbi" TARGET_HOME="$TEST_ROOT_HOME" \
        GTBI_STATE_FILE="relative-state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI ARG1=version" ]]; then
        harness_pass "global gtbi wrapper discards invalid env state file on direct exec"
    else
        harness_fail "global gtbi wrapper discards invalid env state file on direct exec" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_relative_home_state_trap() {
    setup_system_state_target_home_only_env

    local relative_home="relative-home"
    local stale_home="$TEST_HOME/$relative_home"

    mkdir -p \
        "$TEST_HOME/probe" \
        "$TEST_TARGET_HOME/.local/bin" \
        "$stale_home/.gtbi" \
        "$stale_home/.local/bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$stale_home/.gtbi/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$stale_home"
}
EOF
    cat > "$stale_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi" "$stale_home/.local/bin/gtbi"

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$relative_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$TEST_TARGET_HOME SOURCE=live ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores relative HOME state trap"
    else
        harness_fail "global gtbi wrapper ignores relative HOME state trap" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_does_not_guess_current_home_when_target_home_is_unresolved() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"

    mkdir -p "$TEST_ROOT_HOME" "$TEST_FAKE_BIN" "$TEST_HOME/probe"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    local custom_state="$TEST_HOME/system-state.json"
    cat > "$custom_state" <<'JSON'
{
  "target_user": "ubuntu"
}
JSON

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$custom_state" \
        bash "$TEST_HOME/probe/gtbi" version 2>&1 || true)

    if [[ "$output" == *"Unable to determine the GTBI owner automatically."* ]] \
        && [[ "$output" != *"Expected at: $TEST_ROOT_HOME/.local/bin/gtbi"* ]] \
        && [[ "$output" != *"user 'ubuntu'"* ]]; then
        harness_pass "global gtbi wrapper does not guess current HOME when target_home is unresolved"
    else
        harness_fail "global gtbi wrapper does not guess current HOME when target_home is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_stale_explicit_gtbi_home_when_system_state_points_to_live_install() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local live_home="$TEST_HOME/live-home"
    local stale_home="$TEST_HOME/stale-home"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_FAKE_BIN" \
        "$live_home/.local/bin" \
        "$stale_home/.local/bin" \
        "$stale_home/.gtbi" \
        "$TEST_HOME/probe"

    cat > "$live_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$stale_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$live_home/.local/bin/gtbi" "$stale_home/.local/bin/gtbi"

    cat > "$stale_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home"
}
EOF
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$stale_home/.gtbi" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$live_home SOURCE=live ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores stale explicit GTBI_HOME when system state points to live install"
    else
        harness_fail "global gtbi wrapper ignores stale explicit GTBI_HOME when system state points to live install" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_prefers_explicit_gtbi_home_over_current_home_when_system_state_is_missing() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local explicit_home="$TEST_HOME/explicit-home"
    local current_user=""

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi" \
        "$current_home/.local/bin" \
        "$explicit_home/.gtbi" \
        "$explicit_home/.local/bin" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home"
}
EOF
    cat > "$explicit_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$explicit_home"
}
EOF
    cat > "$current_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=current ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$explicit_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=explicit ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$current_home/.local/bin/gtbi" "$explicit_home/.local/bin/gtbi"

    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_HOME="$explicit_home/.gtbi" \
        GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$explicit_home SOURCE=explicit ARG1=version" ]]; then
        harness_pass "global gtbi wrapper prefers explicit GTBI_HOME over current home when system state is missing"
    else
        harness_fail "global gtbi wrapper prefers explicit GTBI_HOME over current home when system state is missing" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_poisoned_bin_dir_after_runtime_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local live_home="$TEST_HOME/live-home"
    local stale_bin="$TEST_HOME/stale-bin"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi" \
        "$live_home/.local/bin" \
        "$live_home/.gtbi" \
        "$stale_bin" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home",
  "bin_dir": "$stale_bin"
}
EOF
    cat > "$live_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF
    cat > "$live_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s GTBI_BIN_DIR=%s ARG1=%s\n' "${TARGET_HOME:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$live_home/.local/bin/gtbi"
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$live_home"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_BIN_DIR="$stale_bin" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$live_home GTBI_BIN_DIR= ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores poisoned bin_dir after runtime resolution"
    else
        harness_fail "global gtbi wrapper ignores poisoned bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_stale_system_state_bin_dir_after_runtime_resolution() {
    setup_mock_env

    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local current_home="$TEST_HOME/current-home"
    local stale_home="$TEST_HOME/stale-home"
    local stale_bin="$TEST_HOME/stale-bin"
    local current_user=""
    local system_state="$TEST_HOME/system-state.json"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p \
        "$TEST_FAKE_BIN" \
        "$current_home/.gtbi" \
        "$current_home/.local/bin" \
        "$stale_bin" \
        "$TEST_HOME/probe"

    cat > "$current_home/.gtbi/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$current_home"
}
EOF
    cat > "$current_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s GTBI_BIN_DIR=%s ARG1=%s\n' "${TARGET_HOME:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$current_home/.local/bin/gtbi"
    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home",
  "bin_dir": "$stale_bin"
}
EOF

    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    local output=""
    output=$(HOME="$current_home" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        GTBI_SYSTEM_STATE_FILE="$system_state" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$current_home GTBI_BIN_DIR= ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores stale system-state bin_dir after runtime resolution"
    else
        harness_fail "global gtbi wrapper ignores stale system-state bin_dir after runtime resolution" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_ignores_stale_home_adjacent_target_user() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_TARGET_HOME="$TEST_HOME/custom-home"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    local other_home="$TEST_HOME/other-home"
    local tool=""

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_TARGET_HOME/.gtbi" \
        "$TEST_TARGET_HOME/.local/bin" \
        "$other_home/.local/bin" \
        "$TEST_HOME/probe" \
        "$TEST_FAKE_BIN"

    cat > "$TEST_TARGET_HOME/.gtbi/state.json" <<'JSON'
{
  "target_user": "otheruser"
}
JSON
    cat > "$TEST_TARGET_HOME/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=live ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    cat > "$other_home/.local/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'TARGET_HOME=%s SOURCE=stale ARG1=%s\n' "${TARGET_HOME:-}" "${1:-}"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gtbi" "$other_home/.local/bin/gtbi"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    for tool in id whoami getent stat jq sed head env bash sudo runuser dirname; do
        cat > "$TEST_FAKE_BIN/$tool" <<EOF
#!/usr/bin/env bash
printf 'poisoned-$tool\n' >&2
exit 99
EOF
        chmod +x "$TEST_FAKE_BIN/$tool"
    done

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" USER="evil" LOGNAME="evil" PATH="$TEST_FAKE_BIN" \
        GTBI_STATE_FILE="$TEST_TARGET_HOME/.gtbi/state.json" \
        /bin/bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "TARGET_HOME=$TEST_TARGET_HOME SOURCE=live ARG1=version" ]]; then
        harness_pass "global gtbi wrapper ignores stale home-adjacent target_user"
    else
        harness_fail "global gtbi wrapper ignores stale home-adjacent target_user" "$output"
    fi

    cleanup_mock_env
}

test_gtbi_global_wrapper_uses_installed_layout_state_context() {
    setup_installed_layout_env

    local current_user=""
    local custom_bin="$TEST_HOME/custom-bin"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$TEST_HOME/probe" "$custom_bin"
    cp "$REPO_ROOT/scripts/gtbi-global" "$TEST_HOME/probe/gtbi"
    chmod +x "$TEST_HOME/probe/gtbi"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/bin/gtbi" <<'EOF'
#!/usr/bin/env bash
printf 'HOME=%s TARGET_HOME=%s GTBI_HOME=%s STATE=%s BIN=%s ARG1=%s\n' "$HOME" "${TARGET_HOME:-}" "${GTBI_HOME:-}" "${GTBI_STATE_FILE:-}" "${GTBI_BIN_DIR:-}" "${1:-}"
EOF
    chmod +x "$TEST_INSTALLED_GTBI/bin/gtbi"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         bash "$TEST_HOME/probe/gtbi" version 2>&1)

    if [[ "$output" == "HOME=$TEST_TARGET_HOME TARGET_HOME=$TEST_TARGET_HOME GTBI_HOME=$TEST_INSTALLED_GTBI STATE=$TEST_INSTALLED_GTBI/state.json BIN=$custom_bin ARG1=version" ]]; then
        harness_pass "global gtbi wrapper uses installed-layout state context"
    else
        harness_fail "global gtbi wrapper uses installed-layout state context" "$output"
    fi

    cleanup_mock_env
}


test_doctor_manifest_checks_prefer_system_bins_over_current_shell_path() {
    setup_installed_layout_env

    local sourceable_doctor="$TEST_HOME/sourceable-doctor.sh"
    sed '$d' "$DOCTOR_SH" > "$sourceable_doctor"
    chmod +x "$sourceable_doctor"

    cat > "$TEST_FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo POISONED_CURL
EOF
    chmod +x "$TEST_FAKE_BIN/curl"

    local current_user=""
    current_user="$(id -un)"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" CURRENT_USER="$current_user"         TARGET_USER="$current_user" TARGET_HOME="$TEST_TARGET_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" GTBI_BIN_DIR="$TEST_TARGET_HOME/.local/bin"         bash -c 'source "$1" >/dev/null 2>&1 || true; TARGET_USER="$CURRENT_USER"; TARGET_HOME="$2"; GTBI_BIN_DIR="$3"; _doctor_run_manifest_check target_user "command -v curl"' _ "$sourceable_doctor" "$TEST_TARGET_HOME" "$TEST_TARGET_HOME/.local/bin")

    if [[ -n "$output" ]] && [[ "$output" != "$TEST_FAKE_BIN/curl" ]] && [[ "$output" != "POISONED_CURL" ]]; then
        harness_pass "doctor manifest checks prefer system bins over current-shell PATH"
    else
        harness_fail "doctor manifest checks prefer system bins over current-shell PATH" "$output"
    fi

    cleanup_mock_env
}

test_doctor_manifest_checks_fail_closed_when_target_home_is_unresolved() {
    setup_installed_layout_env

    local sourceable_doctor="$TEST_HOME/sourceable-doctor.sh"
    sed '$d' "$DOCTOR_SH" > "$sourceable_doctor"
    chmod +x "$sourceable_doctor"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    cat > "$TEST_FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo-called=%s\n' "$*"
EOF
    chmod +x "$TEST_FAKE_BIN/getent" "$TEST_FAKE_BIN/sudo"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TARGET_USER="missinguser" TARGET_HOME="" GTBI_HOME="$TEST_INSTALLED_GTBI" \
        GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" GTBI_BIN_DIR="$TEST_TARGET_HOME/.local/bin" \
        bash -c 'source "$1" >/dev/null 2>&1 || true; TARGET_USER="missinguser"; TARGET_HOME=""; _doctor_run_manifest_check target_user "printf unreachable\\n"' _ "$sourceable_doctor" 2>&1 || true)

    if [[ "$output" == *"Invalid TARGET_HOME for 'missinguser': <empty> (must be an absolute path and cannot be '/')"* ]] \
        && [[ "$output" != *"sudo-called="* ]] \
        && [[ "$output" != *"unreachable"* ]]; then
        harness_pass "doctor manifest checks fail closed when target_home is unresolved"
    else
        harness_fail "doctor manifest checks fail closed when target_home is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_doctor_manifest_checks_reject_invalid_target_user_before_sudo() {
    setup_installed_layout_env

    local sourceable_doctor="$TEST_HOME/sourceable-doctor.sh"
    sed '$d' "$DOCTOR_SH" > "$sourceable_doctor"
    chmod +x "$sourceable_doctor"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
printf 'getent-called=%s\n' "$*"
exit 2
EOF
    cat > "$TEST_FAKE_BIN/runuser" <<'EOF'
#!/usr/bin/env bash
printf 'runuser-called=%s\n' "$*"
EOF
    cat > "$TEST_FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo-called=%s\n' "$*"
EOF
    chmod +x "$TEST_FAKE_BIN/getent" "$TEST_FAKE_BIN/runuser" "$TEST_FAKE_BIN/sudo"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TARGET_USER="../bad user" TARGET_HOME="" GTBI_HOME="$TEST_INSTALLED_GTBI" \
        GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        bash -c 'source "$1" >/dev/null 2>&1 || true; TARGET_USER="../bad user"; TARGET_HOME=""; _doctor_run_manifest_check target_user "printf unreachable\\n"' _ "$sourceable_doctor" 2>&1 || true)

    if [[ "$output" == *"Invalid TARGET_USER '../bad user' (expected: lowercase user name like 'ubuntu')"* ]] \
        && [[ "$output" != *"getent-called="* ]] \
        && [[ "$output" != *"sudo-called="* ]] \
        && [[ "$output" != *"runuser-called="* ]] \
        && [[ "$output" != *"unreachable"* ]]; then
        harness_pass "doctor manifest checks reject invalid target_user before sudo"
    else
        harness_fail "doctor manifest checks reject invalid target_user before sudo" "$output"
    fi

    cleanup_mock_env
}

test_doctor_root_manifest_checks_run_when_target_home_is_unresolved() {
    setup_installed_layout_env

    local sourceable_doctor="$TEST_HOME/sourceable-doctor.sh"
    sed '$d' "$DOCTOR_SH" > "$sourceable_doctor"
    chmod +x "$sourceable_doctor"

    cat > "$TEST_FAKE_BIN/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    cat > "$TEST_FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo-called=%s\n' "$*"
EOF
    chmod +x "$TEST_FAKE_BIN/getent" "$TEST_FAKE_BIN/sudo"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        TARGET_USER="missinguser" TARGET_HOME="" GTBI_HOME="$TEST_INSTALLED_GTBI" \
        GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" \
        bash -c 'source "$1" >/dev/null 2>&1 || true; TARGET_USER="missinguser"; TARGET_HOME=""; _doctor_run_manifest_check root "printf root-check-ran\\n"' _ "$sourceable_doctor" 2>&1 || true)

    if { [[ "$output" == *'sudo-called=-n env TARGET_USER=missinguser PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin bash -o pipefail -c printf root-check-ran\n'* ]] \
        || [[ "$output" == *"root-check-ran"* ]]; } \
        && [[ "$output" != *"Invalid TARGET_HOME"* ]]; then
        harness_pass "doctor root manifest checks still run when target_home is unresolved"
    else
        harness_fail "doctor root manifest checks still run when target_home is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_doctor_deep_optional_probe_ignores_current_shell_only_path_entries() {
    setup_installed_layout_env

    local sourceable_doctor="$TEST_HOME/sourceable-doctor.sh"
    sed '$d' "$DOCTOR_SH" > "$sourceable_doctor"
    chmod +x "$sourceable_doctor"

    cat > "$TEST_FAKE_BIN/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo current-shell-only-tool
EOF
    chmod +x "$TEST_FAKE_BIN/current-shell-only-tool"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TARGET_USER="tester" TARGET_HOME="$TEST_TARGET_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_STATE_FILE="$TEST_INSTALLED_GTBI/state.json" GTBI_BIN_DIR="$TEST_TARGET_HOME/.local/bin"         bash -c 'source "$1" >/dev/null 2>&1 || true; JSON_MODE=true; PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; JSON_CHECKS=(); deep_check_optional_probe "deep.test.current_shell_only_tool" "Current-shell-only tool probe" "current-shell-only-tool" "Install it" "current-shell-only-tool --help"; printf "%s\n" "${JSON_CHECKS[0]}"' _ "$sourceable_doctor")

    if [[ "$output" == *'"id":"deep.test.current_shell_only_tool"'* ]]         && [[ "$output" == *'"status":"warn"'* ]]         && [[ "$output" == *'"details":"not installed"'* ]]; then
        harness_pass "doctor deep optional probe ignores current-shell-only PATH entries"
    else
        harness_fail "doctor deep optional probe ignores current-shell-only PATH entries" "$output"
    fi

    cleanup_mock_env
}

test_doctor_agent_checks_use_target_context_under_root_home() {
    setup_installed_layout_env

    mkdir -p \
        "$TEST_INSTALLED_GTBI/zsh" \
        "$TEST_TARGET_HOME/.claude" \
        "$TEST_TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k" \
        "$TEST_TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
        "$TEST_TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
alias cc='claude'
alias cod='codex'
gmi() { gemini "$@"; }
EOF

    cat > "$TEST_TARGET_HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "dcg test \"$CLAUDE_TOOL_INPUT\""
          }
        ]
      }
    ]
  }
}
JSON

    write_fake_command "$TEST_TARGET_HOME/.local/bin/dcg" "dcg 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rch" "rch 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json)

    if printf '%s\n' "$output" | jq -e --arg native_path "$TEST_TARGET_HOME/.local/bin/claude" '
        ([.checks[] | select(.id == "shell.ohmyzsh") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "shell.p10k") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "shell.plugins.zsh_autosuggestions") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "shell.plugins.zsh_syntax_highlighting") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "agent.alias.cc") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "agent.alias.cod") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "agent.alias.gmi") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) == ("native (" + $native_path + ")") and
        ([.checks[] | select(.id == "stack.dcg") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "stack.rch") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor agent checks use installed target context under root home"
    else
        harness_fail "doctor agent checks use installed target context under root home" "$output"
    fi

    cleanup_mock_env
}

test_doctor_deep_agent_auth_uses_target_context_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.claude" "$TEST_TARGET_HOME/.codex" "$TEST_TARGET_HOME/.gemini"

    cat > "$TEST_TARGET_HOME/.claude/.credentials.json" <<'JSON'
{
  "claudeAiOauth": {
    "accessToken": "claude-token"
  }
}
JSON

    cat > "$TEST_TARGET_HOME/.codex/auth.json" <<'JSON'
{
  "tokens": {
    "access_token": "codex-token"
  }
}
JSON

    cat > "$TEST_TARGET_HOME/.gemini/.env" <<'EOF'
GEMINI_API_KEY=gemini-token
EOF

    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"

    cat > "$TEST_FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '200'
EOF
    chmod +x "$TEST_FAKE_BIN/curl"

    cat > "$TEST_FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/gh"

    cat > "$TEST_FAKE_BIN/wrangler" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/wrangler"

    cat > "$TEST_FAKE_BIN/vercel" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/vercel"

    cat > "$TEST_FAKE_BIN/supabase" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/supabase"

    cat > "$TEST_FAKE_BIN/vault" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/vault"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --deep --json || true)

    if printf '%s\n' "$output" | jq -e '
        .deep_mode == true and
        ([.checks[] | select(.id == "deep.agent.claude_auth") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "deep.agent.codex_auth") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "deep.agent.gemini_auth") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor deep agent auth uses installed target context under root home"
    else
        harness_fail "doctor deep agent auth uses installed target context under root home" "$output"
    fi

    cleanup_mock_env
}

test_doctor_deep_gemini_auth_finds_target_google_cloud_sdk_bin_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.gemini" "$TEST_TARGET_HOME/google-cloud-sdk/bin"
    cat > "$TEST_TARGET_HOME/.gemini/.env" <<'EOF'
GOOGLE_GENAI_USE_VERTEXAI=true
GOOGLE_CLOUD_PROJECT=test-project
GOOGLE_CLOUD_LOCATION=us-central1
EOF

    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    cat > "$TEST_TARGET_HOME/google-cloud-sdk/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "application-default" && "${3:-}" == "print-access-token" ]]; then
    printf '%s\n' 'ya29.test-token'
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TARGET_HOME/google-cloud-sdk/bin/gcloud"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --deep --json || true)

    if printf '%s\n' "$output" | jq -e '
        ([.checks[] | select(.id == "deep.agent.gemini_auth") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor deep gemini auth finds target google-cloud-sdk bin under root home"
    else
        harness_fail "doctor deep gemini auth finds target google-cloud-sdk bin under root home" "$output"
    fi

    cleanup_mock_env
}

test_doctor_agent_checks_prefer_persisted_bin_dir_over_poisoned_env_bin_dir() {
    setup_installed_layout_env

    local custom_bin="$TEST_HOME/custom-bin"
    local stale_state_file="$TEST_HOME/stale-doctor-state.json"
    mkdir -p "$custom_bin"
    mkdir -p "$TEST_INSTALLED_GTBI/zsh"
    mkdir -p "$TEST_TARGET_HOME/.claude"
    mkdir -p "$TEST_TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    mkdir -p "$TEST_TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    mkdir -p "$TEST_TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$custom_bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
    cat > "$stale_state_file" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_ROOT_HOME",
  "bin_dir": "$TEST_FAKE_BIN",
  "started_at": "2026-03-01T00:00:00Z",
  "last_updated": "2026-03-02T00:00:00Z"
}
EOF
    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
alias cc='claude'
alias cod='codex'
gmi() { gemini "$@"; }
EOF
    cat > "$TEST_TARGET_HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "dcg test \"$CLAUDE_TOOL_INPUT\""
          }
        ]
      }
    ]
  }
}
JSON

    rm -f "$TEST_TARGET_HOME/.local/bin/claude"
    write_fake_command "$custom_bin/claude" "claude 1.2.3"
    write_fake_command "$custom_bin/dcg" "dcg 1.2.3"
    write_fake_command "$custom_bin/rch" "rch 1.2.3"
    write_fake_command "$TEST_FAKE_BIN/claude" "claude stale"
    write_fake_command "$TEST_FAKE_BIN/dcg" "dcg stale"
    write_fake_command "$TEST_FAKE_BIN/rch" "rch stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_STATE_FILE="$stale_state_file" GTBI_BIN_DIR="$TEST_FAKE_BIN" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json)

    if printf '%s\n' "$output" | jq -e --arg custom_path "$custom_bin/claude" --arg stale_path "$TEST_FAKE_BIN/claude" '
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) == $custom_path and
        ([.checks[] | select(.id == "agent.path.claude") | .details] | first) != $stale_path and
        ([.checks[] | select(.id == "stack.dcg") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "stack.rch") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor agent checks prefer persisted bin_dir over poisoned env bin_dir"
    else
        harness_fail "doctor agent checks prefer persisted bin_dir over poisoned env bin_dir" "$output"
    fi

    cleanup_mock_env
}


test_doctor_agent_checks_ignore_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
    write_fake_command "$STALE_HOME/.local/bin/claude" "claude stale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --json)

    if printf '%s\n' "$output" | jq -e --arg target_path "$TEST_TARGET_HOME/.local/bin/claude" --arg stale_path "$STALE_HOME/.local/bin/claude" '
        (([.checks[] | select(.id == "agent.path.claude") | .details] | first) | contains($target_path)) and
        ((([.checks[] | select(.id == "agent.path.claude") | .details] | first) | contains($stale_path)) | not)
    ' >/dev/null 2>&1; then
        harness_pass "doctor agent checks ignore other-user home bin_dir from state"
    else
        harness_fail "doctor agent checks ignore other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}
test_doctor_deep_optional_probes_use_target_home_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.asb"
    cat > "$TEST_TARGET_HOME/.local/bin/asb" <<EOF
#!/usr/bin/env bash
if [[ "\${HOME:-}" != "$TEST_TARGET_HOME" ]]; then
    exit 1
fi
echo "asb ok"
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/asb"

    cat > "$TEST_TARGET_HOME/.local/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
    printf '%s\n' '{"BackendState":"Running"}'
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/tailscale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         bash "$TEST_INSTALLED_GTBI/bin/gtbi" doctor --deep --json || true)

    if printf '%s\n' "$output" | jq -e '
        .deep_mode == true and
        ([.checks[] | select(.id == "deep.stack.asb") | .status] | first) == "pass" and
        ([.checks[] | select(.id == "network.tailscale") | .status] | first) == "pass"
    ' >/dev/null 2>&1; then
        harness_pass "doctor deep optional probes use installed target HOME under root home"
    else
        harness_fail "doctor deep optional probes use installed target HOME under root home" "$output"
    fi

    cleanup_mock_env
}

test_info_zero_lessons_hides_onboard_prompt_and_explains_state() {
    setup_mock_env

    local empty_lessons_dir
    empty_lessons_dir="$(mktemp -d)"
    local progress_file="$empty_lessons_dir/progress.json"

    local terminal_output
    terminal_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$empty_lessons_dir" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$REPO_ROOT/scripts/lib/info.sh")

    local html_output
    html_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$empty_lessons_dir" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$REPO_ROOT/scripts/lib/info.sh" --html)

    if [[ "$terminal_output" == *"No lessons available"* ]] \
        && [[ "$terminal_output" != *"Run 'onboard' to continue learning"* ]] \
        && [[ "$html_output" == *"No lessons available."* ]] \
        && [[ "$html_output" != *'<div class="progress-fill">0/0</div>'* ]]; then
        harness_pass "info handles zero lessons without misleading onboarding prompts"
    else
        harness_fail "info handles zero lessons without misleading onboarding prompts" "terminal=$terminal_output html=$html_output"
    fi

    cleanup_mock_env
}

test_info_reads_skipped_tools_without_jq() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_INFO_SCRIPT="$REPO_ROOT/scripts/lib/info.sh" \
        bash -lc '
            command() {
                if [[ "$1" == "-v" && "$2" == "jq" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            source "$TEST_INFO_SCRIPT"
            info_get_skipped_tools
        ')

    if [[ "$output" == "ntm, bv" ]]; then
        harness_pass "info reads skipped tools without jq from system state"
    else
        harness_fail "info reads skipped tools without jq from system state" "$output"
    fi

    cleanup_mock_env
}

test_onboard_cli_aliases_work_in_zero_lessons_mode() {
    setup_mock_env

    local empty_lessons_dir
    empty_lessons_dir="$(mktemp -d)"
    local progress_file="$empty_lessons_dir/progress.json"

    local help_output=""
    local help_exit=0
    help_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$empty_lessons_dir" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" help 2>&1) || help_exit=$?

    local list_output=""
    local list_exit=0
    list_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$empty_lessons_dir" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" list 2>&1) || list_exit=$?

    local version_output=""
    local version_exit=0
    version_output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$empty_lessons_dir" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" version 2>&1) || version_exit=$?

    if [[ "$help_exit" -eq 0 ]] \
        && [[ "$help_output" == *"GTBI Onboarding Tutorial"* ]] \
        && [[ "$list_exit" -eq 0 ]] \
        && [[ "$list_output" == *"No lessons available"* ]] \
        && [[ "$version_exit" -eq 0 ]] \
        && [[ "$version_output" == onboard\ v* ]]; then
        harness_pass "onboard noun-style aliases work in zero-lessons mode"
    else
        harness_fail "onboard noun-style aliases work in zero-lessons mode" "help_exit=$help_exit list_exit=$list_exit version_exit=$version_exit"
    fi

    cleanup_mock_env
}

test_onboard_repairs_malformed_progress_before_showing_lesson() {
    setup_mock_env

    local progress_file="$TEST_HOME/bad-progress.json"
    printf '{not valid json\n' > "$progress_file"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$REPO_ROOT/gtbi/onboard/lessons" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" 0 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]] && [[ "$output" == *"Welcome to GTBI"* ]]; then
        harness_pass "onboard repairs malformed progress before lesson launch"
    else
        harness_fail "onboard repairs malformed progress before lesson launch" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_onboard_accepts_sparse_lesson_numbers() {
    setup_mock_env

    local progress_file="$TEST_HOME/progress.json"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" GTBI_HOME="$TEST_GTBI" GTBI_LESSONS_DIR="$REPO_ROOT/gtbi/onboard/lessons" GTBI_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" 33 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]] && [[ "$output" == *"Lesson 33: Hybrid Search with FSFS"* ]]; then
        harness_pass "onboard accepts sparse lesson numbers"
    else
        harness_fail "onboard accepts sparse lesson numbers" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_onboard_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_INSTALLED_GTBI/onboard"
    cp "$ONBOARD_SH" "$TEST_INSTALLED_GTBI/onboard/onboard.sh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/onboard/onboard.sh" status 2>&1)

    if [[ -f "$TEST_INSTALLED_GTBI/onboard_progress.json" ]] \
        && [[ ! -e "$TEST_ROOT_HOME/.gtbi/onboard_progress.json" ]] \
        && [[ "$output" != *"No lessons available"* ]] \
        && [[ "$output" != *"$TEST_ROOT_HOME/.gtbi/onboard/lessons"* ]]; then
        harness_pass "onboard uses installed layout under root home"
    else
        harness_fail "onboard uses installed layout under root home" "$output"
    fi

    cleanup_mock_env
}

test_onboard_cheatsheet_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_INSTALLED_GTBI/onboard" "$TEST_INSTALLED_GTBI/zsh" "$TEST_INSTALLED_GTBI/scripts/lib"
    cp "$ONBOARD_SH" "$TEST_INSTALLED_GTBI/onboard/onboard.sh"
    cp "$CHEATSHEET_SH" "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh"

    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
if command -v claude >/dev/null 2>&1; then
  alias cc='claude'
fi
alias cod='codex'
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_GTBI/onboard/onboard.sh" cheatsheet --json)

    if printf '%s\n' "$output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" '
        .source == $zshrc and ([.entries[].name] | index("cc")) != null and ([.entries[].name] | index("cod")) != null
    ' >/dev/null 2>&1; then
        harness_pass "onboard cheatsheet uses installed layout under root home"
    else
        harness_fail "onboard cheatsheet uses installed layout under root home" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_use_installed_target_home_under_root_home() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.claude"
    cat > "$TEST_TARGET_HOME/.claude/.credentials.json" <<'JSON'
{
  "claudeAiOauth": {
    "accessToken": "claude-token"
  }
}
JSON
    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_TARGET_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status claude && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" == "0" ]]; then
        harness_pass "onboard auth checks use installed target home under root home"
    else
        harness_fail "onboard auth checks use installed target home under root home" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_find_target_binaries_outside_current_path() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.codex" "$TEST_TARGET_HOME/.gemini" \
        "$TEST_TARGET_HOME/.config/gh" "$TEST_TARGET_HOME/.config/vercel" "$TEST_TARGET_HOME/.supabase"

    cat > "$TEST_TARGET_HOME/.codex/auth.json" <<'JSON'
{
  "tokens": {
    "access_token": "codex-token"
  }
}
JSON

    cat > "$TEST_TARGET_HOME/.gemini/google_accounts.json" <<'JSON'
{
  "active": "tester@example.com"
}
JSON

    cat > "$TEST_TARGET_HOME/.config/gh/hosts.yml" <<'EOF2'
github.com:
    oauth_token: gho_testtoken
    user: octocat
EOF2

    cat > "$TEST_TARGET_HOME/.config/vercel/auth.json" <<'JSON'
{
  "token": "vercel-token"
}
JSON

    printf 'supabase-token\n' > "$TEST_TARGET_HOME/.supabase/access-token"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gh" "gh 2.60.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/vercel" "tester@example.com"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/wrangler" "tester@example.com"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/supabase" "supabase 2.99.0"
    cat > "$TEST_TARGET_HOME/.local/bin/tailscale" <<'EOF2'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
    printf '%s\n' '{"BackendState":"Running"}'
    exit 0
fi
exit 1
EOF2
    chmod +x "$TEST_TARGET_HOME/.local/bin/tailscale"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; for svc in codex gemini github vercel supabase cloudflare tailscale; do check_auth_status "$svc" && rc=0 || rc=$?; printf "%s\n" "$svc=$rc"; done')

    if [[ "$output" == *$'codex=0\n'* ]] \
        && [[ "$output" == *$'gemini=0\n'* ]] \
        && [[ "$output" == *$'github=0\n'* ]] \
        && [[ "$output" == *$'vercel=0\n'* ]] \
        && [[ "$output" == *$'supabase=0\n'* ]] \
        && [[ "$output" == *$'cloudflare=0\n'* ]] \
        && [[ "$output" == *$'tailscale=0'* ]]; then
        harness_pass "onboard auth checks find target binaries outside current PATH"
    else
        harness_fail "onboard auth checks find target binaries outside current PATH" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_reject_placeholder_credentials() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.claude" "$TEST_TARGET_HOME/.codex" "$TEST_TARGET_HOME/.gemini" \
        "$TEST_TARGET_HOME/.config/vercel" "$TEST_TARGET_HOME/.supabase"

    cat > "$TEST_TARGET_HOME/.claude/.credentials.json" <<'JSON'
{
  "claudeAiOauth": {
    "accessToken": "your-token-here"
  }
}
JSON

    cat > "$TEST_TARGET_HOME/.codex/auth.json" <<'JSON'
{
  "tokens": {
    "access_token": "your_token_here"
  },
  "OPENAI_API_KEY": "your_openai_api_key"
}
JSON

    cat > "$TEST_TARGET_HOME/.gemini/google_accounts.json" <<'JSON'
{
  "active": "replace-me"
}
JSON
    cat > "$TEST_TARGET_HOME/.gemini/oauth_creds.json" <<'JSON'
{
  "refresh_token": "your-token-here"
}
JSON
    cat > "$TEST_TARGET_HOME/.gemini/.env" <<'EOF2'
GEMINI_API_KEY="YOUR_GEMINI_API_KEY" # replace me
EOF2

    cat > "$TEST_TARGET_HOME/.config/vercel/auth.json" <<'JSON'
{
  "user": {
    "email": "tester@example.com"
  },
  "token": "your_vercel_token"
}
JSON

    printf '%s\n' 'your_supabase_access_token' > "$TEST_TARGET_HOME/.supabase/access-token"

    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/vercel" "not logged in"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/supabase" "supabase 2.99.0"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; for svc in claude codex gemini vercel supabase; do check_auth_status "$svc" && rc=0 || rc=$?; printf "%s\n" "$svc=$rc"; done')

    if [[ "$output" == *$'claude=1\n'* ]] \
        && [[ "$output" == *$'codex=1\n'* ]] \
        && [[ "$output" == *$'gemini=1\n'* ]] \
        && [[ "$output" == *$'vercel=1\n'* ]] \
        && [[ "$output" == *"supabase=1"* ]]; then
        harness_pass "onboard auth checks reject placeholder credentials"
    else
        harness_fail "onboard auth checks reject placeholder credentials" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_ignore_poisoned_current_path_and_env_bin_dir() {
    setup_installed_layout_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$TEST_TARGET_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    cat > "$TEST_FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/gh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" GTBI_BIN_DIR="$TEST_FAKE_BIN" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status github && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" != "0" ]]; then
        harness_pass "onboard auth checks ignore poisoned current PATH and env bin_dir"
    else
        harness_fail "onboard auth checks ignore poisoned current PATH and env bin_dir" "$output"
    fi

    cleanup_mock_env
}


test_onboard_auth_checks_ignore_other_user_home_bin_dir_from_state() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$TEST_TARGET_HOME",
  "bin_dir": "$STALE_HOME/.local/bin",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF
    cat > "$STALE_HOME/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$STALE_HOME/.local/bin/gh"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status github && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" != "0" ]]; then
        harness_pass "onboard auth checks ignore other-user home bin_dir from state"
    else
        harness_fail "onboard auth checks ignore other-user home bin_dir from state" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_use_explicit_target_user_when_no_authoritative_runtime_home_exists() {
    setup_cross_home_bin_dir_env

    cat > "$TEST_TARGET_HOME/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TARGET_HOME/.local/bin/gh"

    local missing_system_state="$TEST_HOME/missing-system-state.json"
    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="tester" TARGET_HOME="" GTBI_SYSTEM_STATE_FILE="$missing_system_state" \
        TEST_TARGET_HOME="$TEST_TARGET_HOME" TEST_ONBOARD_SCRIPT="$ONBOARD_SH" PATH="/usr/bin:/bin" \
        bash -lc '
            source "$TEST_ONBOARD_SCRIPT" help >/dev/null
            onboard_lookup_passwd_home() {
                if [[ "${1:-}" == "tester" ]]; then
                    printf "%s\n" "$TEST_TARGET_HOME"
                    return 0
                fi
                return 1
            }
            check_auth_status github && status=0 || status=$?
            printf "%s\n" "$status"
        ')

    if [[ "$output" == "0" ]]; then
        harness_pass "onboard auth checks use explicit target_user when no authoritative runtime home exists"
    else
        harness_fail "onboard auth checks use explicit target_user when no authoritative runtime home exists" "$output"
    fi

    cleanup_mock_env
}

test_onboard_auth_checks_do_not_fall_back_to_current_home_when_explicit_target_user_is_unresolved() {
    setup_installed_layout_env

    mkdir -p "$TEST_ROOT_HOME/.local/bin"
    cat > "$TEST_ROOT_HOME/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_ROOT_HOME/.local/bin/gh"

    local missing_system_state="$TEST_HOME/missing-system-state.json"
    local output=""
    output=$(HOME="$TEST_ROOT_HOME" TARGET_USER="missinguser" TARGET_HOME=""         GTBI_SYSTEM_STATE_FILE="$missing_system_state" PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status github && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" == "2" ]]; then
        harness_pass "onboard auth checks do not fall back to current home when explicit target_user is unresolved"
    else
        harness_fail "onboard auth checks do not fall back to current home when explicit target_user is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_onboard_gemini_vertex_auth_finds_target_google_cloud_sdk_bin_outside_current_path() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.gemini" "$TEST_TARGET_HOME/google-cloud-sdk/bin"
    cat > "$TEST_TARGET_HOME/.gemini/.env" <<'EOF'
GOOGLE_GENAI_USE_VERTEXAI=true
GOOGLE_CLOUD_PROJECT=test-project
GOOGLE_CLOUD_LOCATION=us-central1
EOF

    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    cat > "$TEST_TARGET_HOME/google-cloud-sdk/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "application-default" && "${3:-}" == "print-access-token" ]]; then
    printf '%s\n' 'ya29.test-token'
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TARGET_HOME/google-cloud-sdk/bin/gcloud"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status gemini && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" == "0" ]]; then
        harness_pass "onboard gemini vertex auth finds target google-cloud-sdk bin outside current PATH"
    else
        harness_fail "onboard gemini vertex auth finds target google-cloud-sdk bin outside current PATH" "$output"
    fi

    cleanup_mock_env
}

test_onboard_gemini_vertex_auth_finds_target_gcloud_outside_current_path() {
    setup_installed_layout_env

    mkdir -p "$TEST_TARGET_HOME/.gemini"
    cat > "$TEST_TARGET_HOME/.gemini/.env" <<'EOF2'
GOOGLE_GENAI_USE_VERTEXAI=true
GOOGLE_CLOUD_PROJECT=test-project
GOOGLE_CLOUD_LOCATION=us-central1
EOF2

    write_fake_command "$TEST_TARGET_HOME/.local/bin/gemini" "gemini 1.2.3"
    cat > "$TEST_TARGET_HOME/.local/bin/gcloud" <<'EOF2'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "application-default" && "${3:-}" == "print-access-token" ]]; then
    printf '%s\n' 'ya29.test-token'
    exit 0
fi
exit 1
EOF2
    chmod +x "$TEST_TARGET_HOME/.local/bin/gcloud"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" GTBI_HOME="$TEST_INSTALLED_GTBI" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" bash -lc 'source "'"$ONBOARD_SH"'" help >/dev/null; check_auth_status gemini && status=0 || status=$?; printf "%s\n" "$status"')

    if [[ "$output" == "0" ]]; then
        harness_pass "onboard gemini vertex auth finds target gcloud outside current PATH"
    else
        harness_fail "onboard gemini vertex auth finds target gcloud outside current PATH" "$output"
    fi

    cleanup_mock_env
}

test_onboard_copy_install_uses_system_state_under_root_home() {
    setup_mock_env

    local root_home="$TEST_HOME/root-home"
    local target_home="$TEST_HOME/users/tester"
    local installed_gtbi="$target_home/.gtbi"
    local system_state="$TEST_HOME/system-state/state.json"

    mkdir -p "$root_home/.local/bin" "$installed_gtbi/onboard/lessons" "$installed_gtbi/scripts/lib" "$(dirname "$system_state")"
    cp "$ONBOARD_SH" "$root_home/.local/bin/onboard"
    chmod +x "$root_home/.local/bin/onboard"
    cp "$CHEATSHEET_SH" "$installed_gtbi/scripts/lib/cheatsheet.sh"

    cat > "$installed_gtbi/onboard/lessons/01_intro.md" <<'EOF2'
# Intro

hello
EOF2

    cat > "$system_state" <<EOF2
{
  "target_user": "tester",
  "target_home": "$target_home"
}
EOF2

    local output=""
    output=$(HOME="$root_home" GTBI_SYSTEM_STATE_FILE="$system_state" PATH="$root_home/.local/bin:/usr/bin:/bin" onboard status 2>&1)

    if [[ -f "$installed_gtbi/onboard_progress.json" ]] \
        && [[ ! -e "$root_home/.gtbi/onboard_progress.json" ]] \
        && [[ "$output" != *"No lessons available"* ]]; then
        harness_pass "copied onboard binary uses system state under root home"
    else
        harness_fail "copied onboard binary uses system state under root home" "$output"
    fi

    cleanup_mock_env
}

test_onboard_copy_install_uses_target_home_only_system_state_under_root_home() {
    setup_system_state_target_home_only_env

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$TEST_INSTALLED_GTBI/scripts/lib" "$TEST_INSTALLED_GTBI/zsh"
    cp "$ONBOARD_SH" "$TEST_ROOT_HOME/.local/bin/onboard"
    chmod +x "$TEST_ROOT_HOME/.local/bin/onboard"
    cp "$CHEATSHEET_SH" "$TEST_INSTALLED_GTBI/scripts/lib/cheatsheet.sh"

    cat > "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" <<'EOF'
alias cod='codex'
EOF
    write_fake_command "$TEST_TARGET_HOME/.local/bin/codex" "codex 1.2.3"

    local status_output=""
    status_output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        onboard status 2>&1)

    local cheatsheet_output=""
    cheatsheet_output=$(HOME="$TEST_ROOT_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        onboard cheatsheet --json 2>&1)

    if [[ -f "$TEST_INSTALLED_GTBI/onboard_progress.json" ]] \
        && [[ ! -e "$TEST_ROOT_HOME/.gtbi/onboard_progress.json" ]] \
        && [[ "$status_output" != *"No lessons available"* ]] \
        && printf '%s\n' "$cheatsheet_output" | jq -e --arg zshrc "$TEST_INSTALLED_GTBI/zsh/gtbi.zshrc" \
            '.source == $zshrc and ([.entries[].name] | index("cod")) != null' >/dev/null 2>&1; then
        harness_pass "copied onboard uses target_home-only system state under root home"
    else
        harness_fail "copied onboard uses target_home-only system state under root home" "status=$status_output cheatsheet=$cheatsheet_output"
    fi

    cleanup_mock_env
}

test_onboard_repo_local_prefers_system_state_target_user_over_stale_installed_state() {
    setup_system_state_target_home_env
    poison_installed_target_user

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
EOF

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_TARGET_HOME="$TEST_TARGET_HOME" TEST_ONBOARD_SCRIPT="$ONBOARD_SH" PATH="/usr/bin:/bin" \
        bash -lc '
            source "$TEST_ONBOARD_SCRIPT"
            onboard_lookup_passwd_home() {
                if [[ "${1:-}" == "tester" ]]; then
                    printf "%s\n" "$TEST_TARGET_HOME"
                    return 0
                fi
                return 1
            }
            _ONBOARD_GTBI_HOME="$(onboard_resolve_gtbi_home 2>/dev/null || true)"
            onboard_resolve_runtime_home >/dev/null 2>&1 || true
            printf "gtbi=%s\nhome=%s\n" "${_ONBOARD_GTBI_HOME:-}" "${_ONBOARD_RUNTIME_HOME:-}"
        ' \
        2>/dev/null)

    if [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]] \
        && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "onboard repo-local prefers system-state target_user over stale installed state"
    else
        harness_fail "onboard repo-local prefers system-state target_user over stale installed state" "$output"
    fi

    cleanup_mock_env
}

test_onboard_repo_local_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    local missing_system_state="$TEST_HOME/missing-system-state.json"
    local output=""

    mkdir -p "$stale_home"
    cat > "$TEST_INSTALLED_GTBI/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$stale_home",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF

    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$missing_system_state"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_ONBOARD_SCRIPT="$ONBOARD_SH"         bash -lc 'source "$TEST_ONBOARD_SCRIPT"; printf "gtbi=%s\nhome=%s\n" "${_ONBOARD_GTBI_HOME:-}" "${_ONBOARD_RUNTIME_HOME:-}"'         2>/dev/null)

    if [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "onboard repo-local prefers live home-adjacent gtbi path over stale state target_home"
    else
        harness_fail "onboard repo-local prefers live home-adjacent gtbi path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_onboard_repo_local_ignores_stale_explicit_runtime_hints_when_system_state_points_to_live_install() {
    setup_system_state_target_home_env

    local stale_home="$TEST_HOME/stale-home"
    local output=""

    mkdir -p "$stale_home/.gtbi/onboard/lessons"
    cat > "$stale_home/.gtbi/state.json" <<EOF
{
  "mode": "safe",
  "target_user": "tester",
  "target_home": "$stale_home",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
EOF
    printf '# Poison Lesson\n' > "$stale_home/.gtbi/onboard/lessons/01_poison.md"

    output=$(HOME="$TEST_ROOT_HOME" \
        GTBI_HOME="$stale_home/.gtbi" \
        TARGET_HOME="$stale_home" \
        GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -lc 'source "'"$ONBOARD_SH"'"; printf "gtbi=%s\\nhome=%s\\n" "${_ONBOARD_GTBI_HOME:-}" "${_ONBOARD_RUNTIME_HOME:-}"' \
        2>/dev/null)

    if [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]] \
        && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]; then
        harness_pass "onboard repo-local ignores stale explicit GTBI_HOME and TARGET_HOME when system state points to live install"
    else
        harness_fail "onboard repo-local ignores stale explicit GTBI_HOME and TARGET_HOME when system state points to live install" "$output"
    fi

    cleanup_mock_env
}

test_onboard_can_be_sourced_without_mutating_caller_env() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME"         TEST_ONBOARD_SCRIPT="$ONBOARD_SH"         bash -lc '
            set +e +u
            set +o pipefail
            HOME=relative-home
            set -- --bogus keep
            source "$TEST_ONBOARD_SCRIPT"
            if [[ $- == *e* || $- == *u* ]]; then
                printf "bad-shell-flags:%s\n" "$-"
                exit 1
            fi
            if shopt -qo pipefail; then
                printf "bad-shell-flags:pipefail\n"
                exit 1
            fi
            gtbi_home_set=unset
            script_path_set=unset
            script_dir_set=unset
            runtime_home_set=unset
            [[ -v GTBI_HOME ]] && gtbi_home_set=set
            [[ -v SCRIPT_PATH ]] && script_path_set=set
            [[ -v SCRIPT_DIR ]] && script_dir_set=set
            [[ -v ONBOARD_RUNTIME_HOME ]] && runtime_home_set=set
            declare -F onboard_main >/dev/null
            printf "%s|%s|%s|%s|%s|%s|%s|%s\n" "$HOME" "$#" "$1" "$2" "$gtbi_home_set" "$script_path_set" "$script_dir_set" "$runtime_home_set"
        ' 2>/dev/null)

    if [[ "$output" == "relative-home|2|--bogus|keep|unset|unset|unset|unset" ]]; then
        harness_pass "onboard can be sourced without leaking install context"
    else
        harness_fail "onboard can be sourced without leaking install context" "$output"
    fi

    cleanup_mock_env
}

test_onboard_globals_survive_function_scoped_source_under_set_u() {
    setup_mock_env

    local output=""
    output=$(HOME="$TEST_HOME" \
        GTBI_HOME="$TEST_GTBI" \
        GTBI_LESSONS_DIR="$REPO_ROOT/gtbi/onboard/lessons" \
        bash -c '
            set -u
            load_onboard() { source "$1"; }
            load_onboard "$1"
            printf "lessons=%s files=%s auth=%s\n" "${#LESSON_TITLES[@]}" "${#LESSON_FILES[@]}" "${#AUTH_SERVICES[@]}"
        ' _ "$ONBOARD_SH" 2>&1 || true)

    if [[ "$output" == lessons=*files=*auth=* ]] && [[ "$output" != *"unbound variable"* ]]; then
        harness_pass "onboard globals survive function-scoped source under set -u"
    else
        harness_fail "onboard globals survive function-scoped source under set -u" "$output"
    fi

    cleanup_mock_env
}

test_onboard_copy_install_ignores_relative_home_trap() {
    setup_system_state_target_home_only_env
    setup_relative_home_trap

    mkdir -p "$TEST_ROOT_HOME/.local/bin" "$STALE_HOME/.gtbi/onboard/lessons"
    cp "$ONBOARD_SH" "$TEST_ROOT_HOME/.local/bin/onboard"
    chmod +x "$TEST_ROOT_HOME/.local/bin/onboard"

    cat > "$STALE_HOME/.gtbi/onboard/lessons/01_intro.md" <<'EOF'
# Wrong Intro

stale lesson
EOF

    local output=""
    output=$(cd "$TEST_HOME" && HOME="$RELATIVE_HOME" GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        PATH="$TEST_ROOT_HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin" \
        onboard status 2>&1)

    if [[ -f "$TEST_INSTALLED_GTBI/onboard_progress.json" ]] \
        && [[ ! -e "$STALE_HOME/.gtbi/onboard_progress.json" ]] \
        && [[ "$output" != *"No lessons available"* ]]; then
        harness_pass "copied onboard ignores relative HOME trap"
    else
        harness_fail "copied onboard ignores relative HOME trap" "$output"
    fi

    cleanup_mock_env
}

test_runtime_helpers_do_not_guess_home_paths_from_usernames() {
    local output=""

    output="$( {
        grep -RFn "printf '/home/%s\\n' \"\\\$current_user\"" \
            "$CONTINUE_SH" "$DASHBOARD_SH" "$INFO_SH" "$CHANGELOG_SH" "$EXPORT_CONFIG_SH" \
            "$STATUS_SH" "$SUPPORT_SH" "$CHEATSHEET_SH" "$DOCTOR_SH" \
            "$REPO_ROOT/scripts/lib/doctor_fix.sh" "$NOTIFY_SH" "$NOTIFICATIONS_SH" \
            "$WEBHOOK_SH" "$SMOKE_TEST_SH" "$STATE_SH" "$PREFLIGHT_SH" "$ONBOARD_SH" 2>/dev/null || true
        grep -RFn 'echo "/home/$user"' \
            "$CONTINUE_SH" "$DASHBOARD_SH" "$INFO_SH" "$CHANGELOG_SH" "$EXPORT_CONFIG_SH" \
            "$STATUS_SH" "$SUPPORT_SH" "$CHEATSHEET_SH" 2>/dev/null || true
        grep -RFn "printf '/home/%s' \"\\\$user\"" "$ONBOARD_SH" "$AUTOFIX_SH" 2>/dev/null || true
        grep -RFn "printf '/home/%s\\n' \"\\\$TARGET_USER\"" "$STATE_SH" 2>/dev/null || true
        grep -RFn "printf '/home/%s\\n' \"\\\$target_user\"" "$PREFLIGHT_SH" "$UBUNTU_UPGRADE_SH" 2>/dev/null || true
        grep -RFn 'TARGET_HOME="/home/$TARGET_USER"' "$SMOKE_TEST_SH" 2>/dev/null || true
        grep -RFn 'target_home="/home/$target_user"' "$OS_DETECT_SH" 2>/dev/null || true
        grep -RFn 'TARGET_HOME="${2:-/home/${TARGET_USER}}"' "$TEST_INSTALL_ARTIFACTS_SH" 2>/dev/null || true
        grep -RFn "printf '/home/%s\\n' \"\\\$target_user\"" "$TEST_INSTALL_ARTIFACTS_SH" 2>/dev/null || true
    } )"

    if [[ -z "$output" ]]; then
        harness_pass "runtime helpers do not guess home paths from usernames"
    else
        harness_fail "runtime helpers do not guess home paths from usernames" "$output"
    fi
}

test_state_driven_helpers_reject_invalid_target_home_from_state() {
    if grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$INFO_SH" \
        && grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$STATUS_SH" \
        && grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$EXPORT_CONFIG_SH" \
        && grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$SUPPORT_SH" \
        && grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$CHANGELOG_SH" \
        && grep -Fq '[[ "$target_home" != "/" ]] || return 1' "$CONTINUE_SH" \
        && grep -Fq 'dashboard_read_target_home_from_state()' "$DASHBOARD_SH" \
        && grep -Fq 'cheatsheet_read_target_home_from_state()' "$CHEATSHEET_SH" \
        && grep -Fq '[[ "$TARGET_HOME" == "/" ]]' "$DOCTOR_SH"; then
        harness_pass "state-driven helpers reject invalid target_home from state"
    else
        harness_fail "state-driven helpers reject invalid target_home from state"
    fi
}


setup_live_home_adjacent_gtbi_env() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_TARGET_HOME="$TEST_HOME/custom-home"
    STALE_HOME="$TEST_HOME/stale-home"
    TEST_INSTALLED_GTBI="$TEST_TARGET_HOME/.gtbi"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"

    mkdir -p "$TEST_ROOT_HOME" "$TEST_INSTALLED_GTBI" "$STALE_HOME" "$TEST_FAKE_BIN" "$(dirname "$TEST_SYSTEM_STATE_FILE")"

    cat > "$TEST_INSTALLED_GTBI/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON
    printf '2.0.0\n' > "$TEST_INSTALLED_GTBI/VERSION"

    cat > "$TEST_SYSTEM_STATE_FILE" <<EOF
{
  "mode": "safe",
  "target_user": "staleuser",
  "target_home": "$STALE_HOME",
  "started_at": "2030-01-01T00:00:00Z",
  "last_updated": "2030-01-02T00:00:00Z"
}
EOF

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$#" -eq 1 ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    echo "staleuser:x:1001:1001::${STALE_HOME}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "staleuser" ]]; then
    echo "staleuser:x:1001:1001::${STALE_HOME}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"
}

test_export_config_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_live_home_adjacent_gtbi_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_EXPORT_SCRIPT="$EXPORT_CONFIG_SH"         bash -lc '
            source "$TEST_EXPORT_SCRIPT"
            prepare_target_context
            printf "user=%s\nhome=%s\nstate=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${_EXPORT_STATE_FILE:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"state=$TEST_INSTALLED_GTBI/state.json"* ]]; then
        harness_pass "export-config prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "export-config prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_support_bundle_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_live_home_adjacent_gtbi_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_SUPPORT_SCRIPT="$SUPPORT_SH"         bash -lc '
            source "$TEST_SUPPORT_SCRIPT"
            support_initialize_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${SUPPORT_TARGET_USER:-}" "${SUPPORT_TARGET_HOME:-}" "${_SUPPORT_GTBI_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]; then
        harness_pass "support bundle prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "support bundle prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_support_bundle_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_SUPPORT_SCRIPT="$SUPPORT_SH"         bash -lc '
            source "$TEST_SUPPORT_SCRIPT"
            if support_initialize_context; then
                printf "status=ok\nuser=%s\nhome=%s\ngtbi=%s\n" "${SUPPORT_TARGET_USER:-}" "${SUPPORT_TARGET_HOME:-}" "${_SUPPORT_GTBI_HOME:-}"
            else
                printf "status=failed\n"
            fi
        ' 2>/dev/null)

    if [[ "$output" == *"status=ok"* ]]         && [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]; then
        harness_pass "support bundle uses explicit target home when state is missing"
    else
        harness_fail "support bundle uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_support_bundle_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"
    mkdir -p "$TEST_ROOT_HOME/.gtbi/logs"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$TEST_HOME/missing-target-home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_SUPPORT_SCRIPT="$SUPPORT_SH"         bash -lc '
            source "$TEST_SUPPORT_SCRIPT"
            if support_initialize_context; then
                printf "status=ok
user=%s
home=%s
gtbi=%s
" "${SUPPORT_TARGET_USER:-}" "${SUPPORT_TARGET_HOME:-}" "${_SUPPORT_GTBI_HOME:-}"
            else
                printf "status=failed
user=%s
home=%s
gtbi=%s
" "${SUPPORT_TARGET_USER:-}" "${SUPPORT_TARGET_HOME:-}" "${_SUPPORT_GTBI_HOME:-}"
            fi
        ' 2>&1)

    if [[ "$output" == *"status=failed"* ]]         && [[ "$output" == *"refusing to fall back to current HOME"* ]]         && [[ "$output" == *"home="* ]]         && [[ "$output" != *"home=$TEST_ROOT_HOME"* ]]         && [[ "$output" == *"gtbi="* ]]         && [[ "$output" != *"gtbi=$TEST_ROOT_HOME/.gtbi"* ]]; then
        harness_pass "support bundle does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "support bundle does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH"         bash -lc '
            source "$TEST_DASHBOARD_SCRIPT"
            if dashboard_prepare_context; then
                printf "status=ok\nuser=%s\nhome=%s\ngtbi=%s\n" "${_DASHBOARD_RESOLVED_TARGET_USER:-}" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}" "${_DASHBOARD_GTBI_HOME:-}"
            else
                printf "status=failed\n"
            fi
        ' 2>/dev/null)

    if [[ "$output" == *"status=ok"* ]]         && [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]; then
        harness_pass "dashboard uses explicit target home when state is missing"
    else
        harness_fail "dashboard uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"
    mkdir -p "$TEST_ROOT_HOME/.gtbi"
    printf '0.0.0-test
' > "$TEST_ROOT_HOME/.gtbi/VERSION"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$TEST_HOME/missing-target-home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH"         bash -lc '
            source "$TEST_DASHBOARD_SCRIPT"
            if dashboard_prepare_context; then
                printf "status=ok
user=%s
home=%s
gtbi=%s
" "${_DASHBOARD_RESOLVED_TARGET_USER:-}" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}" "${_DASHBOARD_GTBI_HOME:-}"
            else
                printf "status=failed
user=%s
home=%s
gtbi=%s
" "${_DASHBOARD_RESOLVED_TARGET_USER:-}" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}" "${_DASHBOARD_GTBI_HOME:-}"
            fi
        ' 2>&1)

    if [[ "$output" == *"status=failed"* ]]         && [[ "$output" == *"refusing to fall back to current HOME"* ]]         && [[ "$output" == *"home="* ]]         && [[ "$output" != *"home=$TEST_ROOT_HOME"* ]]         && [[ "$output" == *"gtbi="* ]]         && [[ "$output" != *"gtbi=$TEST_ROOT_HOME/.gtbi"* ]]; then
        harness_pass "dashboard does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "dashboard does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_dashboard_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_live_home_adjacent_gtbi_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_DASHBOARD_SCRIPT="$DASHBOARD_SH"         bash -lc '
            source "$TEST_DASHBOARD_SCRIPT"
            dashboard_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${_DASHBOARD_RESOLVED_TARGET_USER:-}" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}" "${_DASHBOARD_GTBI_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]; then
        harness_pass "dashboard prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "dashboard prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_uses_explicit_target_home_when_state_is_missing() {
    setup_system_state_target_home_env
    rm -f "$TEST_INSTALLED_GTBI/state.json" "$TEST_SYSTEM_STATE_FILE"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="tester"         TARGET_HOME="$TEST_TARGET_HOME"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_CHEATSHEET_SCRIPT="$CHEATSHEET_SH"         bash -lc '
            source "$TEST_CHEATSHEET_SCRIPT"
            if cheatsheet_prepare_context; then
                printf "status=ok\nuser=%s\nhome=%s\ngtbi=%s\nPATH=%s\n" "${_CHEATSHEET_RESOLVED_TARGET_USER:-}" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}" "${_CHEATSHEET_GTBI_HOME:-}" "$PATH"
            else
                printf "status=failed\n"
            fi
        ' 2>/dev/null)

    if [[ "$output" == *"status=ok"* ]]         && [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]         && [[ "$output" == *"$TEST_TARGET_HOME/.local/bin"* ]]; then
        harness_pass "cheatsheet uses explicit target home when state is missing"
    else
        harness_fail "cheatsheet uses explicit target home when state is missing" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved() {
    setup_installed_layout_env
    rm -f "$TEST_INSTALLED_GTBI/state.json"
    mkdir -p "$TEST_ROOT_HOME/.gtbi"
    printf '0.0.0-test
' > "$TEST_ROOT_HOME/.gtbi/VERSION"

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         TARGET_USER="ghost"         TARGET_HOME="$TEST_HOME/missing-target-home"         GTBI_SYSTEM_STATE_FILE="$TEST_HOME/missing-system-state.json"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_CHEATSHEET_SCRIPT="$CHEATSHEET_SH"         bash -lc '
            source "$TEST_CHEATSHEET_SCRIPT"
            if cheatsheet_prepare_context; then
                printf "status=ok
user=%s
home=%s
gtbi=%s
PATH=%s
" "${_CHEATSHEET_RESOLVED_TARGET_USER:-}" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}" "${_CHEATSHEET_GTBI_HOME:-}" "$PATH"
            else
                printf "status=failed
user=%s
home=%s
gtbi=%s
PATH=%s
" "${_CHEATSHEET_RESOLVED_TARGET_USER:-}" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}" "${_CHEATSHEET_GTBI_HOME:-}" "$PATH"
            fi
        ' 2>&1)

    if [[ "$output" == *"status=failed"* ]]         && [[ "$output" == *"refusing to fall back to current HOME"* ]]         && [[ "$output" == *"home="* ]]         && [[ "$output" != *"home=$TEST_ROOT_HOME"* ]]         && [[ "$output" == *"gtbi="* ]]         && [[ "$output" != *"gtbi=$TEST_ROOT_HOME/.gtbi"* ]]; then
        harness_pass "cheatsheet does not fall back to current home when explicit target is unresolved"
    else
        harness_fail "cheatsheet does not fall back to current home when explicit target is unresolved" "$output"
    fi

    cleanup_mock_env
}

test_cheatsheet_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home() {
    setup_live_home_adjacent_gtbi_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME"         GTBI_HOME="$TEST_INSTALLED_GTBI"         GTBI_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE"         PATH="$TEST_FAKE_BIN:/usr/bin:/bin"         TEST_CHEATSHEET_SCRIPT="$CHEATSHEET_SH"         bash -lc '
            source "$TEST_CHEATSHEET_SCRIPT"
            cheatsheet_prepare_context
            printf "user=%s\nhome=%s\ngtbi=%s\n" "${_CHEATSHEET_RESOLVED_TARGET_USER:-}" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}" "${_CHEATSHEET_GTBI_HOME:-}"
        ' 2>/dev/null)

    if [[ "$output" == *"user=tester"* ]]         && [[ "$output" == *"home=$TEST_TARGET_HOME"* ]]         && [[ "$output" == *"gtbi=$TEST_INSTALLED_GTBI"* ]]; then
        harness_pass "cheatsheet prefers live home-adjacent GTBI path over stale state target_home"
    else
        harness_fail "cheatsheet prefers live home-adjacent GTBI path over stale state target_home" "$output"
    fi

    cleanup_mock_env
}

main() {
    harness_init "GTBI Changelog/Export/Status Tests"

    if ! command -v jq >/dev/null 2>&1; then
        harness_warn "jq not available — skipping JSON validation tests"
    fi

    harness_section "Changelog"
    test_changelog_json_is_valid || true
    test_changelog_defaults_to_last_updated || true
    test_changelog_rejects_invalid_duration || true

    test_language_cloud_ignore_other_user_home_bin_dir_override || true

    harness_section "Stack"
    test_stack_is_installed_handles_unknown_tool_under_set_u || true
    test_stack_is_installed_ignores_current_shell_only_path_entries || true
    test_stack_target_has_command_finds_target_user_local_claude || true
    test_stack_target_home_ignores_invalid_explicit_target_home_before_passwd_fallback || true
    test_stack_target_command_path_ignores_other_user_home_bin_dir_override || true
    test_stack_target_home_prefers_current_home_over_current_shell_only_getent || true
    test_stack_agent_mail_cli_path_ignores_current_shell_only_am || true
    test_stack_agent_mail_ready_ignores_current_shell_only_am || true
    test_stack_run_as_user_prefers_system_bins_over_current_shell_path || true

    harness_section "Notification Helpers"
    test_notify_uses_target_home_for_config_and_state_when_home_is_relative || true
    test_notify_header_helpers_sanitize_control_characters || true
    test_webhook_reads_config_from_target_home_when_home_is_relative || true
    test_webhook_payload_rejects_non_ip_public_ip_response || true
    test_webhook_public_ip_accepts_valid_ips_only || true
    test_webhook_payload_defaults_missing_summary_timestamp || true
    test_gtbi_notify_uses_resolved_curl_path || true
    test_notifications_cli_uses_target_home_when_home_is_relative || true
    test_notifications_cli_source_preserves_shell_options || true
    test_notifications_cli_sanitizes_headers_before_curl || true
    test_notifications_cli_reports_config_write_failure_when_sourced || true
    test_notifications_cli_rejects_unsafe_topic_and_server_values || true

    harness_section "Autofix"
    test_autofix_uses_target_home_for_state_dir_when_home_is_relative || true
    test_autofix_repairs_stale_target_home_for_state_dir_from_passwd || true
    test_autofix_existing_detects_target_home_install_when_home_is_relative || true
    test_autofix_existing_reads_target_home_version_under_root_home || true
    test_autofix_existing_prefers_target_home_over_poisoned_gtbi_home || true
    test_autofix_existing_backup_preserves_distinct_relative_paths || true
    test_autofix_existing_clean_reinstall_records_manifest_backups || true
    test_autofix_existing_clean_reinstall_aborts_when_recording_fails || true
    test_autofix_existing_clean_reinstall_aborts_when_backup_root_creation_fails || true
    test_autofix_existing_clean_reinstall_aborts_when_state_relocation_fails || true
    test_autofix_existing_clean_reinstall_restores_backup_after_artifact_removal_failure || true
    test_autofix_existing_clean_reinstall_preserves_journal_when_artifact_recovery_fails || true
    test_autofix_existing_clean_reinstall_recovery_preserves_preexisting_journal || true
    test_autofix_existing_drop_changes_since_restores_original_journals_on_late_replace_failure || true
    test_autofix_existing_backup_uses_unique_dir_when_timestamp_collides || true
    test_autofix_existing_backup_avoids_broken_symlink_collision || true
    test_autofix_existing_backup_fsyncs_manifest_and_parent_dir || true
    test_autofix_existing_restore_from_backup_fsyncs_restored_path || true
    test_autofix_existing_backup_cleans_partial_dir_after_copy_failure || true
    test_autofix_existing_artifacts_include_global_wrapper || true
    test_autofix_existing_backup_preserves_symlink_artifacts || true
    test_autofix_existing_handles_broken_symlink_artifacts || true
    test_autofix_existing_clean_shell_configs_records_changes || true
    test_autofix_existing_clean_shell_configs_preserves_symlinked_config || true
    test_autofix_existing_clean_shell_configs_preserves_owner_before_move || true
    test_autofix_existing_clean_shell_configs_restores_file_when_recording_fails || true
    test_autofix_existing_update_path_entries_restores_file_when_recording_fails || true
    test_autofix_existing_update_path_entries_restores_symlink_target_when_recording_fails || true
    test_autofix_existing_update_path_entries_repairs_legacy_gtbi_marker_missing_atuin || true
    test_autofix_existing_update_path_entries_repairs_zprofile_and_ignores_commented_atuin || true
    test_autofix_existing_legacy_config_migration_undo_handles_quoted_paths || true
    test_autofix_existing_legacy_config_migration_undo_cleans_created_dirs || true
    test_autofix_existing_legacy_json_migration_undo_handles_quoted_paths || true
    test_autofix_existing_legacy_config_migration_record_failure_cleans_created_dirs || true
    test_autofix_existing_run_migrations_rolls_back_earlier_steps_on_late_failure || true
    test_autofix_existing_upgrade_restores_version_when_path_repair_fails || true
    test_autofix_existing_upgrade_preserves_journal_when_path_recovery_is_incomplete || true
    test_autofix_existing_upgrade_write_failure_cleans_new_gtbi_home || true
    test_autofix_existing_upgrade_version_backup_failure_rolls_back_migrations || true
    test_autofix_existing_upgrade_record_failure_rolls_back_migrations_and_path_updates || true
    test_autofix_existing_upgrade_record_failure_cleans_new_gtbi_home || true
    test_autofix_existing_upgrade_restores_version_when_recording_fails || true
    test_autofix_existing_clean_shell_configs_allows_empty_result || true
    test_autofix_existing_clean_reinstall_restores_backup_after_shell_cleanup_failure || true
    test_autofix_existing_clean_reinstall_preserves_journal_when_shell_cleanup_recovery_fails || true
    test_autofix_existing_clean_reinstall_preserves_journal_when_shell_file_recovery_is_incomplete || true
    test_autofix_existing_remove_artifacts_propagates_rm_failures || true

    harness_section "Export Config"
    test_export_config_json_is_valid || true
    test_export_config_uses_installed_layout_under_root_home || true
    test_export_config_uses_explicit_target_home_when_state_is_missing || true
    test_export_config_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_export_config_augment_path_ignores_other_user_home_bin_dir || true
    test_export_config_installed_script_ignores_poisoned_explicit_gtbi_home || true
    test_export_config_uses_system_state_when_user_state_missing || true
    test_export_config_uses_system_state_target_home_when_getent_unavailable || true
    test_export_config_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_export_config_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_export_config_can_be_sourced_without_mutating_caller_env || true
    test_export_config_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_export_config_ignores_relative_home_state_trap || true
    test_export_config_does_not_infer_target_home_from_markerless_gtbi_home || true

    harness_section "Status"
    test_status_rejects_unknown_flags || true
    test_status_plain_output_avoids_ansi_when_not_tty || true
    test_status_reports_last_updated_timestamp || true
    test_status_errors_on_malformed_state_json || true
    test_status_uses_installed_layout_under_root_home || true
    test_status_uses_explicit_target_home_when_state_is_missing || true
    test_status_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_status_ignores_current_shell_only_binaries || true
    test_status_binary_path_ignores_other_user_home_bin_dir_from_state || true
    test_status_uses_persisted_bin_dir_over_poisoned_env_bin_dir || true
    test_status_prefers_resolved_install_state_over_stale_system_state_for_target_context || true
    test_status_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_status_uses_system_state_when_user_state_missing || true
    test_status_uses_system_state_target_home_when_getent_unavailable || true
    test_status_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_status_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_status_can_be_sourced_without_running_main || true
    test_status_ignores_relative_home_state_trap || true

    harness_section "Changelog Root Context"
    test_changelog_uses_installed_layout_under_root_home || true
    test_changelog_uses_system_state_when_user_state_missing || true
    test_changelog_uses_system_state_target_home_when_getent_unavailable || true
    test_changelog_uses_explicit_target_home_when_state_is_missing || true
    test_changelog_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_changelog_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_changelog_ignores_relative_home_trap || true
    test_changelog_can_be_sourced_without_leaking_install_context || true
    test_changelog_sourced_helper_uses_cached_current_home_when_runtime_home_is_poisoned || true

    harness_section "Continue"
    test_continue_uses_installed_layout_under_root_home || true
    test_continue_uses_system_state_target_home_when_getent_unavailable || true
    test_continue_uses_explicit_target_home_when_state_is_missing || true
    test_continue_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_continue_ignores_relative_home_state_trap || true
    test_continue_ignores_generic_install_process_matches || true
    test_continue_failed_state_beats_runtime_probe || true
    test_continue_failed_state_prints_resume_hint || true
    test_continue_reports_installed_layout_log_locations || true
    test_continue_live_log_hint_uses_installed_layout_log_dir || true
    test_continue_can_be_sourced_without_leaking_install_context || true
    test_continue_sourced_helper_uses_cached_current_home_when_runtime_home_is_poisoned || true
    test_other_sourced_helpers_use_cached_current_home_when_runtime_home_is_poisoned || true
    test_continue_scans_nonstandard_homes_via_getent || true

    harness_section "Dashboard"
    test_dashboard_generation_is_atomic_on_failure || true
    test_dashboard_rejects_invalid_ports_before_serving || true
    test_dashboard_help_does_not_require_target_context || true
    test_dashboard_prefers_repo_local_info_script || true
    test_dashboard_uses_installed_layout_under_root_home || true
    test_dashboard_serve_uses_target_user_in_ssh_hint || true
    test_dashboard_copy_install_uses_target_home_only_system_state || true
    test_dashboard_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_dashboard_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_dashboard_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_dashboard_uses_explicit_target_home_when_state_is_missing || true
    test_dashboard_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_dashboard_can_be_sourced_without_mutating_caller_env || true
    test_dashboard_copy_install_ignores_relative_home_trap || true

    harness_section "Cheatsheet"
    test_state_library_ignores_relative_home_target_resolution || true
    test_smoke_test_ignores_relative_home_target_resolution || true
    test_smoke_test_does_not_guess_target_home_from_username || true
    test_smoke_test_can_be_sourced_without_leaking_install_context || true
    test_smoke_test_run_preserves_caller_path_when_sourced || true
    test_smoke_binary_path_prefers_persisted_bin_dir_over_poisoned_env_bin_dir || true
    test_smoke_installed_script_ignores_poisoned_explicit_gtbi_home || true
    test_smoke_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_smoke_prefers_explicit_gtbi_home_over_stale_system_state_for_target_context || true
    test_smoke_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_smoke_bootstrap_uses_system_state_target_home_when_getent_unavailable || true
    test_smoke_bootstrap_reads_state_with_poisoned_path || true
    test_smoke_bootstrap_recovers_local_passwd_when_getent_is_broken || true
    test_smoke_bootstrap_ignores_poisoned_current_user_env_and_path_tools || true
    test_cheatsheet_uses_installed_layout_and_target_path_under_root_home || true
    test_cheatsheet_ignores_other_user_home_bin_dir_from_state || true
    test_cheatsheet_copy_install_uses_target_home_only_system_state || true
    test_cheatsheet_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_cheatsheet_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_cheatsheet_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_cheatsheet_can_be_sourced_without_running_main || true
    test_cheatsheet_copy_install_ignores_relative_home_trap || true

    harness_section "Info / Support / Onboard"
    test_state_driven_helpers_reject_invalid_target_home_from_state || true
    test_runtime_helpers_do_not_guess_home_paths_from_usernames || true
    test_runtime_helpers_resolve_current_home_from_passwd_when_home_invalid || true
    test_runtime_helpers_prefer_passwd_home_over_mismatched_absolute_home || true
    test_runtime_helpers_ignore_poisoned_current_user_path_tools || true
    test_runtime_helpers_fail_closed_when_current_home_unresolved || true
    test_runtime_helpers_fail_closed_on_invalid_passwd_home_for_target_user || true
    test_info_uses_installed_layout_under_root_home || true
    test_info_uses_explicit_target_home_when_state_is_missing || true
    test_info_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_info_uses_system_state_target_home_when_getent_unavailable || true
    test_info_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_info_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_info_prefers_resolved_install_state_over_stale_system_state_for_target_context || true
    test_info_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_info_can_be_sourced_without_mutating_caller_home || true
    test_info_ignores_relative_home_state_trap || true
    test_info_uses_target_user_path_under_root_home || true
    test_info_summary_ignores_current_shell_only_binaries || true
    test_info_binary_path_prefers_persisted_bin_dir_over_poisoned_env_bin_dir || true
    test_info_zero_lessons_hides_onboard_prompt_and_explains_state || true
    test_info_reads_skipped_tools_without_jq || true
    test_support_bundle_uses_installed_layout_under_root_home || true
    test_support_bundle_uses_system_state_target_home_when_getent_unavailable || true
    test_support_bundle_repo_local_ignores_poisoned_explicit_gtbi_home || true
    test_support_bundle_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_support_bundle_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_support_bundle_uses_explicit_target_home_when_state_is_missing || true
    test_support_bundle_does_not_fall_back_to_current_home_when_explicit_target_is_unresolved || true
    test_support_can_be_sourced_without_running_main || true
    test_onboard_cli_aliases_work_in_zero_lessons_mode || true
    test_onboard_repairs_malformed_progress_before_showing_lesson || true
    test_onboard_accepts_sparse_lesson_numbers || true
    test_onboard_uses_installed_layout_under_root_home || true
    test_onboard_cheatsheet_uses_installed_layout_under_root_home || true
    test_onboard_auth_checks_use_installed_target_home_under_root_home || true
    test_onboard_auth_checks_find_target_binaries_outside_current_path || true
    test_onboard_auth_checks_reject_placeholder_credentials || true
    test_onboard_auth_checks_ignore_poisoned_current_path_and_env_bin_dir || true
    test_onboard_auth_checks_ignore_other_user_home_bin_dir_from_state || true
    test_onboard_auth_checks_use_explicit_target_user_when_no_authoritative_runtime_home_exists || true
    test_onboard_auth_checks_do_not_fall_back_to_current_home_when_explicit_target_user_is_unresolved || true
    test_onboard_gemini_vertex_auth_finds_target_google_cloud_sdk_bin_outside_current_path || true
    test_onboard_gemini_vertex_auth_finds_target_gcloud_outside_current_path || true
    test_onboard_copy_install_uses_system_state_under_root_home || true
    test_onboard_copy_install_uses_target_home_only_system_state_under_root_home || true
    test_onboard_repo_local_prefers_system_state_target_user_over_stale_installed_state || true
    test_onboard_repo_local_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_onboard_repo_local_ignores_stale_explicit_runtime_hints_when_system_state_points_to_live_install || true
    test_onboard_can_be_sourced_without_mutating_caller_env || true
    test_onboard_globals_survive_function_scoped_source_under_set_u || true
    test_onboard_copy_install_ignores_relative_home_trap || true

    harness_section "Runtime Helper Libs"
    test_cli_tools_ignore_other_user_home_bin_dir_override || true
    test_agents_ignore_other_user_home_bin_dir_override || true
    test_github_api_binary_path_ignores_other_user_home_bin_dir_override || true
    test_nightly_update_ignores_other_user_home_bin_dir_before_preflight_path || true
    test_nightly_update_ignores_stale_explicit_target_home_before_preflight_path || true

    harness_section "Entrypoint Dispatch"
    test_doctor_entrypoint_dispatches_helper_commands || true
    test_doctor_dispatches_installed_layout_under_root_home || true
    test_doctor_ignores_relative_home_state_trap || true
    test_doctor_uses_system_state_target_home_when_installed_state_is_stale || true
    test_doctor_prefers_target_home_over_poisoned_gtbi_home || true
    test_gtbi_wrappers_prefer_passwd_home_over_mismatched_absolute_home || true
    test_gtbi_wrappers_ignore_poisoned_current_user_path_tools || true
    test_gtbi_system_binary_resolvers_cover_usr_local || true
    test_selected_system_binary_resolvers_reject_pathlike_names || true
    test_doctor_manifest_checks_prefer_system_bins_over_current_shell_path || true
    test_doctor_manifest_checks_fail_closed_when_target_home_is_unresolved || true
    test_doctor_manifest_checks_reject_invalid_target_user_before_sudo || true
    test_doctor_root_manifest_checks_run_when_target_home_is_unresolved || true
    test_doctor_deep_optional_probe_ignores_current_shell_only_path_entries || true
    test_gtbi_update_wrapper_uses_system_state_target_home_when_getent_unavailable || true
    test_gtbi_update_wrapper_repairs_runtime_home_on_direct_exec || true
    test_gtbi_update_wrapper_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_gtbi_update_wrapper_repo_local_prefers_system_state_target_home_over_stale_explicit_env || true
    test_gtbi_update_wrapper_passes_bin_dir_from_state || true
    test_gtbi_update_wrapper_prefers_state_bin_dir_over_poisoned_env || true
    test_gtbi_update_wrapper_discards_invalid_env_bin_dir_on_direct_exec || true
    test_gtbi_update_wrapper_discards_invalid_env_state_file_on_direct_exec || true
    test_gtbi_update_wrapper_ignores_relative_home_state_trap || true
    test_gtbi_update_wrapper_does_not_guess_current_home_when_target_home_is_unresolved || true
    test_gtbi_update_wrapper_ignores_stale_explicit_gtbi_home_when_system_state_points_to_live_install || true
    test_gtbi_update_wrapper_prefers_explicit_gtbi_home_over_current_home_when_system_state_is_missing || true
    test_gtbi_update_wrapper_ignores_poisoned_bin_dir_after_runtime_resolution || true
    test_gtbi_update_wrapper_ignores_stale_system_state_bin_dir_after_runtime_resolution || true
    test_gtbi_update_wrapper_ignores_other_user_home_bin_dir_from_state || true
    test_gtbi_update_wrapper_ignores_other_user_home_env_bin_dir_after_runtime_resolution || true
    test_gtbi_update_wrapper_ignores_stale_home_adjacent_target_user || true
    test_gtbi_update_wrapper_uses_installed_layout_state_context || true
    test_gtbi_global_wrapper_uses_system_state_target_home_when_getent_unavailable || true
    test_gtbi_global_wrapper_repairs_runtime_home_on_direct_exec || true
    test_gtbi_global_wrapper_prefers_live_home_adjacent_gtbi_path_over_stale_state_target_home || true
    test_gtbi_global_wrapper_runs_direct_when_owner_unknown_but_target_home_known || true
    test_gtbi_global_wrapper_passes_bin_dir_from_state || true
    test_gtbi_global_wrapper_prefers_state_bin_dir_over_poisoned_env || true
    test_gtbi_global_wrapper_discards_invalid_env_bin_dir_on_direct_exec || true
    test_gtbi_global_wrapper_discards_invalid_env_state_file_on_direct_exec || true
    test_gtbi_global_wrapper_ignores_other_user_home_bin_dir_from_state || true
    test_gtbi_global_wrapper_ignores_other_user_home_env_bin_dir_after_runtime_resolution || true
    test_gtbi_global_wrapper_ignores_relative_home_state_trap || true
    test_gtbi_global_wrapper_does_not_guess_current_home_when_target_home_is_unresolved || true
    test_gtbi_global_wrapper_ignores_stale_explicit_gtbi_home_when_system_state_points_to_live_install || true
    test_gtbi_global_wrapper_prefers_explicit_gtbi_home_over_current_home_when_system_state_is_missing || true
    test_gtbi_global_wrapper_ignores_poisoned_bin_dir_after_runtime_resolution || true
    test_gtbi_global_wrapper_ignores_stale_system_state_bin_dir_after_runtime_resolution || true
    test_gtbi_global_wrapper_ignores_stale_home_adjacent_target_user || true
    test_gtbi_global_wrapper_uses_installed_layout_state_context || true
    test_doctor_agent_checks_use_target_context_under_root_home || true
    test_doctor_agent_checks_prefer_persisted_bin_dir_over_poisoned_env_bin_dir || true
    test_doctor_agent_checks_ignore_other_user_home_bin_dir_from_state || true
    test_doctor_deep_agent_auth_uses_target_context_under_root_home || true
    test_doctor_deep_gemini_auth_finds_target_google_cloud_sdk_bin_under_root_home || true
    test_doctor_deep_optional_probes_use_target_home_under_root_home || true

    harness_summary
}


main "$@"
