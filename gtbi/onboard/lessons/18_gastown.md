# Gastown (gt): Multi-Agent Orchestrator

**Goal:** Coordinate multiple AI coding agents with Gastown (`gt`).

---

## What is Gastown?

Gastown (`gt`) is a Go multi-agent orchestrator from gastownhall. It coordinates several AI coding agents working over **git-backed state**, so a team of agents can collaborate on the same work without colliding.

It builds on the rest of the agent stack you already have installed:
- **dolt** — version-controlled database (see lesson 17)
- **bd** (beads) — issue tracker the agents work from (see lesson 16)

---

## Setup

Install Gastown into a working directory and initialize it as a git-backed workspace:

```bash
gt install ~/gt --git
cd ~/gt
```

### Add a Repo (a "rig")

A **rig** is a repository Gastown manages agents for:

```bash
gt rig add <name> <repo-url>
```

### Attach the Mayor

The **mayor** is the coordinator process that supervises the agents:

```bash
gt mayor attach
```

---

## How It Fits Together

```
gt (mayor)            # coordinates agents
  └─ rigs             # the repos under management
       └─ agents      # Claude / Codex / etc. doing the work
            └─ bd     # issues they pick up (Dolt-backed)
```

Agents pull ready work from beads, do the work over git, and Gastown keeps the whole crew coordinated.

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `gt install ~/gt --git` | Install a git-backed Gastown workspace |
| `gt rig add <name> <repo-url>` | Register a repo for agents to work on |
| `gt mayor attach` | Attach the coordinator process |

---

## Next

You've finished the agent stack (beads → dolt → gastown). To start a new project wired up with this tooling:

```bash
onboard 20
```

---

*Tip: run `gt --help` to explore the full set of orchestration commands once Gastown is set up.*
