Kilo Claude Code
================

![Repository Banner](assets/header.jpg)

![CI](https://github.com/f-schu/kilo-claude-code/actions/workflows/ci.yml/badge.svg)
![Security Scan](https://github.com/f-schu/kilo-claude-code/actions/workflows/security-scan.yml/badge.svg)
![Validate Agents](https://github.com/f-schu/kilo-claude-code/actions/workflows/validate-agents.yml/badge.svg)

This repository contains my Claude Code configuration, hooks, and agent instructions. It is designed to enforce high-quality workflows with explicit planning, subagent orchestration, and strong completion gates.

Workflows
- CI: Lints hooks, runs ShellCheck (if available), validates agent Return Formats.
  Link: https://github.com/f-schu/kilo-claude-code/actions/workflows/ci.yml
- Security Scan: Runs gitleaks (secrets), dependency audits where manifests exist (pip-audit, npm audit, govulncheck, cargo audit).
  Link: https://github.com/f-schu/kilo-claude-code/actions/workflows/security-scan.yml
- Validate Agents: Ensures agent docs include valid Return Format JSON with required keys.
  Link: https://github.com/f-schu/kilo-claude-code/actions/workflows/validate-agents.yml

Key features
- Plan Guard: requires a Task Contract and Subagent Contracts for complex or strict-mode tasks.
- Completion Guard: re-runs lint/tests before stopping, logs evidence under `logs/YYYYMMDD/`, and can auto-comment/close GitHub issues.
- GitHub Issue Automation: optional integration via `gh` CLI to open, comment, and close issues for each task.
- Adaptive Repo Structure: prefer conventional layouts per ecosystem instead of forcing a single structure.

Overview diagram

```mermaid
flowchart LR
  subgraph IDE[Claude Code]
    U[User] -->|UserPromptSubmit| HookInject[hooks/memori-inject.sh]
    A[Assistant] -->|Post-Response| HookRecord[hooks/memori-record.sh]
  end

  HookInject -->|calls| PyInject[scripts/memori_local_inject.py]
  HookRecord -->|calls| PyRecord[scripts/memori_local_record.py]

  subgraph Local Memory (memori_local)
    PyInject --> Store[MemoryStore]
    PyRecord --> Store
    Store -->|record| Heur[HeuristicProcessor]
    Store -->|promote| CA[ConsciousAgent]
    Store -->|search| Ret[RetrievalEngine]
    Ret --> Ctx[ContextBuilder]
  end

  Ctx -->|system-reminder| IDE

  subgraph Storage
    DB[(DuckDB)]
  end

  Store <--> DB

  subgraph CI/CD
    CI1[CI: lint/tests]
    CI2[Security scan]
    CI3[Validate agents]
  end
```

Local memory (memori_local)
- Self-contained memory engine inspired by Memori, implemented locally with DuckDB — no external APIs.
- Stores conversations, derives structured long/short-term memory using deterministic heuristics, and builds bounded system prompts for context injection.
- Full‑text retrieval via DuckDB fts (with LIKE fallback), namespaces for per-repo isolation, basic schema versioning, and privacy redaction.

Components
- Code: `memori_local/` (DB manager, heuristics, retrieval, conscious agent, context builder, store)
- Hooks: `hooks/memori-inject.sh`, `hooks/memori-record.sh`
- CLIs: `scripts/memori_local_inject.py`, `scripts/memori_local_record.py`
- Benchmarks: `scripts/memori_local_bench.py`

Docs and usage
- Hooks + CLI guide: docs/instructions/memori_hooks_guide.md
- Implementation plan: docs/instructions/memori_implementation_plan.md
 - User guide: docs/instructions/memori_user_guide.md
 - API reference: docs/instructions/memori_api_reference.md
 - Performance & tuning: docs/instructions/memori_performance.md

Environment (optional)
- MEMORI_DUCKDB_PATH (default: ~/.claude/memori/memori.duckdb)
- MEMORI_NAMESPACE (default: code:<repo-dir>)
- MEMORI_CONSCIOUS (default: true)
- MEMORI_AUTO (default: true)
- STM_CAPACITY (default: 20)
- PROMOTION_THRESHOLD (default: 0.65)

Scripts
- scripts/memori_local_inject.py — prints <system-reminder> with relevant memories for a query
- scripts/memori_local_record.py — records the last user/assistant exchange

Hooks
- hooks/memori-inject.sh — UserPromptSubmit
- hooks/memori-record.sh — Post-response/record

How to use
- Install GitHub CLI (`gh`) and authenticate (`gh auth login`) to enable issue automation.
- Place a toggle file `.claude/plan-guard.strict` to enforce planning on any write/edit.
- Environment variables:
  - `CLAUDE_PLAN_GUARD_ENFORCE=true|false` (default true)
  - `CLAUDE_PLAN_GUARD_BLOCK_COMPLEX=true|false` (default true)
  - `CLAUDE_GH_AUTO_CLOSE=true|false` (default true)

Quick planning helper
- Generate a lightweight plan and set TTL for complex edits:
  ```bash
  make plan scope="Fix drop order for genome tables" \
            non_goals="no unrelated refactors" \
            constraints="prod data unaffected,time<30m" \
            acceptance="unit tests green,drop order correct" \
            ttl=45
  ```
  This writes `.claude/plan.json` and `.claude/plan-ttl-min`; plan-guard recognizes this fresh plan and allows complex edits for the TTL duration.

Privacy and safety
- Sensitive files (credentials, logs, local snapshots) are excluded via `.gitignore`.
- Review changes before pushing to GitHub.

License
Specify your preferred license here.

System setup
- Required
  - Python 3.10+ (for hooks), pipx or pip
  - GitHub CLI (`gh`) authenticated: `gh auth login`
  - ripgrep (`rg`) for fast search; hooks prefer it when present
  - jq for JSON parsing (used in guards and impact map validation)
- Recommended
  - fd (fast find), yq (YAML parsing), sd (simple sed)
  - gitleaks (secrets scan), pip-audit (Python deps), npm (Node audit), Go (govulncheck), Rust (cargo-audit)
  - Rich for pretty CLI output in validators: `pipx install rich` or `pip install rich`

Optional enhancements
- Rich-powered output: guards and validator use Rich for nicer summaries when installed; otherwise plain text
- Small-edit passthrough: set `CLAUDE_SMALL_EDIT_MAX_LINES` (default 10) or file `.claude/small-edit-max-lines`
- Plan/Completion overrides: see CLAUDE.md for label toggles and env/file-based overrides
- Policies: set plan guard policy via `CLAUDE_PLAN_GUARD_POLICY` or `.claude/plan-guard.policy` to one of `permissive|guided|strict` (default guided)
- Fresh plan recognition: place a short plan in `.claude/plan.json` (valid for `PLAN_TTL_MIN` minutes; default 45) to allow complex edits without blocking
