# Beads (bd): Issue Tracking for AI Agents

**Goal:** Track tasks with dependencies using the `bd` command.

---

## What is beads?

beads (`bd`) is a local-first issue tracker built for AI agents, from gastownhall. Issues live in a local **Dolt** database under `.beads/`, and `.beads/issues.jsonl` is a passive export committed alongside your code so issues travel with the repo.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export.

**Key features:**
- Dolt-backed (version-controlled SQL database)
- Full dependency graph (blocks / blocked-by)
- Labels, priorities, comments, notes
- JSON output for agent consumption
- Persistent memory across sessions (`bd remember`)

> **Note:** `bd` is the command. IDs in a project look like `gtbi-xxx`.

---

## Get Oriented

Run this at the start of a session to load workflow context and project memories:

```bash
bd prime
```

---

## Essential Commands

### Find Ready Work (Unblocked Tasks)

```bash
bd ready
```

### List Open Issues

```bash
bd list --status=open
```

### View Issue Details

```bash
bd show gtbi-123
```

---

## Working with Issues

### Create an Issue

```bash
bd create --title="Add user authentication" --type=feature --priority=1
```

`--type` is one of `task`, `bug`, `feature` (and others); `--priority` is `0`-`4` (0 = highest).

### Claim Work

This atomically assigns the issue to you and sets it to in-progress:

```bash
bd update gtbi-123 --claim
```

### Add a Comment

```bash
bd comment gtbi-123 "Found the root cause - null check missing"
```

### Close an Issue

```bash
bd close gtbi-123 --reason="Fixed in PR #42"
```

---

## Managing Dependencies

Make one issue depend on another (it stays blocked until the dependency closes):

```bash
# gtbi-124 depends on gtbi-123
bd dep add gtbi-124 gtbi-123
```

`bd ready` automatically hides issues that are still blocked.

---

## Syncing

beads stores data in Dolt. Push and pull move issue history to and from your git remote:

```bash
bd dolt push    # publish your issue changes
bd dolt pull    # fetch everyone else's
```

---

## Persistent Memory

Store insights that survive across sessions (injected at `bd prime` time):

```bash
bd remember "auth module uses JWT not sessions"
bd memories            # list all memories
bd memories dolt       # search memories for "dolt"
```

Use `bd remember` instead of MEMORY.md files.

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `bd prime` | Load workflow context + memories |
| `bd ready` | Find unblocked tasks |
| `bd list --status=open` | List open issues |
| `bd show <id>` | View issue details |
| `bd create --title="..." --type=task --priority=N` | Create an issue |
| `bd update <id> --claim` | Claim work (assign + in-progress) |
| `bd close <id> --reason="..."` | Close with a reason |
| `bd dep add <issue> <depends-on>` | Add a dependency |
| `bd dolt push` / `bd dolt pull` | Sync issues with remote |
| `bd remember "..."` / `bd memories` | Persistent memory |

---

## Common Workflow

```bash
# 1. Find what to work on and claim it
bd ready
bd update gtbi-123 --claim

# 2. Do the work
# ...

# 3. Close when done, then sync
bd close gtbi-123 --reason="Implemented in this session"
bd dolt push
```

---

## Next

Learn about Dolt, the database that backs beads:

```bash
onboard 17
```

---

*Run `bd ready` to see available tasks in the current project!*
