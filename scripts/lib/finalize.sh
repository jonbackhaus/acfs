#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# GTBI Installer - Finalize Library
# Final wiring: deploy configs, scripts, CLI commands
# Sourced by detect_environment() in install.sh
# ============================================================

if ! declare -f finalize >/dev/null 2>&1; then
finalize() {
    set_phase "finalize" "Final Wiring"
    log_step "9/9" "Finalizing installation..."

    # Source UI + identity helpers (not sourced by install.sh during the run).
    if ! declare -f gum_input >/dev/null 2>&1 && [[ -f "${GTBI_LIB_DIR:-}/gum_ui.sh" ]]; then
        # shellcheck source=scripts/lib/gum_ui.sh
        source "$GTBI_LIB_DIR/gum_ui.sh"
    fi
    if ! declare -f configure_user_identity >/dev/null 2>&1 && [[ -f "${GTBI_LIB_DIR:-}/identity.sh" ]]; then
        # shellcheck source=scripts/lib/identity.sh
        source "$GTBI_LIB_DIR/identity.sh"
    fi

    if gtbi_use_generated_category "gtbi"; then
        log_detail "Using generated installers for gtbi (phase 10)"
        gtbi_run_generated_category_phase "gtbi" "10" || return 1
        log_detail "Generated gtbi modules are supplemental; continuing legacy finalize for full runtime deployment parity"
    fi

    # Copy tmux config
    log_detail "Installing tmux config"
    try_step "Installing tmux config" install_asset "gtbi/tmux/tmux.conf" "$GTBI_HOME/tmux/tmux.conf" || return 1
    try_step "Setting tmux config ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/tmux/tmux.conf" || return 1

    # Link to target user's tmux.conf if it doesn't exist
    if [[ ! -f "$TARGET_HOME/.tmux.conf" ]]; then
        try_step "Linking tmux.conf" run_as_target ln -sf "$GTBI_HOME/tmux/tmux.conf" "$TARGET_HOME/.tmux.conf" || return 1
    fi

    # Reload tmux config if server is running (fixes #66: prefix key works immediately)
    # This handles the case where tmux started in an earlier phase before config was deployed
    # Note: Use $TARGET_HOME, not ~, since ~ expands to the installer's user (often root)
    run_as_target tmux source-file "$TARGET_HOME/.tmux.conf" 2>/dev/null || true

    # Install onboard lessons + command
    log_detail "Installing onboard lessons"
    try_step "Creating onboard lessons directory" $SUDO mkdir -p "$GTBI_HOME/onboard/lessons" || return 1
    local lesson_path
    local lesson_name
    local nullglob_was_set=0
    if shopt -q nullglob; then
        nullglob_was_set=1
    fi
    shopt -s nullglob
    local lesson_files=("${GTBI_ASSETS_DIR}/onboard/lessons/"*.md)
    if (( ! nullglob_was_set )); then
        shopt -u nullglob
    fi
    if [[ ${#lesson_files[@]} -eq 0 ]]; then
        log_error "No onboard lessons found in ${GTBI_ASSETS_DIR}/onboard/lessons"
        return 1
    fi
    for lesson_path in "${lesson_files[@]}"; do
        lesson_name=$(basename "$lesson_path")
        try_step "Installing onboard lesson: $lesson_name" install_asset "gtbi/onboard/lessons/$lesson_name" "$GTBI_HOME/onboard/lessons/$lesson_name" || return 1
    done

    log_detail "Installing onboard command"
    try_step "Installing onboard script" install_asset "packages/onboard/onboard.sh" "$GTBI_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard permissions" $SUDO chmod 755 "$GTBI_HOME/onboard/onboard.sh" || return 1
    try_step "Setting onboard ownership" gtbi_chown_tree "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/onboard" || return 1

    try_step "Creating bin directory ($GTBI_BIN_DIR)" gtbi_ensure_primary_bin_dir || return 1
    try_step "Linking onboard command" gtbi_link_primary_bin_command "$GTBI_HOME/onboard/onboard.sh" "onboard" || return 1
    try_step "Linking global onboard command" gtbi_link_global_bin_command "$GTBI_HOME/onboard/onboard.sh" "onboard" || return 1

    # Install gtbi scripts (for gtbi CLI subcommands)
    log_detail "Installing gtbi scripts"
    try_step "Creating GTBI scripts directory" $SUDO mkdir -p "$GTBI_HOME/scripts/lib" || return 1
    try_step "Creating GTBI generated scripts directory" $SUDO mkdir -p "$GTBI_HOME/scripts/generated" || return 1
    try_step "Creating GTBI templates directory" $SUDO mkdir -p "$GTBI_HOME/scripts/templates" || return 1
    
    # Install script libraries
    try_step "Installing logging.sh" install_asset "scripts/lib/logging.sh" "$GTBI_HOME/scripts/lib/logging.sh" || return 1
    try_step "Installing output.sh" install_asset "scripts/lib/output.sh" "$GTBI_HOME/scripts/lib/output.sh" || return 1
    try_step "Installing gum_ui.sh" install_asset "scripts/lib/gum_ui.sh" "$GTBI_HOME/scripts/lib/gum_ui.sh" || return 1
    try_step "Installing identity.sh" install_asset "scripts/lib/identity.sh" "$GTBI_HOME/scripts/lib/identity.sh" || return 1
    try_step "Installing progress.sh" install_asset "scripts/lib/progress.sh" "$GTBI_HOME/scripts/lib/progress.sh" || return 1
    try_step "Installing install_helpers.sh" install_asset "scripts/lib/install_helpers.sh" "$GTBI_HOME/scripts/lib/install_helpers.sh" || return 1
    try_step "Installing stack.sh" install_asset "scripts/lib/stack.sh" "$GTBI_HOME/scripts/lib/stack.sh" || return 1
    try_step "Installing finalize.sh" install_asset "scripts/lib/finalize.sh" "$GTBI_HOME/scripts/lib/finalize.sh" || return 1
    try_step "Installing contract.sh" install_asset "scripts/lib/contract.sh" "$GTBI_HOME/scripts/lib/contract.sh" || return 1
    try_step "Installing security.sh" install_asset "scripts/lib/security.sh" "$GTBI_HOME/scripts/lib/security.sh" || return 1
    try_step "Installing github_api.sh" install_asset "scripts/lib/github_api.sh" "$GTBI_HOME/scripts/lib/github_api.sh" || return 1
    try_step "Installing tools.sh" install_asset "scripts/lib/tools.sh" "$GTBI_HOME/scripts/lib/tools.sh" || return 1
    try_step "Installing autofix.sh" install_asset "scripts/lib/autofix.sh" "$GTBI_HOME/scripts/lib/autofix.sh" || return 1
    try_step "Installing doctor_fix.sh" install_asset "scripts/lib/doctor_fix.sh" "$GTBI_HOME/scripts/lib/doctor_fix.sh" || return 1
    try_step "Installing doctor.sh" install_asset "scripts/lib/doctor.sh" "$GTBI_HOME/scripts/lib/doctor.sh" || return 1
    try_step "Installing nightly_update.sh (source)" install_asset "scripts/lib/nightly_update.sh" "$GTBI_HOME/scripts/lib/nightly_update.sh" || return 1
    try_step "Installing nightly-update.sh (runtime wrapper)" install_asset "scripts/lib/nightly_update.sh" "$GTBI_HOME/scripts/nightly-update.sh" || return 1
    try_step "Installing update.sh" install_asset "scripts/lib/update.sh" "$GTBI_HOME/scripts/lib/update.sh" || return 1
    try_step "Installing session.sh" install_asset "scripts/lib/session.sh" "$GTBI_HOME/scripts/lib/session.sh" || return 1
    try_step "Installing continue.sh" install_asset "scripts/lib/continue.sh" "$GTBI_HOME/scripts/lib/continue.sh" || return 1
    try_step "Installing info.sh" install_asset "scripts/lib/info.sh" "$GTBI_HOME/scripts/lib/info.sh" || return 1
    try_step "Installing status.sh" install_asset "scripts/lib/status.sh" "$GTBI_HOME/scripts/lib/status.sh" || return 1
    try_step "Installing rescue.sh" install_asset "scripts/lib/rescue.sh" "$GTBI_HOME/scripts/lib/rescue.sh" || return 1
    try_step "Installing capacity.sh" install_asset "scripts/lib/capacity.sh" "$GTBI_HOME/scripts/lib/capacity.sh" || return 1
    try_step "Installing policy_lint.sh" install_asset "scripts/lib/policy_lint.sh" "$GTBI_HOME/scripts/lib/policy_lint.sh" || return 1
    try_step "Installing credential_preflight.sh" install_asset "scripts/lib/credential_preflight.sh" "$GTBI_HOME/scripts/lib/credential_preflight.sh" || return 1
    try_step "Installing landing_plane.sh" install_asset "scripts/lib/landing_plane.sh" "$GTBI_HOME/scripts/lib/landing_plane.sh" || return 1
    try_step "Installing provenance.sh" install_asset "scripts/lib/provenance.sh" "$GTBI_HOME/scripts/lib/provenance.sh" || return 1
    try_step "Installing offline_artifact_pack.sh" install_asset "scripts/lib/offline_artifact_pack.sh" "$GTBI_HOME/scripts/lib/offline_artifact_pack.sh" || return 1
    try_step "Installing changelog.sh" install_asset "scripts/lib/changelog.sh" "$GTBI_HOME/scripts/lib/changelog.sh" || return 1
    try_step "Installing export-config.sh" install_asset "scripts/lib/export-config.sh" "$GTBI_HOME/scripts/lib/export-config.sh" || return 1
    try_step "Installing cheatsheet.sh" install_asset "scripts/lib/cheatsheet.sh" "$GTBI_HOME/scripts/lib/cheatsheet.sh" || return 1
    try_step "Installing webhook.sh" install_asset "scripts/lib/webhook.sh" "$GTBI_HOME/scripts/lib/webhook.sh" || return 1
    try_step "Installing notify.sh" install_asset "scripts/lib/notify.sh" "$GTBI_HOME/scripts/lib/notify.sh" || return 1
    try_step "Installing notifications.sh" install_asset "scripts/lib/notifications.sh" "$GTBI_HOME/scripts/lib/notifications.sh" || return 1
    try_step "Installing dashboard.sh" install_asset "scripts/lib/dashboard.sh" "$GTBI_HOME/scripts/lib/dashboard.sh" || return 1
    try_step "Installing support.sh" install_asset "scripts/lib/support.sh" "$GTBI_HOME/scripts/lib/support.sh" || return 1
    try_step "Installing gtbi-nightly-update.service template" install_asset "scripts/templates/gtbi-nightly-update.service" "$GTBI_HOME/scripts/templates/gtbi-nightly-update.service" || return 1
    try_step "Installing gtbi-nightly-update.timer template" install_asset "scripts/templates/gtbi-nightly-update.timer" "$GTBI_HOME/scripts/templates/gtbi-nightly-update.timer" || return 1

    local generated_script=""
    local generated_basename=""
    local generated_count=0
    for generated_script in "$GTBI_GENERATED_DIR"/*.sh; do
        [[ -f "$generated_script" ]] || continue
        generated_basename="$(basename "$generated_script")"
        try_step "Installing generated script: $generated_basename" install_asset_from_path "$generated_script" "$GTBI_HOME/scripts/generated/$generated_basename" || return 1
        generated_count=$((generated_count + 1))
    done
    if [[ $generated_count -eq 0 ]]; then
        log_error "No generated GTBI scripts found to install from $GTBI_GENERATED_DIR"
        return 1
    fi

    # Install gtbi-update wrapper command
    try_step "Installing gtbi-update" install_asset "scripts/gtbi-update" "$GTBI_HOME/bin/gtbi-update" || return 1
    try_step "Setting gtbi-update permissions" $SUDO chmod 755 "$GTBI_HOME/bin/gtbi-update" || return 1
    try_step "Setting gtbi-update ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/bin/gtbi-update" || return 1
    try_step "Linking gtbi-update command" gtbi_link_primary_bin_command "$GTBI_HOME/bin/gtbi-update" "gtbi-update" || return 1
    try_step "Linking global gtbi-update command" gtbi_link_global_bin_command "$GTBI_HOME/bin/gtbi-update" "gtbi-update" || return 1

    # Install root AGENTS.md generator (if available) and generate /AGENTS.md once
    if try_step "Installing flywheel-update-agents-md" install_asset "scripts/generate-root-agents-md.sh" "$GTBI_HOME/bin/flywheel-update-agents-md"; then
        try_step "Setting flywheel-update-agents-md permissions" $SUDO chmod 755 "$GTBI_HOME/bin/flywheel-update-agents-md" || return 1
        try_step "Setting flywheel-update-agents-md ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/bin/flywheel-update-agents-md" || return 1
        try_step "Linking flywheel-update-agents-md command" $SUDO ln -sf "$GTBI_HOME/bin/flywheel-update-agents-md" "/usr/local/bin/flywheel-update-agents-md" || return 1
        try_step "Generating /AGENTS.md" $SUDO /usr/local/bin/flywheel-update-agents-md || true
    else
        log_warn "Root AGENTS.md generator not found; skipping /AGENTS.md generation"
    fi

    try_step "Setting lib scripts permissions" $SUDO chmod 755 "$GTBI_HOME/scripts/lib/"*.sh "$GTBI_HOME/scripts/nightly-update.sh" || return 1
    try_step "Setting generated scripts permissions" $SUDO find "$GTBI_HOME/scripts/generated" -maxdepth 1 -type f -name '*.sh' -exec chmod 755 {} + || return 1
    try_step "Setting scripts ownership" gtbi_chown_tree "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/scripts" || return 1
    try_step "Configuring GTBI nightly update timer" configure_gtbi_nightly_timer || return 1

    # Install newproj command scripts (used by gtbi newproj CLI and TUI wizard)
    log_detail "Installing newproj scripts"
    try_step "Installing newproj.sh" install_asset "scripts/lib/newproj.sh" "$GTBI_HOME/scripts/lib/newproj.sh" || return 1
    try_step "Installing newproj_agents.sh" install_asset "scripts/lib/newproj_agents.sh" "$GTBI_HOME/scripts/lib/newproj_agents.sh" || return 1
    try_step "Installing newproj_detect.sh" install_asset "scripts/lib/newproj_detect.sh" "$GTBI_HOME/scripts/lib/newproj_detect.sh" || return 1
    try_step "Installing newproj_errors.sh" install_asset "scripts/lib/newproj_errors.sh" "$GTBI_HOME/scripts/lib/newproj_errors.sh" || return 1
    try_step "Installing newproj_logging.sh" install_asset "scripts/lib/newproj_logging.sh" "$GTBI_HOME/scripts/lib/newproj_logging.sh" || return 1
    try_step "Installing newproj_screens.sh" install_asset "scripts/lib/newproj_screens.sh" "$GTBI_HOME/scripts/lib/newproj_screens.sh" || return 1
    try_step "Installing newproj_tui.sh" install_asset "scripts/lib/newproj_tui.sh" "$GTBI_HOME/scripts/lib/newproj_tui.sh" || return 1

    try_step "Creating newproj_screens directory" $SUDO mkdir -p "$GTBI_HOME/scripts/lib/newproj_screens" || return 1
    
    local screens=(
        "screen_agents_preview.sh"
        "screen_confirmation.sh"
        "screen_directory.sh"
        "screen_features.sh"
        "screen_progress.sh"
        "screen_project_name.sh"
        "screen_success.sh"
        "screen_tech_stack.sh"
        "screen_welcome.sh"
    )
    for screen in "${screens[@]}"; do
        try_step "Installing $screen" install_asset "scripts/lib/newproj_screens/$screen" "$GTBI_HOME/scripts/lib/newproj_screens/$screen" || return 1
    done
    try_step "Setting newproj permissions" $SUDO chmod 755 "$GTBI_HOME/scripts/lib/"newproj*.sh "$GTBI_HOME/scripts/lib/newproj_screens/"*.sh || return 1
    try_step "Setting newproj ownership" gtbi_chown_tree "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/scripts/lib" || return 1

    # Install checksums + version metadata so `gtbi update --stack` can verify upstream scripts.
    try_step "Installing checksums.yaml" install_checksums_yaml "$GTBI_HOME/checksums.yaml" || return 1
    try_step "Installing VERSION" install_asset "VERSION" "$GTBI_HOME/VERSION" || return 1
    try_step "Setting metadata ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/checksums.yaml" "$GTBI_HOME/VERSION" || true

    # Legacy: Install doctor as gtbi binary (for backwards compat)
    try_step "Installing gtbi CLI" install_asset "scripts/lib/doctor.sh" "$GTBI_HOME/bin/gtbi" || return 1
    try_step "Setting gtbi permissions" $SUDO chmod 755 "$GTBI_HOME/bin/gtbi" || return 1
    try_step "Setting gtbi ownership" $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_HOME/bin/gtbi" || return 1
    try_step "Linking gtbi command" gtbi_link_primary_bin_command "$GTBI_HOME/bin/gtbi" "gtbi" || return 1

    # Install global gtbi wrapper (works for root and all users)
    # This wrapper finds the target user from state and runs gtbi as that user
    try_step "Installing global gtbi wrapper" install_asset "scripts/gtbi-global" "/usr/local/bin/gtbi" || return 1
    try_step "Setting global gtbi permissions" $SUDO chmod 755 "/usr/local/bin/gtbi" || return 1

    # Configure workspace trust for coding agents (fixes #159)
    # In vibe/yolo mode, Claude Code requires explicit workspace trust to avoid
    # interactive prompts. Set skipDangerousModePermissionPrompt and trust /data/projects + $HOME.
    if [[ "$MODE" == "vibe" ]]; then
        log_detail "Configuring workspace trust for coding agents..."
        local claude_settings_file="$TARGET_HOME/.claude/settings.json"
        if [[ -f "$claude_settings_file" ]] && command -v jq &>/dev/null; then
            # Use run_as_target for the entire jq+mv pipeline so the temp file
            # is created with target user ownership (not root). Previously the
            # shell redirect "> $tmp_settings" ran as root, leaving a root-owned
            # settings file that the target user couldn't modify later.
            local tmp_settings="${claude_settings_file}.tmp.$$"
            if run_as_target bash -c "jq '.skipDangerousModePermissionPrompt = true' \"\$1\" > \"\$2\" && mv \"\$2\" \"\$1\"" \
                    _ "$claude_settings_file" "$tmp_settings" 2>/dev/null; then
                log_detail "Claude workspace trust configured"
            else
                run_as_target rm -f "$tmp_settings" 2>/dev/null || true
            fi
        elif [[ ! -f "$claude_settings_file" ]]; then
            # Create minimal settings with trust enabled
            run_as_target mkdir -p "$TARGET_HOME/.claude" 2>/dev/null || true
            run_as_target tee "$claude_settings_file" > /dev/null << 'CLAUDE_TRUST_EOF'
{
  "skipDangerousModePermissionPrompt": true
}
CLAUDE_TRUST_EOF
            log_detail "Claude settings created with workspace trust"
        fi

        # Gemini CLI trust pre-configuration (fixes #159 follow-up)
        # Gemini CLI prompts for folder trust on first run. Pre-configure trusted
        # folders so agents can start without interactive approval.
        local gemini_settings_file="$TARGET_HOME/.gemini/settings.json"
        if [[ -f "$gemini_settings_file" ]] && command -v jq &>/dev/null; then
            local tmp_gemini="${gemini_settings_file}.tmp.$$"
            # Enable folder trust and set yolo-equivalent sandbox bypass
            if run_as_target bash -c "jq '
                .security = (.security // {})
                | .security.folderTrust = (.security.folderTrust // {})
                | .security.folderTrust.enabled = true
            ' \"\$1\" > \"\$2\" && mv \"\$2\" \"\$1\"" \
                    _ "$gemini_settings_file" "$tmp_gemini" 2>/dev/null; then
                log_detail "Gemini workspace trust configured"
            else
                run_as_target rm -f "$tmp_gemini" 2>/dev/null || true
            fi
        elif [[ ! -f "$gemini_settings_file" ]]; then
            run_as_target mkdir -p "$TARGET_HOME/.gemini" 2>/dev/null || true
            run_as_target tee "$gemini_settings_file" > /dev/null << 'GEMINI_TRUST_EOF'
{
  "security": {
    "folderTrust": {
      "enabled": true
    }
  }
}
GEMINI_TRUST_EOF
            log_detail "Gemini settings created with workspace trust"
        fi

        # Pre-populate Gemini trusted folders list so agents skip the
        # interactive "Trust this folder?" prompt entirely.
        # Gemini CLI 0.33.0+ expects trustedFolders.json as a JSON object
        # mapping folder paths to "TRUST_FOLDER", not a JSON array.
        local gemini_trusted_folders="$TARGET_HOME/.gemini/trustedFolders.json"
        if [[ ! -f "$gemini_trusted_folders" ]]; then
            local tmp_folders="${gemini_trusted_folders}.tmp.$$"
            if run_as_target bash -c '
                jq -n --arg home "$1" '"'"'{"/data/projects": "TRUST_FOLDER", ($home): "TRUST_FOLDER"}'"'"' > "$2" &&
                mv "$2" "$3"
            ' _ "$TARGET_HOME" "$tmp_folders" "$gemini_trusted_folders" 2>/dev/null; then
                log_detail "Gemini trusted folders pre-configured"
            else
                run_as_target rm -f "$tmp_folders" 2>/dev/null || true
                log_warn "Gemini trusted folders pre-configuration failed"
            fi
        elif command -v jq &>/dev/null; then
            # Merge paths into existing file, handling both legacy array format
            # and current object format (fixes #213).
            local tmp_folders="${gemini_trusted_folders}.tmp.$$"
            if run_as_target bash -c '
                content=$(cat "$1" 2>/dev/null) || content="{}"
                is_array=$(echo "$content" | jq -e "type == \"array\"" 2>/dev/null) || is_array="false"
                if [ "$is_array" = "true" ]; then
                    # Migrate legacy array format to object format
                    migrated=$(echo "$content" | jq "reduce .[] as \$p ({}; . + {(\$p): \"TRUST_FOLDER\"})")
                    content="$migrated"
                fi
                # Merge required paths into object
                updated=$(echo "$content" | jq \
                    --arg p1 "/data/projects" \
                    --arg p2 "$2" \
                    ". + {(\$p1): \"TRUST_FOLDER\", (\$p2): \"TRUST_FOLDER\"}")
                if [ "$updated" != "$content" ]; then
                    echo "$updated" > "$3" && mv "$3" "$1"
                fi
            ' _ "$gemini_trusted_folders" "$TARGET_HOME" "$tmp_folders" 2>/dev/null; then
                log_detail "Gemini trusted folders updated"
            else
                run_as_target rm -f "$tmp_folders" 2>/dev/null || true
            fi
        fi
    fi

    # Legacy state file (only if state.sh is unavailable)
    if type -t state_load &>/dev/null; then
        if [[ -f "$GTBI_STATE_FILE" ]]; then
            $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_STATE_FILE" || true
        fi
    else
        cat > "$GTBI_STATE_FILE" << EOF
{
  "version": "$GTBI_VERSION",
  "installed_at": "$(date -Iseconds)",
  "mode": "$MODE",
  "target_user": "$TARGET_USER",
  "target_home": "$TARGET_HOME",
  "bin_dir": "$GTBI_BIN_DIR",
  "yes_mode": $YES_MODE,
  "completed_phases": [1, 2, 3, 4, 5, 6, 7, 8]
}
EOF
        $SUDO chown "$TARGET_USER:$TARGET_USER" "$GTBI_STATE_FILE"
    fi

    # Configure Git/Dolt user identity (idempotent; non-fatal; never blocks).
    # Placed after Dolt is installed (stack phase). Skips cleanly with no TTY/--yes.
    try_step "Configuring Git/Dolt identity" configure_user_identity || true

    log_success "Installation complete!"
}
fi
