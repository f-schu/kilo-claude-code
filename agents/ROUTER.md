---
title: Agent Router
description: Quick decision guide to pick the right specialist agents and when to orchestrate multiple in parallel.
---

Purpose
- Help select the best agent(s) when a task is ambiguous
- Encourage parallelization and subagent contracts
- Standardize handoffs between agents

Routing Checklist
- Scope clarity: Is the task well-scoped? If not → project-planning-orchestrator
- Expertise needed: Domain/data/ML/visualization/infra/security?
- Parallelizable: ≥2 independent subtasks? Split across agents and define Subagent Contracts
- Evidence required: Benchmarks, tests, docs, or scientific validation?

Common Paths
- Plan first (complex/ambiguous): project-planning-orchestrator → produces Task Contract + Agent Allocation + Subagent Contracts
- Data/ML: ai-ml-innovation-advisor (approach) + benchmark-evaluator (metrics) + scientific-evidence-validator (claims)
- Visualization for publication: publication-dataviz-expert (figure spec/exports)
- Python implementation & repo hygiene: tidy-python-developer
- Security/privacy: security-privacy-auditor (secrets, SCA, SAST)
- CI/CD, releases, caches: devops-ci-cd-engineer
- Genomics + DuckDB: genomics-database-architect

Subagent Contracts (minimum)
- id, role, inputs → outputs, success criteria, return format (JSON)

Escalation
- Conflicts: project-planning-orchestrator arbitrates; document trade-offs and decision
- Missing evidence: benchmark-evaluator (performance) or scientific-evidence-validator (claims)

