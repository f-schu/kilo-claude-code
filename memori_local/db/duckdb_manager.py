import os
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

try:
    import duckdb  # type: ignore
except Exception as e:  # pragma: no cover
    duckdb = None


DEFAULT_DB_PATH = str((Path.cwd() / "memori" / "memori.duckdb").resolve())


DDL = {
    "chat_history": (
        """
        CREATE TABLE IF NOT EXISTS chat_history (
          chat_id TEXT PRIMARY KEY,
          session_id TEXT,
          namespace TEXT NOT NULL,
          user_input TEXT NOT NULL,
          ai_output TEXT NOT NULL,
          model TEXT,
          timestamp TIMESTAMP NOT NULL DEFAULT current_timestamp,
          tokens_used INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_ch_ns_ts ON chat_history(namespace, timestamp);
        """
    ),
    "short_term_memory": (
        """
        CREATE TABLE IF NOT EXISTS short_term_memory (
          memory_id TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          category_primary TEXT NOT NULL,
          summary TEXT NOT NULL,
          searchable_content TEXT NOT NULL,
          importance_score DOUBLE NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
          expires_at TIMESTAMP,
          access_count INTEGER NOT NULL DEFAULT 0,
          is_permanent_context BOOLEAN NOT NULL DEFAULT FALSE
        );
        CREATE INDEX IF NOT EXISTS idx_st_ns_cat ON short_term_memory(namespace, category_primary);
        """
    ),
    "long_term_memory": (
        """
        CREATE TABLE IF NOT EXISTS long_term_memory (
          memory_id TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          category_primary TEXT NOT NULL,
          summary TEXT NOT NULL,
          searchable_content TEXT NOT NULL,
          importance_score DOUBLE NOT NULL,
          classification TEXT,
          created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
          access_count INTEGER NOT NULL DEFAULT 0,
          topic TEXT,
          entities_json TEXT,
          keywords_json TEXT,
          content_hash TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_lt_ns_cat ON long_term_memory(namespace, category_primary);
        """
    ),
    "rules_memory": (
        """
        CREATE TABLE IF NOT EXISTS rules_memory (
          rule_id TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          rule_text TEXT NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT current_timestamp
        );
        """
    ),
    "meta": (
        """
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT
        );
        INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', '1');
        """
    ),
}


@dataclass
class QueryResult:
    rows: List[Dict[str, Any]]


class DuckDBManager:
    """Minimal DuckDB manager with schema init and FTS adapter (LIKE fallback)."""

    def __init__(self, db_path: Optional[str] = None, auto_init_schema: bool = True) -> None:
        self.db_path = db_path or DEFAULT_DB_PATH
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)

        if duckdb is None:
            raise RuntimeError("duckdb package is not available. Please install duckdb.")

        # Open connection
        self.con = duckdb.connect(self.db_path)
        self.fts_enabled = False

        if auto_init_schema:
            self.initialize_schema()
            self.enable_fts_or_fallback()

    def initialize_schema(self) -> None:
        # Create base tables if missing
        for _, ddl in DDL.items():
            self.con.execute(ddl)
        # Ensure migrations run to bring schema up to date
        self.apply_migrations()

    def enable_fts_or_fallback(self) -> None:
        try:
            self.con.execute("INSTALL fts;")
            self.con.execute("LOAD fts;")
            # Attempt FTS indexes on STM & LTM (searchable_content, summary)
            self.con.execute(
                "CREATE INDEX IF NOT EXISTS fts_st ON short_term_memory USING fts(searchable_content, summary);"
            )
            self.con.execute(
                "CREATE INDEX IF NOT EXISTS fts_lt ON long_term_memory USING fts(searchable_content, summary);"
            )
            self.fts_enabled = True
        except Exception:
            self.fts_enabled = False

    # Schema versioning & migrations
    def _get_schema_version(self) -> int:
        try:
            q = self.execute("SELECT value FROM meta WHERE key = 'schema_version' LIMIT 1")
            if q.rows:
                return int(q.rows[0]["value"])
        except Exception:
            pass
        return 0

    def _set_schema_version(self, v: int) -> None:
        self.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)", (str(v),))

    def _column_exists(self, table: str, column: str) -> bool:
        q = self.execute(f"PRAGMA table_info('{table}')")
        for row in q.rows:
            if str(row.get("name", "")) == column:
                return True
        return False

    def apply_migrations(self) -> None:
        cur = self._get_schema_version()

        # Migration to v1: ensure content_hash column on long_term_memory
        if cur < 1:
            if not self._column_exists("long_term_memory", "content_hash"):
                self.execute("ALTER TABLE long_term_memory ADD COLUMN content_hash TEXT")
            self._set_schema_version(1)

    # Basic helpers
    def execute(self, sql: str, params: Optional[Sequence[Any]] = None) -> QueryResult:
        cur = self.con.execute(sql, params or [])
        try:
            cols = [d[0] for d in cur.description] if cur.description else []
            rows = cur.fetchall() if cur.description else []
            dict_rows = [dict(zip(cols, r)) for r in rows]
            return QueryResult(rows=dict_rows)
        finally:
            # duckdb keeps statements; no explicit cursor close needed
            pass

    # Inserts
    def insert_chat(self, namespace: str, session_id: str, user_input: str, ai_output: str, model: Optional[str] = None, tokens_used: Optional[int] = None) -> str:
        chat_id = str(uuid.uuid4())
        self.execute(
            """
            INSERT INTO chat_history(chat_id, session_id, namespace, user_input, ai_output, model, tokens_used)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (chat_id, session_id, namespace, user_input, ai_output, model, tokens_used),
        )
        return chat_id

    def insert_ltm(
        self,
        memory_id: str,
        namespace: str,
        category_primary: str,
        summary: str,
        searchable_content: str,
        importance_score: float,
        classification: Optional[str],
        entities_json: Optional[str],
        keywords_json: Optional[str],
        content_hash: Optional[str],
    ) -> None:
        self.execute(
            """
            INSERT INTO long_term_memory(
              memory_id, namespace, category_primary, summary, searchable_content,
              importance_score, classification, entities_json, keywords_json, content_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                memory_id,
                namespace,
                category_primary,
                summary,
                searchable_content,
                importance_score,
                classification,
                entities_json,
                keywords_json,
                content_hash,
            ),
        )

    def insert_stm(
        self,
        memory_id: str,
        namespace: str,
        category_primary: str,
        summary: str,
        searchable_content: str,
        importance_score: float,
        is_permanent_context: bool = False,
        expires_at: Optional[str] = None,
    ) -> None:
        self.execute(
            """
            INSERT INTO short_term_memory(
              memory_id, namespace, category_primary, summary, searchable_content,
              importance_score, is_permanent_context, expires_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                memory_id,
                namespace,
                category_primary,
                summary,
                searchable_content,
                importance_score,
                is_permanent_context,
                expires_at,
            ),
        )

    # Lookups
    def find_ltm_duplicate(self, namespace: str, summary_norm: str, content_norm: str) -> Optional[Dict[str, Any]]:
        # Simple duplicate check: normalized equality on summary or content hash
        q = self.execute(
            """
            SELECT * FROM long_term_memory
            WHERE namespace = ? AND (lower(summary) = ? OR lower(searchable_content) = ?)
            LIMIT 1
            """,
            (namespace, summary_norm, content_norm),
        )
        return q.rows[0] if q.rows else None

    def bump_ltm_access(self, memory_id: str) -> None:
        self.execute(
            "UPDATE long_term_memory SET access_count = access_count + 1 WHERE memory_id = ?",
            (memory_id,),
        )

    def stm_count(self, namespace: str) -> int:
        q = self.execute(
            "SELECT COUNT(*) AS c FROM short_term_memory WHERE namespace = ?",
            (namespace,),
        )
        return int(q.rows[0]["c"]) if q.rows else 0

    def prune_stm_by_capacity(self, namespace: str, capacity: int) -> None:
        # Remove non-permanent lowest-importance/oldest until under capacity
        q = self.execute(
            """
            SELECT memory_id FROM short_term_memory
            WHERE namespace = ? AND is_permanent_context = FALSE
            ORDER BY importance_score ASC, created_at ASC
            OFFSET ?
            """,
            (namespace, max(capacity - 1, 0)),
        )
        to_prune = [r["memory_id"] for r in q.rows]
        if to_prune:
            placeholders = ",".join(["?"] * len(to_prune))
            self.execute(
                f"DELETE FROM short_term_memory WHERE memory_id IN ({placeholders})",
                to_prune,
            )

    # Search
    def search_memories(self, namespace: str, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        if self.fts_enabled and query.strip():
            # Use FTS virtual indexes (duckdb fts)
            # Query STM
            stm = self.execute(
                """
                SELECT *, 'short_term' AS memory_type
                FROM short_term_memory
                WHERE namespace = ? AND fts_main('fts_st', ?) MATCH rowid
                ORDER BY importance_score DESC, created_at DESC
                LIMIT ?
                """,
                (namespace, query, limit),
            ).rows
            # Query LTM
            ltm = self.execute(
                """
                SELECT *, 'long_term' AS memory_type
                FROM long_term_memory
                WHERE namespace = ? AND fts_main('fts_lt', ?) MATCH rowid
                ORDER BY importance_score DESC, created_at DESC
                LIMIT ?
                """,
                (namespace, query, limit),
            ).rows
        else:
            like = f"%{query.strip()}%" if query.strip() else "%"
            stm = self.execute(
                """
                SELECT *, 'short_term' AS memory_type
                FROM short_term_memory
                WHERE namespace = ? AND (summary ILIKE ? OR searchable_content ILIKE ?)
                ORDER BY importance_score DESC, created_at DESC
                LIMIT ?
                """,
                (namespace, like, like, limit),
            ).rows
            ltm = self.execute(
                """
                SELECT *, 'long_term' AS memory_type
                FROM long_term_memory
                WHERE namespace = ? AND (summary ILIKE ? OR searchable_content ILIKE ?)
                ORDER BY importance_score DESC, created_at DESC
                LIMIT ?
                """,
                (namespace, like, like, limit),
            ).rows

        # Merge; caller can re-rank
        return stm + ltm

    # Admin utilities
    def delete_chat_history(self, namespace: str, session_id: Optional[str] = None) -> int:
        if session_id:
            res = self.execute(
                "DELETE FROM chat_history WHERE namespace = ? AND session_id = ? RETURNING 1",
                (namespace, session_id),
            )
        else:
            res = self.execute(
                "DELETE FROM chat_history WHERE namespace = ? RETURNING 1",
                (namespace,),
            )
        return len(res.rows)

    def delete_stm(self, namespace: str) -> int:
        res = self.execute(
            "DELETE FROM short_term_memory WHERE namespace = ? RETURNING 1",
            (namespace,),
        )
        return len(res.rows)

    def delete_ltm(self, namespace: str) -> int:
        res = self.execute(
            "DELETE FROM long_term_memory WHERE namespace = ? RETURNING 1",
            (namespace,),
        )
        return len(res.rows)

    def export_namespace(self, namespace: str) -> Dict[str, Any]:
        data: Dict[str, Any] = {}
        data["chat_history"] = self.execute(
            "SELECT * FROM chat_history WHERE namespace = ? ORDER BY timestamp",
            (namespace,),
        ).rows
        data["short_term_memory"] = self.execute(
            "SELECT * FROM short_term_memory WHERE namespace = ? ORDER BY created_at",
            (namespace,),
        ).rows
        data["long_term_memory"] = self.execute(
            "SELECT * FROM long_term_memory WHERE namespace = ? ORDER BY created_at",
            (namespace,),
        ).rows
        data["rules_memory"] = self.execute(
            "SELECT * FROM rules_memory WHERE namespace = ? ORDER BY created_at",
            (namespace,),
        ).rows
        return data
