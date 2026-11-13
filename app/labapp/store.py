"""PostgreSQL-backed visit counter. One short connection per request keeps it simple."""

import psycopg

from .config import Config

SCHEMA = "CREATE TABLE IF NOT EXISTS visits (id BIGSERIAL PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT now())"


class PostgresStore:
    def __init__(self, config: Config):
        self._conninfo = config.conninfo()

    def _connect(self):
        return psycopg.connect(self._conninfo, autocommit=True)

    def visit_count(self) -> int:
        with self._connect() as conn:
            conn.execute(SCHEMA)
            return conn.execute("SELECT count(*) FROM visits").fetchone()[0]

    def record_visit(self) -> int:
        with self._connect() as conn:
            conn.execute(SCHEMA)
            conn.execute("INSERT INTO visits DEFAULT VALUES")
            return conn.execute("SELECT count(*) FROM visits").fetchone()[0]
