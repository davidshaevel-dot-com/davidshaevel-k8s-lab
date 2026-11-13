"""Runs only against a real PostgreSQL: set LABAPP_TEST_DB_* (same names as DB_*)."""

import os

import pytest

from labapp.config import load_config
from labapp.store import PostgresStore

PREFIX = "LABAPP_TEST_"
env = {k[len(PREFIX):]: v for k, v in os.environ.items() if k.startswith(PREFIX + "DB_")}

pytestmark = pytest.mark.skipif("DB_HOST" not in env, reason="no test database configured")


def test_record_visit_increments_persisted_count():
    store = PostgresStore(load_config(env))
    before = store.visit_count()
    assert store.record_visit() == before + 1
    assert store.visit_count() == before + 1
