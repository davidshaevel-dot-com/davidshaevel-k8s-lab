"""Configuration from environment variables. Bad values fail fast at startup."""

from dataclasses import dataclass
from typing import Mapping


class ConfigError(ValueError):
    pass


REQUIRED = ("DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD")


@dataclass(frozen=True)
class Config:
    db_host: str
    db_name: str
    db_user: str
    db_password: str
    db_port: int = 5432
    db_connect_timeout: int = 3
    db_sslmode: str = "prefer"

    def conninfo(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.db_name} "
            f"user={self.db_user} password={self.db_password} "
            f"connect_timeout={self.db_connect_timeout} sslmode={self.db_sslmode}"
        )


def _int(env: Mapping[str, str], name: str, default: int) -> int:
    raw = env.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        raise ConfigError(f"invalid integer for {name}={raw!r}") from None


def load_config(env: Mapping[str, str]) -> Config:
    missing = [name for name in REQUIRED if not env.get(name)]
    if missing:
        raise ConfigError(f"missing required environment variable(s): {', '.join(missing)}")
    return Config(
        db_host=env["DB_HOST"],
        db_name=env["DB_NAME"],
        db_user=env["DB_USER"],
        db_password=env["DB_PASSWORD"],
        db_port=_int(env, "DB_PORT", 5432),
        db_connect_timeout=_int(env, "DB_CONNECT_TIMEOUT", 3),
        db_sslmode=env.get("DB_SSLMODE") or "prefer",
    )
