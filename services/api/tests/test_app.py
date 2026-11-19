"""Unit test cho api: dùng Redis giả trong bộ nhớ, không cần Redis thật."""
import pytest
import redis

from app import create_app


class FakeRedis:
    """Redis giả: chỉ cài các lệnh mà app dùng."""

    def __init__(self, healthy=True):
        self.healthy = healthy
        self.store = {}

    def _check(self):
        if not self.healthy:
            raise redis.ConnectionError("down")

    def ping(self):
        self._check()
        return True

    def incr(self, key):
        self._check()
        self.store[key] = self.store.get(key, 0) + 1
        return self.store[key]


@pytest.fixture
def client():
    return create_app(redis_client=FakeRedis()).test_client()


@pytest.fixture
def broken_client():
    return create_app(redis_client=FakeRedis(healthy=False)).test_client()


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_health_ok_even_when_redis_down(broken_client):
    # Liveness không phụ thuộc Redis: Redis chết thì không được restart api
    assert broken_client.get("/health").status_code == 200


def test_ready_ok(client):
    assert client.get("/ready").status_code == 200


def test_ready_fails_when_redis_down(broken_client):
    assert broken_client.get("/ready").status_code == 503


def test_info(client):
    data = client.get("/api/info").get_json()
    assert data["service"] == "api"
    assert "version" in data


def test_visits_increments(client):
    assert client.get("/api/visits").get_json()["visits"] == 1
    assert client.get("/api/visits").get_json()["visits"] == 2


def test_visits_returns_503_when_redis_down(broken_client):
    assert broken_client.get("/api/visits").status_code == 503
