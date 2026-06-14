#!/usr/bin/env bash
# ============================================================
# GTBI Installer - Version Upgrade Test (Docker)
#
# Installs the previous tagged release of GTBI, then runs the
# current installer (--force-reinstall) on top and verifies
# the system is healthy. Tests the version upgrade path.
#
# Runs INSIDE a Docker container. Mount the repo at /repo:
#
#   docker run --rm \
#     -e GTBI_CI=true \
#     -v /path/to/gtbi:/repo:rw \
#     ubuntu:25.10 bash /repo/tests/docker/test_upgrade.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

ARTIFACTS_DIR="$REPO_ROOT/tests/artifacts"
mkdir -p "$ARTIFACTS_DIR"

log()  { echo "[GTBI-UPGRADE] $1"; }
fail() { echo "[FAIL] $1" >&2; exit 1; }

# Bootstrap prerequisites if not already present
if ! command -v sudo >/dev/null 2>&1; then
    log "Installing bootstrap prerequisites..."
    apt-get update -qq
    apt-get install -y -qq sudo curl git ca-certificates jq unzip tar xz-utils gnupg >/dev/null
fi

# Pre-configure sudoers if not already done
if [[ ! -f /etc/sudoers.d/90-gtbi-ubuntu ]]; then
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-gtbi-ubuntu
    chmod 440 /etc/sudoers.d/90-gtbi-ubuntu
fi

CURRENT_VERSION="$(cat "$REPO_ROOT/VERSION")"

# ── Find previous tag ──────────────────────────────────────────────────────────

log "Resolving previous release tag (current: ${CURRENT_VERSION})"
PREV_TAG="$(git -C "$REPO_ROOT" tag --sort=-version:refname | grep -v "^v\?${CURRENT_VERSION}$" | head -1 || true)"

if [[ -z "$PREV_TAG" ]]; then
    log "[SKIP] No previous tag found — skipping upgrade test"
    exit 0
fi

log "Previous tag: ${PREV_TAG}"

# ── Phase 1: Install previous release ─────────────────────────────────────────

log "Phase 1: Install previous release (${PREV_TAG})"
git -C "$REPO_ROOT" show "${PREV_TAG}:install.sh" > /tmp/install_old.sh
chmod +x /tmp/install_old.sh

if GTBI_CI=true bash /tmp/install_old.sh \
        --yes --skip-preflight --skip-ubuntu-upgrade --mode vibe \
        > "${ARTIFACTS_DIR}/upgrade_old_install.log" 2>&1; then
    log "Previous release installed successfully"
else
    log "Previous release install failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/upgrade_old_install.log"
    fail "Previous release install failed"
fi

# ── Assert state.json from old install ────────────────────────────────────────

STATE_FILE="/home/ubuntu/.gtbi/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
    fail "state.json not found at $STATE_FILE after old install"
fi

SCHEMA_VERSION="$(jq -r '.schema_version // 0' "$STATE_FILE")"
OLD_VERSION="$(jq -r '.version // ""' "$STATE_FILE")"
log "Old state: schema_version=${SCHEMA_VERSION}, version=${OLD_VERSION}"

if [[ "$SCHEMA_VERSION" -lt 3 ]]; then
    fail "state.json schema_version is ${SCHEMA_VERSION}, expected >= 3"
fi

# ── Phase 2: Upgrade to current release ───────────────────────────────────────

log "Phase 2: Upgrade to current release (${CURRENT_VERSION}) via --force-reinstall"
if GTBI_CI=true bash "$REPO_ROOT/install.sh" \
        --yes --skip-preflight --skip-ubuntu-upgrade --force-reinstall --mode vibe \
        > "${ARTIFACTS_DIR}/upgrade_new_install.log" 2>&1; then
    log "Current release installed successfully"
else
    log "Current release install failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/upgrade_new_install.log"
    fail "Current release install failed"
fi

# ── Assert VERSION updated in state.json ──────────────────────────────────────

NEW_VERSION="$(jq -r '.version // ""' "$STATE_FILE")"
log "New state: version=${NEW_VERSION}"

if [[ "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
    fail "state.json version is '${NEW_VERSION}', expected '${CURRENT_VERSION}'"
fi

# ── Phase 3: Doctor verification ──────────────────────────────────────────────

log "Phase 3: Doctor verification"
if su - ubuntu -c "GTBI_DOCTOR_CI=true zsh -ic 'gtbi doctor'" \
        > "${ARTIFACTS_DIR}/upgrade_doctor.log" 2>&1; then
    log "Doctor passed"
else
    log "Doctor failed — output:"
    cat "${ARTIFACTS_DIR}/upgrade_doctor.log"
    fail "Doctor failed after upgrade"
fi

# ── Phase 4: Module-level idempotency on resume (gtbi-d8b) ────────────────────
# Simulate a module that was added in a newer release after the phase was recorded
# complete: the stack phase is marked complete in state.json, but one of its
# modules (gt / stack.gastown) is absent. A plain resume install (NO
# --force-reinstall) must re-enter the completed phase, reinstall the missing
# module, and NOT redundantly reinstall the modules that are already present.

log "Phase 4: Module-level idempotency on resume (remove gt, then resume install)"

GT_BIN="/home/ubuntu/.local/bin/gt"
if [[ ! -x "$GT_BIN" ]]; then
    fail "Expected gt at $GT_BIN after upgrade, but it is missing"
fi

# Confirm the stack phase is recorded complete (precondition for the bug).
if ! jq -e '.completed_phases | index("stack") != null' "$STATE_FILE" >/dev/null 2>&1; then
    fail "Precondition failed: 'stack' phase not marked complete in state.json"
fi

# Remove only gt, leaving dolt/bd in place.
rm -f "$GT_BIN"
log "Removed $GT_BIN; running resume install (no --force-reinstall)"

if GTBI_CI=true bash "$REPO_ROOT/install.sh" \
        --yes --skip-preflight --skip-ubuntu-upgrade --mode vibe \
        > "${ARTIFACTS_DIR}/upgrade_resume_install.log" 2>&1; then
    log "Resume install completed"
else
    log "Resume install failed — last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/upgrade_resume_install.log"
    fail "Resume install failed"
fi

# The missing module must now be installed.
if [[ -x "$GT_BIN" ]] || su - ubuntu -c "zsh -ic 'command -v gt >/dev/null'" >/dev/null 2>&1; then
    log "  [ok] gt reinstalled by resume"
else
    log "Resume install log tail:"
    tail -n 60 "${ARTIFACTS_DIR}/upgrade_resume_install.log"
    fail "gt was NOT reinstalled by resume install (module-level idempotency broken)"
fi

# Already-present modules must self-skip (not redundantly reinstall).
if grep -q "stack.dolt already installed; skipping" "${ARTIFACTS_DIR}/upgrade_resume_install.log" \
   && grep -q "stack.bd already installed; skipping" "${ARTIFACTS_DIR}/upgrade_resume_install.log"; then
    log "  [ok] dolt and bd self-skipped (no redundant reinstall)"
else
    log "Resume install log tail:"
    tail -n 60 "${ARTIFACTS_DIR}/upgrade_resume_install.log"
    fail "Expected dolt/bd to self-skip on resume, but skip markers were not found"
fi

# ── Spot-check key binaries ───────────────────────────────────────────────────

log "Spot-checking key binaries"
failed=0
check() {
    local name="$1" cmd="$2"
    if su - ubuntu -c "$cmd" >> "${ARTIFACTS_DIR}/upgrade_doctor.log" 2>&1; then
        echo "  [ok] $name"
    else
        echo "  [fail] $name"
        failed=$((failed + 1))
    fi
}

check "gh"     "zsh -ic 'gh --version >/dev/null'"
check "jq"     "zsh -ic 'jq --version >/dev/null'"
check "sg"     "zsh -ic 'sg --version >/dev/null'"
check "claude" "zsh -ic 'claude --version >/dev/null'"

if [[ $failed -gt 0 ]]; then
    fail "Spot-check failed for $failed binary/binaries"
fi

log "ALL TESTS PASSED (upgraded ${PREV_TAG} → ${CURRENT_VERSION})"
