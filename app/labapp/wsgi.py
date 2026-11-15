"""Gunicorn entry point: `gunicorn --preload labapp.wsgi:app`.

With --preload the app, including its configuration, is loaded once in the master
process before the workers fork, so configuration is validated before any request
is served.
"""

import logging
import os

from .factory import build_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

app = build_app(os.environ)
