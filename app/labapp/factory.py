"""Builds the app from an environment mapping."""

from typing import Mapping

from .app import create_app
from .config import load_config
from .store import PostgresStore


def build_app(env: Mapping[str, str]):
    config = load_config(env)
    store = PostgresStore(config)
    app = create_app(config, store)
    app.config["LABAPP_STORE"] = store
    return app
