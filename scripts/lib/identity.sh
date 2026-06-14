#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# GTBI Installer - User Identity Library (gtbi-90i)
# Idempotently configures Git and Dolt user.name / user.email
# for the target user. Both Git and Dolt need an identity to
# create commits. Runs all reads/writes AS the target user so
# config lands in ~/.gitconfig and ~/.dolt/config_global.json.
# ============================================================

# Read a single identity value as the target user. Echoes the value (may be
# empty) on stdout; never fails the caller.
# Usage: _identity_read git user.name   |   _identity_read dolt user.email
_identity_read() {
    local tool="$1"
    local key="$2"

    case "$tool" in
        git)
            run_as_target_shell "git config --global --get $key 2>/dev/null || true"
            ;;
        dolt)
            run_as_target_shell "dolt config --global --get $key 2>/dev/null || true"
            ;;
    esac
}

# Write an identity value as the target user.
# Usage: _identity_write git user.name "Jane Doe"
_identity_write() {
    local tool="$1"
    local key="$2"
    local value="$3"
    local q
    # Single-quote the value to keep it literal inside the remote shell.
    q="'${value//\'/\'\\\'\'}'"

    case "$tool" in
        git)
            run_as_target_shell "git config --global $key $q"
            ;;
        dolt)
            run_as_target_shell "dolt config --global --add $key $q"
            ;;
    esac
}

# Validate an identity pair. Returns 0 if name is non-empty and email contains '@'.
_identity_valid() {
    local name="$1"
    local email="$2"
    [[ -n "$name" ]] && [[ "$email" == *@* ]]
}

# Configure Git and Dolt identity for the target user.
# Non-fatal: any failure logs a warning and returns 0 so the install continues.
configure_user_identity() {
    local git_name git_email dolt_name dolt_email
    git_name="$(_identity_read git user.name)"
    git_email="$(_identity_read git user.email)"
    dolt_name="$(_identity_read dolt user.name)"
    dolt_email="$(_identity_read dolt user.email)"

    local git_has_both=false dolt_has_both=false
    _identity_valid "$git_name" "$git_email" && git_has_both=true
    _identity_valid "$dolt_name" "$dolt_email" && dolt_has_both=true

    # Both already configured -> nothing to do.
    if [[ "$git_has_both" == "true" && "$dolt_has_both" == "true" ]]; then
        log_detail "identity already configured (git + dolt)"
        return 0
    fi

    # Git has both, Dolt missing -> copy Git -> Dolt (no prompt).
    if [[ "$git_has_both" == "true" && "$dolt_has_both" != "true" ]]; then
        log_detail "Copying Git identity to Dolt"
        _identity_write dolt user.name "$git_name" || log_warn "Failed to set Dolt user.name"
        _identity_write dolt user.email "$git_email" || log_warn "Failed to set Dolt user.email"
        return 0
    fi

    # Dolt has both, Git missing -> copy Dolt -> Git (no prompt).
    if [[ "$dolt_has_both" == "true" && "$git_has_both" != "true" ]]; then
        log_detail "Copying Dolt identity to Git"
        _identity_write git user.name "$dolt_name" || log_warn "Failed to set Git user.name"
        _identity_write git user.email "$dolt_email" || log_warn "Failed to set Git user.email"
        return 0
    fi

    # Neither (or partial) -> obtain name + email from env, then prompt.
    local name="" email=""

    if [[ -n "${GTBI_GIT_NAME:-}" ]] && [[ -n "${GTBI_GIT_EMAIL:-}" ]]; then
        name="$GTBI_GIT_NAME"
        email="$GTBI_GIT_EMAIL"
    elif [[ -n "${GIT_AUTHOR_NAME:-}" ]] && [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
        name="$GIT_AUTHOR_NAME"
        email="$GIT_AUTHOR_EMAIL"
    fi

    if [[ -n "$name" || -n "$email" ]]; then
        # Came from env: validate, but never block. Skip with guidance if invalid.
        if ! _identity_valid "$name" "$email"; then
            log_warn "Provided GTBI_GIT_NAME/GTBI_GIT_EMAIL (or GIT_AUTHOR_*) are invalid; skipping identity setup"
            _identity_skip_hint
            return 0
        fi
    else
        # No env values. Prompt only if interactive (TTY available, not --yes).
        if [[ "${YES_MODE:-false}" == "true" ]] || { [[ ! -r /dev/tty ]] && [[ ! -t 0 ]]; }; then
            log_warn "No Git/Dolt identity configured and running non-interactively; skipping"
            _identity_skip_hint
            return 0
        fi

        local attempts=0
        while (( attempts < 3 )); do
            ((attempts++))
            name="$(gum_input "Your full name (for Git/Dolt commits):" "Jane Doe")" || {
                log_warn "Unable to read input; skipping identity setup"
                _identity_skip_hint
                return 0
            }
            email="$(gum_input "Your email (for Git/Dolt commits):" "jane@example.com")" || {
                log_warn "Unable to read input; skipping identity setup"
                _identity_skip_hint
                return 0
            }
            if _identity_valid "$name" "$email"; then
                break
            fi
            log_warn "Name must be non-empty and email must contain '@'. Try again."
            name=""
            email=""
        done

        if ! _identity_valid "$name" "$email"; then
            log_warn "Identity not provided after 3 attempts; skipping"
            _identity_skip_hint
            return 0
        fi
    fi

    # Apply to whichever tool is missing values (only write absent ones).
    if [[ "$git_has_both" != "true" ]]; then
        _identity_write git user.name "$name" || log_warn "Failed to set Git user.name"
        _identity_write git user.email "$email" || log_warn "Failed to set Git user.email"
    fi
    if [[ "$dolt_has_both" != "true" ]]; then
        _identity_write dolt user.name "$name" || log_warn "Failed to set Dolt user.name"
        _identity_write dolt user.email "$email" || log_warn "Failed to set Dolt user.email"
    fi
    log_detail "Configured Git/Dolt identity: $name <$email>"
    return 0
}

# Print guidance for configuring identity later.
_identity_skip_hint() {
    log_warn "Set it later with:"
    log_warn "  git config --global user.name \"Your Name\" && git config --global user.email \"you@example.com\""
    log_warn "  dolt config --global --add user.name \"Your Name\" && dolt config --global --add user.email \"you@example.com\""
}
