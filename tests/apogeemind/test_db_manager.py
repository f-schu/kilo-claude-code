from pathlib import Path

from apogeemind.db.duckdb_manager import DuckDBManager


def test_schema_init_and_basic_inserts(tmp_path: Path):
    db_path = tmp_path / "memori.duckdb"
    db = DuckDBManager(str(db_path), auto_init_schema=True)
    # Tables exist: simple count queries should work
    for table in [
        "chat_history",
        "short_term_memory",
        "long_term_memory",
        "rules_memory",
        "meta",
    ]:
        res = db.execute(f"SELECT COUNT(*) AS c FROM {table}")
        assert "c" in res.rows[0]

    # Insert a chat and read it back via a direct query
    chat_id = db.insert_chat("ns1", "sess1", "hello", "world", model="local")
    res = db.execute("SELECT chat_id, user_input, ai_output FROM chat_history WHERE chat_id = ?", (chat_id,))
    assert res.rows and res.rows[0]["user_input"] == "hello"


def test_search_like_fallback(tmp_path: Path):
    db_path = tmp_path / "memori.duckdb"
    db = DuckDBManager(str(db_path), auto_init_schema=True)
    # Force LIKE path to avoid FTS version differences in CI
    db.fts_enabled = False
    # Insert STM/LTM
    db.insert_stm(
        memory_id="stm1",
        namespace="ns",
        category_primary="conscious_context",
        summary="Use pytest",
        searchable_content="We use pytest for tests",
        importance_score=0.8,
    )
    db.insert_ltm(
        memory_id="ltm1",
        namespace="ns",
        category_primary="skill",
        summary="FastAPI knowledge",
        searchable_content="fastapi app structure",
        importance_score=0.7,
        classification=None,
        entities_json=None,
        keywords_json=None,
        content_hash=None,
    )

    items = db.search_memories(namespace="ns", query="pytest", limit=5)
    assert any(r["memory_type"] == "short_term" for r in items)
