Kilo Claude Code
================

![Repository Banner](assets/header.jpg)

![CI](https://github.com/f-schu/kilo-claude-code/actions/workflows/ci.yml/badge.svg)
![Security Scan](https://github.com/f-schu/kilo-claude-code/actions/workflows/security-scan.yml/badge.svg)
![Validate Agents](https://github.com/f-schu/kilo-claude-code/actions/workflows/validate-agents.yml/badge.svg)

This repository contains my Claude Code configuration, hooks, and agent instructions. It is designed to enforce high-quality workflows with explicit planning, subagent orchestration, and strong completion gates.

Key features
- Plan Guard: requires a Task Contract and Subagent Contracts for complex or strict-mode tasks.
- Completion Guard: re-runs lint/tests before stopping, logs evidence under `logs/YYYYMMDD/`, and can auto-comment/close GitHub issues.
- GitHub Issue Automation: optional integration via `gh` CLI to open, comment, and close issues for each task.
- Adaptive Repo Structure: prefer conventional layouts per ecosystem instead of forcing a single structure.

How to use
- Install GitHub CLI (`gh`) and authenticate (`gh auth login`) to enable issue automation.
- Place a toggle file `.claude/plan-guard.strict` to enforce planning on any write/edit.
- Environment variables:
  - `CLAUDE_PLAN_GUARD_ENFORCE=true|false` (default true)
  - `CLAUDE_PLAN_GUARD_BLOCK_COMPLEX=true|false` (default true)
  - `CLAUDE_GH_AUTO_CLOSE=true|false` (default true)

Privacy and safety
- Sensitive files (credentials, logs, local snapshots) are excluded via `.gitignore`.
- Review changes before pushing to GitHub.

License
Specify your preferred license here.
