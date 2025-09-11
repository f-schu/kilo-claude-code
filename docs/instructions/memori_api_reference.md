Title: memori_local API Reference

Overview
- This document summarizes the primary classes and methods in memori_local.

Config
- memori_local/config.py
  - Config.from_env(default_db?, default_namespace?) → Config
    - Reads MEMORI_* env vars and constructs a configuration dataclass.

DB Layer
- memori_local/db/duckdb_manager.py
  - DuckDBManager(db_path, auto_init_schema=True)
    - initialize_schema(): creates tables and runs migrations
    - enable_fts_or_fallback(): tries to enable FTS; sets fts_enabled flag
    - execute(sql, params?) → QueryResult
    - insert_chat(namespace, session_id, user_input, ai_output, model?, tokens_used?) → chat_id
    - insert_ltm(...), insert_stm(...)
    - find_ltm_duplicate(namespace, summary_norm, content_norm) → row|None
    - bump_ltm_access(memory_id)
    - prune_stm_by_capacity(namespace, capacity)
    - search_memories(namespace, query, limit) → list of STM+LTM rows (caller re-ranks)
    - delete_chat_history(namespace, session_id?) → count
    - delete_stm(namespace) → count; delete_ltm(namespace) → count
    - export_namespace(namespace) → dict

Processing
- memori_local/processing/heuristics.py
  - HeuristicProcessor(promotion_threshold=0.65)
    - process_conversation(user_input, ai_output) → [ProcessedMemory]
      - Determines category_primary, summary, entities/keywords, importance_score, promotion_eligible

Retrieval
- memori_local/retrieval/retrieval_engine.py
  - RetrievalEngine(db)
    - execute_search(namespace, query, limit=5) → RetrievalResult(items=[...])
      - Re-ranks STM first, then by importance and recency; deduplicates

Conscious Agent
- memori_local/agents/conscious_agent.py
  - ConsciousAgent(db, stm_capacity=20, promotion_threshold=0.65)
    - run_initial_promotion(namespace) → promoted_count
    - start_scheduler(namespace, interval_hours=6.0)
    - stop_scheduler()

Context Builder
- memori_local/utils/context_builder.py
  - ContextBuilder(max_chars=2000, line_max=240)
    - build_system_block(items, header_label="Relevant Memories", namespace="") → str

Redaction
- memori_local/utils/redaction.py
  - redact(text, extra_patterns=None, replacement="[REDACTED]") → text

Store (Facade)
- memori_local/store/memory_store.py
  - MemoryStore(MemoryStoreConfig | env)
    - record_conversation(user_input, ai_output, model=None, metadata=None) → chat_id
    - retrieve_context(query, limit=5) → [rows]
    - get_conscious_system_prompt() → str
    - get_auto_ingest_system_prompt(user_input) → str
    - start_background_scheduler(interval_hours=6.0), stop_background_scheduler()
    - clear_conversation_history(session_id=None) → count
    - clear_memory(memory_type=None|'short_term'|'long_term') → dict
    - export_namespace(path=None) → dict

