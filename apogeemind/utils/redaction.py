import re
from typing import List, Pattern


DEFAULT_PATTERNS: List[Pattern[str]] = [
    # API keys / tokens (generic-ish, conservative)
    re.compile(r"\b(?:sk|tok|key)_[A-Za-z0-9_\-]{16,}\b"),
    # Bearer tokens
    re.compile(r"Bearer\s+[A-Za-z0-9\-_.~+/=]{10,}"),
    # Email addresses
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    # Simple URL with basic auth
    re.compile(r"https?://[^\s:@]+:[^\s@]+@[^\s]+"),
]


def redact(text: str, extra_patterns: List[Pattern[str]] | None = None, replacement: str = "[REDACTED]") -> str:
    patterns = list(DEFAULT_PATTERNS)
    if extra_patterns:
        patterns.extend(extra_patterns)
    out = text
    for pat in patterns:
        out = pat.sub(replacement, out)
    return out

