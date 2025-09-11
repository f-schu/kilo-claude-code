import json
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..agents.conscious_agent import ConsciousAgent
from ..config import Config as EnvConfig
from ..db.duckdb_manager import DuckDBManager
from ..processing.heuristics import HeuristicProcessor
from ..retrieval.retrieval_engine import RetrievalEngine
from ..utils.context_builder import ContextBuilder
from ..utils.redaction import redact


def default_namespace() -> str:
    try:
        return f"code:{Path.cwd().name}"
    except Exception:
        return "default"


@dataclass
class MemoryStoreConfig:
    db_path: str
    namespace: str
    conscious_ingest: bool = True
    auto_ingest: bool = True
    stm_capacity: int = 20
    promotion_threshold: float = 0.65


class MemoryStore:
    """Orchestrates DB, heuristics, retrieval, and promotion."""

    def __init__(self, config: Optional[MemoryStoreConfig] = None) -> None:
        # Merge env config with provided config; provided values take precedence
        env = EnvConfig.from_env(
            default_db=str(Path.cwd() / "memori" / "memori.duckdb"),
            default_namespace=default_namespace(),
        )
        if config is None:
            cfg = MemoryStoreConfig(
                db_path=env.db_path,
                namespace=env.namespace,
                conscious_ingest=env.conscious_ingest,
                auto_ingest=env.auto_ingest,
                stm_capacity=env.stm_capacity,
                promotion_threshold=env.promotion_threshold,
            )
        else:
            # Override env with explicit config
            cfg = MemoryStoreConfig(
                db_path=config.db_path or env.db_path,
                namespace=config.namespace or env.namespace,
                conscious_ingest=config.conscious_ingest,
                auto_ingest=config.auto_ingest,
                stm_capacity=config.stm_capacity,
                promotion_threshold=config.promotion_threshold,
            )
        self.config = cfg
        self.db = DuckDBManager(cfg.db_path, auto_init_schema=True)
        self.session_id = str(uuid.uuid4())

        # Components
        self.heur = HeuristicProcessor(promotion_threshold=cfg.promotion_threshold)
        self.retrieval = RetrievalEngine(self.db)
        self.conscious = ConsciousAgent(self.db, stm_capacity=cfg.stm_capacity, promotion_threshold=cfg.promotion_threshold)
        self.ctx_builder = ContextBuilder()

        # Initial conscious promotion if enabled
        if cfg.conscious_ingest:
            self.conscious.run_initial_promotion(cfg.namespace)

    # Recording
    def record_conversation(self, user_input: str, ai_output: str, model: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> str:
        # Redact sensitive data before persisting
        user_input_red = redact(user_input or "")
        ai_output_red = redact(ai_output or "")
        chat_id = self.db.insert_chat(
            namespace=self.config.namespace,
            session_id=self.session_id,
            user_input=user_input_red,
            ai_output=ai_output_red,
            model=model,
            tokens_used=(metadata or {}).get("tokens_used"),
        )

        # Process and store derived LTM, and possibly promote to STM
        processed = self.heur.process_conversation(user_input_red, ai_output_red)
        for pm in processed:
            # Dedup check
            dup = self.db.find_ltm_duplicate(
                namespace=self.config.namespace,
                summary_norm=pm.summary.lower(),
                content_norm=pm.searchable_content.lower(),
            )
            if dup:
                self.db.bump_ltm_access(dup["memory_id"])  # soft update
                continue

            mem_id = str(uuid.uuid4())
            self.db.insert_ltm(
                memory_id=mem_id,
                namespace=self.config.namespace,
                category_primary=pm.category_primary,
                summary=pm.summary,
                searchable_content=pm.searchable_content,
                importance_score=pm.importance_score,
                classification=pm.classification,
                entities_json=json.dumps(pm.entities) if pm.entities else None,
                keywords_json=json.dumps(pm.keywords) if pm.keywords else None,
                content_hash=pm.content_hash,
            )

            # Promote eligible
            if pm.promotion_eligible and self.config.conscious_ingest:
                try:
                    self.db.insert_stm(
                        memory_id=f"conscious_{mem_id}",
                        namespace=self.config.namespace,
                        category_primary="conscious_context",
                        summary=pm.summary,
                        searchable_content=pm.searchable_content,
                        importance_score=pm.importance_score,
                        is_permanent_context=pm.category_primary in ("preference", "rule"),
                    )
                except Exception:
                    pass
                self.db.prune_stm_by_capacity(self.config.namespace, self.config.stm_capacity)

        return chat_id

    # Retrieval & prompts
    def retrieve_context(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        result = self.retrieval.execute_search(namespace=self.config.namespace, query=query, limit=limit)
        return result.items

    def get_conscious_system_prompt(self) -> str:
        # Pull top STM items
        rows = self.db.execute(
            """
            SELECT * FROM short_term_memory
            WHERE namespace = ?
            ORDER BY importance_score DESC, created_at DESC
            LIMIT 10
            """,
            (self.config.namespace,),
        ).rows
        return self.ctx_builder.build_system_block(rows, header_label="Conscious Working Memory", namespace=self.config.namespace)

    def get_auto_ingest_system_prompt(self, user_input: str) -> str:
        items = self.retrieve_context(user_input, limit=5)
        return self.ctx_builder.build_system_block(items, header_label="Relevant Memories", namespace=self.config.namespace)

    # Background scheduler controls
    def start_background_scheduler(self, interval_hours: float = 6.0) -> None:
        self.conscious.start_scheduler(self.config.namespace, interval_hours=interval_hours)

    def stop_background_scheduler(self) -> None:
        self.conscious.stop_scheduler()

    # Admin utilities
    def clear_conversation_history(self, session_id: Optional[str] = None) -> int:
        return self.db.delete_chat_history(namespace=self.config.namespace, session_id=session_id)

    def clear_memory(self, memory_type: Optional[str] = None) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        if memory_type in (None, "short_term"):
            counts["short_term"] = self.db.delete_stm(self.config.namespace)
        if memory_type in (None, "long_term"):
            counts["long_term"] = self.db.delete_ltm(self.config.namespace)
        return counts

    def export_namespace(self, path: Optional[str] = None) -> Dict[str, Any]:
        data = self.db.export_namespace(self.config.namespace)
        if path:
            from pathlib import Path
            import json

            p = Path(path)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(data, indent=2))
        return data
