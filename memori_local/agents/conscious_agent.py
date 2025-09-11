import threading
import time
from typing import List, Optional

from ..db.duckdb_manager import DuckDBManager


class ConsciousAgent:
    """Promotion of eligible LTM items to STM with capacity and expiry enforcement."""

    def __init__(self, db: DuckDBManager, stm_capacity: int = 20, promotion_threshold: float = 0.65) -> None:
        self.db = db
        self.stm_capacity = stm_capacity
        self.promotion_threshold = promotion_threshold
        self._thread: Optional[threading.Thread] = None
        self._stop_event: Optional[threading.Event] = None

    def run_initial_promotion(self, namespace: str) -> int:
        # Select candidate LTM rows above threshold with preferred categories
        q = self.db.execute(
            """
            SELECT memory_id, category_primary, summary, searchable_content, importance_score
            FROM long_term_memory
            WHERE namespace = ? AND importance_score >= ? AND category_primary IN ('preference','rule','skill','context')
            ORDER BY importance_score DESC, created_at DESC
            LIMIT 100
            """,
            (namespace, self.promotion_threshold),
        )

        promoted = 0
        for row in q.rows:
            try:
                self.db.insert_stm(
                    memory_id=f"conscious_{row['memory_id']}",
                    namespace=namespace,
                    category_primary="conscious_context",
                    summary=row["summary"],
                    searchable_content=row["searchable_content"],
                    importance_score=float(row["importance_score"]),
                    is_permanent_context=row["category_primary"] in ("preference", "rule"),
                )
                promoted += 1
            except Exception:
                # Likely duplicate key; skip
                continue

        # Enforce capacity
        self.db.prune_stm_by_capacity(namespace=namespace, capacity=self.stm_capacity)
        return promoted

    # Background scheduling (thread-based)
    def start_scheduler(self, namespace: str, interval_hours: float = 6.0) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event = threading.Event()

        def loop():
            while self._stop_event and not self._stop_event.is_set():
                try:
                    self.run_initial_promotion(namespace)
                except Exception:
                    pass
                # Sleep with early exit support
                if self._stop_event and self._stop_event.wait(timeout=max(60.0, interval_hours * 3600.0)):
                    break

        self._thread = threading.Thread(target=loop, name="MemoriConsciousScheduler", daemon=True)
        self._thread.start()

    def stop_scheduler(self) -> None:
        if self._stop_event:
            self._stop_event.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5.0)
        self._thread = None
        self._stop_event = None
