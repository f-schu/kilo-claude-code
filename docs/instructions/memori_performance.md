Title: memori_local Performance & Tuning

Benchmarking
- Use the provided script:
  ```bash
  python3 scripts/memori_local_bench.py --db-path ./memori/memori.duckdb \
      --namespace bench --chats 300 --retrievals 100 --query pytest --fts auto
  ```
- Reports:
  - Recording throughput (ops/sec)
  - Promotion time
  - Retrieval latency (avg/p95/max)

Tuning Knobs
- FTS: enable DuckDB fts for faster retrievals (`--fts on`). Falls back to LIKE if extension unavailable.
- STM size: keep short-term memory small (<=20) for faster prompt construction and injection.
- Retrieval limit: keep to ~5 items; larger payloads add latency and can overfill prompts.
- Redaction patterns: reduce/disable unnecessary patterns to cut recording overhead in trusted environments.
- Background promotion: run promotion in the scheduler to avoid blocking the main path.
- Storage: keep the DuckDB file on SSD; avoid remote/network filesystems for best latency.

Expected Ranges (on typical laptops)
- Recording: tens to low hundreds ops/sec depending on redaction and text size.
- Promotion: < 0.5s for modest LTM sizes; schedule periodically.
- Retrieval: < 50ms average with FTS on small/medium datasets; LIKE fallback can be slower.

Troubleshooting
- If FTS queries fail, the system switches to LIKE path automatically.
- If retrieval is slow, check that query terms actually match indexed fields (summary/searchable_content).
- Use namespaces to keep datasets smaller and query filters tight.
