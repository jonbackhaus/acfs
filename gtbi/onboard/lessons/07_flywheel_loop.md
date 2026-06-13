# The Flywheel Loop

**Goal:** Understand how the pieces work together.

---

## The GTBI Flywheel

This isn't just a collection of tools. It's a **compounding loop**:

```
Plan (bd) --> Execute (your agent) --> Review & commit
   ^                                        |
   |                                        v
   +-------- Capture what you learned ------+
```

Each cycle makes the next one better.

---

## The Core Pieces

### Coding agents
**Commands:** `claude`, `codex`, `gemini`, `opencode`

These do the actual work. Pick the one you prefer (or switch between them) and
drive it from your project directory.

### Beads (`bd`) - Task Tracking
**Command:** `bd`

Plan work as issues, track dependencies, and see what's ready to pick up next.

```bash
bd ready              # See what's unblocked
bd close <id>         # Mark work done
```

Beads is backed by Dolt, so your issue history is versioned alongside your code.

### GTBI lifecycle
**Commands:** `gtbi`, `gtbi-update`, `gtbi doctor`

Scaffold projects, keep tools current, and check your environment is healthy.

---

## A Complete Workflow

Here's how a real session might look:

```bash
# 1. Plan your work
bd ready                       # See what's ready to work on

# 2. Start your agent in the project
cd /data/projects/myproject
claude                         # or codex / gemini / opencode

# 3. Build, review, and commit small and often

# 4. Close the task
bd close <task-id>
```

---

## The Flywheel Effect

With each cycle:
- **Beads** keeps the plan and history in one place
- **Small, frequent commits** keep the repo easy to reason about
- **Your agent** gets clearer context from the work that came before

This is why it's called a **flywheel** - it gets better the more you use it.

---

## Your First Real Task

You're ready! Here's how to start your first project:

```bash
# 1. Create project with GTBI (recommended!)
gtbi newproj my-first-project --interactive

# This creates:
# - /data/projects/my-first-project
# - Git repository initialized
# - Beads (bd) for task tracking
# - AGENTS.md with project guidance
# - Claude settings

# 2. Open it and start building!
cd /data/projects/my-first-project
claude
```

**Why `gtbi newproj`?** It sets up everything agents need to work effectively,
including AGENTS.md which tells them about your project conventions.

For more details, run:

```bash
onboard 20
```

---

## Getting Help

- **`gtbi doctor`** - Check everything is working
- **`onboard`** - Re-run this tutorial anytime

---

## Next

One final lesson: keeping everything updated.

```bash
onboard 8
```

Also recommended: learn how git works with multiple agents in `onboard 21`.

---

*Gastown Batteries Included - https://github.com/jonbackhaus/gtbi*
