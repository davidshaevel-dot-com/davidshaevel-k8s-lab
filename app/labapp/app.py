"""HTTP endpoints. The store is injected so tests can run without PostgreSQL."""

import logging
import socket

from flask import Flask, jsonify

from . import __version__
from .config import Config

log = logging.getLogger("labapp")


def create_app(config: Config, store) -> Flask:
    app = Flask("labapp")

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        # Deliberately independent of the database: a database outage shows up as
        # 503s from /api/visits on a Ready pod, not as an unready rollout.
        return jsonify(status="ready")

    @app.get("/")
    def index():
        return jsonify(app="labapp", version=__version__, hostname=socket.gethostname())

    def _db(action):
        try:
            return jsonify(count=action())
        except Exception as exc:  # noqa: BLE001 - every DB failure maps to 503
            log.error("database error: %s", exc)
            return jsonify(error="database unavailable", detail=str(exc).strip()), 503

    @app.get("/api/visits")
    def get_visits():
        return _db(store.visit_count)

    @app.post("/api/visits")
    def post_visit():
        return _db(store.record_visit)

    return app
