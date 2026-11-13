"""PostgreSQL-backed visit counter. One short connection per request keeps it simple."""

import psycopg

from .config import Config

SCHEMA = "CREATE TABLE IF NOT EXISTS visits (id BIGSERIAL PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT now())"


class PostgresStore:
    def __init__(self, config: Config):
        self._conninfo = config.conninfo()

    def _connect(self):
        conn = psycopg.connect(self._conninfo, autocommit=True)
        # Create the table only when missing: on AKS the app role may lack CREATE on
        # the schema, and the deploy step creates the table ahead of time.
        if conn.execute("SELECT to_regclass('visits')").fetchone()[0] is None:
            conn.execute(SCHEMA)
        return conn

    def visit_count(self) -> int:
        with self._connect() as conn:
            return conn.execute("SELECT count(*) FROM visits").fetchone()[0]

    def record_visit(self) -> int:
        with self._connect() as conn:
            conn.execute("INSERT INTO visits DEFAULT VALUES")
            return conn.execute("SELECT count(*) FROM visits").fetchone()[0]
