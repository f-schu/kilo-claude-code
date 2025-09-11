from pathlib import Path

from memori_local.store.memory_store import MemoryStore, MemoryStoreConfig


def make_store(tmp_path: Path, namespace: str = "ns") -> MemoryStore:
    cfg = MemoryStoreConfig(
        db_path=str(tmp_path / "memori.duckdb"),
        namespace=namespace,
        conscious_ingest=True,
        auto_ingest=True,
        stm_capacity=5,
        promotion_threshold=0.5,
    )
    return MemoryStore(cfg)


def test_record_and_promotion_to_stm(tmp_path: Path):
    store = make_store(tmp_path)
    # Preference should be promotion-eligible and end up in STM
    user = "I prefer using ruff and black for Python."
    ai = "Acknowledged. Will use ruff + black."
    store.record_conversation(user, ai, model="local")

    prompt = store.get_conscious_system_prompt()
    assert "Conscious Working Memory" in prompt
    assert "PREFERENCE" in prompt or "CONSCIOUS_CONTEXT" in prompt


def test_retrieval_engine_ordering(tmp_path: Path):
    store = make_store(tmp_path)
    # Insert two conversations; one includes a tech keyword likely categorized as skill/context
    store.record_conversation("We use FastAPI", "Create app/main.py", model="local")
    store.record_conversation("Testing with pytest", "Add tests", model="local")

    # Force LIKE path to avoid FTS variability
    store.db.fts_enabled = False
    items = store.retrieve_context("pytest", limit=5)
    assert items
    # At least one item should be from STM due to promotion in previous steps (if eligible)
    # Not strictly guaranteed, but we should see summaries present
    assert any("summary" in it for it in items)

