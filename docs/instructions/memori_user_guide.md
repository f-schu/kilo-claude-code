Title: memori_local User Guide (Self‑Contained DuckDB Memory)

Overview
- memori_local provides a local memory layer similar to Memori without external APIs. It stores chats, derives structured long/short-term memory, and retrieves relevant context.

Install
- Requires Python 3.10+ and duckdb (`pip install duckdb`).
- Optional: jq for shell hooks.

Quick Start (Python)
```python
from memori_local.store.memory_store import MemoryStore, MemoryStoreConfig

store = MemoryStore(MemoryStoreConfig(db_path="~/.claude/memori/memori.duckdb", namespace="my-repo"))

chat_id = store.record_conversation(
    user_input="I prefer using ruff and black.",
    ai_output="Acknowledged. I'll adopt ruff+black.",
    model="claude-code",
)

print(store.get_conscious_system_prompt())
print(store.get_auto_ingest_system_prompt("python tests"))
```

Hooks Integration
- See: docs/instructions/memori_hooks_guide.md

Background Scheduler
```python
store.start_background_scheduler(interval_hours=6.0)
# ... later
store.stop_background_scheduler()
```

Admin Utilities
```python
# Clear history (namespace-wide or per session)
store.clear_conversation_history()
store.clear_conversation_history(session_id="...optional...")

# Clear STM/LTM
store.clear_memory()              # both
store.clear_memory("short_term")  # just STM
store.clear_memory("long_term")   # just LTM

# Export namespace
data = store.export_namespace(path="/tmp/memori_export.json")
```

Environment Vars
- MEMORI_DUCKDB_PATH (default: ~/.claude/memori/memori.duckdb)
- MEMORI_NAMESPACE (default: code:<repo-dir>)
- MEMORI_CONSCIOUS (default: true)
- MEMORI_AUTO (default: true)
- STM_CAPACITY (default: 20)
- PROMOTION_THRESHOLD (default: 0.65)

Tips
- Keep STM small (<=20) for fast prompt building.
- Prefer FTS enabled for faster retrievals; falls back to LIKE otherwise.
- Use namespaces per repo/workspace for clean isolation.
- Redaction is applied before storage; extend patterns if needed.

