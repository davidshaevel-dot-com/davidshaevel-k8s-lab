"""Gunicorn entry point: `gunicorn --preload labapp.wsgi:app`.

With --preload a bad configuration fails in the master process and the container
exits non-zero, so Kubernetes restarts it (CrashLoopBackOff) with the reason in the logs.
"""

import logging
import os

from .factory import build_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

app = build_app(os.environ)
