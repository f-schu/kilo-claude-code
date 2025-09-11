import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


def _env_bool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class Config:
    db_path: str
    namespace: str
    conscious_ingest: bool = True
    auto_ingest: bool = True
    stm_capacity: int = 20
    promotion_threshold: float = 0.65

    @classmethod
    def from_env(
        cls,
        default_db: Optional[str] = None,
        default_namespace: Optional[str] = None,
    ) -> "Config":
        db_path = os.environ.get(
            "APOGEEMIND_DUCKDB_PATH", default_db or str(Path.cwd() / "apogeemind" / "apogeemind.duckdb")
        )
        namespace = os.environ.get("APOGEEMIND_NAMESPACE", default_namespace or "default")
        conscious = _env_bool("APOGEEMIND_CONSCIOUS", True)
        auto = _env_bool("APOGEEMIND_AUTO", True)
        stm_capacity = int(os.environ.get("APOGEEMIND_STM_CAPACITY", os.environ.get("STM_CAPACITY", "20")))
        promotion_threshold = float(os.environ.get("APOGEEMIND_PROMOTION_THRESHOLD", os.environ.get("PROMOTION_THRESHOLD", "0.65")))
        return cls(
            db_path=db_path,
            namespace=namespace,
            conscious_ingest=conscious,
            auto_ingest=auto,
            stm_capacity=stm_capacity,
            promotion_threshold=promotion_threshold,
        )
