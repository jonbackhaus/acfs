# GTBI — Gastown Batteries Included

```
   ██████╗ ████████╗██████╗ ██╗
  ██╔════╝    ██║   ██╔══██╗██║
  ██║  ███╗   ██║   ██████╔╝██║
  ██║   ██║   ██║   ██╔══██╗██║
  ╚██████╔╝   ██║   ██████╔╝██║
   ╚═════╝    ╚═╝   ╚═════╝ ╚═╝
  Gastown Batteries Included
```

![Version](https://img.shields.io/badge/Version-0.2.0-bd93f9?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2025.10-6272a4?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT%2BOpenAI%2FAnthropic%20Rider-blue?style=for-the-badge)
![Shell](https://img.shields.io/badge/Shell-Bash-ff79c6?style=for-the-badge)

> **From zero to fully-configured agentic coding VPS in 30 minutes.**
> A complete bootstrapping system that transforms a fresh Ubuntu VPS into a professional AI-powered development environment.

> **Fork notice:** GTBI is forked from [ACFS (Agentic Coding Flywheel Setup)](https://github.com/Dicklesworthstone/gastown_batteries_included) by Jeffrey Emanuel ([@Dicklesworthstone](https://github.com/Dicklesworthstone)). This fork adapts ACFS for the Gastown toolchain with customized workflows and configurations.

<div align="center" style="margin: 1.2em 0;">
  <table>
    <tr>
      <td align="center" style="padding: 8px;">
        <strong>The Vision</strong><br/>
        <sub>Beginner with laptop → SSH → VPS → Agents coding for you</sub>
      </td>
    </tr>
  </table>
</div>

### Quick Install

```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
```

The installer is **idempotent**—if interrupted, simply re-run it. It will automatically resume from the last completed phase without prompts.

> **Production environments:** For stable, reproducible installs, pin to a tagged release or specific commit:
> ```bash
> # Preferred: use a tagged release (e.g., v0.5.0)
> curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/v0.5.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.5.0
>
> # Alternative: pin to a specific commit SHA
> curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/abc1234/install.sh" | bash -s -- --yes --mode vibe --ref abc1234
> ```
> Tagged releases are tested and stable. Passing `--ref` ensures all fetched scripts use the same version.

---

## TL;DR

**GTBI** is a complete system for bootstrapping agentic coding environments:

**Why you'd care:**
- **Zero to Hero:** Takes complete beginners from "I have a laptop" to "I have Claude/Codex/Gemini agents writing code for me on a VPS"
- **One-Liner Magic:** A single `curl | bash` command installs the toolchain, configures everything, and sets up the AI coding agents
- **Vibe Mode:** Pre-configured for maximum velocity—passwordless sudo, dangerous agent flags enabled, optimized shell environment
- **Agent Stack:** Local-first, Dolt-backed issue tracking and orchestration (beads + Gastown) for multi-agent workflows

**What you get:**
- Modern shell (zsh + oh-my-zsh + powerlevel10k)
- Language runtimes (bun, uv/Python, Rust, Go, Node via nvm)
- AI coding agents (Claude Code, Codex CLI, Gemini CLI; OpenCode optional)
- Agent stack (Dolt + beads + Gastown)
- A curated set of modern CLI/dev tools

---

## The GTBI Experience

```mermaid
graph LR
    %%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#e8f5e9', 'lineColor': '#90a4ae'}}}%%

    subgraph user ["User's Machine"]
        TERMINAL["Terminal / SSH client"]
    end

    subgraph vps ["Fresh VPS"]
        UBUNTU["Ubuntu 25.10"]
        INSTALLER["install.sh"]
        CONFIGURED["Configured VPS"]
    end

    subgraph agents ["AI Agents"]
        CLAUDE["Claude Code"]
        CODEX["Codex CLI"]
        GEMINI["Gemini CLI"]
    end

    TERMINAL -->|SSH + curl| UBUNTU
    UBUNTU --> INSTALLER
    INSTALLER --> CONFIGURED
    CONFIGURED --> CLAUDE
    CONFIGURED --> CODEX
    CONFIGURED --> GEMINI

    classDef user fill:#e3f2fd,stroke:#90caf9,stroke-width:2px
    classDef vps fill:#f3e5f5,stroke:#ce93d8,stroke-width:2px
    classDef agent fill:#e8f5e9,stroke:#a5d6a7,stroke-width:2px

    class TERMINAL user
    class UBUNTU,INSTALLER,CONFIGURED vps
    class CLAUDE,CODEX,GEMINI agent
```

### For Beginners
GTBI provides step-by-step guidance for complete beginners to:
1. Install a terminal on their local machine
2. Generate SSH keys (for secure access later)
3. Rent a VPS from providers like OVH or Contabo
4. Connect via SSH with a password (initial setup)
5. Run the installer (which sets up key-based access)
6. Reconnect securely with your SSH key
7. Start coding with AI agents

See the [VPS Providers](#vps-providers) section and `scripts/providers/` for per-provider setup guides.

### For Developers
GTBI is a **one-liner** that transforms any fresh Ubuntu VPS into a fully-configured development environment with modern tooling and three AI coding agents ready to go.

### For Teams
GTBI provides a **reproducible, idempotent** setup that ensures every team member's VPS environment is identical—eliminating "works on my machine" for agentic workflows.

---

## Architecture & Design

GTBI is built around a **single source of truth**: the manifest file. Everything else—the installer scripts, doctor checks, website content—derives from this central definition. This architecture ensures consistency and makes the system easy to extend.

### One-Page System Data Flow

```mermaid
flowchart TB
  subgraph U["User (local machine)"]
    Terminal["Terminal / SSH client"]
  end

  %% Repo sources
  subgraph R["Repo (source)"]
    Manifest["gtbi.manifest.yaml<br/>Modules + install + verify + deps"]
    Generator["packages/manifest<br/>Parser (Zod) + generate.ts"]
    Generated["scripts/generated/* (reference)<br/>category installers + doctor_checks.sh"]
    Installer["install.sh (production one-liner)"]
    Lib["scripts/lib/*<br/>security / doctor / update / services-setup"]
    Configs["gtbi/*<br/>zshrc + tmux.conf + onboard lessons"]
    Checksums["checksums.yaml<br/>sha256 for upstream installers"]
    Tests["tests/vm/test_install_ubuntu.sh<br/>Docker integration test"]
  end

  %% Target VPS
  subgraph V["Target VPS (Ubuntu 25.10, auto-upgraded)"]
    Run["Run install.sh"]
    Verify["Verified upstream installers<br/>(security.sh + checksums.yaml)"]
    GtbiHome["~/.gtbi/<br/>configs + scripts + state.json"]
    Commands["Commands<br/>gtbi doctor / gtbi update / gtbi services-setup / onboard"]
    Tools["Installed tools<br/>bun/uv/rust/go/nvm + tmux/rg/gh + ..."]
    Agents["Agent CLIs<br/>claude / codex / gemini / opencode"]
    Stack["Agent stack<br/>dolt / bd (beads) / gt (Gastown)"]
  end

  %% How users fetch/run the installer
  Terminal -->|curl / bash| Installer
  Terminal -->|SSH| Run

  %% Manifest-driven generation (reference today)
  Manifest --> Generator --> Generated
  Generated -.->|planned: install.sh calls generated install_all.sh| Installer

  %% Installer composition
  Lib --> Installer
  Configs --> Installer
  Checksums --> Installer
  Tests -->|validates| Installer

  %% VPS install results
  Installer --> Run
  Run --> Verify
  Verify --> Tools
  Verify --> Agents
  Verify --> Stack
  Run --> GtbiHome --> Commands
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SOURCE OF TRUTH                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  gtbi.manifest.yaml                                                  │    │
│  │  Tool Definitions • Install Commands • Verification Logic           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────┐
│        CODE GENERATION            │
│  ┌─────────────────────────────┐  │
│  │ TypeScript Parser (Zod)     │  │
│  │ generate.ts                 │  │
│  └─────────────────────────────┘  │
└───────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                     GENERATED OUTPUTS (REFERENCE)                          │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐   │
│  │ scripts/generated/ │  │ doctor_checks.sh   │  │ install_all.sh     │   │
│  │ 11 Category Scripts│  │ Verification Logic │  │ Master Installer   │   │
│  └────────────────────┘  └────────────────────┘  └────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            INSTALLER                                       │
│  install.sh + scripts/lib/*.sh + checksums.yaml (SHA256 verification)     │
│  (scripts/generated/* are sourced; execution is feature-flagged)            │
└───────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           TARGET VPS                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ 30+ Tools    │  │ zsh + p10k   │  │ AI Agents    │  │ ~/.gtbi/     │   │
│  │ Installed    │  │ Shell Config │  │ Claude/Codex │  │ Configurations│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```

### Why This Architecture?

**Single Source of Truth**: The manifest file (`gtbi.manifest.yaml`) defines every tool—its name, description, install commands, and verification logic. When you add or edit a tool in the manifest, the generator automatically updates the generated scripts and manifest-derived checks. The production one-liner installer (`install.sh`) is still hand-written today, so behavior changes may also require updating `install.sh` until full migration.

**TypeScript + Zod Validation**: The manifest parser uses Zod schemas to validate the YAML at parse time. Typos, missing fields, and structural errors are caught immediately during generation—not at runtime on a user's VPS when the installer fails halfway through.

**Generated Scripts**: Rather than hand-maintaining 11 category installer scripts and keeping them synchronized, the generator produces them from the manifest. This means:
- A consistent, auditable view of manifest-defined install logic (some modules intentionally emit TODOs)
- Consistent error handling and logging across all modules
- A clear path toward future installer integration

### Components

| Component | Path | Technology | Purpose |
|-----------|------|------------|---------|
| **Manifest** | `gtbi.manifest.yaml` | YAML | Single source of truth for all tools |
| **Generator** | `packages/manifest/src/generate.ts` | TypeScript/Bun | Produces installer scripts from manifest |
| **Installer** | `install.sh` | Bash | One-liner bootstrap script |
| **Lib Scripts** | `scripts/lib/` | Bash | Modular installer functions |
| **Generated Scripts** | `scripts/generated/` | Bash | Auto-generated category installers (sourced by `install.sh`; execution is feature-flagged) |
| **Configs** | `gtbi/` | Shell/Tmux configs | Files deployed to `~/.gtbi/` |
| **Onboarding** | `gtbi/onboard/` | Bash + Markdown | Interactive tutorial system |
| **Checksums** | `checksums.yaml` | YAML | SHA256 hashes for upstream installers |

---

## The Manifest System

`gtbi.manifest.yaml` is the **single source of truth** for all tools installed by GTBI. It defines what gets installed, how to install it, and how to verify the installation worked.

### Manifest Structure

```yaml
version: "1.0"
meta:
  name: "GTBI"
  description: "Gastown Batteries Included"
  version: "0.1.0"

modules:
  base.system:
    description: "Base packages + sane defaults"
    category: base
    install:
      - sudo apt-get update -y
      - sudo apt-get install -y curl git ca-certificates unzip tar xz-utils jq build-essential
    verify:
      - curl --version
      - git --version
      - jq --version

  agents.claude:
    description: "Claude Code"
    category: agents
    install:
      - "Install claude code via official method"
    verify:
      - claude --version || claude --help
```

Each module specifies:
- **description**: Human-readable name
- **category**: Grouping for installer organization (base, shell, cli, lang, tools, db, cloud, agents, stack, gtbi)
- **install**: Commands to run (or descriptions that become TODOs)
- **verify**: Commands that must succeed to confirm installation

### The Generator Pipeline

The TypeScript generator (`packages/manifest/src/generate.ts`) reads the manifest and produces:

1. **Category Scripts** (`scripts/generated/install_base.sh`, `install_agents.sh`, etc.)
   - One script per category with individual install functions
   - Consistent logging and error handling
   - Verification checks after each module

2. **Doctor Checks** (`scripts/generated/doctor_checks.sh`)
   - All verify commands extracted into a runnable health check
   - Tab-delimited format (to safely handle `||` in shell commands)
   - Reports pass/fail/skip for each module

3. **Master Installer** (`scripts/generated/install_all.sh`)
   - Sources all category scripts
   - Runs them in dependency order
   - Single entry point for running the generated installers

> Note: The production one-liner installer (`install.sh`) defaults to the legacy implementations; generated installers are sourced and can be enabled per-category via feature flags during migration.

To regenerate after manifest changes:

```bash
cd packages/manifest
bun run generate        # Generate scripts
bun run generate:dry    # Preview without writing
```

### Why TypeScript for Code Generation?

Shell can parse YAML with `yq`, but TypeScript + Zod offers:
- **Type safety**: The parser knows the exact shape of a manifest
- **Validation**: Zod catches malformed YAML with descriptive errors
- **Transformation**: Complex logic (sorting by dependencies, escaping) is natural in TypeScript
- **Consistency**: All generated code follows the same patterns

The generator itself is ~400 lines of TypeScript. The generated output is ~1000 lines of Bash across 13 files. The trade-off is clearly in favor of maintaining the generator.

---

## Security Verification

GTBI downloads and executes installer scripts from the internet. This is inherently risky—a compromised upstream could inject malicious code. The security verification system mitigates this risk.

### How It Works

The `checksums.yaml` file contains SHA256 hashes for all upstream installer scripts:

```yaml
# checksums.yaml
installers:
  bun:
    url: "https://bun.sh/install"
    sha256: "a1b2c3d4..."

  rust:
    url: "https://sh.rustup.rs"
    sha256: "e5f6a7b8..."
```

The security library (`scripts/lib/security.sh`) provides:

1. **HTTPS Enforcement**: All installer URLs must use HTTPS. Non-HTTPS URLs fail immediately.

2. **Checksum Verification**: Before executing a downloaded script, the system:
   - Downloads the content to memory
   - Calculates the SHA256 hash
   - Compares against the stored hash
   - Only executes if they match

3. **Verification Modes**:
   ```bash
   ./scripts/lib/security.sh --print              # List all upstream URLs
   ./scripts/lib/security.sh --verify             # Verify all against saved checksums
   ./scripts/lib/security.sh --update-checksums   # Generate new checksums.yaml
   ./scripts/lib/security.sh --checksum URL       # Calculate SHA256 of any URL
   ```

### When Checksums Fail

A checksum mismatch can mean:
1. **Normal update**: The upstream maintainer released a new version
2. **Potential compromise**: Someone modified the script maliciously

The verification report distinguishes these cases:
- If multiple checksums fail simultaneously, investigate before updating
- If a single checksum fails after a known release, update is likely safe

To update after verifying a legitimate upstream change:
```bash
./scripts/lib/security.sh --update-checksums > checksums.yaml
git diff checksums.yaml  # Review what changed
git commit -m "chore: update upstream checksums"
```

### Why This Approach?

The `curl | bash` pattern is controversial but practical. GTBI makes it safer by:
- Verifying content before execution (not just transport via HTTPS)
- Making checksums auditable in version control
- Providing tools to detect and investigate changes
- Failing closed (no execution on mismatch)

This is defense in depth—HTTPS protects transport, checksums protect content.

---

## The Installer

The installer is the heart of GTBI—a modular Bash script that transforms a fresh Ubuntu VPS into a fully-configured development environment.

### Usage

Full vibe mode (recommended for throwaway VPS):

```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
```

Interactive mode (asks for confirmation):

```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh" | bash
```

Safe mode (no passwordless sudo, agent confirmations enabled):

```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh" | bash -s -- --mode safe
```

### Installer Modes

| Mode | Passwordless Sudo | Agent Flags | Best For |
|------|-------------------|-------------|----------|
| **vibe** | Yes | `--dangerously-skip-permissions` | Throwaway VPS, maximum velocity |
| **safe** | No | Standard confirmations | Production-like environments |

### Installation Phases

```mermaid
graph TD
    %%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#e8f5e9', 'lineColor': '#90a4ae'}}}%%

    A["Phase 1: System Base<br/><small>APT bootstrap, essential packages</small>"]
    B["Phase 2: User Normalization<br/><small>Create ubuntu user, migrate SSH keys</small>"]
    C["Phase 3: Filesystem<br/><small>Workspace dirs, permissions</small>"]
    D["Phase 4: Shell Setup<br/><small>zsh, oh-my-zsh, powerlevel10k</small>"]
    E["Phase 5: CLI &amp; Networking<br/><small>ripgrep, fzf, lazygit/lazydocker, tailscale</small>"]
    F["Phase 6: Languages &amp; Tools<br/><small>bun, uv, rust, go, nvm, atuin, zoxide, ast-grep</small>"]
    G["Phase 7: AI Agents<br/><small>claude, codex, gemini, opencode</small>"]
    H["Phase 9: Agent Stack<br/><small>dolt, bd (beads), gt (Gastown)</small>"]
    I["Phase 10: GTBI Lifecycle<br/><small>workspace, onboard, update, nightly, doctor</small>"]

    A --> B --> C --> D --> E --> F --> G --> H --> I

    classDef phase fill:#e8f5e9,stroke:#81c784,stroke-width:2px,color:#2e7d32
    class A,B,C,D,E,F,G,H,I phase
```

### Key Properties

| Property | Description |
|----------|-------------|
| **Idempotent** | Safe to re-run; skips already-installed tools |
| **Checkpointed** | Phases resume automatically from `~/.gtbi/state.json` |
| **Pre-flight validated** | Run `scripts/preflight.sh` to catch issues before install |
| **Logged** | Colored output with progress indicators |
| **Modular** | Each category is a separate sourceable script |

### Resume Capability

The installer tracks progress in `~/.gtbi/state.json`. If interrupted:
- Re-run the same command—it resumes from the last completed phase
- No prompts or confirmations needed (with `--yes`)
- Already-installed tools are detected and skipped

To force a fresh reinstall of all tools:
```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh" | bash -s -- --yes --mode vibe --force-reinstall
```

### Pre-Flight Check

Before running the full installer, validate your system:
```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/scripts/preflight.sh" | bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/scripts/preflight.sh" | bash -s -- --json
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/scripts/preflight.sh" | bash -s -- --format toon
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/scripts/preflight.sh" | bash -s -- --network=skip
```

This checks:
- OS compatibility (Ubuntu 22.04+; installer upgrades to 25.10)
- Architecture (x86_64 or ARM64)
- Memory and disk space (minimum 4GB RAM, 10GB free disk)
- Network connectivity to required URLs
- Cached `checksums.yaml` availability for verified upstream installers
- APT lock status
- Potential conflicts (nvm, pyenv, existing GTBI)

**Network checks performed:**
| Check | What it verifies | Fix if failing |
|-------|------------------|----------------|
| DNS resolution | Can resolve github.com, raw.githubusercontent.com | Check provider DNS settings; inspect `resolvectl status` or `/etc/resolv.conf` |
| GitHub HTTPS | Can reach github.com:443 | Check firewall, proxy, or VPN settings |
| Verified installer URLs | Critical upstream installer endpoints from `checksums.yaml` plus GTBI raw content | May need to retry; transient failures OK; checksum verification still stays enabled |
| APT mirrors | Default Ubuntu mirror reachable | Check `/etc/apt/sources.list` or try different mirror |
| Offline/cache mode | `--network=skip` skips live URL checks while still reporting local checksum availability | Re-run with `--network=check` when online before a release or difficult install |

For checksum-refresh review, compare a generated candidate without changing `checksums.yaml`:
```bash
candidate="/tmp/gtbi-checksums.$$.candidate.yaml"
./scripts/lib/security.sh --update-checksums > "$candidate"
./scripts/preflight.sh --checksum-candidate "$candidate"
```

**Common preflight failures:**

| Error | Cause | Solution |
|-------|-------|----------|
| "Cannot resolve github.com" | DNS misconfigured | Check provider DNS settings or reboot; do not overwrite managed resolver files |
| "Cannot reach github.com" | Firewall blocking HTTPS | Allow outbound port 443 |
| "timeout contacting github.com" | Network, proxy, or provider route is slow | Retry with `--network=check`; if it persists after install bootstrap, run `gtbi support-bundle` |
| "APT mirror slow or unreachable" | Regional mirror down | Edit `/etc/apt/sources.list` to use `archive.ubuntu.com` |
| "checksum candidate differs" | Upstream verified installer content changed | Review the diff; do not install from unverified fallback sources |
| "APT lock held" | Another apt process running | Wait for it to finish; reboot and resume if it remains stuck |
| "Insufficient disk space" | Less than 10GB free | Clean up with `sudo apt autoremove` or expand disk |

### Console Output

The installer uses semantic colors for progress visibility:

```bash
[1/8] Installing essential packages...     # Blue: progress steps
    Installing zsh, git, curl...           # Gray: details
⚠️  May take a few minutes                 # Yellow: warnings
✖ Failed to install package               # Red: errors
✔ Shell setup complete                    # Green: success
```

### Automatic Ubuntu Upgrade

GTBI automatically upgrades Ubuntu to version **25.10** before installation when running on older versions. This ensures compatibility with the latest packages and optimal performance.

**How it works:**
1. Detects your current Ubuntu version
2. Calculates the upgrade path (e.g., 24.04 → 25.04 → 25.10)
3. Performs sequential `do-release-upgrade` operations
4. Reboots after each upgrade (handled automatically)
5. Resumes via systemd service after reboot
6. Continues GTBI installation once at target version

**Expected timeline:**
- Each version hop takes 30-60 minutes
- Full chain from 24.04 → 25.10 takes 1.5-3 hours
- SSH sessions disconnect during reboots (reconnect to monitor)

**To skip automatic upgrade:**
```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh" | bash -s -- --yes --mode vibe --skip-ubuntu-upgrade
```

**To specify a different target version:**
```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh" | bash -s -- --yes --mode vibe --target-ubuntu=25.04
```

**Monitoring upgrade progress:**
```bash
# Check current status
/var/lib/gtbi/check_status.sh

# View upgrade logs
journalctl -u gtbi-upgrade-resume -f

# View detailed logs
tail -f /var/log/gtbi/upgrade_resume.log
```

**Important notes:**
- Create a VM snapshot before upgrading (recommended but not required)
- Upgrades cannot be undone without restoring from snapshot
- The system will reboot multiple times automatically
- EOL interim releases (like 24.10) may be skipped automatically if they are no longer offered by `do-release-upgrade`
- Reconnect via SSH after each reboot to monitor progress

---

## The Update Command

After installation, keeping tools current is handled by `gtbi-update`. It provides a unified interface for updating all installed components.

### Usage

```bash
gtbi-update                  # Update apt, runtimes, shell, agents, cloud CLIs, and stack tools
gtbi-update --agents-only    # Only update coding agents
gtbi-update --runtime-only   # Only update runtimes (bun, rust, uv, go)
gtbi-update --dry-run        # Preview changes without making them
gtbi-update --yes --quiet --no-self-update
                             # Automated mode that avoids changing the GTBI tree itself
gtbi-update --bootstrap-self-update
                             # Explicitly convert a non-git GTBI install into a git checkout
```

### What Gets Updated

| Category | Tools | Method |
|----------|-------|--------|
| **System** | apt packages | `apt update && apt upgrade` |
| **Shell** | OMZ, P10K, plugins | `git pull` on each repo |
| **Shell** | Atuin, Zoxide | Re-run upstream installers |
| **Runtime** | Bun | `bun upgrade` |
| **Runtime** | Rust | `rustup update stable` |
| **Runtime** | uv (Python) | `uv self update` |
| **Runtime** | Go | `apt upgrade` (if apt-managed) |
| **Agents** | Claude Code | `claude update --channel latest` |
| **Agents** | Codex, Gemini | `bun install -g @latest` |
| **Stack** | Dolt, beads, Gastown | Re-run verified installers |

### Options

**Category Selection:**
```bash
--apt-only       Only update system packages
--agents-only    Only update coding agents
--cloud-only     Only update cloud CLIs
--shell-only     Only update shell tools (OMZ, P10K, plugins, Atuin, Zoxide)
--runtime-only   Only update runtimes (bun, rust, uv, go)
--stack          Include the agent stack (dolt, beads, Gastown; enabled by default)
```

**Skip Categories:**
```bash
--no-apt         Skip apt updates
--no-agents      Skip agent updates
--no-cloud       Skip cloud CLI updates
--no-shell       Skip shell tool updates
--no-runtime     Skip runtime updates (bun, rust, uv, go)
```

**Behavior:**
```bash
--force            Install missing tools (not just update existing)
--dry-run          Preview changes without making them
--yes, -y          Non-interactive mode (skip prompts)
--quiet, -q        Minimal output (only errors and summary)
--verbose, -v      Show detailed command output
--abort-on-failure Stop on first failure (default: continue)
```

### Logs

Update logs are automatically saved to `~/.gtbi/logs/updates/` with timestamps:
```bash
# View most recent log
cat ~/.gtbi/logs/updates/$(ls -1t ~/.gtbi/logs/updates | head -1)

# Follow a running update
tail -f ~/.gtbi/logs/updates/$(ls -1t ~/.gtbi/logs/updates | head -1)
```

### Why Separate from the Installer?

The installer transforms a fresh VPS. The update command maintains an existing installation. Separating them allows:
- **Focused updates**: Update just agents without touching system packages
- **Dry-run previews**: See what would change before committing
- **Skip flags**: Temporarily exclude categories that are working fine
- **Stack control**: Stack updates are included by default; skip with `--no-stack`
- **Automated updates**: Run via cron with `--yes --quiet`

---

## GTBI CLI Commands

After installation, the `gtbi` command provides a unified interface for managing your environment. Each subcommand is designed to be fast, informative, and scriptable.

### Quick Reference

```bash
gtbi info                    # Lightning-fast system overview
gtbi cheatsheet              # Discover installed aliases
gtbi dashboard generate      # Generate HTML status page
gtbi doctor                  # Health checks
gtbi newproj                 # Create a new project (TUI or CLI)
gtbi update                  # Update all tools
gtbi services-setup          # Configure agent credentials
gtbi continue                # View upgrade progress after reboot
```

### `gtbi newproj` — New Project Wizard

Create a new project directory with GTBI defaults (git init, optional br/beads, Claude settings, AGENTS.md).
The interactive wizard is recommended for beginners.

Interactive wizard (recommended):
```bash
gtbi newproj --interactive
gtbi newproj -i
gtbi newproj -i myapp         # Prefill project name
```

The wizard guides you through:
- Project naming and location
- Tech stack detection/selection
- Feature selection (br/beads, Claude settings, AGENTS.md, UBS ignore)
- AGENTS.md customization preview

<details>
<summary><strong>TUI Wizard Screenshots</strong></summary>

**Welcome Screen:**
```
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║      █████╗  ██████╗ ███████╗ ███████╗                ║
    ║     ██╔══██╗██╔════╝ ██╔════╝ ██╔════╝                ║
    ║     ███████║██║      █████╗   ███████╗                ║
    ║     ██╔══██║██║      ██╔══╝   ╚════██║                ║
    ║     ██║  ██║╚██████╗ ██║      ███████║                ║
    ║     ╚═╝  ╚═╝ ╚═════╝ ╚═╝      ╚══════╝                ║
    ║                                                       ║
    ║          Gastown Batteries Included                   ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝

This wizard will help you set up a new project with:

  ✓ Project directory structure
  ✓ Git repository initialization
  ✓ AGENTS.md for AI coding assistants
  ✓ Beads issue tracking (optional)
  ✓ Claude Code settings (optional)
```

**Confirmation Screen:**
```
──────────────────── Review & Confirm ────────────────────
                                              Step 7 of 9

Please review your selections before creating the project.

Project Summary
──────────────────────────────────────────────────────────
  Name:       myapp
  Location:   /home/user/projects/myapp
  Tech:       Node.js, TypeScript

Features
──────────────────────────────────────────────────────────
  ✓ Beads tracking
  ✓ Claude Code settings
  ✓ AGENTS.md
  ✓ UBS ignore

Files to Create
──────────────────────────────────────────────────────────
myapp/
├── .git/
├── AGENTS.md
├── .beads/
│   └── beads.db
├── .claude/
│   └── settings.local.json
├── .ubsignore
├── README.md
└── .gitignore

Options:
  [Enter/c]   Create project
  [e]         Edit selections (go back)
  [q/Esc]     Cancel
```

</details>

CLI mode (automation):
```bash
gtbi newproj myapp
gtbi newproj myapp /custom/path
gtbi newproj myapp --no-br
```

Notes:
- The TUI uses gum when available (arrow keys, Space to toggle, Enter to confirm). Without gum, it falls back to numbered prompts.
- Minimum terminal size: 60x15.
- CLI mode skips existing AGENTS.md; the wizard overwrites it, so move it aside if you want to keep the old one.

### `gtbi info` — System Overview

Displays installation status in under 1 second by reading cached state (no verification).

```bash
gtbi info                # Terminal output (default)
gtbi info --json         # JSON output for scripting
gtbi info --html         # Self-contained HTML page
gtbi info --minimal      # Just essentials (IP, key commands)
```

Example output:
```
╔══════════════════════════════════════════════════════════════╗
║                    GTBI System Info                           ║
╠══════════════════════════════════════════════════════════════╣
║  Host: vps-12345.contabo.net                                  ║
║  IP: 192.168.1.100                                            ║
║  User: ubuntu                                                 ║
║  Uptime: 3 days, 4 hours                                      ║
║                                                               ║
║  Quick Commands:                                              ║
║    cc    → Claude Code (dangerous mode)                       ║
║    cod   → Codex CLI (dangerous mode)                         ║
║    gmi   → Gemini CLI (yolo mode)                             ║
║    bd    → beads issue tracker                                ║
║    gt    → Gastown orchestrator                               ║
╚══════════════════════════════════════════════════════════════╝
```

**Design Philosophy:**
- **Speed**: Must complete in <1 second
- **Read-only**: Never verifies or tests (that's doctor's job)
- **Offline**: No network calls required
- **Fallback**: Graceful degradation if data missing

### `gtbi cheatsheet` — Alias Discovery

Parses `~/.gtbi/zsh/gtbi.zshrc` to show all installed aliases and commands.

```bash
gtbi cheatsheet              # List all aliases
gtbi cheatsheet git          # Filter by category or search term
gtbi cheatsheet --category Agents
gtbi cheatsheet --search docker
gtbi cheatsheet --json       # JSON output for tooling
```

Example output:
```
╔═══════════════════════════════════════════════════════════════╗
║  GTBI Cheatsheet                                               ║
╠═══════════════════════════════════════════════════════════════╣
║  Agents                                                        ║
║    cc   → claude --dangerously-skip-permissions                ║
║    cod  → codex --dangerously-bypass-approvals-and-sandbox     ║
║    gmi  → gemini --yolo                                        ║
║                                                                ║
║  Git                                                           ║
║    gs   → git status                                           ║
║    gp   → git push                                             ║
║    gl   → git pull                                             ║
║    gco  → git checkout                                         ║
║                                                                ║
║  Modern CLI                                                    ║
║    ls   → lsd --inode --long --all                             ║
║    cat  → bat                                                  ║
║    grep → rg                                                   ║
║    lg   → lazygit                                              ║
╚═══════════════════════════════════════════════════════════════╝
```

### `gtbi dashboard` — HTML Status Page

Generates a self-contained HTML dashboard and optionally serves it.

```bash
gtbi dashboard generate              # Generate ~/.gtbi/dashboard/index.html
gtbi dashboard generate --force      # Force regeneration
gtbi dashboard serve                 # Serve on localhost:8080
gtbi dashboard serve --port 3000     # Custom port
gtbi dashboard serve --public        # Bind to 0.0.0.0
```

The dashboard provides:
- System health at a glance
- Tool versions and status
- Quick command reference
- Recent activity summary

### `gtbi services-setup` — Credential Configuration

Interactive wizard for configuring AI agent credentials and cloud service logins.

```bash
gtbi services-setup          # Run full setup wizard
```

Guides you through:
- **Claude Code**: API key configuration
- **Codex CLI**: ChatGPT account login
- **Gemini CLI**: Google account authentication
- **GitHub CLI**: `gh auth login`

### `gtbi continue` — Upgrade Progress

After an Ubuntu upgrade reboot, view installation progress:

```bash
gtbi continue                # Show current upgrade status
```

Displays:
- Original Ubuntu version
- Target version
- Current upgrade stage
- Next steps after completion

---

## Interactive Onboarding (TUI)

After installation, users can learn the GTBI workflow through an interactive terminal-based tutorial. The onboarding TUI discovers lesson markdown files dynamically from `gtbi/onboard/lessons`, so the curriculum can grow as new tools and workflows are added without changing the launcher.

### Running Onboarding

```bash
onboard                # Launch interactive menu
onboard status         # Show completion status
onboard --list         # Alias for status
onboard 3              # Jump to lesson 3
onboard reset          # Reset progress and start fresh
onboard --reset        # Alias for reset
```

### Lessons

Run `onboard --help` to see the currently discovered lesson list. The curriculum covers Linux and SSH basics, tmux, agent login, the flywheel workflow, keeping the system updated, the beads issue tracker, and other GTBI tools. Because lessons are discovered by filename, adding a new `NN_name.md` file automatically extends the tutorial.

### Progress Tracking

Progress is saved in `~/.gtbi/onboard_progress.json`:

```json
{
  "completed": [0, 1, 2],
  "current": 3,
  "started_at": "2024-12-20T10:30:00-05:00"
}
```

The TUI shows completion status for each lesson and suggests the next one to take. Users can jump to any lesson or re-take completed ones.

### Enhanced UX with Gum

If [Charmbracelet Gum](https://github.com/charmbracelet/gum) is installed, the onboarding system uses it for enhanced terminal UI—selection menus, styled prompts, and better formatting. Without Gum, it falls back to simple numbered menus that work everywhere.

---

## Tools Installed

GTBI installs a curated set of tools organized into categories:

### Shell & Terminal UX

| Tool | Command | Description |
|------|---------|-------------|
| **zsh** | `zsh` | Modern shell |
| **oh-my-zsh** | - | zsh plugin framework |
| **powerlevel10k** | - | Fast, customizable prompt |
| **lsd** | `ls` (aliased) | Modern ls with icons |
| **atuin** | `Ctrl+R` | Shell history with search |
| **fzf** | `fzf` | Fuzzy finder |
| **zoxide** | `z` | Smarter cd |
| **direnv** | - | Directory-specific env vars |

### Languages & Package Managers

| Tool | Command | Description |
|------|---------|-------------|
| **bun** | `bun` | Fast JS/TS runtime + package manager |
| **uv** | `uv` | Fast Python package manager |
| **Rust** | `cargo` | Rust toolchain |
| **Go** | `go` | Go toolchain |
| **nvm** | `nvm` | Node version manager (installs Node LTS) |

### Dev Tools

| Tool | Command | Description |
|------|---------|-------------|
| **tmux** | `tmux` | Terminal multiplexer |
| **ripgrep** | `rg` | Fast recursive grep |
| **fd** | `fd` (`fdfind`) | Fast, user-friendly find |
| **ast-grep** | `sg` | Structural code search |
| **lazygit** | `lg` (aliased) | Git TUI |
| **lazydocker** | `lzd` (aliased) | Docker TUI |
| **GitHub CLI** | `gh` | GitHub auth, issues, PRs |
| **Git LFS** | `git-lfs` | Large file support for Git |
| **bat** | `cat` (aliased) | Cat with syntax highlighting |
| **lsd / eza** | `ls` (aliased) | Modern ls with icons |
| **btop** | `btop` | Resource monitor |
| **dust** | `dust` | Intuitive disk usage |
| **neovim** | `nvim` | Modern vim |
| **jq** | `jq` | JSON processor |
| **sqlite3** | `sqlite3` | Embedded SQL database |
| **rsync** | `rsync` | Fast file sync/copy |
| **direnv** | - | Directory-specific env vars |
| **Docker** | `docker` | Containers + compose plugin |
| **lsof** | `lsof` | Debug open files/ports |
| **dnsutils** | `dig` | DNS debugging |
| **netcat** | `nc` | Network debugging |
| **strace** | `strace` | Syscall tracing |

### Networking

| Tool | Command | Description |
|------|---------|-------------|
| **Tailscale** | `tailscale` | Zero-config mesh VPN |
| **SSH keepalive** | - | Server-side `ClientAliveInterval` so long agent sessions don't drop |

**Tailscale Integration:**

Tailscale provides secure, encrypted networking between your devices without complex firewall configuration:

```bash
# Authenticate and join your tailnet
tailscale up

# Check connection status
tailscale status

# Get your Tailscale IP
tailscale ip

# SSH over Tailscale (bypasses firewalls)
ssh ubuntu@your-vps.tailnet-name.ts.net
```

Benefits for agentic workflows:
- **Firewall-free access**: Connect even when behind NAT or restrictive firewalls
- **MagicDNS**: Access your VPS by hostname instead of IP
- **SSH keys over Tailscale**: Use `tailscale ssh` for key-free authentication
- **ACLs**: Fine-grained access control for team environments

### AI Coding Agents

| Agent | Command | Alias (Vibe Mode) |
|-------|---------|-------------------|
| **Claude Code** | `claude` | `cc` (dangerous mode) |
| **Codex CLI** | `codex` | `cod` (dangerous mode) |
| **Gemini CLI** | `gemini` | `gmi` (dangerous mode) |
| **OpenCode** (optional) | `opencode` | - |

**Vibe Mode Aliases:**
```bash
# Claude Code with max memory (background tasks enabled by default)
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'

# Codex with bypass and dangerous filesystem access
alias cod='codex --dangerously-bypass-approvals-and-sandbox'

# Gemini with yolo mode
alias gmi='gemini --yolo'
```

**Installation & Updates:**
Claude Code should be installed and updated using its native mechanisms:
- **Install:** GTBI uses the official native installer (`claude.ai/install.sh`), checksum-verified via `checksums.yaml` (installs to `~/.local/bin/claude`)
- **Update:** Use `claude update --channel latest` (built-in) or run `gtbi update --agents-only`

This ensures proper authentication handling and avoids issues with alternative package manager builds. For Codex and Gemini, GTBI uses standard bun global package updates.

### Agent Stack

Local-first issue tracking and multi-agent orchestration, all built on a version-controlled database:

| Tool | Command | Description |
|------|---------|-------------|
| **Dolt** | `dolt` | Version-control database (backs beads) |
| **beads** | `bd` | Dolt-backed local-first issue tracker for AI agents |
| **Gastown** | `gt` | Go multi-agent orchestrator |

---

## Doctor Command

`gtbi doctor` performs comprehensive health checks on your installation:

```bash
$ gtbi doctor

╔══════════════════════════════════════════════════════════════╗
║                    GTBI Health Check                          ║
╠══════════════════════════════════════════════════════════════╣
║ Identity                                                      ║
║   ✔ Running as ubuntu user                                    ║
║   ✔ Passwordless sudo enabled                                 ║
║                                                               ║
║ Workspace                                                     ║
║   ✔ /data/projects exists                                     ║
║                                                               ║
║ Shell                                                         ║
║   ✔ zsh installed                                             ║
║   ✔ oh-my-zsh installed                                       ║
║   ✔ powerlevel10k installed                                   ║
║   ✔ gtbi.zshrc sourced                                        ║
║                                                               ║
║ Core Tools                                                    ║
║   ✔ bun 1.2.16                                                ║
║   ✔ uv 0.5.14                                                 ║
║   ✔ cargo 1.84.0                                              ║
║   ✔ go 1.23.4                                                 ║
║   ✔ ripgrep 14.1.0                                            ║
║   ✔ ast-grep 0.30.1                                           ║
║                                                               ║
║ Agents                                                        ║
║   ✔ claude 1.0.24                                             ║
║   ✔ codex 0.1.2504252326                                      ║
║   ✔ gemini 0.1.12                                             ║
║                                                               ║
║ Agent Stack                                                   ║
║   ✔ dolt 1.43.0                                               ║
║   ✔ bd (beads) 0.6.0                                          ║
║   ✔ gt (Gastown) 0.4.0                                        ║
╠══════════════════════════════════════════════════════════════╣
║ Overall: 18/18 checks passed                                  ║
╚══════════════════════════════════════════════════════════════╝
```

### Generated Doctor Checks

Doctor checks are generated from the manifest (`scripts/generated/doctor_checks.sh`) to keep verification logic close to `gtbi.manifest.yaml`. The `gtbi doctor` command automatically sources these generated checks to verify all manifest-defined tools.

**How it works:**
1. The manifest generator creates `doctor_checks.sh` with verify commands for each module
2. `gtbi doctor` sources this file and runs each verification check
3. Failed checks display a **fix suggestion** with the exact command to reinstall

**Example output with fix suggestion:**
```
  ✗ tools.lazygit - Lazygit terminal UI not found
    Fix: gtbi install --only tools.lazygit
```

This architecture ensures doctor checks stay in sync with the installer—if a tool is in the manifest, it will be verified.

### Options

```bash
gtbi doctor              # Interactive colorful output
gtbi doctor --json       # Machine-readable JSON output
gtbi doctor --quiet      # Exit code only (0=healthy, 1=issues)
gtbi doctor --deep       # Run functional tests (auth, connections)
gtbi doctor --fix        # Apply safe fixes for failed checks
gtbi doctor --dry-run    # Preview fixes without applying
gtbi doctor --no-cache   # Skip cache, run all checks fresh
```

### Deep Checks (`--deep`)

The `--deep` flag runs functional tests beyond binary existence:

| Category | Checks |
|----------|--------|
| **Agent Auth** | Claude config, Codex OAuth, Gemini credentials |
| **Database** | PostgreSQL connection, ubuntu role exists |
| **Cloud CLIs** | `gh auth status`, `wrangler whoami`, Supabase/Vercel tokens |
| **Vault** | `VAULT_ADDR` configured |

Deep checks use 5-second timeouts to avoid hanging on network issues. Results are cached for 5 minutes to speed up repeated runs.

Example output:
```
Deep Checks
  ✔ Claude auth configured
  ✔ PostgreSQL connection working
  ⚠ Codex not authenticated (run: codex login)
  ✔ GitHub CLI authenticated

8/9 functional tests passed in 3.2s
```

### Auto-Fix Mode (`--fix`)

The `--fix` flag automatically applies safe, deterministic fixes for common issues:

```bash
gtbi doctor --fix             # Apply safe fixes
gtbi doctor --fix --dry-run   # Preview fixes without applying
```

#### Safe Auto-Fixers

These fixes are applied automatically when `--fix` is used:

| Fix ID | Description | Undo Strategy |
|--------|-------------|---------------|
| `fix.path.ordering` | Prepend GTBI directories to PATH in .zshrc | Restore backup |
| `fix.config.copy` | Copy missing ~/.gtbi config files | Remove copied file |
| `fix.symlink.create` | Create missing tool symlinks | Remove symlink |
| `fix.plugin.clone` | Clone missing zsh plugins | Remove cloned directory |
| `fix.gtbi.sourcing` | Add GTBI sourcing to .zshrc | Restore backup |
| `fix.stack.<tool>` | Reinstall a missing stack tool via verified installer | Remove installed binary |
| `fix.ssh.keepalive` | Configure SSH `ClientAliveInterval` keepalive | Restore backup |

#### Safety Guarantees

- **Never deletes user files** — Only creates, modifies, or symlinks
- **Backups before modify** — SHA256-verified backups of all modified files
- **Idempotent** — Safe to run multiple times
- **Logged** — All changes recorded to `~/.local/share/gtbi/doctor.log`
- **Reversible** — Every fix has an undo command

#### Example Dry-Run Output

```
DRY-RUN: gtbi doctor --fix

Would apply the following fixes:

  [fix.path.ordering]
    Action: Prepend PATH directories to ~/.zshrc
    File: ~/.zshrc
    Backup: Yes (SHA256 verified)

  [fix.gtbi.sourcing]
    Action: Add GTBI sourcing to .zshrc
    File: ~/.zshrc
    Backup: Yes (SHA256 verified)

Fixes that require manual action:
  [shell.ohmyzsh]
    Status: FAIL
    Suggestion: curl -fsSL https://install.ohmyz.sh/ | bash

Summary: 2 auto-fixes, 0 prompted, 1 manual
```

#### Manual-Only Fixes

Some operations are never auto-fixed and instead provide suggestions:

- Package manager operations (`apt install ...`)
- Anything requiring sudo
- File deletions
- Complex shell configuration changes

#### Undoing Changes

All changes made by `--fix` can be undone:

```bash
gtbi undo --list      # List all changes
gtbi undo chg_0001    # Undo specific change
gtbi undo --all       # Undo all changes from last session
```

---

## Configuration Files

GTBI deploys optimized configuration files to `~/.gtbi/` on the target VPS.

### `~/.gtbi/zsh/gtbi.zshrc`

A comprehensive zsh configuration that's sourced by `~/.zshrc`:

**Oh-My-Zsh Plugins (14 total):**

| Plugin | Category | What It Provides |
|--------|----------|------------------|
| `git` | VCS | 150+ git aliases (gs, gp, gl, gco, gcm, etc.) |
| `sudo` | Shell | Double-tap Esc to prefix previous command with sudo |
| `colored-man-pages` | Shell | Colorized man pages for better readability |
| `command-not-found` | Shell | Suggests packages when command not found |
| `docker` | Containers | Docker command completion and aliases |
| `docker-compose` | Containers | docker-compose completion and aliases |
| `python` | Lang | Python aliases (pyfind, pyclean, pygrep) |
| `pip` | Lang | pip completion and cache management |
| `tmux` | Terminal | tmux aliases (ta, tad, ts, tl, tkss) |
| `tmuxinator` | Terminal | tmuxinator project completion |
| `systemd` | System | systemctl aliases (sc-status, sc-start, sc-stop) |
| `rsync` | Tools | rsync completion and common flag aliases |
| `zsh-autosuggestions` | UX | Fish-like autosuggestions from history |
| `zsh-syntax-highlighting` | UX | Real-time command syntax highlighting |

> **Note**: `zsh-autosuggestions` and `zsh-syntax-highlighting` are custom plugins installed from GitHub. They must be listed last for optimal performance.

**Path Configuration:**
```bash
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.atuin/bin:$PATH"
```

**Modern CLI Aliases:**
```bash
alias ls='lsd --inode --long --all'
alias ll='lsd -l'
alias tree='lsd --tree'
alias cat='bat'
alias grep='rg'
alias vim='nvim'
alias lg='lazygit'
```

**Tool Integrations:**
```bash
# Atuin (better shell history)
eval "$(atuin init zsh)"

# Zoxide (smarter cd)
eval "$(zoxide init zsh)"

# direnv (directory env vars)
eval "$(direnv hook zsh)"

# fzf (fuzzy finder)
source /usr/share/doc/fzf/examples/key-bindings.zsh
```

**Shell Keybindings (Quality of Life):**

| Keybind | Action | Notes |
|---------|--------|-------|
| `Ctrl+→` | Forward word | Navigate by word |
| `Ctrl+←` | Backward word | Navigate by word |
| `Alt+→` | Forward word | Alternative binding |
| `Alt+←` | Backward word | Alternative binding |
| `Ctrl+Backspace` | Delete word backward | Fast deletion |
| `Ctrl+Delete` | Delete word forward | Fast deletion |
| `Home` | Beginning of line | Works in all terminals |
| `End` | End of line | Works in all terminals |
| `Ctrl+R` | Atuin history search | Interactive fuzzy search |

**Atuin History Bindings:**
The config forces Atuin bindings to load last (after OMZ plugins) ensuring `Ctrl+R` triggers Atuin's fuzzy history search rather than zsh's default:

```bash
# Forced at end of zshrc
bindkey -e  # Emacs mode
bindkey -M emacs '^R' atuin-search
bindkey -M viins '^R' atuin-search-viins
bindkey -M vicmd '^R' atuin-search-vicmd
```

### `~/.gtbi/tmux/tmux.conf`

A tmux configuration specifically optimized for NTM and multi-agent workflows:

**Key Bindings:**
```
Prefix: Ctrl+a (not Ctrl+b - more ergonomic)
Split horizontal: |  (preserves working directory)
Split vertical: -    (preserves working directory)
Navigate panes: h/j/k/l (vim-style)
Resize panes: H/J/K/L (repeatable with -r flag)
Reload config: r
New window: c (preserves working directory)
```

**Copy Mode (vim-style):**
```
Enter copy mode: prefix + [
Begin selection: v
Rectangle selection: r
Copy and exit: y
```

**Agent Workflow Optimizations:**

| Setting | Value | Purpose |
|---------|-------|---------|
| `history-limit` | 50,000 | Extended scrollback for long agent sessions |
| `escape-time` | 10ms | Faster key response (reduced from default 500ms) |
| `focus-events` | on | Enables vim/neovim autoread in agent windows |
| `detach-on-destroy` | off | NTM compatibility—don't detach when session ends |
| `monitor-activity` | on | Track agent window activity |
| `visual-activity` | off | Silent monitoring (no bell) |

**Catppuccin-Inspired Theme:**
```bash
# Status bar (top position, less intrusive)
status-style: bg=#1e1e2e, fg=#cdd6f4

# Session indicator (blue accent)
status-left: #[fg=#89b4fa,bold] #S

# Active window highlight (pink accent)
window-status-current-format: #[fg=#f5c2e7,bold] #I:#W

# Pane borders
pane-border-style: fg=#313244
pane-active-border-style: fg=#89b4fa  # Blue highlight
```

**Local Overrides:**
The config sources `~/.tmux.conf.local` if it exists, allowing personal customizations without modifying GTBI defaults.

---

## Library Modules

The installer is organized into modular Bash libraries in `scripts/lib/`:

### `logging.sh`

Colored console output utilities:

```bash
log_step "1/8" "Installing packages..."  # Blue step indicator
log_detail "Installing zsh..."           # Gray indented detail
log_success "Complete"                    # Green checkmark
log_warn "May take a while"              # Yellow warning
log_error "Failed"                        # Red error
log_fatal "Cannot continue"              # Red error + exit 1
```

### `security.sh`

HTTPS enforcement and checksum verification:

```bash
enforce_https "$url"                     # Fail if not HTTPS
verify_checksum "$url" "$sha256" "$name" # Verify before execute
fetch_and_run "$url" "$sha256" "$name"   # Verify + execute in one
```

### `os_detect.sh`

OS detection and validation:

```bash
detect_os()      # Sets OS_ID, OS_VERSION, OS_CODENAME
validate_os()    # Checks for Ubuntu 25.10 (or upgrade path)
is_fresh_vps()   # Heuristic detection of fresh VPS
get_arch()       # Returns amd64/arm64
is_wsl()         # Detects WSL
is_docker()      # Detects Docker container
```

### `user.sh`

User account normalization:

```bash
ensure_user()              # Creates ubuntu user if missing
enable_passwordless_sudo() # Adds NOPASSWD to sudoers
migrate_ssh_keys()         # Copies keys from root to ubuntu
normalize_user()           # Full normalization sequence
```

### `update.sh`

Component update logic with version tracking and logging:

```bash
update_apt()       # apt update/upgrade with lock detection
update_bun()       # bun upgrade with version tracking
update_agents()    # Claude, Codex, Gemini (version before/after)
update_cloud()     # Wrangler, Supabase, Vercel (Supabase uses verified release tarball)
update_rust()      # rustup update stable
update_uv()        # uv self update
update_go()        # Go toolchain update
update_shell()     # OMZ, P10K, plugins, Atuin, Zoxide
update_stack()     # Dicklesworthstone stack tools

# Features:
# - Automatic logging to ~/.gtbi/logs/updates/
# - Version tracking (before/after for each tool)
# - APT lock detection and warning
# - Reboot-required detection for kernel updates
# - Dry-run mode with --dry-run flag
```

### `gum_ui.sh`

Enhanced terminal UI using Charmbracelet Gum:

```bash
print_banner()           # ASCII art GTBI banner
gum_step/gum_detail      # Styled output
gum_success/warn/error   # Colored messages
gum_spin                 # Spinner for long operations
gum_confirm              # Yes/No prompt
gum_choose               # Selection menu
```

Falls back to basic echo if Gum is not installed.

### `error_tracking.sh`

Sophisticated error collection and reporting:

```bash
track_error "phase" "step" "error_message"
track_warning "phase" "step" "warning_message"
get_error_report                    # Generate structured error report
get_error_count                     # Count of tracked errors
has_errors                          # Boolean check for any errors
```

Features:
- Collects errors without aborting execution
- Associates errors with phase and step context
- Generates end-of-run summary reports
- Distinguishes warnings from errors

### `state.sh`

State machine management for installation progress (v3 schema):

```bash
state_init                          # Initialize state file
state_get_phase                     # Current phase
state_set_phase "phase_name"        # Set current phase
state_mark_complete "phase_name"    # Mark phase complete
state_has_completed "phase_name"    # Check if phase done
state_save                          # Persist to disk (atomic)
state_load                          # Load from disk
```

The state file (`~/.gtbi/state.json`) uses atomic writes to prevent corruption.

### `contract.sh`

Runtime contract validation for generated scripts:

```bash
gtbi_require_contract "module_id"   # Assert environment is ready
gtbi_check_contract                 # Non-fatal contract check
```

Validates that required environment variables and functions exist before execution:
- `TARGET_USER`, `TARGET_HOME`, `MODE`
- `GTBI_BOOTSTRAP_DIR`, `GTBI_LIB_DIR`
- Logging functions: `log_detail`, `log_success`, etc.

### `smoke_test.sh`

Post-install verification that runs automatically after installation:

```bash
run_smoke_test                      # Execute all smoke tests
```

**Critical Checks** (must pass):
- Running as ubuntu user
- Passwordless sudo enabled
- Zsh is default shell
- Core tools accessible (bun, uv, cargo)

**Non-Critical Checks** (warnings only):
- Agent authentication configured
- Cloud CLIs authenticated
- Optional tools installed

Example output:
```
[Smoke Test]
  ✅ Running as ubuntu user
  ✅ Passwordless sudo enabled
  ✅ Zsh is default shell
  ✅ bun --version works
  ⚠️  Codex not authenticated (run: codex login)
  ✅ 8/9 checks passed
```

### `session.sh`

Agent session export functionality for sharing and replay:

```bash
session_export "claude-code" "session_id" "/output/path"
session_list                        # List exportable sessions
session_validate "/export/file.json"
```

Implements the **Session Export Schema** for cross-agent sharing:

```typescript
interface SessionExport {
  schema_version: 1;
  exported_at: string;              // ISO8601
  session_id: string;
  agent: "claude-code" | "codex" | "gemini";
  model: string;
  summary: string;
  duration_minutes: number;
  stats: {
    turns: number;
    files_created: number;
    files_modified: number;
    commands_run: number;
  };
  outcomes: Array<{
    type: "file_created" | "file_modified" | "command_run";
    path?: string;
    description: string;
  }>;
  key_prompts: string[];            // Notable prompts for learning
  sanitized_transcript: Array<{
    role: "user" | "assistant";
    content: string;
    timestamp: string;
  }>;
}
```

### `tailscale.sh`

Zero-config VPN setup for secure remote access:

```bash
install_tailscale                   # Install via official APT repo
verify_tailscale                    # Check installation
tailscale_status                    # Get connection status
```

Tailscale provides:
- **Secure mesh networking** between your devices
- **SSH over Tailscale** for firewall-free access
- **MagicDNS** for hostname-based addressing
- **ACL-based access control**

After installation, run `tailscale up` to authenticate and join your tailnet.

### `ubuntu_upgrade.sh`

Multi-reboot Ubuntu version upgrade automation:

```bash
start_ubuntu_upgrade                # Begin upgrade chain
check_upgrade_status                # Current upgrade state
resume_upgrade_after_reboot         # Continue after reboot
```

Handles the complex multi-step Ubuntu upgrade process:
1. Detects current version
2. Calculates upgrade path (e.g., 24.04 → 25.04 → 25.10)
3. Performs sequential `do-release-upgrade` operations
4. Installs systemd service for post-reboot resume
5. Continues GTBI installation after reaching target

---

## CI/CD

GTBI uses GitHub Actions for continuous integration:

### Installer Testing (`installer.yml`)

```yaml
# Runs on every push and PR
jobs:
  shellcheck:
    - Lints all bash scripts with ShellCheck

  integration:
    - Matrix tests across Ubuntu 24.04, 25.04, 25.10
    - Runs full installation in Docker
    - Verifies all tools installed correctly
    - Runs gtbi doctor to confirm health

  factory-e2e:
    - Runs the literal public curl|bash installer on QEMU/KVM or a fresh real Ubuntu host
    - Requires systemd, SSH, and a disposable factory VM/VPS semantics
    - Verifies ubuntu user creation, SSH key merge, user services, tool health, and idempotency
```

Docker catches shell and package regressions early. The factory E2E is the authoritative release gate for the real beginner VPS path because it exercises systemd, SSH, login/user-service behavior, and provider image defaults that containers cannot model. A Docker pass is not sufficient release proof by itself.

### Local Release Doctor (`scripts/release-doctor.sh`)

Run the local release gate before tagging or publishing a release candidate:

```bash
bash scripts/release-doctor.sh --full --network=check
bash scripts/release-doctor.sh --json --full --network=check > release-doctor.json
```

For a fast local readiness check while developing:

```bash
bash scripts/release-doctor.sh --json
```

The release doctor composes the maintainer checks that are easy to forget:
- branch policy and clean worktree status
- `shellcheck install.sh scripts/**/*.sh`
- manifest/generated/checksum drift via `scripts/check-manifest-drift.sh --json --quiet`
- verified-installer checksum candidate review with `--network=check`
The checksum candidate check uses the canonical updater output. If the generated body differs from `checksums.yaml`, review the diff before release; if only the timestamp header differs, leave `checksums.yaml` unchanged. The default `--network=skip` keeps routine runs offline.

### Stack Provenance Report (`scripts/stack-provenance-report.sh`)

Use the stack provenance report when reviewing Dicklesworthstone stack tool freshness before release:

```bash
bash scripts/stack-provenance-report.sh --json
bash scripts/stack-provenance-report.sh --network=check --json
```

Offline mode reports local manifest/checksum consistency for stack tools. Network mode also checks GitHub latest release metadata and generates a checksum candidate without writing `checksums.yaml`. Changed stack installer hashes fail the report, unrelated checksum diffs are called out separately, and `rch` release changes are flagged as mandatory checksum-refresh review items.

### Agent Readiness Audit (`scripts/agent-readiness-audit.sh`)

Run the local agent readiness audit before launching a swarm on a freshly installed VPS:

```bash
bash scripts/agent-readiness-audit.sh
bash scripts/agent-readiness-audit.sh --json
```

The audit checks Claude Code, Codex CLI, Gemini CLI, and `caam` without printing token values or auth file contents. It reports CLI presence, version availability, parseable auth/config files, CAAM default profile consistency, and stale CAAM defaults that point at missing profiles.

Useful options:

```bash
bash scripts/agent-readiness-audit.sh --no-version  # Skip CLI --version probes
bash scripts/agent-readiness-audit.sh --home /home/ubuntu --path "$PATH"
```

Treat failures as launch blockers. Warnings usually mean the CLI is installed but needs a user sign-in or CAAM default profile selection.

### Automated Checksum + Drift Repair (`checksum-monitor.yml`)

GTBI automatically monitors upstream installers for changes, and also repairs generated artifact checksum drift:

```yaml
# Runs every 15 minutes + on upstream changes
schedule: "*/15 * * * *"
triggers:
  - Schedule (every 15 minutes)
  - Webhook from upstream repos (repository_dispatch)
  - Pushes touching installer/checksum/generator files
```

**How It Works:**

1. **Verify Generated Artifact Drift**: Runs `scripts/check-manifest-drift.sh --json` to detect:
   - `GTBI_MANIFEST_SHA256` mismatches
   - internal script checksum drift (`scripts/generated/internal_checksums.sh`)
   - generated installer and web metadata drift via `bun run generate:diff`
   - semantic manifest contract drift across `scripts/generated/doctor_checks.sh`, `gtbi/onboard/lessons`, README snippets, and `checksums.yaml`
2. **Auto-Repair Drift**: If drift is detected, runs `--fix` (regenerate + commit + push)
3. **Verify Current Upstream Checksums**: Downloads all upstream installers, calculates SHA256
4. **Detect Upstream Changes**: Compares against `checksums.yaml`
5. **Categorize Tools**: Separates "trusted" tools (can auto-update) from others
6. **Auto-Update Upstream Checksums**: Commits updated `checksums.yaml` when safe
7. **Alert**: For non-trusted tool changes, creates GitHub issue for manual review

The monitor **fails closed** when verification returns fetch errors or skipped entries; it will not emit partial/placeholder checksum updates.

**Trusted Tools (Auto-Update Enabled):**
- Installers whose upstream URL is author-maintained (currently the Gemini CLI crash-fix patch script)
- These are maintained by a trusted author, so upstream changes are auto-applied

**Non-Trusted Tools (Manual Review Required):**
- Third-party installers (bun, uv, rust, oh-my-zsh, atuin, zoxide, nvm, dolt, claude, opencode)
- Changes trigger a GitHub issue with diff details for human review

This ensures:
- **Security**: Third-party changes are reviewed before deployment
- **Velocity**: Internal tool updates are deployed automatically
- **Auditability**: All changes tracked via git commits

**Upstream Repo Dispatch (Fast Path):**
- GTBI-owned tool repos emit a `repository_dispatch` event (`upstream-changed`) when their `install.sh` changes or a release is published.
- Requires a PAT secret named `GTBI_REPO_DISPATCH_TOKEN` in each tool repo (repo scope for this org/user).
- If dispatch fails, the 15-minute scheduled monitor still catches drift (but slower).

### Production Smoke Tests (`production-smoke.yml`)

Validates deployments on real environments:

```yaml
# Runs after deployment
jobs:
  smoke:
    - Fetches install.sh from production URL
    - Verifies checksum matches repository
    - Validates shell syntax
    - Confirms no uncommitted drift
```

### Installer Canary (Docker) (`installer-canary.yml`)

Runs the installer inside fresh Ubuntu containers on a daily schedule. This is a fast regression canary, not the final proof of the factory VPS path.

```yaml
schedule: "30 7 * * *" # daily
jobs:
  canary:
    - Run tests/vm/test_install_ubuntu.sh (vibe mode)
    - Defaults to Ubuntu 25.10; --all covers 24.04, 25.04, and 25.10
    - Uses GTBI_CHECKSUMS_REF=main for freshest hashes
```

### Factory Installer E2E (`installer-factory-e2e.yml`)

Runs the literal public installer through the authoritative factory harness. The QEMU/KVM backend uses the official Ubuntu cloud image and requires a runner with `/dev/kvm`; set the repository variable `GTBI_FACTORY_RUNNER`, the manual `runner` input, or `client_payload.runner` to a KVM-capable larger/self-hosted runner. The real-host backend runs against a disposable Ubuntu VPS over SSH and is intended for provider-specific sentinel runs.

```yaml
schedule: "0 8 * * 0" # weekly QEMU/KVM factory canary when GTBI_FACTORY_RUNNER has /dev/kvm
workflow_dispatch:
  inputs:
    backend: qemu|real-host
    runner: "" # optional override; blank uses GTBI_FACTORY_RUNNER or ubuntu-latest
    ref: main
    mode: vibe
    expect_ubuntu: "25.10"
    expect_final_ubuntu: "25.10"
repository_dispatch:
  types: [gtbi-factory-host-ready]
real-host secrets:
  GTBI_FACTORY_SSH_PRIVATE_KEY: private key for real-host backend
  GTBI_FACTORY_SSH_TARGET: optional fallback root@fresh-host for real-host backend
```

Standard GitHub-hosted runners do not provide a contractual nested-virtualization environment. If the QEMU backend runs without `/dev/kvm`, the workflow fails at the KVM preflight with an environment-specific error before invoking the installer.

Reusable workflow callers may use the QEMU backend without passing SSH secrets. The real-host backend still needs a private key plus either `client_payload.ssh_target` for dispatch runs or `GTBI_FACTORY_SSH_TARGET` as a fallback.

If `backend=real-host` is requested without those SSH credentials, the workflow fails during configuration resolution. It must never report a green canary when no disposable host was tested.

Workflow artifact directories and uploads include only the current GitHub run id and attempt. That keeps repeated scheduled/manual runs from reusing or uploading old QEMU overlay disks on KVM-capable self-hosted runners with persistent workspaces. The QEMU backend writes its generated private SSH key outside the repository checkout, so upload-artifact and future Git commits never package guest login credentials. Factory diagnostics are redacted before local upload, including installer logs and the remote diagnostic archive.

The target host must be freshly provisioned. By default the harness fails if the `ubuntu` user already exists before install, because the real beginner path must prove GTBI creates that user automatically. The harness also requires `gtbi doctor --json` to report zero failures and zero warnings, then separately verifies Agent Mail liveness/systemd service state and the GTBI nightly user timer.

For the slower upgrade/resume gate, provision a fresh Ubuntu 24.04 host and run the same workflow or script with `--expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot`.

For provider-specific real VPS sentinels, use an external provisioning job to create a disposable server, wait for root SSH, dispatch `gtbi-factory-host-ready`, and destroy the server after artifact collection. The dispatch payload should include the fresh host address so the repository does not store a stale long-lived VPS as `GTBI_FACTORY_SSH_TARGET`:

```json
{
  "event_type": "gtbi-factory-host-ready",
  "client_payload": {
    "backend": "real-host",
    "ssh_target": "root@203.0.113.10",
    "ref": "main",
    "mode": "vibe",
    "expect_ubuntu": "25.10",
    "expect_final_ubuntu": "25.10"
  }
}
```

### Local QEMU Factory E2E (`test_factory_install_qemu.sh`)

Runs the same factory-host harness inside a real local VM instead of a Docker container. The wrapper downloads and verifies the official Ubuntu cloud image, boots it with QEMU/KVM and cloud-init, exposes root SSH on a local forwarded port, then delegates to `tests/vm/test_factory_install_ubuntu.sh`. Generated private SSH keys are kept outside the repository checkout; use `--key-dir` with a path under `/tmp` or another non-repo directory when you need a specific local key location for debugging.

```bash
sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils openssh-client
./tests/vm/test_factory_install_qemu.sh
```

Use this when Docker passes but you need local proof for systemd, sshd, cloud-init, kernel, filesystem, and login behavior before spending time on a disposable provider VPS.

---

## VPS Providers

GTBI works on any Ubuntu VPS with SSH access and either root password login or a provider console that lets you become root for the first install. Here are recommended providers optimized for multi-agent workloads.

> **Why 48-64GB RAM?** Each AI coding agent uses ~2GB RAM. To run 10-20+ agents simultaneously, you need 48GB+ RAM. Don't bottleneck a $400+/month AI investment to save $20 on hosting.

After installation, run `gtbi capacity --profile 25-agents` on the VPS for a local RAM/CPU/disk sizing report with recommended agent counts.

### Contabo (Best Value — Top Pick)

| Plan | RAM | vCPU | Storage | Price | Notes |
|------|-----|------|---------|-------|-------|
| **Cloud VPS 50** | 64GB | 16 | 400GB NVMe | ~$56/mo (US) | **Recommended** — Best for serious multi-agent work |
| Cloud VPS 40 | 48GB | 12 | 300GB NVMe | ~$36/mo (US) | Budget option, still comfortable |

- Best specs-to-price ratio on the market
- Month-to-month pricing, no commitment required
- US datacenter pricing includes ~$10/month premium

### OVH (Great Alternative)

| Plan | RAM | vCore | Storage | Price | Notes |
|------|-----|-------|---------|-------|-------|
| **VPS-5** | 64GB | 16 | 320GB NVMe | ~$40/mo | **Recommended** — Great EU and US datacenters |
| VPS-4 | 48GB | 12 | 240GB NVMe | ~$26/mo | Budget option |

- Anti-DDoS included
- Month-to-month, 5-15% discount for longer commitments
- Typically faster activation than Contabo

### Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Ubuntu 22.04+ (auto-upgraded) | Ubuntu 25.10 |
| **RAM** | 32GB (tight) | 48-64GB |
| **Storage** | 250GB NVMe SSD | 300GB+ NVMe SSD |
| **CPU** | 12 vCPU | 16 vCPU |
| **Price** | ~$26/mo | ~$40-56/mo |

### Other Providers

Any provider with an Ubuntu VPS, SSH access, and a first-login root password or root console works. See `scripts/providers/` for setup guides.

### Provider Setup Guides

GTBI includes detailed step-by-step guides for each supported provider in `scripts/providers/`:

| Provider | Guide | Key Sections |
|----------|-------|--------------|
| **Contabo** | `contabo.md` | Account creation, plan selection, data center choice, root password setup |
| **OVH** | `ovh.md` | Control panel navigation, password authentication, instance configuration, networking |
| **Hetzner** | `hetzner.md` | Project setup, firewall rules, console access |

Each guide includes:
- **Screenshots** for every step (in `scripts/providers/screenshots/`)
- **Pricing breakdowns** with recommendations
- **Region selection** guidance (latency, privacy)
- Password-first login guidance and post-install SSH key recovery specific to that provider
- **Troubleshooting** for common provisioning issues

**Provider Comparison:**

| Aspect | Contabo | OVH | Hetzner |
|--------|---------|-----|---------|
| Best For | Maximum value | EU data residency | German engineering |
| Provisioning | 1-3 hours | 5-30 minutes | 2-10 minutes |
| Support | Email only | Phone + chat | 24/7 ticket system |
| Data Centers | EU, US, Asia | Global | EU only |
| Payment | Monthly | Hourly or monthly | Hourly or monthly |

**Recommendation Flow:**
1. **Budget**: Contabo (best specs per dollar)
2. **Speed**: Hetzner (instant provisioning)
3. **Support**: OVH (phone support available)
4. **Privacy**: Any EU provider (GDPR compliance)

---

## Project Structure

```
gtbi/
├── README.md                     # This file
├── AGENTS.md                     # Development guidelines
├── VERSION                       # Current version (0.2.0)
├── install.sh                    # Main installer entry point
├── gtbi.manifest.yaml            # Canonical tool manifest (510 lines)
├── checksums.yaml                # SHA256 hashes for upstream scripts
├── package.json                  # Root monorepo config
│
├── packages/
│   ├── manifest/                 # Manifest parser + generator
│   │   └── src/
│   │       ├── parser.ts         # YAML parsing
│   │       ├── schema.ts         # Zod validation schemas
│   │       ├── types.ts          # TypeScript types
│   │       ├── utils.ts          # Helper functions
│   │       └── generate.ts       # Script generator
│   └── onboard/                  # Onboard TUI source
│
├── gtbi/                         # Files deployed to ~/.gtbi/
│   ├── zsh/
│   │   └── gtbi.zshrc            # Shell configuration
│   ├── tmux/
│   │   └── tmux.conf             # Tmux configuration
│   └── onboard/
│       ├── onboard.sh            # Onboarding TUI script
│       └── lessons/              # Tutorial markdown (11 files)
│
├── scripts/
│   ├── lib/                      # Installer bash libraries
│   │   ├── logging.sh            # Console output
│   │   ├── security.sh           # HTTPS + checksum verification
│   │   ├── os_detect.sh          # OS detection
│   │   ├── user.sh               # User management
│   │   ├── zsh.sh                # Shell setup
│   │   ├── update.sh             # Update command logic
│   │   ├── gum_ui.sh             # Enhanced UI
│   │   ├── cli_tools.sh          # Tool installation
│   │   └── doctor.sh             # Health checks
│   ├── generated/                # Auto-generated from manifest
│   │   ├── install_base.sh       # Base packages
│   │   ├── install_shell.sh      # Shell tools
│   │   ├── install_cli.sh        # CLI tools
│   │   ├── install_lang.sh       # Language runtimes
│   │   ├── install_agents.sh     # AI coding agents
│   │   ├── install_cloud.sh      # Cloud CLIs
│   │   ├── install_stack.sh      # Dicklesworthstone stack
│   │   ├── install_all.sh        # Master installer
│   │   └── doctor_checks.sh      # Verification checks
│   ├── providers/                # VPS provider guides
│   │   ├── ovh.md
│   │   ├── contabo.md
│   │   └── hetzner.md
│   └── sync/
│       └── sync_ntm_palette.sh   # Sync NTM command palette
│
├── .github/
│   └── workflows/
│       ├── installer.yml         # ShellCheck + Ubuntu matrix tests
│       └── website.yml           # Next.js build + deploy
│
└── tests/
    └── vm/
        ├── test_install_ubuntu.sh # Docker integration test
        ├── test_factory_install_ubuntu.sh # Real VM/VPS factory install test
        └── test_factory_install_qemu.sh # Local QEMU/KVM factory install test
```

---

## Development

### Manifest Development

```bash
cd packages/manifest
bun install           # Install dependencies
bun run generate      # Generate installer scripts
bun run generate:dry  # Preview without writing files
```

### Installer Testing

```bash
# Local lint
shellcheck install.sh scripts/lib/*.sh

# Full installer integration test (Docker, same as CI)
./tests/vm/test_install_ubuntu.sh

# Authoritative factory-host E2E (requires a disposable fresh Ubuntu 25.10 VM/VPS)
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10

# Local authoritative VM E2E (QEMU/KVM + official Ubuntu cloud image)
./tests/vm/test_factory_install_qemu.sh

# Slow real-host upgrade/resume gate from Ubuntu 24.04 to 25.10
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10 --expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot
```

### Security Verification

```bash
# Print all upstream URLs
./scripts/lib/security.sh --print

# Verify all checksums
./scripts/lib/security.sh --verify

# Update checksums after reviewing upstream changes
./scripts/lib/security.sh --update-checksums > checksums.yaml
```

### Manifest Validation

The manifest parser includes comprehensive validation beyond basic schema checking:

**Validation Error Codes:**

| Code | Description |
|------|-------------|
| `MISSING_DEPENDENCY` | Module references non-existent dependency |
| `DEPENDENCY_CYCLE` | Circular dependency detected (A→B→C→A) |
| `PHASE_VIOLATION` | Module runs before its dependencies |
| `FUNCTION_NAME_COLLISION` | Two modules generate same bash function |
| `RESERVED_NAME_COLLISION` | Module uses reserved identifier |
| `INVALID_VERIFIED_INSTALLER_RUNNER` | Runner not in allowlist (bash/sh only) |

**Running Validation:**
```bash
cd packages/manifest
bun run validate              # Full validation
bun run validate --verbose    # Show all checks
```

**Cycle Detection Algorithm:**
```
Tarjan's strongly connected components (SCC):
1. DFS with discovery/low-link tracking
2. Identify SCCs with size > 1 as cycles
3. Report cycle path for human debugging
```

### Test Harness

GTBI includes a comprehensive test harness (`tests/vm/lib/test_harness.sh`) for integration testing:

```bash
# Source the harness
source tests/vm/lib/test_harness.sh

# Initialize test suite
harness_init "GTBI Installation Tests"

# Create test sections
harness_section "Phase 1: Base Packages"

# Run commands with automatic logging
harness_run "Installing curl" apt install -y curl

# Assert results
harness_pass "curl installed successfully"
harness_fail "curl installation failed"
harness_skip "Skipping optional test"

# Generate summary
harness_summary  # Outputs: 15 passed, 0 failed, 2 skipped
```

**Test Files:**

| Test | Purpose |
|------|---------|
| `test_install_ubuntu.sh` | Full Docker-based installation |
| `test_factory_install_ubuntu.sh` | Real systemd VM/VPS factory install from public curl\|bash |
| `test_factory_install_qemu.sh` | Local QEMU/KVM factory install using Ubuntu cloud images |
| `test_gtbi_update.sh` | Update mechanism validation |
| `bootstrap_offline_checks.sh` | Offline system readiness |
| `resume_checks.sh` | State resume validation |
| `selection_checks.sh` | Module selection unit tests |
| `selection_e2e.sh` | End-to-end selection flow |

**Running Tests:**
```bash
# Full Docker integration test
./tests/vm/test_install_ubuntu.sh

# Full Docker integration matrix
./tests/vm/test_install_ubuntu.sh --all

# Real factory-host integration test
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10

# Local QEMU/KVM factory-host integration test
./tests/vm/test_factory_install_qemu.sh

# Real upgrade/resume integration test
./tests/vm/test_factory_install_ubuntu.sh --ssh-target root@203.0.113.10 --expect-ubuntu 24.04 --expect-final-ubuntu 25.10 --allow-install-reboot

# Selection logic tests
./tests/vm/selection_checks.sh

# Web E2E tests
./tests/web/run_e2e.sh
```

### Sync Scripts

Sync scripts keep GTBI documentation aligned with upstream projects:

```bash
# Sync NTM command palette from upstream
./scripts/sync/sync_ntm_palette.sh

# Check if update available (without downloading)
./scripts/sync/sync_ntm_palette.sh --check
```

**Current Sync Sources:**

| Script | Source | Destination |
|--------|--------|-------------|
| `sync_ntm_palette.sh` | NTM repo `command_palette.md` | `gtbi/onboard/docs/ntm/` |

All sync scripts use the security library for HTTPS enforcement and content hashing.

### Requirements

- **Runtime:** Bun (not npm/yarn/pnpm)
- **Node:** Latest
- **Shell:** Bash 5+

---

## FAQ

### Why "Vibe Mode"?

Vibe mode is designed for **throwaway VPS environments** where velocity matters more than safety:
- Passwordless sudo eliminates friction
- Agent dangerous flags skip confirmation dialogs
- Pre-configured aliases for maximum speed

**Never use vibe mode on production or shared systems.**

### Can I use this on my local machine?

GTBI is designed for fresh Ubuntu VPS instances. While you *could* run it locally:
- It may conflict with existing configurations
- It assumes root/sudo access
- It's not designed for macOS or Windows

For local development, use the individual tools directly.

### What if the installer fails?

The installer is **checkpointed**. Simply re-run it:
```bash
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe
```

It will skip already-completed phases and resume where it left off.

### How do I update tools?

Use the built-in update command:
```bash
gtbi update                  # Update all standard components
gtbi update --stack          # Include Dicklesworthstone stack
gtbi update --agents-only    # Just update AI agents
```

### How do I uninstall?

There's no uninstall script. To reset:
1. Delete the VPS instance
2. Create a new one
3. Run the installer fresh

This is intentional—GTBI is designed for ephemeral VPS environments.

### Can I customize which tools are installed?

Currently, GTBI installs the full suite. Future versions will support:
- Manifest-based tool selection
- Interactive mode for choosing components
- Modular installation scripts

---

## Why GTBI Exists

### The Problem: The Agentic Coding Barrier

The rise of AI coding agents (Claude Code, Codex CLI, Gemini CLI) has created a new paradigm in software development. These agents can write code, debug issues, and even architect solutions—but only if they have the right environment.

**The barrier isn't the agents themselves.** It's the **hours of setup** required to create an environment where agents can actually be productive:

```
┌────────────────────────────────────────────────────────────────────────────┐
│  TIME INVESTMENT WITHOUT GTBI                                               │
│                                                                              │
│  VPS Setup ..................... 30-60 min                                   │
│  Shell Configuration ........... 20-30 min                                   │
│  Language Runtimes ............. 30-45 min                                   │
│  Dev Tools ..................... 20-30 min                                   │
│  Agent Installation ............ 15-30 min                                   │
│  Agent Configuration ........... 20-40 min                                   │
│  Coordination Tools ............ 30-60 min                                   │
│  Troubleshooting ............... 30-120 min                                  │
│  ─────────────────────────────────────────                                   │
│  TOTAL: 3-7 hours (and that's if everything works)                          │
│                                                                              │
│  TIME INVESTMENT WITH GTBI                                                   │
│                                                                              │
│  Run one command ............... 25-30 min                                   │
│  ─────────────────────────────────────────                                   │
│  TOTAL: 30 minutes                                                           │
└────────────────────────────────────────────────────────────────────────────┘
```

**GTBI eliminates this barrier entirely.** One command, 30 minutes, fully configured.

### The Deeper Problem: Beginners Can't Start

For experienced developers, the setup is tedious but doable. For beginners—the people who would benefit *most* from AI coding assistance—it's an insurmountable wall:

- What's SSH? How do I generate keys?
- What's a VPS? How do I rent one?
- What's a terminal? Which one should I use?
- How do I connect to a remote server?
- What are all these tools and why do I need them?

GTBI's README and provider guides (`scripts/providers/`) address this by providing:

1. **Absolute beginner guidance** — Explains every concept in plain English
2. **OS-specific instructions** — Shows the right commands per platform
3. **Pre-flight checks** — `scripts/preflight.sh` to validate the VPS before running the full install
4. **Troubleshooting help** — Common failure scenarios and recovery steps
5. **Resume capability** — Re-run the installer; it resumes from where it left off

---

## The 10x Multiplier Effect

GTBI isn't just a collection of tools—it's a **carefully curated system** where each component amplifies the others. The value isn't additive; it's multiplicative.

### Tool Synergy Model

```
                              ┌─────────────────┐
                              │   PRODUCTIVITY  │
                              │   MULTIPLIER    │
                              └────────┬────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  ENVIRONMENT    │         │    AGENTS       │         │  COORDINATION   │
│  LAYER          │         │    LAYER        │         │  LAYER          │
├─────────────────┤         ├─────────────────┤         ├─────────────────┤
│ • zsh + p10k    │────────▶│ • Claude Code   │────────▶│ • Gastown (gt)  │
│ • tmux          │         │ • Codex CLI     │         │ • beads (bd)    │
│ • Modern CLI    │         │ • Gemini CLI    │         │ • Dolt          │
│ • Language VMs  │         │ • OpenCode      │         │                 │
└─────────────────┘         └─────────────────┘         └─────────────────┘
         │                             │                             │
         │    Each layer enables       │    Agents become more      │
         │    the next layer           │    powerful together       │
         └─────────────────────────────┴─────────────────────────────┘
```

### Why These Specific Tools?

Every tool in GTBI earns its place through **concrete productivity gains**:

| Tool | Individual Value | Synergy Value |
|------|-----------------|---------------|
| **tmux** | Persistent sessions | Agents can work while you're disconnected |
| **beads** (`bd`) | Task tracking | Agents share one dependency-aware issue graph, avoid rework |
| **Dolt** | Versioned database | Task state is branchable, diffable, and syncable |
| **Gastown** (`gt`) | Orchestration | Drives multiple agents against ready work |
| **atuin** | Shell history | Search commands across sessions, share patterns |
| **zoxide** | Smart cd | `z proj` beats `cd ~/projects/my-long-name` |
| **ripgrep** | Fast search | Agents find code 100x faster than grep |
| **fzf** | Fuzzy finding | Interactive selection instead of typing paths |

### The Compounding Effect

A single agent with basic tooling is useful. Three agents with:
- A shared project structure
- A shared, dependency-aware task graph via beads
- Version-controlled task state via Dolt
- Orchestration via Gastown

...can accomplish in one day what would take a solo developer a week.

Tip: run `gtbi services-setup` to configure agent logins.

**This is the flywheel effect in action.** Better tools → more capable agents → more code shipped → better understanding of what tools are needed → better tools.

---

## Design Algorithms & Decisions

GTBI implements several algorithmic patterns that ensure reliability and maintainability.

### Idempotency Algorithm

Every installation function follows the **check-before-install** pattern:

```bash
install_tool() {
    if command_exists "tool"; then
        log_success "tool already installed"
        return 0
    fi

    # ... installation logic ...

    if command_exists "tool"; then
        log_success "tool installed successfully"
        return 0
    else
        log_error "tool installation failed"
        return 1
    fi
}
```

This guarantees:
1. **Safe re-runs** — Running the installer twice doesn't break anything
2. **Resume capability** — Failures don't require starting over
3. **Declarative intent** — The end state is defined, not the transition

### Checksum Verification Algorithm

The security system uses **content-addressable verification**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  VERIFICATION FLOW                                                       │
│                                                                          │
│  1. Download script to memory (not disk)                                 │
│  2. Calculate SHA256 of downloaded content                               │
│  3. Compare against stored hash in checksums.yaml                        │
│  4. If match → execute                                                   │
│  5. If mismatch → refuse execution, report discrepancy                   │
│                                                                          │
│  Key insight: We verify CONTENT, not just transport                      │
│  (HTTPS only protects the channel, not the content at source)            │
└─────────────────────────────────────────────────────────────────────────┘
```

### Manifest-Driven Generation

The generator uses a **template expansion** pattern:

1. **Parse** — Read YAML manifest, validate with Zod schemas
2. **Transform** — Convert manifest entries to installation functions
3. **Group** — Organize by category (base, shell, cli, lang, agents, etc.)
4. **Generate** — Emit Bash scripts with consistent structure
5. **Verify** — Generate doctor checks from verification commands

This ensures the manifest is the **single source of truth**—no drift between documentation, installer, and verification.

### Code Generator Architecture

The manifest generator (`packages/manifest/src/generate.ts`) is a sophisticated TypeScript program that transforms YAML into bash:

**Input Processing:**
```typescript
// 1. Parse YAML with validation
const manifest = parseManifestFile(MANIFEST_PATH);  // Zod-validated

// 2. Load checksums for verified installers
const checksums = parseYaml(readFileSync(CHECKSUMS_PATH));

// 3. Topological sort for dependency order
const sorted = sortModulesByInstallOrder(manifest.modules);
```

**Security-First Code Generation:**
```typescript
// Shell-safe quoting (prevents command injection)
function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}

// Allowlisted runners only (belt-and-suspenders)
const ALLOWED_RUNNERS = ['bash', 'sh'] as const;

// Verified installer pipe construction
function buildVerifiedInstallerPipe(module: Module, checksums: Checksums): string {
  // Generates: curl -fsSL "$URL" | verify_checksum "$SHA256" | bash
}
```

**Output Structure:**
```
scripts/generated/
├── install_base.sh        # Base system packages (apt)
├── install_users.sh       # User normalization (ubuntu user)
├── install_filesystem.sh  # Directory structure (/data/projects)
├── install_shell.sh       # zsh + oh-my-zsh + p10k
├── install_cli.sh         # ripgrep, tmux, fzf, lazygit, etc.
├── install_network.sh     # Tailscale
├── install_lang.sh        # bun, uv, rust, go
├── install_tools.sh       # ast-grep, atuin, zoxide
├── install_agents.sh      # claude, codex, gemini
├── install_db.sh          # PostgreSQL 18, Vault
├── install_cloud.sh       # wrangler, supabase, vercel
├── install_stack.sh       # Dicklesworthstone 10-tool stack + utilities
├── install_gtbi.sh        # GTBI config deployment
├── install_all.sh         # Orchestration helper
├── doctor_checks.sh       # Health verification
└── manifest_index.sh      # Module metadata arrays
```

**Generated Script Structure:**
```bash
#!/usr/bin/env bash
# AUTO-GENERATED FROM gtbi.manifest.yaml - DO NOT EDIT

install_module_id() {
    gtbi_require_contract "module.id"  # Validate environment

    if run_installed_check "module.id"; then
        log_step "module.id already installed"
        return 0
    fi

    set_phase "Installing module..."
    run_as_target_shell <<'HEREDOC'
        # Installation commands from manifest
    HEREDOC

    verify_module "module.id"  # Post-install checks
}
```

**Regeneration:**
```bash
cd packages/manifest
bun run generate           # Full regeneration
bun run generate:dry       # Preview without writing
```

### Generated Manifest Index

The generator produces `manifest_index.sh`, a comprehensive bash metadata file that provides programmatic access to manifest data at runtime:

**Associative Arrays:**
```bash
# Module metadata lookup
declare -gA GTBI_MODULE_DESC
GTBI_MODULE_DESC["lang.bun"]="Bun JavaScript/TypeScript runtime"
GTBI_MODULE_DESC["agents.claude"]="Claude Code CLI agent"

# Phase mapping (determines install order)
declare -gA GTBI_MODULE_PHASE
GTBI_MODULE_PHASE["base.system"]="1"
GTBI_MODULE_PHASE["lang.bun"]="6"
GTBI_MODULE_PHASE["agents.claude"]="7"

# Dependency relationships (comma-separated)
declare -gA GTBI_MODULE_DEPS
GTBI_MODULE_DEPS["agents.codex"]="lang.bun"
GTBI_MODULE_DEPS["stack.bd"]="stack.dolt"

# Generated function name mapping
declare -gA GTBI_MODULE_FUNC
GTBI_MODULE_FUNC["lang.bun"]="install_lang_bun"

# Category grouping
declare -gA GTBI_MODULE_CATEGORY
GTBI_MODULE_CATEGORY["lang.bun"]="lang"

# Default inclusion in install
declare -gA GTBI_MODULE_DEFAULT
GTBI_MODULE_DEFAULT["lang.bun"]="1"
GTBI_MODULE_DEFAULT["stack.dolt"]="1"
```

**Runtime Access Pattern:**
```bash
# Iterate modules in deterministic install order
for module in "${GTBI_MODULES_IN_ORDER[@]}"; do
  [[ "${GTBI_MODULE_CATEGORY[$module]}" == "agents" ]] || continue
  printf '%s\n' "$module"
done

# Check if module is default-installed
[[ "${GTBI_MODULE_DEFAULT[tools.lazygit]:-1}" == "1" ]]

# Get installation phase
printf '%s\n' "${GTBI_MODULE_PHASE[stack.bd]}"  # 9
```

**Use Cases:**
- `gtbi doctor` queries module metadata for health checks
- `install.sh --list-modules` displays available modules
- `--skip <module>` validates module existence before skipping
- `--only-phase <n|name>` uses phase mapping for selective installs

The manifest index bridges the TypeScript generator with bash runtime, enabling sophisticated module selection logic while keeping the bash scripts simple.

### Progressive Disclosure in the Wizard

The wizard website implements **progressive disclosure** for complexity management:

```
Level 1: Core instructions (visible by default)
├── Copy this command
├── Paste in terminal
└── Press Enter

Level 2: Troubleshooting (expandable)
├── "Permission denied" → fix instructions
├── "Command not found" → prerequisites
└── "Connection refused" → diagnostics

Level 3: Deep explanations (collapsible "Beginner Guide")
├── What is SSH?
├── What is a VPS?
├── Why these specific steps?
└── What happens under the hood?
```

This allows beginners to get deep context when needed, while experts can skip straight to the commands.

---

## Multi-Agent Orchestration Model

GTBI is designed for **multi-agent workflows** where several AI coding agents work on the same project simultaneously.

### The Coordination Problem

Without coordination, multiple agents cause chaos:
- **File conflicts** — Two agents edit the same file
- **Duplicated work** — Agents solve the same problem independently
- **Communication gaps** — No visibility into what others are doing
- **Safety risks** — Dangerous operations without oversight

### The GTBI Solution Stack

GTBI coordinates agents through a small, Dolt-backed stack:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         AGENT COORDINATION LAYER                           │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                         │
│  │   Gastown   │  │    beads    │  │    Dolt     │                         │
│  │ (Orchestr.) │  │   (Tasks)   │  │ (Versioned  │                         │
│  │             │  │             │  │  database)  │                         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                         │
│         │                │                │                                 │
│         └────────────────┴────────────────┘                                │
│                          │                                                  │
│                          ▼                                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                      SHARED TASK GRAPH (beads)                        │ │
│  │                                                                        │ │
│  │  Agent A claims: bd-101 (auth)                                         │ │
│  │  Agent B claims: bd-102 (api)                                          │ │
│  │  Agent C claims: bd-103 (tests)                                        │ │
│  │                                                                        │ │
│  │  → Dependencies and blockers visible to every agent                    │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
```

### Agent Coordination Patterns

**1. Shared task graph (beads)**
```
Agent A: bd update bd-101 --claim   → owns the auth task
Agent B: bd ready                    → sees bd-101 is taken, picks bd-102
Agent C: bd dep add bd-104 bd-101    → records a blocker every agent can see
```

**2. Version-controlled state (Dolt)**
```
beads stores issues in a Dolt database, so task state is branchable,
diffable, and syncable across machines via refs/dolt/data.
```

**3. Orchestration (Gastown)**
```
gt drives multi-agent runs over the shared beads graph,
spawning and supervising agents against ready work.
```

### Dry-Run Swarm Simulation

Before launching any real swarm, ask GTBI for a queue-aware plan:

```bash
gtbi swarm plan --agents 25 --profile balanced --workload standard
```

The planner reads the local swarm status and capacity model, incorporates
active tmux sessions, beads in-progress counts, and host resource headroom,
then prints a pass/warn/fail recommendation. It is advisory only: it does not
launch agents, mutate beads, or run build commands. JSON output is available
with `--json`, and fixture replay is available with `--status-file`.

For multi-host planning, keep a local redacted inventory at
`~/.gtbi/swarm/hosts.inventory.json`:

```bash
gtbi swarm inventory report
gtbi swarm inventory validate --json
gtbi swarm inventory export --format json --output inventory.redacted.json
gtbi swarm inventory import --input inventory.redacted.json
```

The inventory commands are local and advisory. They read or write JSON files,
preserve unknown fields for future versions, reject sensitive field names such
as hostnames, IPs, keys, tokens, passwords, and home paths, and never SSH,
launch agents, mutate beads, or change config.

For each agent you plan to launch, generate a bounded startup packet from the
selected bead plus current repo instructions:

```bash
gtbi swarm packet --bead bd-1234 --agent-name BlueLake --role implementation
gtbi swarm packet --json --bead bd-1234 --agent-name BlueLake
```

The packet is designed for prompt injection at agent launch. It prioritizes live
AGENTS.md, README.md, and beads state over memory-derived hints and includes
drift checks. It is read-only: it does not claim work, send messages, start
agents, run builds, or edit generated files.

Before launching a large real swarm, GTBI can run an offline simulation of the control plane:

```bash
gtbi swarm simulate
```

The default simulation runs 10, 25, and 50 logical-agent scenarios without launching tmux sessions, model CLIs, beads mutations, or local CPU-heavy builds. It writes artifacts for each scenario: generated launch plan, telemetry JSON, capacity/resource sample, timing, and pass/fail summary. Treat this as a local readiness harness, not a substitute for provider factory tests on real VPS hosts.

After one or more simulation runs, calibrate the static capacity assumptions
against those local artifacts:

```bash
gtbi swarm calibration --artifact-dir ~/.gtbi/logs/swarm-simulations
gtbi swarm calibration --json --artifact-dir ./swarm-artifacts --rch-file ./rch-timing.json
```

The calibration report is read-only. It classifies the local evidence as
conservative, aligned, or too aggressive, handles missing or partial artifacts
with warnings, and never changes capacity defaults, tmux sessions, or beads.

---

## Philosophy

### The Flywheel

The "Agentic Coding Flywheel" is a virtuous cycle:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│    Better Environment → More Agent Productivity →               │
│    More Code Written → Better Understanding →                   │
│    Better Prompts → Better Environment                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

GTBI kicks off this flywheel by providing the **best possible starting environment** for agentic coding.

### Design Principles

1. **Beginner-Friendly, Expert-Fast:** The wizard guides beginners; the one-liner serves experts.

2. **Vibe-First:** Optimize for velocity in throwaway environments. Safety features exist in safe mode.

3. **Idempotent:** Re-run without fear. The installer handles already-installed tools gracefully.

4. **Single Source of Truth:** The manifest defines everything. Installer scripts are generated from it.

5. **Security by Default:** HTTPS enforcement, checksum verification, no blind `curl | bash`.

6. **Modern Defaults:** Latest versions, modern tools, optimal configurations out of the box.

---

## The Vibe Coding Manifesto

"Vibe coding" isn't just a catchy name—it's a philosophy about how humans and AI should collaborate on software development.

### What Is Vibe Coding?

Vibe coding is the practice of **directing AI agents to write code while you focus on intent, architecture, and quality**. Instead of typing every line yourself, you:

1. **Describe what you want** in natural language
2. **Review and guide** the agent's output
3. **Iterate rapidly** through multiple approaches
4. **Ship faster** while maintaining quality

The "vibe" comes from the flow state you enter when you're no longer fighting syntax, boilerplate, or implementation details—you're just vibing with your AI partner.

### The Three Laws of Vibe Coding

**1. Velocity Over Ceremony**

Traditional development is ceremony-heavy: create branch, write tests first, implement, refactor, write docs, create PR, wait for review, merge, deploy. Each step has friction.

Vibe coding inverts this: ship fast, iterate faster. The AI handles boilerplate while you focus on the 10% that requires human judgment.

```
Traditional: Think → Plan → Implement → Test → Document → Ship
Vibe:        Describe → Generate → Verify → Ship → Iterate
```

**2. Throwaway Environments Enable Boldness**

The magic of vibe coding happens on **ephemeral VPS instances**. When your environment is disposable:
- You can experiment without fear
- Catastrophic failures are just "rebuild the VPS"
- Agents can have dangerous permissions (they can't break what's disposable)
- You focus on output, not on protecting your setup

This is why GTBI's "vibe mode" enables passwordless sudo and dangerous agent flags—on a $5/month throwaway VPS, there's nothing worth protecting.

**3. Multi-Agent Is The Default**

One agent is useful. Three agents working in parallel are transformative.

Vibe coding assumes you'll run multiple agents simultaneously:
- Claude for complex reasoning and architecture
- Codex for rapid prototyping and refactoring
- Gemini for documentation and research

GTBI provides the coordination layer (Dolt + beads + Gastown) that makes this practical.

### The Anti-Patterns

Vibe coding is **NOT**:
- Blindly accepting agent output without review
- Abandoning tests and quality standards
- Ignoring security on production systems
- Treating agents as replacements for understanding

The goal is **augmented human judgment**, not abdicated human judgment.

### When NOT to Vibe Code

- Production systems with real users
- Security-critical infrastructure
- Anything involving credentials or secrets
- Long-running servers (use safe mode)
- Shared team environments (use coordination tools)

Vibe coding is for **greenfield development, prototyping, experimentation, and learning**. Use GTBI's safe mode for everything else.

---

## State Machine & Checkpoint System

GTBI implements a robust **checkpoint-based state machine** that enables reliable resume-from-failure. This section explains how it works under the hood.

### State File Format

Progress is tracked in `~/.gtbi/state.json`:

```json
{
  "schema_version": 3,
  "started_at": "2024-12-21T10:30:00Z",
  "last_updated": "2024-12-21T10:45:23Z",
  "mode": "vibe",
  "completed_phases": ["user_setup", "filesystem", "shell_setup"],
  "current_phase": "cli_tools",
  "current_step": "Installing ripgrep",
  "failed_phase": null,
  "failed_step": null,
  "failed_error": null,
  "skipped_phases": [],
  "phase_timings": {
    "user_setup": 12,
    "filesystem": 8,
    "shell_setup": 145
  }
}
```

### Phase State Transitions

Each phase goes through a defined state machine:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE STATE MACHINE                                                         │
│                                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                             │
│  │ PENDING  │────▶│ RUNNING  │────▶│ COMPLETE │                             │
│  └──────────┘     └────┬─────┘     └──────────┘                             │
│       │                │                                                     │
│       │                ▼                                                     │
│       │          ┌──────────┐     ┌──────────┐                              │
│       │          │  FAILED  │────▶│  RETRY   │──┐                           │
│       │          └──────────┘     └──────────┘  │                           │
│       │                                ▲        │                           │
│       │                                └────────┘                           │
│       │                                                                      │
│       └──────────────────────▶┌──────────┐                                  │
│          (--skip flag)        │ SKIPPED  │                                  │
│                               └──────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Resume Logic

When the installer runs, it follows this decision tree:

```python
def should_run_phase(phase_id):
    state = load_state_file()

    if phase_id in state.completed_phases:
        return SKIP  # Already done

    if phase_id in state.skipped_phases:
        return SKIP  # User explicitly skipped

    if state.failed_phase == phase_id:
        if user_wants_retry():
            return RUN  # Retry failed phase
        else:
            return ABORT  # Don't continue past failure

    return RUN  # Normal execution
```

### Atomic State Updates

State file updates are **atomic** to prevent corruption from interrupted writes:

```bash
# Write to temp file first
echo "$new_state" > "$state_file.tmp.$$"

# Atomic rename (POSIX guarantees this is atomic on same filesystem)
mv "$state_file.tmp.$$" "$state_file"
```

This ensures the state file is never partially written, even if the process is killed mid-update.

### Recovery from Common Failures

| Failure Type | Detection | Recovery |
|--------------|-----------|----------|
| Network timeout | curl exit code 28 | Retry with exponential backoff |
| APT lock held | `/var/lib/dpkg/lock` exists | Wait and retry up to 60s |
| Disk full | df check before write | Abort with clear error |
| Out of memory | OOM killer | Resume picks up from last phase |
| SSH disconnect | N/A (session dies) | Resume on reconnect |
| Ctrl+C | Trap handler | Clean exit, state preserved |

### Phase Timings & Performance

The state file tracks how long each phase takes. This enables:
- Accurate progress estimation ("Phase 4/9, ~3 minutes remaining")
- Performance regression detection across GTBI versions
- Identifying slow phases that need optimization

---

## Error Handling & Recovery Patterns

GTBI is designed to **fail gracefully and recover automatically**. This section documents the error handling patterns used throughout the codebase.

### The Try-Step Pattern

Every installation step is wrapped in a `try_step` function that captures errors without aborting:

```bash
try_step "Installing ripgrep" install_ripgrep
```

This pattern provides:
- **Context tracking**: Errors include step name, not just exit code
- **Graceful continuation**: Non-critical failures don't abort the whole install
- **Structured reporting**: Failures are collected and reported at the end

### Network Resilience

Network operations implement **exponential backoff with jitter**:

```bash
retry_with_backoff() {
    local max_attempts=5
    local delay=1

    for attempt in $(seq 1 $max_attempts); do
        if "$@"; then
            return 0
        fi

        # Exponential backoff: 1s, 2s, 4s, 8s, 16s
        # With jitter: ±25% randomization
        local jitter=$(( (RANDOM % 50 - 25) * delay / 100 ))
        sleep $((delay + jitter))
        delay=$((delay * 2))
    done

    return 1
}
```

### APT Lock Handling

The most common installation failure is APT lock contention (another process using apt):

```bash
wait_for_apt_lock() {
    local max_wait=60
    local waited=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [[ $waited -ge $max_wait ]]; then
            log_error "APT lock held for >60s, aborting"
            return 1
        fi
        log_detail "Waiting for apt lock... (${waited}s)"
        sleep 5
        waited=$((waited + 5))
    done

    return 0
}
```

### Graceful Degradation

When a non-critical tool fails to install, GTBI continues with a warning:

```
Category: Critical    → Failure aborts installation
          Standard    → Failure logged, installation continues
          Optional    → Failure noted, no warning

Examples:
  Critical: bun, zsh, git (can't proceed without these)
  Standard: ast-grep, lazygit (nice to have, not blocking)
  Optional: atuin, zoxide (pure enhancements)
```

### The Error Report

At the end of installation (or on abort), GTBI generates a structured error report:

```
═══════════════════════════════════════════════════════════════════════════════
  INSTALLATION REPORT
═══════════════════════════════════════════════════════════════════════════════

  Status: PARTIAL SUCCESS (8/9 phases completed)

  ✓ Completed Phases:
    • User Setup (12s)
    • Filesystem (8s)
    • Shell Setup (2m 25s)
    • CLI Tools (4m 12s)
    • Languages (3m 45s)
    • Agents (1m 30s)
    • Cloud (2m 10s)
    • Stack (5m 20s)

  ✗ Failed Phase: Finalize
    Step: Configuring tmux
    Error: tmux.conf syntax error on line 42

  Suggested Fix:
    Check ~/.gtbi/tmux/tmux.conf for syntax errors
    Then run: curl ... | bash -s -- --yes --mode vibe --resume

═══════════════════════════════════════════════════════════════════════════════
```

---

## Troubleshooting Guide

This section covers common issues and their solutions. For quick debugging, start with `gtbi doctor`.

### Installation Fails Immediately

**Symptom**: Installer exits within seconds of starting.

**Common Causes & Solutions**:

| Cause | Detection | Fix |
|-------|-----------|-----|
| Not running as root | "Permission denied" | `sudo bash` or use `sudo` in curl command |
| Not Ubuntu | "Unsupported OS" | GTBI only supports Ubuntu 22.04+ |
| No internet | "curl: (6) Could not resolve host" | Check DNS, try `ping google.com` |
| Old bash | Syntax errors | Upgrade to bash 4+ |

### Installation Failure Recovery

When the installer fails mid-way through, it provides an **auto-resume hint** with a precise command to continue from where it left off.

**What you'll see on failure:**

```
[ERROR] GTBI installation failed!

To debug:
  1. Check the log: cat /var/log/gtbi/install.log
  2. If installed, run: gtbi doctor (try as ubuntu)

╔══════════════════════════════════════════════════════════════╗
║  To resume installation from this point:                     ║
╚══════════════════════════════════════════════════════════════╝

  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/.../install.sh | bash -s -- --resume --yes

  Failed phase: phase_9
  Failed step: install_stack
```

**Key features of the resume hint:**

| Feature | Description |
|---------|-------------|
| **Pinned commit** | Uses exact SHA from original run for reproducibility |
| **Preserved flags** | Includes all original flags (--skip-*, --mode, --strict) |
| **Automatic detection** | Reads failed phase/step from `~/.gtbi/state.json` |
| **Copyable command** | Ready to paste and run immediately |

**Manual recovery steps:**

1. **Review the error**:
   ```bash
   # Check the full log
   cat /var/log/gtbi/install.log | tail -50

   # Or search for ERROR
   grep -i error /var/log/gtbi/install.log
   ```

2. **Run diagnostics**:
   ```bash
   # As the target user (ubuntu)
   gtbi doctor

   # If running as root
   sudo -u ubuntu -i bash -lc 'gtbi doctor'
   ```

3. **Resume installation**:
   ```bash
   # Use the exact command from the failure output
   # Or use the generic resume command:
   curl -fsSL https://gtbi.sh | bash -s -- --resume --yes --mode vibe
   ```

4. **Check state file** (advanced):
   ```bash
   # View current installation state
   cat ~/.gtbi/state.json | jq .

   # See the stored resume hint
   jq '.resume_hint' ~/.gtbi/state.json
   ```

**Common failure scenarios:**

| Scenario | Typical Cause | Recovery |
|----------|---------------|----------|
| Network timeout | Transient connectivity | Wait, then resume |
| APT lock held | Unattended-upgrades | Wait 2-3 min, resume |
| Disk full | Insufficient space | Free space, resume |
| SSH disconnect | Session timeout | Reconnect, resume |
| Tool install failed | Upstream unavailable | Check status, resume |

### APT Lock Errors

**Symptom**: `E: Could not get lock /var/lib/dpkg/lock-frontend`

**Solutions**:

1. **Wait for unattended-upgrades** (most common on fresh VPS):
   ```bash
   # Check what's holding the lock
   sudo lsof /var/lib/dpkg/lock-frontend

   # Wait for it to finish (usually 2-3 minutes on fresh VPS)
   # Then re-run installer
   ```

2. **Inspect and recover if waiting doesn't help**:
   ```bash
   sudo fuser -v /var/lib/dpkg/lock-frontend || true
   sudo systemctl status unattended-upgrades --no-pager || true

   # If it still looks stuck after several minutes, reboot the VPS,
   # reconnect, then repair interrupted package configuration:
   sudo dpkg --configure -a
   sudo apt-get update
   ```

### Install Logs & Summary JSON

Every GTBI install run produces two artifacts for debugging and tooling:

**Log File Location:**
```
~/.gtbi/logs/install-YYYYMMDD_HHMMSS.log
```

The log file captures all stderr output from the installer, with:
- Header containing version, date, and mode
- All progress messages and errors
- ANSI colors stripped after completion
- Footer with completion timestamp

**Summary JSON Location:**
```
~/.gtbi/logs/install_summary_YYYYMMDD_HHMMSS.json
```

**Summary JSON Schema (v1):**
```json
{
  "schema_version": 1,
  "status": "success",           // "success" or "failure"
  "timestamp": "2026-01-27T...", // ISO 8601
  "total_seconds": 1200,         // Wall clock time
  "environment": {
    "gtbi_version": "0.9.0",
    "mode": "vibe",
    "ubuntu_version": "25.04",
    "target_user": "ubuntu",
    "target_home": "/home/ubuntu"
  },
  "phases": [
    {"id": "phase_0", "duration_seconds": 5},
    {"id": "phase_1", "duration_seconds": 45},
    // ... completed phases in order
  ],
  "failure": null,               // null on success, or:
  // "failure": {
  //   "phase": "phase_9",
  //   "step": "install_stack",
  //   "error": "curl failed with exit code 7",
  //   "resume_hint": "curl -fsSL ... | bash -s -- --resume --yes"
  // }
  "log_file": "/home/ubuntu/.gtbi/logs/install-20260127_120000.log"
}
```

**Accessing logs:**
```bash
# Find the latest log
ls -lt ~/.gtbi/logs/install-*.log | head -1

# Find the latest summary
ls -lt ~/.gtbi/logs/install_summary_*.json | head -1

# Parse summary JSON
jq . ~/.gtbi/logs/install_summary_*.json | head -1

# Get failed phase (if any)
jq '.failure // "No failure"' ~/.gtbi/logs/install_summary_*.json | tail -1

# Get phase timings
jq '.phases[] | "\(.id): \(.duration_seconds)s"' ~/.gtbi/logs/install_summary_*.json | tail -1
```

**Sharing logs for support:**

```bash
# Create a support bundle (strips sensitive data)
gtbi support-bundle > support-bundle.txt

# Or manually share (review for secrets first):
cat ~/.gtbi/logs/install-*.log | tail -200  # Last 200 lines
cat ~/.gtbi/logs/install_summary_*.json | tail -1  # Latest summary
```

### Support Bundle Command

The `gtbi support-bundle` command collects all diagnostic data into a single archive for troubleshooting.

**Usage:**
```bash
gtbi support-bundle [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--verbose, -v` | Show detailed output during collection |
| `--output, -o DIR` | Output directory (default: `~/.gtbi/support`) |
| `--no-redact` | Disable secret redaction (WARNING: bundle may contain secrets) |
| `--help, -h` | Show help |

**Output files:**
```
~/.gtbi/support/<timestamp>/          # Unpacked bundle directory
~/.gtbi/support/<timestamp>.tar.gz    # Compressed archive (shareable)
~/.gtbi/support/<timestamp>/manifest.json  # Bundle manifest
```

**What's collected:**

| File | Description |
|------|-------------|
| `state.json` | Installation state and checkpoints |
| `VERSION` | GTBI version |
| `checksums.yaml` | Upstream verification checksums |
| `logs/install-*.log` | Recent install logs (up to 10) |
| `logs/install_summary_*.json` | Recent install summaries |
| `doctor.json` | Health check results |
| `versions.json` | Installed tool versions |
| `environment.json` | OS, memory, disk, user info |
| `os-release` | Linux distribution info |
| `journal-gtbi.log` | Systemd journal for GTBI services |
| `config/.zshrc` | Shell configuration |

**Security & Redaction:**

By default, sensitive data is automatically redacted:

| Pattern | Example | Redacted To |
|---------|---------|-------------|
| OpenAI API keys | `sk-abc123...` | `<REDACTED:api_key>` |
| AWS keys | `AKIAIOSFODNN...` | `<REDACTED:aws_key>` |
| GitHub tokens | `ghp_xxxx...` | `<REDACTED:github_token>` |
| Vault tokens | `hvs.xxxx...` | `<REDACTED:vault_token>` |
| Slack tokens | `xoxb-xxxx...` | `<REDACTED:slack_token>` |
| Bearer tokens | `Bearer xxx...` | `Bearer <REDACTED:bearer>` |
| JWTs | `eyJhbGc...` | `<REDACTED:jwt>` |
| Passwords | `"password": "..."` | `"password": "<REDACTED:password>"` |
| Private key blocks | `-----BEGIN ... PRIVATE KEY-----` | `<REDACTED:private_key>` |

Before launching a large agent swarm or sharing a support bundle, run a local credential preflight:

```bash
gtbi credential-preflight --json
```

The preflight scans bounded GTBI state/log files plus shell config/history surfaces and reports only categories, counts, file labels, and remediation guidance. It never prints raw secret values or snippets.

**Example workflow:**

```bash
# Create support bundle
gtbi support-bundle

# Output: ~/.gtbi/support/20260127_120000.tar.gz

# Share the archive when filing an issue
# The archive is safe to share (secrets redacted)
```

**Disable redaction (use with caution):**
```bash
# WARNING: Bundle may contain API keys, tokens, and passwords
gtbi support-bundle --no-redact
```

**When to use:**
- Installation failed and you need to share logs
- Filing a GitHub issue about GTBI
- Diagnosing tool installation problems
- Sharing system state with support

### Shell Not Changing to zsh

**Symptom**: Still seeing bash prompt after install.

**Solutions**:

1. **Log out and back in** (the change happens at next login)

2. **Manually set shell**:
   ```bash
   chsh -s $(which zsh)
   # Then log out and back in
   ```

3. **Check shell was installed**:
   ```bash
   which zsh  # Should show /usr/bin/zsh
   cat /etc/shells  # zsh should be listed
   ```

### Agent Authentication Issues

Start with the safe readiness report:

```bash
bash scripts/agent-readiness-audit.sh --json
```

**Claude Code**:
```bash
# Check auth status
claude --version
ls -la ~/.claude/  # or ~/.config/claude/

# Re-authenticate
claude  # Follow prompts, then use /login inside Claude Code to switch accounts
```

**Codex CLI**:
```bash
# Check auth status
codex --version

# Re-authenticate (uses ChatGPT account, not API key)
codex  # Follow first-run sign-in prompts
```

**Gemini CLI**:
```bash
# Check auth status
gemini --version

# Re-authenticate
gemini  # Follow Google login flow, or use /auth inside Gemini CLI
```

### "Command Not Found" After Install

**Symptom**: `claude: command not found` even though install succeeded.

**Solutions**:

1. **Reload shell config**:
   ```bash
   source ~/.zshrc
   # Or start a new shell
   exec zsh
   ```

2. **Check PATH**:
   ```bash
   echo $PATH | tr ':' '\n' | grep -E "(bun|local|cargo)"
   # Should include: ~/.bun/bin, ~/.local/bin, ~/.cargo/bin
   ```

3. **Manual path fix**:
   ```bash
   export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
   ```

### Doctor Shows Missing Tools

**Symptom**: `gtbi doctor` shows failed checks for tools you expected to be installed.

**Understanding doctor output:**

Doctor checks are generated directly from the manifest, so they verify the exact same tools the installer provides. When a check fails, doctor shows a copy-pasteable fix command:

```
  ✗ tools.lazygit - Lazygit terminal UI not found
    Fix: gtbi install --only tools.lazygit
```

**Solutions**:

1. **Re-run the specific module** (use the fix suggestion):
   ```bash
   gtbi install --only tools.lazygit   # Install just that tool
   gtbi install --only lang.go         # Install a language runtime
   gtbi install --only stack.bd        # Install a stack tool
   ```

2. **Re-run an entire phase** (for multiple failures in one category):
   ```bash
   gtbi install --only-phase 5       # Re-run CLI tools
   gtbi install --only-phase 9       # Re-run the agent stack
   ```

3. **Run auto-fix mode** (applies safe, deterministic fixes):
   ```bash
   gtbi doctor --fix
   gtbi doctor --fix --dry-run  # Preview fixes first
   ```

**Note**: Doctor checks match the manifest verify commands exactly. If a tool was skipped during installation (e.g., using `--mode safe`), the check will fail. This is expected—run `gtbi doctor` to see which tools are missing and decide which to install.

### Tmux Configuration Errors

**Symptom**: Tmux won't start or shows config errors.

**Solutions**:

1. **Check syntax**:
   ```bash
   tmux source-file ~/.tmux.conf
   # Will show line number of any errors
   ```

2. **Reset to GTBI defaults**:
   ```bash
   cp ~/.gtbi/tmux/tmux.conf ~/.tmux.conf
   ```

3. **Version mismatch** (old tmux, new config):
   ```bash
   tmux -V  # Check version
   # GTBI config requires tmux 3.0+
   ```

### Stack Tools Not Working

**Symptom**: `dolt`, `bd` (beads), or `gt` (Gastown) not found or erroring.

**Solutions**:

1. **Reinstall the stack**:
   ```bash
   gtbi update --stack --force
   ```

2. **Check the binaries are present and on PATH**:
   ```bash
   command -v dolt bd gt
   ls ~/.local/bin/  # bd and gt typically install here
   ```

3. **Confirm beads can reach its Dolt database**:
   ```bash
   bd ready          # Should list ready work, not a DB error
   ```

### Complete Reset

When all else fails, the nuclear option:

```bash
# Save any important files first!

# Backup GTBI state (recommended)
ts="$(date +%Y%m%d_%H%M%S)"
[ -d ~/.gtbi ] && mv ~/.gtbi ~/.gtbi.backup."$ts"

# Backup installed configs (optional)
for f in ~/.zshrc ~/.tmux.conf ~/.p10k.zsh; do
  [ -f "$f" ] && mv "$f" "$f".backup."$ts"
done

curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe --force-reinstall
```

---

## Security Threat Model

GTBI takes security seriously while acknowledging the inherent risks of `curl | bash` installation. This section documents our threat model and mitigations.

### What We Protect Against

| Threat | Mitigation |
|--------|------------|
| **Man-in-the-middle (MITM)** | HTTPS enforcement for all downloads |
| **Compromised upstream scripts** | SHA256 checksum verification |
| **Malicious package injection** | Official package sources only (apt, cargo, bun) |
| **Credential exposure** | No credentials stored in scripts or configs |
| **Privilege escalation** | Minimal sudo usage, explicit permission grants |
| **Persistent backdoors** | Ephemeral VPS model; start fresh if concerned |

### What We Don't Protect Against

| Threat | Why Not | Mitigation |
|--------|---------|------------|
| **Compromised GitHub** | Would require GitHub-level breach | Use release tags, verify commits |
| **Compromised upstream maintainers** | Can't verify humans | Trust + checksum verification |
| **Zero-day in installed tools** | Beyond our control | Keep tools updated, follow CVEs |
| **Physical VPS access** | Provider responsibility | Choose reputable providers |
| **Vibe mode abuse** | By design for throwaway VPS | Use safe mode on important systems |

### The `curl | bash` Debate

The `curl | bash` pattern is controversial. Critics argue:
- You're executing arbitrary code from the internet
- The download could be swapped mid-stream
- You can't audit before executing

Our response:
1. **HTTPS** prevents mid-stream swapping
2. **Checksums** verify content matches known-good versions
3. **Ephemeral environments** limit blast radius
4. **Open source** allows pre-audit of install.sh

For maximum security, you can:
```bash
curl -fsSL "https://..." -o install.sh
less install.sh
bash install.sh --yes --mode vibe
```

### Checksum Verification Deep Dive

Every upstream installer we fetch is verified against known-good checksums:

```yaml
# checksums.yaml excerpt
installers:
  bun:
    url: "https://bun.sh/install"
    sha256: "a1b2c3d4e5f6..."
    last_verified: "2024-12-15"
    notes: "Official Bun installer"
```

The verification process:

```
1. Download script to memory (not disk)
2. Calculate SHA256 of downloaded bytes
3. Compare against stored checksum
4. If match: execute
5. If mismatch: abort with warning
```

A mismatch could mean:
- Upstream released a new version (common, usually safe)
- Upstream was compromised (rare, investigate before updating)

Our update process:
1. Monitor upstream releases
2. Review changes in new installer versions
3. Update checksums only after manual review
4. Commit with descriptive message explaining what changed

### Vibe Mode Security Implications

Vibe mode (`--mode vibe`) enables:
- Passwordless sudo for ubuntu user
- `--dangerously-skip-permissions` for Claude
- `--dangerously-bypass-approvals-and-sandbox` for Codex
- `--yolo` for Gemini

This is **intentionally insecure for velocity**. Use only on:
- Throwaway VPS you don't care about
- Non-production environments
- Personal experimentation

Never on:
- Production servers
- Shared team infrastructure
- Systems with sensitive data
- Long-running servers

---

## Comparison to Alternatives

How does GTBI compare to other ways of setting up a development environment?

### vs. Manual Setup

| Aspect | Manual | GTBI |
|--------|--------|------|
| Time | 3-7 hours | 30 minutes |
| Consistency | Varies | Identical every time |
| Documentation | Your memory | This README |
| Resume on failure | Start over | Automatic |
| Updates | Manual each tool | `gtbi update` |

**When to use manual**: When you need to understand every detail, or have highly specific requirements.

### vs. Dotfiles Repos

| Aspect | Dotfiles | GTBI |
|--------|----------|------|
| Scope | Configs only | Full tool installation |
| Portability | Mac/Linux | Ubuntu-focused |
| Maintenance | DIY | Maintained project |
| Agent focus | None | Core feature |

**When to use dotfiles**: When you already have tools installed and just want configs.

### vs. Nix/NixOS

| Aspect | Nix | GTBI |
|--------|-----|------|
| Reproducibility | Perfect | Good |
| Learning curve | Steep | Gentle |
| Rollback | Native | Manual |
| Complexity | High | Low |
| Adoption | Growing | Easy |

**When to use Nix**: When you need perfect reproducibility and are willing to invest in learning Nix.

### vs. DevContainers

| Aspect | DevContainers | GTBI |
|--------|--------------|------|
| Isolation | Container | Full VPS |
| Resource overhead | Container runtime | None |
| IDE integration | VSCode-centric | Terminal-native |
| Agent experience | Limited | Native |

**When to use DevContainers**: When you want isolated project environments within an existing machine.

### vs. Ansible/Terraform

| Aspect | Ansible/TF | GTBI |
|--------|------------|------|
| Scope | Infrastructure | Development env |
| Complexity | High | Low |
| Audience | DevOps | Developers |
| Learning curve | Steep | Gentle |

**When to use Ansible/Terraform**: When you're managing fleets of servers, not individual dev environments.

### The GTBI Sweet Spot

GTBI is optimal when you need:
- **Fast setup** of a complete agentic coding environment
- **Fresh Ubuntu VPS** as your target
- **AI coding agents** as primary tools
- **Throwaway/ephemeral** infrastructure mindset
- **Minimal configuration** to get started

---

## The Agent Stack Philosophy

The agent stack in GTBI is deliberately small: **Dolt**, **beads**, and **Gastown**. Each layer addresses a problem that surfaces when multiple AI coding agents work on the same project.

### The Problems

Running multiple AI coding agents simultaneously surfaces problems that don't exist with single-agent or no-agent development:

1. **No task visibility**: Hard to see what each agent is working on
2. **Duplicated work**: Agents solve the same problem independently
3. **Hidden dependencies**: Blockers between tasks aren't recorded anywhere shared
4. **Ephemeral state**: Task state lives in someone's head, not in version control
5. **No orchestration**: Spawning and supervising agents against ready work is manual

### The Solutions

Each layer of the stack addresses specific problems:

| Tool | Problem Solved | Philosophy |
|------|----------------|------------|
| **Dolt** | Ephemeral state | A version-controlled SQL database — task state is branchable and diffable |
| **beads** (`bd`) | No task visibility + hidden dependencies | A Dolt-backed issue graph every agent reads and writes |
| **Gastown** (`gt`) | No orchestration | Drives multi-agent runs against ready work in the beads graph |

### The Synergy Effect

The layers are designed to work together:

```
Dolt stores task state in a version-controlled database →
beads exposes it as a dependency-aware issue graph →
Gastown spawns and supervises agents against ready work →
agents claim, update, and unblock issues that every other agent can see
```

No single layer is transformative alone. Together they enable workflows that would otherwise be fragile:

- **Multiple agents working in parallel** against a shared, consistent task graph
- **Auditable history** of task state via Dolt commits
- **Coordination** without manual intervention
- **Context recovery** across sessions and disconnects

### Design Principles of the Stack

1. **Unix Philosophy**: Each tool does one thing well
2. **Local-first**: State lives on the box, synced via git, not a SaaS
3. **Terminal-First**: TUI/CLI over GUI, speed over polish
4. **Agent-Native**: Built for AI, not adapted for AI
5. **Git-Friendly**: All state is auditable in version control

---

## Advanced Configuration

GTBI supports various configuration mechanisms for advanced users.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GTBI_HOME` | `~/.gtbi` | Configuration directory |
| `GTBI_REF` | `main` | Git ref to install from (tag, branch, or commit SHA) |
| `GTBI_CHECKSUMS_REF` | `main` (when pinned) / `GTBI_REF` (when branch) | Ref used to fetch `checksums.yaml` |
| `GTBI_LOG_DIR` | `/var/log/gtbi` | Log directory |
| `TARGET_USER` | `ubuntu` | User to configure |
| `TARGET_HOME` | Resolved from `TARGET_USER` | User home directory (or explicit override) |

**Examples:**
```bash
# Install from a tagged release (recommended for production)
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/v0.1.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.1.0

# Install from a specific branch (development/testing)
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/feature/new-tool/install.sh" | bash -s -- --yes --mode vibe --ref feature/new-tool

# Install from a specific commit (reproducibility)
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/abc1234/install.sh" | bash -s -- --yes --mode vibe --ref abc1234

# Pin installer version but use latest checksums (avoid stale hash mismatches)
curl -fsSL "https://raw.githubusercontent.com/jonbackhaus/gtbi/v0.5.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.5.0 --checksums-ref main
```

> **Tip:** Always match the URL path with `--ref` so the initial script and all subsequently fetched scripts come from the same ref. If you use environment variables in a pipeline, attach them to `bash`, not `curl`: `curl ... | GTBI_REF=v0.5.0 bash -s -- --yes --mode vibe`.
> **Tip:** For pinned installs (tags/SHAs), checksums default to `main` to avoid stale installer hashes. Override with `GTBI_CHECKSUMS_REF` if you want checksums pinned to the same ref.

### Complete Installer CLI Options

The installer supports extensive command-line customization:

**Execution Control:**
```bash
--yes, -y              # Skip all prompts (non-interactive)
--dry-run              # Simulate without making changes
--print                # Print what would be installed
--mode vibe|safe       # Installation mode (default: vibe)
--interactive          # Force interactive mode with prompts
--strict               # Abort on any error (vs. continue with warnings)
--ref <ref>            # Git ref to install from (branch, tag, or commit SHA)
--checksums-ref <ref>  # Fetch checksums.yaml from this ref (default: main for pinned tags/SHAs)
```

**Resume & State:**
```bash
--resume               # Resume from last checkpoint
--force-reinstall      # Ignore state, reinstall everything
--reset-state          # Clear state.json and start fresh
```

**Ubuntu Upgrade:**
```bash
--skip-ubuntu-upgrade           # Don't upgrade Ubuntu version
--target-ubuntu=25.10           # Specify target Ubuntu version
--target-ubuntu 25.04           # Alternative syntax
```

**Skip Flags:**
```bash
--skip-postgres        # Skip PostgreSQL 18
--skip-vault           # Skip HashiCorp Vault
--skip-cloud           # Skip Wrangler, Supabase, Vercel CLIs
--skip-preflight       # Skip pre-flight validation
```

### Module Selection

Fine-grained control over what gets installed using manifest-driven selection:

```bash
--list-modules           # List available modules
--print-plan             # Show execution plan without running
--only <module>          # Only run specific module(s)
--only-phase <phase>     # Only run modules in a phase
--skip <module>          # Skip specific module(s)
--no-deps                # Don't auto-include dependencies (⚠️ advanced)
```

**Key behaviors:**
- **Dependency closure:** `--only` automatically includes required dependencies (safe by default)
- **Skip safety:** `--skip` fails early if it would break a required dependency chain
- **Deterministic:** `--print-plan` shows exactly what will run, in what order

**Examples:**
Only install agents (plus their dependencies):

```bash
curl -fsSL "..." | bash -s -- --yes --only-phase agents
```

Skip PostgreSQL and Vault:

```bash
curl -fsSL "..." | bash -s -- --yes --skip db.postgres18 --skip tools.vault
```

Preview what would run without executing:

```bash
curl -fsSL "..." | bash -s -- --print-plan
```

> **Note:** Using `--no-deps` bypasses safety checks and may result in broken installs. Only use if you've already installed dependencies separately.

### Custom Post-Install Hooks

Add custom steps by placing scripts in `~/.gtbi/hooks/`:

```bash
mkdir -p ~/.gtbi/hooks
cat > ~/.gtbi/hooks/post-install.sh << 'EOF'
#!/bin/bash
# Custom post-install steps
echo "Running custom configuration..."
# Your commands here
EOF
chmod +x ~/.gtbi/hooks/post-install.sh
```

GTBI will execute `post-install.sh` after the main installation completes.

### Override Tool Versions

To pin specific tool versions, set environment variables:

```bash
export BUN_VERSION="1.1.0"
export UV_VERSION="0.5.0"
# Then run installer
```

Note: Not all tools support version pinning. Check individual tool documentation.

---

## Future Roadmap

GTBI is actively developed. Here's what's coming:

### Near-Term (Q1 2025)

- [ ] **Full manifest-driven execution**: install.sh consumes generated scripts
- [x] **Tailscale integration**: Zero-config VPN for secure remote access ✓
- [x] **Services setup wizard**: Guide users through service account setup (`gtbi services-setup`) ✓
- [ ] **Interactive module selection**: Choose what to install via TUI

### Mid-Term (Q2 2025)

- [ ] **ARM64 optimization**: Native Apple Silicon and ARM VPS support
- [ ] **Offline mode**: Pre-downloaded package bundles
- [ ] **Team mode**: Shared configurations across team members
- [ ] **Plugin system**: Third-party tool integrations

### Long-Term (2025+)

- [ ] **GTBI Cloud**: Managed VPS provisioning + GTBI install in one click
- [ ] **IDE integrations**: VSCode/Cursor extensions for remote GTBI management
- [ ] **Agent marketplace**: Pre-configured agent personalities and workflows
- [ ] **Enterprise features**: SSO, audit logging, compliance

---

## Performance Benchmarks

Installation times vary by VPS provider and network conditions. Here are typical benchmarks:

### Installation Time by Phase

| Phase | Typical Duration | Notes |
|-------|-----------------|-------|
| User Setup | 10-15s | Fast, mostly checks |
| Filesystem | 5-10s | Creating directories |
| Shell Setup | 2-4 min | Oh-My-Zsh clone is slow |
| CLI Tools | 3-5 min | Many apt packages |
| Languages | 3-5 min | Rust compile takes longest |
| Agents | 1-2 min | Fast bun installs |
| Agent Stack | 1-2 min | Dolt, beads, Gastown installers |
| Finalize | 30-60s | Config deployment |
| **Total** | **15-25 min** | **Typical full install** |

### Factors Affecting Speed

| Factor | Impact | Optimization |
|--------|--------|--------------|
| Network latency | High | Choose VPS close to package mirrors |
| Disk I/O | Medium | SSD/NVMe preferred |
| CPU cores | Medium | More cores = faster compilation |
| RAM | Low | 4GB is sufficient |
| Provider | Variable | OVH and Contabo offer excellent value |

### Resume Performance

Resuming from checkpoint is fast because completed phases are skipped:

```
Full install:     20 minutes
Resume from 50%:  10 minutes
Resume from 90%:  2 minutes
```

---

## License

MIT License (with OpenAI/Anthropic Rider). See [LICENSE](LICENSE) for details.

---

## Links

- **GitHub:** [jonbackhaus/gtbi](https://github.com/jonbackhaus/gtbi)
- **Upstream (ACFS):** [Dicklesworthstone/gastown_batteries_included](https://github.com/Dicklesworthstone/gastown_batteries_included)
- **Agent Stack:**
  - [Dolt](https://github.com/dolthub/dolt) - Version-controlled SQL database
  - [beads](https://github.com/gastownhall/beads) - Dolt-backed local-first issue tracker

---

## Acknowledgements

GTBI is a fork of [ACFS (Agentic Coding Flywheel Setup)](https://github.com/Dicklesworthstone/gastown_batteries_included), created by **Jeffrey Emanuel** ([@Dicklesworthstone](https://github.com/Dicklesworthstone) · [X/Twitter](https://x.com/doodlestein)).

A sincere thank you to Jeff for the original ACFS project — the installer architecture, the manifest-driven generation system, the Dicklesworthstone coordination stack, and the overall philosophy that makes agentic coding practical. This fork would not exist without his work, and the vast majority of the code here originated with him.

---

<div align="center">
  <sub>Forked from <a href="https://github.com/Dicklesworthstone/gastown_batteries_included">ACFS</a> by <a href="https://github.com/jonbackhaus">Jon Backhaus</a>. Original work by <a href="https://github.com/Dicklesworthstone">Jeffrey Emanuel (@Dicklesworthstone)</a>.</sub>
</div>
