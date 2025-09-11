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
    ap = ArgumentParser(description="Memori-local inject: print system-reminder with relevant memories")
    ap.add_argument("--query", help="User query text to retrieve context for", default="")
    args = ap.parse_args()

    db_path = os.environ.get("MEMORI_DUCKDB_PATH", os.path.expanduser("~/.claude/memori/memori.duckdb"))
    namespace = os.environ.get("MEMORI_NAMESPACE")
    conscious = get_env_bool("MEMORI_CONSCIOUS", True)
    auto = get_env_bool("MEMORI_AUTO", True)

    cfg = MemoryStoreConfig(
        db_path=db_path,
        namespace=namespace if namespace else None or "default",
        conscious_ingest=conscious,
        auto_ingest=auto,
    )
    store = MemoryStore(cfg)

    query = args.query.strip()
    if not query:
        return 0

    block = store.get_auto_ingest_system_prompt(query)
    if not block.strip():
        return 0

    # Wrap in a system-reminder for Claude Code hooks compatibility
    sys.stdout.write("<system-reminder>\n")
    sys.stdout.write(block)
    sys.stdout.write("\n</system-reminder>\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

