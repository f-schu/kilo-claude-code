Title: Local Hooks and CLI Integration (ApogeeMind, DuckDB)

Purpose
- Wire the local memory system (apogeemind) into Claude Code using shell hooks and tiny Python CLIs.
- No external APIs. All storage is local DuckDB.

Overview
- Scripts
  - scripts/apogeemind_inject.py — prints a <system-reminder> block with relevant memories for a given query.
  - scripts/apogeemind_record.py — records the most recent user/assistant exchange.
- Hooks
- hooks/apogeemind-inject.sh — UserPromptSubmit: extracts the current user prompt and prints the system block via the injector.
- hooks/apogeemind-record.sh — Post-response: extracts last user/assistant texts and records them.

Environment Variables (optional)
- APOGEEMIND_DUCKDB_PATH — DB location (default: ./apogeemind/apogeemind.duckdb within the project)
- APOGEEMIND_NAMESPACE — Logical namespace (default: code:<repo-dir>)
- APOGEEMIND_CONSCIOUS — Enable initial promotion / working memory (default: true)
- APOGEEMIND_AUTO — Enable per-query retrieval (default: true)
- APOGEEMIND_MODEL — Free-text model label stored in chat_history (default: claude-code)

Install & Register
1) Ensure jq and python3 are available.
2) Make hooks executable:
   - chmod +x hooks/apogeemind-inject.sh hooks/apogeemind-record.sh
3) In Claude Code hooks UI, add:
   - UserPromptSubmit: hooks/apogeemind-inject.sh
   - Post-response (or closest): hooks/apogeemind-record.sh

Behavior
- On user prompt, `apogeemind-inject.sh` parses the pending text and calls `scripts/apogeemind_inject.py`.
  - The script prints a `<system-reminder>…</system-reminder>` block that Claude Code appends to the context.
- After the assistant responds, `apogeemind-record.sh` parses the transcript’s last user/assistant texts and calls `scripts/apogeemind_record.py` to store them and update memories.
- Both hooks set `APOGEEMIND_DUCKDB_PATH` to `./apogeemind/apogeemind.duckdb` (per project) if not already set, and will create/initialize the DB on first run.

Validation & Troubleshooting
- Quick run (outside of hooks):
  - python3 scripts/apogeemind_record.py --user "I prefer ruff" --assistant "Implemented ruff config"
  - python3 scripts/apogeemind_inject.py --query "python tests"
    - Should print a system-reminder block with relevant items.
- If DuckDB FTS isn’t available, the system uses LIKE fallback automatically.
- If you see `ModuleNotFoundError: apogeemind`, ensure you’re using the hooks from this repo; the scripts add the repo root to `PYTHONPATH` at runtime for reliability.
- To reset locally, remove ./memori/memori.duckdb (this clears all data for the project).

Security / Privacy
- Data is local. Consider adding redaction (Phase 3) to strip secrets before writing.

Notes
- Namespacing allows per-repo or per-project isolation (default: code:<repo-dir>).
- Conscious (working memory) keeps essential facts readily available; Auto adds per‑query dynamic retrieval.
