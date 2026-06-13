# Dolt: The Database Behind Beads

**Goal:** Understand Dolt's role in GTBI — the version-controlled SQL database that backs `bd`.

---

## What is Dolt?

Dolt is a SQL database with **git-style version control built in** — branches, commits, diffs, and merges, but for your data instead of your files. Think "git for data."

In GTBI, you rarely call Dolt directly. It's installed because **beads (`bd`) stores all its issue data in Dolt** under the project's `.beads/` directory. When you run `bd create`, `bd close`, or `bd dolt push`, beads is talking to Dolt under the hood.

> **Note:** dolt requires root to install (it's a system binary), which is why GTBI installs it as part of the agent stack alongside `bd` and `gt`.

---

## Check It's Installed

```bash
dolt version
```

You should see a version string (the database engine that `bd` relies on).

---

## Where the Data Lives

Beads keeps its Dolt database inside the project:

```
.beads/                # Dolt database backing bd
.beads/issues.jsonl    # passive export, committed to git
```

The Dolt DB is the source of truth for issues. `.beads/issues.jsonl` is just a flat export so issues are visible in normal git diffs — do **not** hand-edit it.

---

## Sync = Git for Data

Because Dolt is version-controlled, beads can push and pull issue history to your git remote (on `refs/dolt/data`). You drive this through `bd`, not raw dolt:

```bash
bd dolt push    # publish issue changes
bd dolt pull    # fetch others' changes
```

This is how multiple agents share the same issue tracker without stepping on each other.

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `dolt version` | Confirm Dolt is installed |
| `bd dolt push` | Push beads issue data to remote |
| `bd dolt pull` | Pull beads issue data from remote |
| `bd dolt status` | Show the beads Dolt server status |

---

## Next

Learn about Gastown, the multi-agent orchestrator built on this stack:

```bash
onboard 18
```

---

*You usually let `bd` manage Dolt for you — but `dolt version` is a handy way to confirm the stack is healthy.*
