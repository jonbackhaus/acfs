# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Behavioral Rules

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## Definition of Done

Before closing any task:
1. All changes committed and pushed to remote
2. Unit tests pass
3. PR open with auto-merge + squash (`gh pr create` → `gh pr merge --auto --squash`)
4. GitHub CI passes
5. Beads issue closed only after PR merges to main

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS INTEGRATION -->


## Git Workflow

**MANDATORY:** Never commit directly to `main`. All work goes on a feature branch.

- **Feature branches**: `git checkout -b fix/<topic>` or `feat/<topic>` before any code changes
- **Worktrees for sub-agents**: Use `git worktree add` to give each sub-agent an isolated copy of the repo — prevents concurrent edits from colliding on the same working tree
- **Sub-agents: never `git checkout -b` against the shared checkout**: A worktree starts on its own `worktree-agent-*` branch. If a sub-agent `cd`s out of its worktree (a bare `cd` in a compound command can do this) and then runs `git checkout -b <branch>`, it switches the **shared/parent** checkout onto the new branch and commits there — contaminating the main working tree and leaving stale local branches. Sub-agents must stay inside their worktree dir and create the branch there (`git switch -c <branch>` from within the worktree), or target it explicitly with `git -C "$WORKTREE" switch -c <branch>`. Prefer `git -C "$WORKTREE" …` for all git ops; if a `git checkout -b` shows up in the shared tree, recover with `git checkout main`.
- **Worktree cleanup**: Remove worktrees after merging — `git worktree remove <path> && git branch -d <branch>`; or `git worktree prune` to clean up stale entries. Also delete the now-merged local branch (`git branch -D <branch>`) — squash-merged branches aren't recognized by `git branch -d` and otherwise pile up across a long session.
- **Commit often**: Small, atomic commits are easier to bisect and revert; don't batch unrelated changes
- **Push when complete**: Work is not done until `git push` succeeds (see Definition of Done above)
- **PRs for non-trivial changes**: Any code or script change → open a PR. Docs/CLAUDE.md-only edits may go direct to `main`.
- **Auto-merge**: After opening a PR, enable auto-merge so it merges when CI passes:
  ```bash
  gh pr create --title "..." --body "..."
  gh pr merge --auto --squash   # auto-merges when all CI checks pass
  ```

## Build & Test

```bash
# Generate scripts after any manifest or lib change
export PATH="$HOME/.bun/bin:$PATH"
bun run --cwd packages/manifest generate

# Manifest test baseline: 272 pass / 11 fail (pre-existing — category name assertions
# expecting 'db'/'cloud' that no longer match the manifest). Not regressions.

# Run Docker integration test (Ubuntu 25.10 greenfield install)
./tests/docker/run.sh install

# Test artifacts written to:
# tests/artifacts/install.log
```

## Architecture Overview

- `gtbi.manifest.yaml` — single source of truth: all install modules, phases, checksums
- `packages/manifest/` — TypeScript generator; `bun run generate` compiles manifest → shell scripts
- `scripts/generated/` — **do not edit directly**; always edit manifest and regenerate
- `scripts/lib/` — shared shell helpers (`install_helpers.sh`, `state.sh`, `security.sh`, etc.)
- `install.sh` — top-level orchestrator; calls generated phase scripts
- `checksums.yaml` — SHA256 of every external installer (uv, dolt, claude, bun, …)
- `tests/docker/` — hermetic Docker integration tests

## Version Bumps

`VERSION` is the single source of truth. When bumping the version, update all of these together:

1. `VERSION` — read by the generator
2. `install.sh` — `GTBI_VERSION=` hardcoded (can't read from file when curl-piped)
3. `package.json`, `packages/manifest/package.json` — npm workspace versions
4. `bun.lock` — run `bun install` so the lockfile's workspace `version` matches package.json (a stale lockfile makes every CI `bun install` dirty the tree)
5. Run `bun run generate` — regenerates scripts in `scripts/generated/`
6. Comment in `scripts/lib/update.sh` (line ~224) — example in comment only

After merging to main: `git tag v<version> && git push --tags`, then `gh release create`.

## Conventions & Patterns

- **Manifest → generate → scripts**: Any change to `gtbi.manifest.yaml` or `scripts/lib/*.sh` requires `bun run generate` before committing. Generated files live in `scripts/generated/`.
- **Checksums must stay fresh**: If an external installer URL serves new content, update `checksums.yaml` and rerun generate to update `internal_checksums.sh`.
- **`run_as` in manifest**: `target_user` runs as the ubuntu user; `root` runs as root. Installers that require root (e.g. dolt) must use `run_as: root`.
- **Docker-safe installs**: Avoid bare `systemctl enable/start` — use `|| true`; no systemd in Docker.
