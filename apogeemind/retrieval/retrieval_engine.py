from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

from ..db.duckdb_manager import DuckDBManager


@dataclass
class RetrievalResult:
    items: List[Dict[str, Any]]


class RetrievalEngine:
    """Retrieval across STM and LTM with re-ranking and fallback."""

    def __init__(self, db: DuckDBManager) -> None:
        self.db = db

    def execute_search(
        self,
        namespace: str,
        query: str,
        limit: int = 5,
        recent_boost_window: int = 30,  # days (placeholder, not used in basic version)
    ) -> RetrievalResult:
        raw = self.db.search_memories(namespace=namespace, query=query, limit=limit * 3)

        # Simple re-ranking: STM first, then importance desc, then created_at desc
        def key_fn(r: Dict[str, Any]) -> Tuple[int, float, str]:
            stm_rank = 1 if r.get("memory_type") == "short_term" else 0
            return (
                stm_rank,
                float(r.get("importance_score", 0.0)),
                str(r.get("created_at", "")),
            )

        ranked = sorted(raw, key=key_fn, reverse=True)

        # Dedup by memory_id/summary
        seen: set = set()
        deduped: List[Dict[str, Any]] = []
        for r in ranked:
            k = (r.get("memory_id"), r.get("summary"))
            if k in seen:
                continue
            seen.add(k)
            deduped.append(r)
            if len(deduped) >= limit:
                break

        return RetrievalResult(items=deduped)

