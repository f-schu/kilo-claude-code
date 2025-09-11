#!/usr/bin/env python3
import argparse
import os
import random
import string
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any, Dict

from memori_local.store.memory_store import MemoryStore, MemoryStoreConfig


def rand_text(prefix: str, n: int = 12) -> str:
    return f"{prefix}-" + "".join(random.choices(string.ascii_lowercase, k=n))


def bench_record(store: MemoryStore, n: int) -> Dict[str, Any]:
    start = time.time()
    for i in range(n):
        if i % 4 == 0:
            user = "I prefer using ruff and black for Python."
            ai = "Acknowledged. Will use ruff + black."
        elif i % 4 == 1:
            user = "We use FastAPI for the service and test with pytest."
            ai = f"Create app/{rand_text('main', 6)}.py and add routers."
        elif i % 4 == 2:
            user = f"Implement feature {rand_text('FEAT', 4)} and link issue #{random.randint(10,999)}"
            ai = "Added endpoints and basic tests."
        else:
            user = f"General refactor in {rand_text('module', 5)}.py"
            ai = "Completed cleanup and renamed functions."
        store.record_conversation(user, ai, model="bench")
    dur = time.time() - start
    return {"count": n, "seconds": dur, "ops_per_sec": n / dur if dur > 0 else None}


def bench_promotion(store: MemoryStore) -> Dict[str, Any]:
    start = time.time()
    promoted = store.conscious.run_initial_promotion(store.config.namespace)
    dur = time.time() - start
    return {"promoted": promoted, "seconds": dur}


def bench_retrieval(store: MemoryStore, query: str, n: int) -> Dict[str, Any]:
    latencies = []
    for _ in range(n):
        s = time.time()
        _ = store.retrieve_context(query, limit=5)
        latencies.append(time.time() - s)
    return {
        "count": n,
        "avg_ms": (sum(latencies) / n) * 1000.0 if n else 0.0,
        "p95_ms": sorted(latencies)[int(0.95 * max(0, n - 1))] * 1000.0 if n else 0.0,
        "max_ms": max(latencies) * 1000.0 if n else 0.0,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Benchmark memori_local operations")
    ap.add_argument("--db-path", default=str(Path.home() / ".claude/memori/memori.duckdb"))
    ap.add_argument("--namespace", default="bench")
    ap.add_argument("--chats", type=int, default=200)
    ap.add_argument("--retrievals", type=int, default=50)
    ap.add_argument("--query", default="pytest")
    ap.add_argument("--fts", choices=["auto", "on", "off"], default="auto")
    ap.add_argument("--conscious", action="store_true", default=True)
    ap.add_argument("--no-conscious", dest="conscious", action="store_false")
    ap.add_argument("--auto", action="store_true", default=True)
    ap.add_argument("--no-auto", dest="auto", action="store_false")
    args = ap.parse_args()

    cfg = MemoryStoreConfig(
        db_path=args.db_path,
        namespace=args.namespace,
        conscious_ingest=args.conscious,
        auto_ingest=args.auto,
    )
    store = MemoryStore(cfg)

    # Control FTS path if requested
    if args.fts == "on":
        store.db.fts_enabled = True
    elif args.fts == "off":
        store.db.fts_enabled = False

    print("== Record benchmark ==")
    rec = bench_record(store, args.chats)
    print(rec)

    print("\n== Promotion benchmark ==")
    prom = bench_promotion(store)
    print(prom)

    print("\n== Retrieval benchmark ==")
    ret = bench_retrieval(store, args.query, args.retrievals)
    print(ret)

    # Suggestions
    print("\n== Suggestions ==")
    if rec["ops_per_sec"] and rec["ops_per_sec"] < 50:
        print("- Recording is < 50 ops/sec; consider disabling redaction patterns that you don't need or reduce text size.")
    if ret["avg_ms"] > 50:
        print("- Retrieval avg > 50ms; enable FTS (--fts on) if not already, or reduce STM size / query limit.")
    if prom["seconds"] > 0.5:
        print("- Promotion took > 0.5s; run it in the background scheduler and keep STM capacity modest (<=20).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

