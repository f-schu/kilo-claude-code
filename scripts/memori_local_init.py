#!/usr/bin/env python3
import os
from pathlib import Path
from memori_local.store.memory_store import MemoryStore, MemoryStoreConfig


def main() -> int:
    db_path = os.environ.get("MEMORI_DUCKDB_PATH", str(Path.cwd() / "memori" / "memori.duckdb"))
    namespace = os.environ.get("MEMORI_NAMESPACE") or f"code:{Path.cwd().name}"
    cfg = MemoryStoreConfig(db_path=db_path, namespace=namespace)
    store = MemoryStore(cfg)
    # Touch the DB by building a minimal prompt (no output required)
    _ = store.get_conscious_system_prompt()
    print(f"memori_local initialized at: {db_path} (namespace={namespace})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

