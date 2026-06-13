# Git Strategy for Multi-Agent Work

**Goal:** Understand how git works when multiple agents edit the same repo simultaneously.

---

## The Single-Branch Model

GTBI uses **one branch (`main`) with one worktree**. All agents commit directly to `main`.

This may surprise you if you're used to feature branches, but it's the right call when
dozens of agents work concurrently on the same repo.

---

## Why Not Branches or Worktrees?

Traditional git workflows assume humans working sequentially on isolated features.
Agent swarms break those assumptions:

**Branch-per-agent creates merge hell.** With 10+ agents making frequent commits,
merging N branches back to main produces cascading conflicts that waste more time
than they save.

**Worktrees add filesystem complexity.** Each worktree is a full checkout. With many
agents, disk usage multiplies and path confusion leads to cross-worktree edits that
corrupt state.

**Agents lose context across branches.** When an agent switches branches, its
in-context understanding of the codebase becomes stale. Single-branch means every
agent always sees the latest state.

**Logical conflicts survive textual merges.** Even when two changes don't conflict
at the text level, they can break semantics. A function signature change on one
branch and a new callsite on another will merge cleanly but fail to compile. On a
single branch, the second agent sees the signature change immediately and adapts.

---

## How Conflicts Are Prevented

Instead of branch isolation, GTBI relies on discipline that keeps every agent
working against the latest shared state:

**Coordinate before editing.** Agree on who owns which files before touching them,
so two agents don't edit the same file at once.

**Avoid destructive git commands.** Commands like `git reset --hard`,
`git checkout -- .`, and `git clean -fd` can wipe uncommitted work from other
agents. Don't run them on a shared repo.

**Pull, then commit small and often.** Frequent small commits against the latest
`main` keep the window for conflicts tiny.

---

## The Recommended Workflow

```
1. Pull latest          git pull --rebase
2. Edit and test        cargo test / bun test / go test
3. Commit immediately   git add <files> && git commit
4. Push                 git push
```

**Key principles:**

- **Commit early, commit often.** Small commits reduce the window for conflicts.
- **Push after every commit.** Unpushed commits are invisible to other agents.
- **Coordinate before editing.** Don't touch files another agent is already editing.
- **Pull before you start.** Always work against the latest `main`.

---

## What About Logical Conflicts?

The issue reporter correctly notes that avoiding textual merge conflicts doesn't
guarantee semantic correctness. GTBI addresses this with:

- **Frequent small commits** keep the delta small, reducing logical conflict surface
- **Compiler checks** (`cargo check`, `go vet`, `tsc`) run before every commit
- **Test suites** catch regressions immediately
- **Clear ownership** of files and interfaces keeps agents from stepping on each other

For projects where this isn't sufficient, consider:
- Splitting the repo into smaller, focused crates/packages
- Using workspace-level dependency management (Cargo workspaces, npm workspaces)
- Defining clear module boundaries with stable interfaces

---

## Quick Reference

| Mechanism | What It Does |
|-----------|-------------|
| Coordinate file ownership | Prevents two agents editing same files |
| Avoid destructive git | Protects other agents' uncommitted work |
| `git pull --rebase` | Stays current with other agents' work |
| Commit small and often | Shrinks the conflict window |

---

## AGENTS.md Sets the Rules

Each project's `AGENTS.md` file configures agent behavior, including:
- Branch policy (always `main`)
- Commit conventions
- File editing discipline
- How to handle unexpected changes from other agents

When you create a project with `gtbi newproj`, this is set up automatically.

---

*Gastown Batteries Included - https://github.com/jonbackhaus/gtbi*
