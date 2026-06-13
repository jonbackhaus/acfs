#!/usr/bin/env bash
# ============================================================
# GTBI Output Formatting Library
#
# Provides JSON output formatting support.
#
# Usage:
#   source "${SCRIPT_DIR}/output.sh"
#
#   # Resolve output format from CLI and environment
#   format=$(gtbi_resolve_format "$cli_format")
#
#   # Format and emit JSON data
#   gtbi_format_output "$json_data" "$format"
#
# Environment Variables:
#   GTBI_OUTPUT_FORMAT   - Default format (json)
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_GTBI_OUTPUT_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_GTBI_OUTPUT_SH_LOADED=1

# ============================================================
# Format Resolution
# ============================================================

# Resolve output format from CLI argument and environment variables.
# Only JSON is supported, so this always normalizes to "json".
#
# Usage: format=$(gtbi_resolve_format "$cli_format")
# Returns: "json"
gtbi_resolve_format() {
    echo "json"
}

# ============================================================
# Output Formatting
# ============================================================

# Emit JSON data.
#
# Usage: gtbi_format_output "$json_data" "$format"
# Arguments:
#   $1 - JSON data string
#   $2 - Output format (ignored; always JSON)
# Output: JSON data to stdout
gtbi_format_output() {
    local json_data="$1"
    printf '%s\n' "$json_data"
}
