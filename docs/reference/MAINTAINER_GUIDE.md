# GTBI Maintainer Guide

Internal reference for maintaining the GTBI installer and manifest.

## Manifest-Driven Architecture

GTBI uses a single source of truth pattern:

```
gtbi.manifest.yaml
       ↓
packages/manifest/src/generate.ts
       ↓
scripts/generated/
       ↓
install.sh (orchestrator)
```

The manifest defines what gets installed. The generator produces bash functions. The installer orchestrates execution.

## Adding a New Module

### 1. Add to gtbi.manifest.yaml

```yaml
modules:
  - id: category.toolname
    name: Tool Name
    category: category  # base, shell, cli, lang, tools, agents, db, cloud, stack, gtbi
    phase: 6            # Execution order (0-10)
    enabled_by_default: true  # Include in default install
    
    # Installation
    run_as: target_shell  # root, target, target_shell, current, current_shell
    install:
      - command1
      - command2
    
    # Verification (for gtbi doctor)
    installed_check: command -v toolname
    verify:
      - toolname --version
    
    # Optional
    optional: false       # If true, failure doesn't kill install
    dependencies:         # Module IDs that must run first
      - lang.bun
    tags:
      - dev-tools
```

### 2. Add Checksums (for external scripts)

If the module downloads scripts from external URLs, add checksums to `checksums.yaml`:

```yaml
scripts:
  https://example.com/install.sh: sha256:abc123...
```

Generate checksums:
```bash
curl -fsSL "https://example.com/install.sh" | sha256sum
```

### 3. Regenerate

```bash
cd packages/manifest
bun run generate
```

Or with the pre-commit hook:
```bash
./scripts/hooks/install.sh  # One-time hook setup
git add gtbi.manifest.yaml
git commit  # Hook auto-regenerates
```

### 4. Validate

```bash
# Check for drift
cd packages/manifest && bun run generate --diff

# Syntax check all scripts
bash -n scripts/generated/*.sh

# Run selection tests
bash scripts/lib/test_selection.sh

# Full integration test
./tests/vm/test_install_ubuntu.sh
```

## run_as Modes

| Mode | Description | Use When |
|------|-------------|----------|
| `root` | Runs as root user | System packages, apt installs |
| `target` | Runs as target user | User config, no shell needed |
| `target_shell` | Target user with login shell | Most tools (needs PATH) |
| `current` | Current user context | Bootstrap scripts |
| `current_shell` | Current user with shell | Debugging |

## Verified Installers

For security, external install scripts must be:
1. HTTPS only
2. SHA256 checksummed in `checksums.yaml`
3. Listed in `KNOWN_INSTALLERS` (scripts/lib/security.sh)

The installer verifies checksums before execution.

## Testing Changes

### Local Testing

```bash
# Quick syntax check
bash -n install.sh scripts/lib/*.sh scripts/generated/*.sh

# Unit tests
bash scripts/lib/test_selection.sh
bash scripts/lib/test_contract.sh
bash scripts/lib/test_security.sh
bash scripts/lib/test_install_helpers.sh

# Bootstrap simulation
bash tests/vm/bootstrap_offline_checks.sh
```

### Docker Integration

```bash
# Single Ubuntu version
./tests/vm/test_install_ubuntu.sh

# All supported versions
./tests/vm/test_install_ubuntu.sh --all

# Specific version
./tests/vm/test_install_ubuntu.sh --ubuntu 25.04
```

### CI Checks

PR checks include:
- ShellCheck lint
- Manifest drift detection
- Selection/contract tests
- Full Docker integration matrix

## Common Tasks

### Updating a Tool Version

1. Edit `gtbi.manifest.yaml` with new version
2. Update checksum if external script changed
3. Regenerate and test

### Adding a Skip Flag

Legacy skip flags are mapped in `scripts/lib/install_helpers.sh`:

```bash
if [[ "${SKIP_NEWTOOL:-false}" == "true" ]]; then
    SKIP_MODULES+=("category.newtool")
fi
```

### Debugging Selection

```bash
# Preview execution plan
./install.sh --print-plan

# List available modules
./install.sh --list-modules

# Test specific selection
./install.sh --only category.tool --print-plan
```

## Files Overview

| File | Purpose |
|------|---------|
| `gtbi.manifest.yaml` | Module definitions (source of truth) |
| `checksums.yaml` | SHA256 hashes for external scripts |
| `packages/manifest/` | TypeScript generator |
| `scripts/generated/` | Generated bash functions (don't edit) |
| `scripts/lib/` | Installer libraries |
| `install.sh` | Orchestrator (thin wrapper) |
