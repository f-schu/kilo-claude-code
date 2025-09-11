import hashlib
import json
import re
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


TECH_KEYWORDS = {
    # Languages / Runtimes
    "python",
    "go",
    "golang",
    "rust",
    "node",
    "typescript",
    "javascript",
    "java",
    "kotlin",
    "swift",
    # Frameworks / Libraries
    "fastapi",
    "flask",
    "django",
    "react",
    "vue",
    "svelte",
    "pytest",
    "junit",
    # Databases / Infra
    "postgres",
    "postgresql",
    "mysql",
    "sqlite",
    "duckdb",
    "redis",
    "docker",
    "kubernetes",
}

FILE_PATTERN = re.compile(r"(?:\b|\./|/)[\w./-]+\.(?:py|go|ts|tsx|js|rs|md|json|yaml|yml|toml)\b")
ISSUE_PATTERN = re.compile(r"\b(?:#\d+|[A-Z]{2,10}-\d{1,6})\b")
PREF_PATTERN = re.compile(r"\b(i\s+prefer|i\s+like|default\s+to|please\s+always)\b", re.I)
RULE_PATTERN = re.compile(r"\b(always|never|do\s+not|must|should)\b", re.I)


@dataclass
class ProcessedMemory:
    category_primary: str
    summary: str
    searchable_content: str
    importance_score: float
    classification: Optional[str]
    entities: List[str]
    keywords: List[str]
    promotion_eligible: bool
    content_hash: str


class HeuristicProcessor:
    """Deterministic processing of conversations into structured memory items."""

    def __init__(self, promotion_threshold: float = 0.65) -> None:
        self.promotion_threshold = promotion_threshold

    def process_conversation(self, user_input: str, ai_output: str) -> List[ProcessedMemory]:
        text = self._normalize(f"{user_input}\n\n{ai_output}")
        summary = self._summarize(ai_output or user_input)
        category = self._classify(user_input, ai_output)
        entities, keywords = self._extract_entities_keywords(text)
        importance = self._importance_score(text, category, entities, keywords)
        content_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()

        classification = None
        if category in {"preference", "rule"}:
            classification = "conscious-info"

        promotion_eligible = importance >= self.promotion_threshold and category in {
            "preference",
            "rule",
            "skill",
            "context",
        }

        pm = ProcessedMemory(
            category_primary=category,
            summary=summary,
            searchable_content=text,
            importance_score=importance,
            classification=classification,
            entities=entities,
            keywords=keywords,
            promotion_eligible=promotion_eligible,
            content_hash=content_hash,
        )

        return [pm]

    def _normalize(self, s: str) -> str:
        # Strip code blocks, condense whitespace
        s = re.sub(r"```[\s\S]*?```", " ", s)
        s = re.sub(r"\s+", " ", s).strip()
        return s

    def _summarize(self, s: str, max_len: int = 280) -> str:
        s = self._normalize(s)
        if len(s) <= max_len:
            return s
        # Try to keep first sentence or meaningful chunk
        dot = s.find(". ")
        if 0 < dot < max_len:
            head = s[: max_len - 3]
        else:
            head = s[: max_len - 3]
        return head + "…"

    def _classify(self, user: str, ai: str) -> str:
        combo = f"{user}\n{ai}"
        if PREF_PATTERN.search(combo):
            return "preference"
        if RULE_PATTERN.search(combo):
            return "rule"
        # Skills/knowledge if tech mentions present
        tokens = set(self._normalize(combo).split())
        if any(tok in tokens for tok in TECH_KEYWORDS):
            return "skill"
        # Context if issues/paths present
        if FILE_PATTERN.search(combo) or ISSUE_PATTERN.search(combo):
            return "context"
        return "context"  # default conservative

    def _extract_entities_keywords(self, text: str) -> Tuple[List[str], List[str]]:
        entities: List[str] = []
        for m in FILE_PATTERN.findall(text):
            entities.append(m)
        for m in ISSUE_PATTERN.findall(text):
            entities.append(m)

        tokens = set(text.lower().split())
        kws = sorted(list(tokens.intersection(TECH_KEYWORDS)))
        return list(dict.fromkeys(entities)), kws

    def _importance_score(self, text: str, category: str, entities: List[str], keywords: List[str]) -> float:
        # Length penalty
        l = len(text)
        length_penalty = 0.0 if l < 800 else 0.15 if l < 2000 else 0.3

        # Category boost
        cat_boost = {
            "preference": 0.25,
            "rule": 0.25,
            "skill": 0.15,
            "context": 0.1,
        }.get(category, 0.0)

        # Entities/keywords boost
        ent_kw_boost = min(0.2, 0.02 * (len(entities) + len(keywords)))

        base = 0.4 + cat_boost + ent_kw_boost - length_penalty
        # Bound to [0,1]
        return max(0.0, min(1.0, base))

