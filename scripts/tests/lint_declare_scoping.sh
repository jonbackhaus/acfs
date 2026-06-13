#!/usr/bin/env bash
# ============================================================
# Lint: Declare Scoping
#
# Sourceable GTBI Bash files are sometimes sourced inside functions.
# Without the -g flag, top-level declare -A and declare -a create
# function-local arrays that vanish when the function returns.
#
# This linter scans for any declare -A or declare -a that is missing
# the -g flag, and for global arrays declared without an initial value.
# A bare `declare -ga NAME` is still unbound under `set -u`; use
# `declare -ga NAME=()` or `declare -gA NAME=()`.
#
# Related bugs: #85-#90 (chg_0001: unbound variable crash)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"

declare -a SCAN_FILES=()
for file in "$LIB_DIR"/*.sh; do
    [[ -f "$file" ]] || continue
    SCAN_FILES+=("$file")
done
SCAN_FILES+=(
    "$REPO_ROOT/packages/onboard/onboard.sh"
)

errors=0
checked=0

echo "=== Declare Scoping Linter ==="
echo "Scanning sourceable Bash files for unsafe declare -A/-a usage..."
echo ""

for file in "${SCAN_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    basename_file="$(basename "$file")"
    rel_file="${file#"$REPO_ROOT/"}"

    # Skip test files - they run standalone, not sourced inside a function
    if [[ "$basename_file" == test_* ]]; then
        continue
    fi

    ((checked++)) || true

    # Find declare -A or declare -a lines that do NOT have -g
    # Valid patterns:   declare -gA, declare -Ag, declare -ga, declare -ag
    # Invalid patterns: declare -A, declare -a (no -g anywhere in flags)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        lineno="${match%%:*}"
        line="${match#*:}"

        # Skip comments
        stripped="${line#"${line%%[![:space:]]*}"}"
        if [[ "$stripped" == \#* ]]; then
            continue
        fi

        if [[ "$stripped" =~ ^declare[[:space:]]+(-[[:alpha:]]*[aA][[:alpha:]]*)[[:space:]]+ ]]; then
            flags="${BASH_REMATCH[1]}"
            [[ "$flags" != *g* ]] || continue
        else
            continue
        fi

        echo "ERROR: $rel_file:$lineno: declare without -g flag (will be function-local when sourced)"
        echo "  $line"
        echo "  Fix: Add -g flag (e.g., 'declare -gA' or 'declare -ga')"
        echo ""
        ((errors++)) || true
    done < <(grep -nE '^[[:space:]]*declare[[:space:]]+-[[:alpha:]]*[Aa][[:alpha:]]*[[:space:]]+' "$file" || true)

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        lineno="${match%%:*}"
        line="${match#*:}"

        stripped="${line#"${line%%[![:space:]]*}"}"
        if [[ "$stripped" == \#* ]]; then
            continue
        fi

        if [[ "$stripped" =~ ^declare[[:space:]]+(-[[:alpha:]]*[aA][[:alpha:]]*)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:];]*(#.*)?)?$ ]]; then
            flags="${BASH_REMATCH[1]}"
            if [[ "$flags" == *g* ]]; then
                echo "ERROR: $rel_file:$lineno: global array declared without allocation (unbound under set -u)"
                echo "  $line"
                echo "  Fix: Initialize it at declaration (e.g., 'declare -gA NAME=()' or 'declare -ga NAME=()')"
                echo ""
                ((errors++)) || true
            fi
        fi
    done < <(grep -nE '^[[:space:]]*declare[[:space:]]+-[[:alpha:]]*[Aa][[:alpha:]]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" || true)
done

echo "---"
echo "Checked $checked sourceable Bash files, found $errors violations."

if [[ $errors -gt 0 ]]; then
    echo ""
    echo "FAIL: $errors unsafe declare statement(s)."
    echo "All global declare -A/-a in sourceable Bash files must use -g and initialize with =()."
    exit 1
fi

echo "PASS: All global array declare statements are scoped and initialized safely."
exit 0
