"""
memori_local: A self-contained, API-free memory layer using DuckDB.

Modules:
- db.duckdb_manager: DB access, schema, FTS adapter
- processing.heuristics: deterministic processing (summary, classification, scoring)
- retrieval.retrieval_engine: context retrieval across STM/LTM with re-ranking
- agents.conscious_agent: promotion of long-term items to short-term
- utils.context_builder: bounded system block formatting
- store.memory_store: thin orchestration over the components
"""

__all__ = [
    "__version__",
]

__version__ = "0.1.0"

