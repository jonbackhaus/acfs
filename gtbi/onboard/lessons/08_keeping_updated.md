# Keeping Everything Updated

**Goal:** Learn how to keep your GTBI tools current.

---

## Why Updates Matter

Your VPS has 30+ tools installed. Each one gets improvements:
- Bug fixes and security patches
- New features and capabilities
- Better performance

Keeping things updated means:
- Fewer mysterious errors
- Better security
- Access to new agent features

---

## The Update Command

GTBI provides a single command to update everything:

```bash
gtbi-update
```

That's it! This updates:
- System packages (apt)
- Shell tools (OMZ, P10K, plugins)
- Coding agents (Claude, Codex, Gemini, OpenCode)
- Language runtimes (Bun, Rust, uv)
- Gastown stack tools (dolt, bd, gt)

---

## Common Update Patterns

### Quick Agent Update

If you just want the latest agent versions:

```bash
gtbi-update --agents-only
```

### Skip System Packages

apt updates can be slow. Skip them when you're in a hurry:

```bash
gtbi-update --no-apt
```

### Preview Changes

See what would be updated without changing anything:

```bash
gtbi-update --dry-run
```

### GTBI Self-Update Safety

If your machine is running from a deployed `~/.gtbi` tree instead of a git checkout, GTBI now skips self-update by default to avoid overwriting local files. Routine tool updates still run normally.

If you want a fully safe preview on any machine:

```bash
gtbi-update --dry-run --no-self-update
```

If you intentionally want to convert a non-git install into a git checkout for future GTBI self-updates:

```bash
gtbi-update --bootstrap-self-update
```

---

## Automated Updates

For hands-off maintenance, use quiet mode:

```bash
gtbi-update --yes --quiet --no-self-update
```

This runs without prompts, only shows errors, and leaves the GTBI tree itself alone.

You can add this to a cron job for weekly updates:

```bash
# Edit crontab
crontab -e

# Add this line for weekly Sunday 3am updates
0 3 * * 0 $HOME/.local/bin/gtbi-update --yes --quiet --no-self-update >> $HOME/.gtbi/logs/cron-update.log 2>&1
```

---

## Checking Update Logs

Every update is logged:

```bash
# List recent logs
ls -lt ~/.gtbi/logs/updates/ | head -5

# View the most recent log
cat ~/.gtbi/logs/updates/$(ls -1t ~/.gtbi/logs/updates | head -1)

# Watch a running update
tail -f ~/.gtbi/logs/updates/$(ls -1t ~/.gtbi/logs/updates | head -1)
```

---

## Troubleshooting

### apt is locked

If you see "apt is locked by another process":

```bash
# See which process is holding the lock
sudo fuser -v /var/lib/dpkg/lock-frontend || true

# Wait for other apt operations to finish, then repair interrupted packages
sudo dpkg --configure -a
```

### Agent update failed

Try updating directly:

```bash
# Claude
claude update --channel latest

# Codex
bun install -g --trust @openai/codex@latest

# Gemini
bun install -g --trust @google/gemini-cli@latest
```

### Shell tools won't update

Check git remote access:

```bash
git -C ~/.oh-my-zsh remote -v
```

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `gtbi-update` | Update everything, including stack tools |
| `gtbi-update --agents-only` | Just update agents |
| `gtbi-update --no-apt` | Skip apt (faster) |
| `gtbi-update --dry-run` | Preview changes |
| `gtbi-update --yes --quiet --no-self-update` | Automated mode |
| `gtbi-update --bootstrap-self-update` | Opt into git bootstrap for GTBI self-update |
| `gtbi-update --help` | Full help |

---

## How Often to Update?

Recommendations:
- **Weekly**: Full update including stack
- **After issues**: If something breaks, update first
- **Before major work**: Get latest agent versions

---

## Next

Learn about the beads issue tracker:

```bash
onboard 16
```

---

*Tip: Run `gtbi-update --dry-run` right now to see what's out of date!*
