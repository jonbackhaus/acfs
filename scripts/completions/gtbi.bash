#!/bin/bash
# Bash completion for GTBI (Gastown Batteries Included)
# Install: source this file in ~/.bashrc or copy to /etc/bash_completion.d/
#
# Related: bead bd-zhdi

_gtbi_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="newproj new doctor check session sessions update status continue progress info i capacity cap policy-lint policy_lint credential-preflight credential_preflight secrets-preflight secrets_preflight offline-pack artifact-pack cheatsheet cs changelog changes log export-config export dashboard dash support-bundle bundle version help"

    # Subcommand-specific flags
    local newproj_flags="-i --interactive --no-br --no-claude --no-agents -h --help"
    local doctor_flags="--json --deep --no-cache --fix --dry-run -h --help"
    local status_flags="--json --short --check-updates -h --help"
    local info_flags="--json --html --minimal"
    local capacity_flags="--json --workload --profile --recommend-ntm -h --help"
    local policy_lint_flags="--json --human --root --file -h --help"
    local credential_preflight_flags="--json --human --home --gtbi-home --root --file --exclude --max-bytes -h --help"
    local offline_pack_flags="build --json --markdown --output --module --dry-run --best-effort --source-root --manifest-file --checksums-file --arch --ubuntu-version --timeout --expires-days -h --help"
    local cheatsheet_flags="--json"
    local changelog_flags="--all --since --json -h --help"
    local export_config_flags="--json --minimal --output -h --help"
    local session_subcommands="list export recent import convert show list-imported help"
    local session_list_flags="--json --days --agent --limit"
    local session_export_flags="--format --no-sanitize --output"
    local session_recent_flags="--workspace --format"
    local session_import_flags="--dry-run"
    local session_convert_flags="--from --to --workspace --session-id --dry-run --json --no-json"
    local session_show_flags="--format"
    local dashboard_subcommands="generate serve"
    local common_flags="-h --help"

    # Determine the subcommand
    local cmd=""
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            newproj|new|doctor|check|session|sessions|update|status|continue|progress|info|i|capacity|cap|policy-lint|policy_lint|credential-preflight|credential_preflight|secrets-preflight|secrets_preflight|offline-pack|artifact-pack|cheatsheet|cs|changelog|changes|log|export-config|export|dashboard|dash|support-bundle|bundle|version|help)
                cmd="${words[i]}"
                break
                ;;
        esac
    done

    case "$cmd" in
        newproj|new)
            mapfile -t COMPREPLY < <(compgen -W "$newproj_flags" -- "$cur")
            return
            ;;
        doctor|check)
            mapfile -t COMPREPLY < <(compgen -W "$doctor_flags" -- "$cur")
            return
            ;;
        status)
            mapfile -t COMPREPLY < <(compgen -W "$status_flags" -- "$cur")
            return
            ;;
        info|i)
            mapfile -t COMPREPLY < <(compgen -W "$info_flags" -- "$cur")
            return
            ;;
        capacity|cap)
            mapfile -t COMPREPLY < <(compgen -W "$capacity_flags" -- "$cur")
            return
            ;;
        policy-lint|policy_lint)
            mapfile -t COMPREPLY < <(compgen -W "$policy_lint_flags" -- "$cur")
            return
            ;;
        credential-preflight|credential_preflight|secrets-preflight|secrets_preflight)
            mapfile -t COMPREPLY < <(compgen -W "$credential_preflight_flags" -- "$cur")
            return
            ;;
        offline-pack|artifact-pack)
            mapfile -t COMPREPLY < <(compgen -W "$offline_pack_flags" -- "$cur")
            return
            ;;
        cheatsheet|cs)
            mapfile -t COMPREPLY < <(compgen -W "$cheatsheet_flags" -- "$cur")
            return
            ;;
        changelog|changes|log)
            mapfile -t COMPREPLY < <(compgen -W "$changelog_flags" -- "$cur")
            return
            ;;
        export-config|export)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "$export_config_flags" -- "$cur")
            else
                _filedir
            fi
            return
            ;;
        session|sessions)
            # Check if we have a session subcommand
            local session_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    list|export|recent|import|convert|show|list-imported|help)
                        session_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$session_cmd" in
                list)
                    mapfile -t COMPREPLY < <(compgen -W "$session_list_flags" -- "$cur")
                    ;;
                export)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_export_flags" -- "$cur")
                    else
                        _filedir
                    fi
                    ;;
                recent)
                    mapfile -t COMPREPLY < <(compgen -W "$session_recent_flags" -- "$cur")
                    ;;
                import)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_import_flags" -- "$cur")
                    else
                        _filedir '@(json)'
                    fi
                    ;;
                convert)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_convert_flags" -- "$cur")
                    else
                        _filedir
                    fi
                    ;;
                show)
                    mapfile -t COMPREPLY < <(compgen -W "$session_show_flags" -- "$cur")
                    ;;
                help)
                    COMPREPLY=()
                    ;;
                list-imported)
                    COMPREPLY=()
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$session_subcommands" -- "$cur")
                    ;;
            esac
            return
            ;;
        dashboard|dash)
            # Check if we have a dashboard subcommand
            local dash_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    generate|serve)
                        dash_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            if [[ -z "$dash_cmd" ]]; then
                mapfile -t COMPREPLY < <(compgen -W "$dashboard_subcommands" -- "$cur")
            fi
            return
            ;;
        update|continue|progress|support-bundle|bundle|version|help)
            mapfile -t COMPREPLY < <(compgen -W "$common_flags" -- "$cur")
            return
            ;;
    esac

    # No subcommand yet, complete commands
    mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
}

complete -F _gtbi_completions gtbi
