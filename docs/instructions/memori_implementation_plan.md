Below is a tightened, implementation‑ready version of your plan with corrections, power‑ups, and a few drop‑in code snippets. I’ve kept it fully local (no LLMs, no embeddings, no network calls) and tuned for Claude Code hooks + DuckDB FTS. This document now describes the ApogeeMind memory layer.

---

## 0) What to fix from the draft

**DuckDB FTS details.** DuckDB’s FTS is created with a `PRAGMA create_fts_index(table, id, cols…)` and queried via the generated schema function `fts_<schema>_<table>.match_bm25(id, 'query', …)`. The index **does not auto‑update** after inserts/updates; you must drop/recreate (or periodically rebuild). Also you can set `stemmer`, `stopwords`, `ignore`, etc. at index creation.

**Hooks for Claude Code.** Use `UserPromptSubmit` to inject context (stdout becomes added context) and `Stop` to record the last exchange. Hooks are configured in `~/.claude/settings.json` or per‑project.

**Persistence of the FTS extension.** In an offline/self‑contained setup, **vendor** the FTS extension and `INSTALL … FROM '<local_dir>'` + `LOAD fts`; otherwise you’ll hit the autoloader (network).

**Upsert & concurrency.** DuckDB supports `INSERT … ON CONFLICT DO UPDATE/DO NOTHING` and is fine with concurrent appends within a process (we’ll still batch writes).

**Performance knobs.** You can set `threads`, `memory_limit`, and `temp_directory` in process—useful for large transcripts.

**FYI on memori upstream.** The repo you linked is a fork of GibsonAI/memori, which uses LLM‑based agents; we’re mirroring the high‑level shape but keeping all processing deterministic.

---

## 1) Goals & Non‑Goals (confirmed + refined)

**Goals (unchanged with additions)**

* Fully offline memory layer for coding/agent sessions; **DuckDB** storage with **FTS** (BM25).
* Programmatic APIs to record, classify, summarize, retrieve, and emit a compact “system block” for Claude Code.
* Namespacing per project/repo/branch; short‑ vs long‑term; conscious promotion.
* **Deterministic** heuristics only (regex/keyword lists/state machines).
* **FTS rebuild policy** built‑in (debounced background rebuilds).
* **Redaction** before storage.

**Non‑Goals (clarified)**

* No embeddings/vector indexes; no internet; no UI (library + CLI only).
* No DuckDB triggers (DuckDB doesn’t have them)—we’ll manage rebuilds in code.

---

## 2) Architecture (revised)

* **DuckDBManager**
  Connection lifecycle, schema, **offline FTS install/load**, index creation, debounced **FTS rebuilds**, transactions, upserts, and settings (`threads`, `memory_limit`, `temp_directory`).

* **MemoryStore**
  High‑level API for sessions, record/retrieve, conscious promotion, namespacing.

* **HeuristicProcessor**
  Deterministic: summarization, classification, keyword/entity extraction, importance scoring, promotion eligibility.

* **RetrievalEngine**
  Hybrid scoring: **BM25** (from FTS) + recency + importance + entity overlap; dedup; size guard. (BM25 via `match_bm25`).

* **ConsciousAgent**
  Initial promotion / periodic maintenance; FTS rebuild scheduler.

* **ContextBuilder**
  Compact, bounded system block.

* **CLI/Hooks**
  Two small CLIs: `memori-local inject` and `memori-local record`. Hooks: `UserPromptSubmit` → inject; `Stop` → record.

---

## 3) Database design (DuckDB) — with FTS‑friendly tweaks

**Engine**

* DB path: `~/.claude/memori-local/memori.duckdb` (default) or project‑local.
* On connect: `SET threads = <n>; SET memory_limit = '<XGB>'; SET temp_directory = '<path>.tmp';` (configurable).

**Tables** (mostly as you wrote; small additions):

* Add `checksum TEXT` to LTM/STM for dedup.
* Add `last_accessed_at TIMESTAMP` (for re‑rank + cleanup).
* Add `schema_version` in `meta(key,value)`.

**Indexes & FTS (correct syntax)**

```sql
INSTALL fts FROM '<local_ext_dir>'; -- offline
LOAD fts;

-- FTS: choose aggressive settings for code/text mixed corpora
PRAGMA create_fts_index(
  'short_term_memory', 'memory_id', 'searchable_content', 'summary',
  stemmer='porter', stopwords='none', ignore='(\\.|[^a-z0-9_])+', lower=1, overwrite=1
);
PRAGMA create_fts_index(
  'long_term_memory', 'memory_id', 'searchable_content', 'summary',
  stemmer='porter', stopwords='none', ignore='(\\.|[^a-z0-9_])+', lower=1, overwrite=1
);
```

Query with BM25:

```sql
SELECT m.*, s.score
FROM (
  SELECT *, fts_main_short_term_memory.match_bm25(memory_id, ? /*query*/, fields := 'searchable_content,summary') AS score
  FROM short_term_memory
  WHERE namespace = ?
) AS s
JOIN short_term_memory m USING (memory_id)
WHERE s.score IS NOT NULL
ORDER BY s.score DESC
LIMIT ?;
```

Note: FTS **does not auto‑update** on writes; we rebuild on a debounce timer or on N‑inserts.

---

## 4) Data models (minor additions)

* **ConversationRecord**: add `meta_json TEXT` for arbitrary metadata (tool runs, file paths).
* **MemoryItem**: add `checksum`, `last_accessed_at`, `source_chat_id`.
* **ProcessedMemory**: add `reason_codes` (why important), `promotion_score`, `duplicate_of?`.

---

## 5) Heuristics (sharper rules)

**Summarization (deterministic)**

* Strip code blocks → keep first 2–3 sentences with nouns/verbs (simple POS‑ish regex or sentence heuristics).
* 300 chars hard cap; drop URLs; collapse whitespace.

**Classification**

* `preference`: regex on “I prefer|please always|default to|never …” (case‑insensitive).
* `rule`: line‑initial imperatives (“Always|Never|Do not|Must …”). Also store in `rules_memory`.
* `skill/knowledge`: curated lists (languages, frameworks, tools) + version patterns.
* `fact/context`: repo name, path, branch, ticket IDs `(PROJECT-\d+)`, file globs `(\w+\.py|\w+\.ts)` etc.
* `conscious_context`: synthetic label for promoted STM items.

**Importance (0–1)**
`0.45 * type_boost + 0.25 * recency + 0.20 * repetition + 0.10 * brevity_bonus`

* `type_boost`: preferences/rules/skills (1.0), facts (0.7), other (0.4).
* `recency`: exp decay from now.
* `repetition`: frequency of same entities/keywords in last 30 days.
* `brevity_bonus`: summaries < 200 chars.

**Entities/Keywords (stored JSON)**

* File paths, code identifiers, repo/branch; person handles `@foo`; technologies; versions; ports; env vars.

**Promotion**

* Eligible if `classification ∈ {preference, rule, skill/knowledge, fact}` AND `importance ≥ 0.65`.
* Recency window 30 days **or** repetition ≥ 3 across sessions.

---

## 6) Memory lifecycle

* **STM**
  Capacity default 20; TTL 14 days except `is_permanent_context`. LRU + importance eviction.

* **LTM**
  Dedup by `checksum = sha1(normalized(searchable_content))`; if duplicate, `ON CONFLICT` update `importance_score = GREATEST(old,new)` and bump repetition counters.

* **FTS Rebuild Policy (critical)**
  Maintain a tiny table `fts_status(table_name, last_built_at, pending_inserts INT)`.

  * On write: increment `pending_inserts`.
  * Background (every 5 min or when `pending_inserts ≥ 200`):

    ```
    PRAGMA drop_fts_index('short_term_memory');
    PRAGMA create_fts_index('short_term_memory', 'memory_id', 'searchable_content','summary', ...);
    UPDATE fts_status SET last_built_at=now(), pending_inserts=0 WHERE table_name='short_term_memory';
    ```

  Same for `long_term_memory`. (DuckDB FTS doesn’t auto‑update.)

---

## 7) Retrieval (scoring formula)

**Candidate generation**

* Top `N1` from STM by `match_bm25` (conjunctive=0), union top `N2` from LTM.
* If FTS disabled/unavailable, fallback to case‑insensitive `ILIKE` on `summary`/`searchable_content` with a simple frequency score.

**Re‑rank (all to 0–1 ranges)**
`final = 0.50 * bm25_norm + 0.25 * importance + 0.15 * recency + 0.10 * entity_overlap`

* `entity_overlap`: Jaccard of recent entities vs memory entities.
* Dedup by `checksum/summary`.
* Return `limit` items (default 5) with updated `last_accessed_at` and `access_count += 1`.

---

## 8) Context block (tight format)

```
--- Relevant Memories (namespace=<ns>) ---
- [PREFERENCE] Prefer black+ruff for Python formatting (2025-09-10; imp=0.82)
- [SKILL] FastAPI, pytest, Docker (2025-09-10; imp=0.78)
- [RULE] Always run unit tests before commit (2025-09-09; imp=0.76)
--- End Memories ---
```

**Budget**: ≤ 2 KB. If over budget, drop lowest `final` score, then oldest.

---

## 9) Public APIs (Python)

**DuckDBManager (key methods)**

* `__init__(db_path, ext_dir=None, threads=None, memory_limit=None, temp_dir=None)`
* `initialize_schema()` / `migrate_if_needed()`
* `enable_fts_or_fallback()`: try `INSTALL fts FROM ext_dir; LOAD fts;` else set `self.fts_enabled=False`.
* `rebuild_fts(table)` (drop+create)
* `insert_chat(record)` (batched)
* `upsert_memory(table, item)` → `INSERT … ON CONFLICT DO UPDATE`
* `search_bm25(table, namespace, query, limit)` (if FTS)
* `search_like(table, namespace, query, limit)` (fallback)

**MemoryStore**

* `start_new_session() → session_id`
* `record_conversation(user_input, ai_output, model=None, metadata=None)`
* `retrieve_context(query, limit=5)`
* `get_conscious_system_prompt()`
* `get_auto_ingest_system_prompt(user_input)`
* `clear_*` helpers.

**ConsciousAgent**

* `run_initial_promotion(namespace)`
* `schedule_background(interval_hours=6)` → also runs `maybe_rebuild_fts()`.

**ContextBuilder**

* `build_system_block(items, header_label) -> str`

---

## 10) Claude Code integration (ready‑to‑paste)

**Project settings** `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/memori_inject.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/memori_record.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/memori_bootstrap.sh"
          }
        ]
      }
    ]
  }
}
```

* `memori_inject.sh` should call `memori-local inject --db ~/.claude/memori-local/memori.duckdb --ns $(basename $CLAUDE_PROJECT_DIR) --query-file "$1"` and **echo the system block to stdout**. `UserPromptSubmit` stdout is added as context.
* `memori_record.sh` should read `transcript_path` from JSON stdin and append the last user/assistant pair via `memori-local record …`.
* `memori_bootstrap.sh` runs initial promotion so the first turn already has STM context.
  (Events and behavior per Anthropic docs.)

---

## 11) Security & privacy

* **Redaction** before storage (API keys, tokens, emails, domains, cloud creds).
* Consider OS‑level disk encryption (FileVault/BitLocker) for the DuckDB file; DuckDB open‑source does not provide first‑class DB‑file encryption. If exporting backups, you can encrypt Parquet outputs.
* Avoid loading extensions from untrusted paths (review “Securing Extensions”).

---

## 12) Performance considerations

* Batch inserts in a single transaction; rebuild FTS debounced.
* Tune `threads`, `memory_limit`, and `temp_directory` per host.
* Keep STM small (≤20); FTS `LIMIT` bounded.
* Cache last N retrievals (query → ids).
* Periodically `VACUUM` isn’t needed; DuckDB manages storage, but you can copy DB to compact if required (not mandatory).

---

## 13) Testing

**Unit**

* Heuristic classification (golden regex fixtures).
* Importance scoring (edge cases).
* FTS enabled vs fallback LIKE.

**Integration**

* Record K conversations → assert LTM rows; run promotion → STM populated; run retrieval on typical queries → check ranked order.
* FTS rebuild: insert 1k rows, search before/after rebuild → score changes (smoke test).
* Hooks: simulate `UserPromptSubmit` and ensure stdout context appears.

---

## 14) Migrations / meta

* `meta(key TEXT PRIMARY KEY, value TEXT)` with `schema_version`.
* Migration scripts idempotent; version bump when adding columns/indexes.

---

## 15) Deliverables & milestones (tight)

* **P0 (Core)**: `DuckDBManager` + schema + FTS (offline load + fallback), `MemoryStore.record/retrieve`, Heuristics v1, ContextBuilder, CLI `inject` & `record`.
* **P1 (Conscious/Promotion)**: promotion + STM capacity/TTL + rebuild scheduler.
* **P2 (Hooks)**: scripts + docs + examples for Claude Code.
* **P3 (Hardening)**: dedup, redaction, tests, benchmarks.

---

## 16) Updated DDL (DuckDB; excerpt)

```sql
CREATE TABLE IF NOT EXISTS chat_history (
  chat_id TEXT PRIMARY KEY,
  session_id TEXT,
  namespace TEXT NOT NULL,
  user_input TEXT NOT NULL,
  ai_output TEXT NOT NULL,
  model TEXT,
  timestamp TIMESTAMP NOT NULL DEFAULT current_timestamp,
  tokens_used INTEGER,
  meta_json TEXT
);

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
  last_accessed_at TIMESTAMP,
  is_permanent_context BOOLEAN NOT NULL DEFAULT FALSE,
  checksum TEXT
);

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
  last_accessed_at TIMESTAMP,
  topic TEXT,
  entities_json TEXT,
  keywords_json TEXT,
  checksum TEXT,
  source_chat_id TEXT
);

CREATE TABLE IF NOT EXISTS rules_memory (
  rule_id TEXT PRIMARY KEY,
  namespace TEXT NOT NULL,
  rule_text TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT current_timestamp
);

CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS fts_status (
  table_name TEXT PRIMARY KEY,
  last_built_at TIMESTAMP,
  pending_inserts INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_ch_ns_ts ON chat_history(namespace, timestamp);
CREATE INDEX IF NOT EXISTS idx_st_ns_cat ON short_term_memory(namespace, category_primary);
CREATE INDEX IF NOT EXISTS idx_lt_ns_cat ON long_term_memory(namespace, category_primary);
```

**FTS creation**: see Section 3.

---

## 17) Minimal manager code (drop‑in skeleton)

```python
# duckdb_manager.py
import duckdb, hashlib, json, time
from contextlib import contextmanager

class DuckDBManager:
    def __init__(self, db_path, ext_dir=None, threads=None, memory_limit=None, temp_dir=None):
        self.con = duckdb.connect(db_path)
        if threads: self.con.execute(f"SET threads = {int(threads)}")
        if memory_limit: self.con.execute(f"SET memory_limit = '{memory_limit}'")
        if temp_dir: self.con.execute(f"SET temp_directory = '{temp_dir}'")
        self.ext_dir = ext_dir
        self.fts_enabled = False

    def initialize_schema(self):
        self.con.execute("""-- DDL from section 16 --""")  # paste DDL here

    def enable_fts_or_fallback(self):
        try:
            if self.ext_dir:
                self.con.execute(f"INSTALL fts FROM '{self.ext_dir}'")
            else:
                # If ext_dir not provided, rely on already-installed local cache only
                self.con.execute("INSTALL fts")
            self.con.execute("LOAD fts")
            self.fts_enabled = True
        except Exception:
            self.fts_enabled = False  # LIKE fallback

    def rebuild_fts(self, table):
        if not self.fts_enabled: return
        self.con.execute(f"PRAGMA drop_fts_index('{table}')")
        self.con.execute(f"""
            PRAGMA create_fts_index(
              '{table}', 'memory_id', 'searchable_content','summary',
              stemmer='porter', stopwords='none', ignore='(\\.|[^a-z0-9_])+', lower=1, overwrite=1
            );
        """)
        self.con.execute(
            "INSERT OR REPLACE INTO fts_status(table_name,last_built_at,pending_inserts) VALUES (?, current_timestamp, 0)",
            [table],
        )

    def upsert_memory(self, table, item):
        # item is a dict; compute checksum
        canonical = item.get("searchable_content","") + "|" + item.get("summary","")
        item["checksum"] = hashlib.sha1(canonical.encode("utf-8")).hexdigest()
        cols = ",".join(item.keys())
        vals = [item[k] for k in item.keys()]
        placeholders = ",".join(["?"]*len(item))
        set_clause = ",".join([f"{k}=EXCLUDED.{k}" for k in item.keys() if k not in ("memory_id",)])
        self.con.execute(
            f"INSERT INTO {table} ({cols}) VALUES ({placeholders}) "
            f"ON CONFLICT(memory_id) DO UPDATE SET {set_clause}",
            vals,
        )
        self.con.execute("UPDATE fts_status SET pending_inserts = pending_inserts + 1 WHERE table_name=?", [table])

    def search_memories(self, table, namespace, query, limit):
        if self.fts_enabled:
            fts_schema = f"fts_main_{table}"
            sql = f"""
            SELECT m.*, s.score
            FROM (
              SELECT *, {fts_schema}.match_bm25(memory_id, ?, fields := 'searchable_content,summary') AS score
              FROM {table}
              WHERE namespace = ?
            ) AS s
            JOIN {table} m USING (memory_id)
            WHERE s.score IS NOT NULL
            ORDER BY s.score DESC
            LIMIT ?
            """
            return self.con.execute(sql, [query, namespace, limit]).fetchdf()
        else:
            like = f"%{query}%"
            sql = f"""
            SELECT *, 0.0 as score
            FROM {table}
            WHERE namespace = ?
              AND (summary ILIKE ? OR searchable_content ILIKE ?)
            LIMIT ?
            """
            return self.con.execute(sql, [namespace, like, like, limit]).fetchdf()

    def maybe_rebuild_fts(self, debounce_min=5, threshold=200):
        if not self.fts_enabled: return
        for table in ("short_term_memory","long_term_memory"):
            row = self.con.execute("SELECT pending_inserts, last_built_at FROM fts_status WHERE table_name=?", [table]).fetchone()
            if not row:
                self.con.execute("INSERT INTO fts_status(table_name,last_built_at,pending_inserts) VALUES (?, current_timestamp, 0)", [table])
                continue
            pending, last = row
            if pending >= threshold:
                self.rebuild_fts(table)
```

---

## 18) CLI stubs (to wire hooks quickly)

* `memori-local inject --db <file> --ns <namespace> --query-file <path>` → prints system block to stdout.
* `memori-local record --db <file> --ns <namespace> --user <path> --assistant <path> [--meta <json>]` → stores conversation and derived memory.

(Use `argparse`; read files; update STM/LTM; call `maybe_rebuild_fts()`.)

---

## 19) Open questions (resolved)

* **FTS query API**: use `match_bm25` created under `fts_<schema>_<table>`; add `fields := '…'`.
* **Conscious categories**: `{rules, preferences, skills/tools, current project facts}` (as proposed).
* **STM defaults**: `capacity=20`, `TTL=14d`, `promotion_threshold=0.65`.

---

## 20) Quick reference snippets

**Install & load FTS (offline)**

```sql
INSTALL fts FROM '/opt/memori-local/duckdb_extensions';  -- your packaged dir
LOAD fts;
```

**Create indexes** (repeatable) and **search**: see §3.

**Tuning**

```sql
SET threads = 4;            -- host dependent
SET memory_limit = '2GB';   -- host dependent
SET temp_directory = '/tmp/memori.duckdb.tmp/';
```

---

### Why this will work well

* **Correct FTS usage** with BM25 and proper rebuild policy (a common gotcha).
* **Deterministic heuristics** catch 80/20 signal (preferences, rules, skills, project facts).
* **Claude Code hooks** give you deterministic injection/recording at the right lifecycle points.
* **Local‑only** and resource‑aware (threads/memory/temp).

If you want, I can turn this into a tiny reference repo (`memori-local/`) with the DDL, the `DuckDBManager`, the two CLIs, and example `.claude/hooks/*` scripts so you can `pipx install` and be ready to test inside Claude Code.
