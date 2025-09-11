Title: Local Hooks and CLI Integration (Self‑Contained, DuckDB)

Purpose
- Wire the local memory system (memori_local) into Claude Code using shell hooks and tiny Python CLIs.
- No external APIs. All storage is local DuckDB.

Overview
- Scripts
  - scripts/memori_local_inject.py — prints a <system-reminder> block with relevant memories for a given query.
  - scripts/memori_local_record.py — records the most recent user/assistant exchange.
- Hooks
  - hooks/memori-inject.sh — UserPromptSubmit: extracts the current user prompt and prints the system block via the injector.
  - hooks/memori-record.sh — Post-response: extracts last user/assistant texts and records them.

Environment Variables (optional)
- MEMORI_DUCKDB_PATH — DB location (default: ./memori/memori.duckdb within the project)
- MEMORI_NAMESPACE — Logical namespace (default: code:<repo-dir>)
- MEMORI_CONSCIOUS — Enable initial promotion / working memory (default: true)
- MEMORI_AUTO — Enable per-query retrieval (default: true)
- MEMORI_MODEL — Free-text model label stored in chat_history (default: claude-code)

Install & Register
1) Ensure jq and python3 are available.
2) Make hooks executable:
   - chmod +x hooks/memori-inject.sh hooks/memori-record.sh
3) In Claude Code hooks UI, add:
   - UserPromptSubmit: hooks/memori-inject.sh
   - Post-response (or closest): hooks/memori-record.sh

Behavior
- On user prompt, `memori-inject.sh` parses the pending text and calls `scripts/memori_local_inject.py`.
  - The script prints a `<system-reminder>…</system-reminder>` block that Claude Code appends to the context.
- After the assistant responds, `memori-record.sh` parses the transcript’s last user/assistant texts and calls `scripts/memori_local_record.py` to store them and update memories.
- Both hooks set `MEMORI_DUCKDB_PATH` to `./memori/memori.duckdb` (per project) if not already set, and will create/initialize the DB on first run.

Validation & Troubleshooting
- Quick run (outside of hooks):
  - python3 scripts/memori_local_record.py --user "I prefer ruff" --assistant "Implemented ruff config"
  - python3 scripts/memori_local_inject.py --query "python tests"
    - Should print a system-reminder block with relevant items.
- If DuckDB FTS isn’t available, the system uses LIKE fallback automatically.
- If you see `ModuleNotFoundError: memori_local`, ensure you’re using the hooks from this repo; the scripts add the repo root to `PYTHONPATH` at runtime for reliability.
- To reset locally, remove ./memori/memori.duckdb (this clears all data for the project).

Security / Privacy
- Data is local. Consider adding redaction (Phase 3) to strip secrets before writing.

Notes
- Namespacing allows per-repo or per-project isolation (default: code:<repo-dir>).
- Conscious (working memory) keeps essential facts readily available; Auto adds per‑query dynamic retrieval.
