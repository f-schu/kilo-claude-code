#!/usr/bin/env python3
import json
import os
import sys
from argparse import ArgumentParser

from memori_local.store.memory_store import MemoryStore, MemoryStoreConfig


def get_env_bool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


def main() -> int:
    ap = ArgumentParser(description="Memori-local record: record a user/assistant exchange")
    ap.add_argument("--user", help="User input text", default="")
    ap.add_argument("--assistant", help="Assistant output text", default="")
    args = ap.parse_args()

    user = (args.user or "").strip()
    assistant = (args.assistant or "").strip()
    if not user and not assistant:
        return 0

    db_path = os.environ.get("MEMORI_DUCKDB_PATH", os.path.expanduser("~/.claude/memori/memori.duckdb"))
    namespace = os.environ.get("MEMORI_NAMESPACE")
    conscious = get_env_bool("MEMORI_CONSCIOUS", True)
    auto = get_env_bool("MEMORI_AUTO", True)
    model = os.environ.get("MEMORI_MODEL", "claude-code")

    cfg = MemoryStoreConfig(
        db_path=db_path,
        namespace=namespace if namespace else None or "default",
        conscious_ingest=conscious,
        auto_ingest=auto,
    )
    store = MemoryStore(cfg)
    store.record_conversation(user, assistant, model=model, metadata=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

