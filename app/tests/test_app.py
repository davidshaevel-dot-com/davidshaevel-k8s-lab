import pytest

from labapp.app import create_app
from labapp.config import load_config

CFG = load_config({"DB_HOST": "postgres", "DB_NAME": "labapp", "DB_USER": "labapp", "DB_PASSWORD": "x"})


class FakeStore:
    """In-memory stand-in for the PostgreSQL store; set .error to simulate an outage."""

    def __init__(self):
        self.count = 0
        self.error = None

    def _check(self):
        if self.error:
            raise self.error

    def visit_count(self):
        self._check()
        return self.count

    def record_visit(self):
        self._check()
        self.count += 1
        return self.count


@pytest.fixture
def store():
    return FakeStore()


@pytest.fixture
def client(store):
    return create_app(CFG, store).test_client()


def test_healthz_is_ok_without_touching_the_database(client, store):
    store.error = RuntimeError("db down")
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_readyz_does_not_depend_on_the_database(client, store):
    store.error = RuntimeError("db down")
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ready"}


def test_index_identifies_the_app(client):
    body = client.get("/").get_json()
    assert body["app"] == "labapp"
    assert "version" in body and "hostname" in body


def test_post_visit_writes_and_returns_new_count(client, store):
    assert client.post("/api/visits").get_json() == {"count": 1}
    assert client.post("/api/visits").get_json() == {"count": 2}
    assert store.count == 2


def test_get_visits_reads_count(client, store):
    store.count = 7
    resp = client.get("/api/visits")
    assert resp.status_code == 200
    assert resp.get_json() == {"count": 7}


@pytest.mark.parametrize("method", ["get", "post"])
def test_database_error_is_503_with_detail(client, store, method):
    store.error = RuntimeError('could not translate host name "postgress" to address')
    resp = getattr(client, method)("/api/visits")
    assert resp.status_code == 503
    body = resp.get_json()
    assert body["error"] == "database unavailable"
    assert "could not translate host name" in body["detail"]
