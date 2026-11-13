import pytest

from labapp.config import ConfigError
from labapp.store import PostgresStore
from labapp.factory import build_app

ENV = {"DB_HOST": "postgres", "DB_NAME": "labapp", "DB_USER": "labapp", "DB_PASSWORD": "x"}


def test_build_app_wires_a_postgres_store_without_connecting():
    app = build_app(ENV)
    assert isinstance(app.config["LABAPP_STORE"], PostgresStore)
    assert app.test_client().get("/healthz").status_code == 200


def test_build_app_rejects_bad_config_before_serving():
    with pytest.raises(ConfigError, match="DB_CONNECT_TIMEOUT='5s'"):
        build_app({**ENV, "DB_CONNECT_TIMEOUT": "5s"})
