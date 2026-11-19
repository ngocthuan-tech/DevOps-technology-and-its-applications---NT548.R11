"""Unit test cho frontend: giả lập api bằng đối tượng HTTP giả, không cần api thật."""
import requests

from app import create_app


class FakeResponse:
    def __init__(self, payload, status=200):
        self.payload = payload
        self.status_code = status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code}")

    def json(self):
        return self.payload


class FakeHttp:
    def __init__(self, response=None, exc=None):
        self.response = response
        self.exc = exc

    def get(self, url, timeout):
        if self.exc:
            raise self.exc
        return self.response


def test_health():
    client = create_app(http=FakeHttp()).test_client()
    assert client.get("/health").status_code == 200


def test_index_shows_visits_and_versions():
    http = FakeHttp(FakeResponse({"visits": 42, "version": "abc123"}))
    html = create_app(http=http).test_client().get("/").get_data(as_text=True)
    assert "42" in html
    assert "abc123" in html


def test_index_still_renders_when_api_down():
    http = FakeHttp(exc=requests.ConnectionError("down"))
    resp = create_app(http=http).test_client().get("/")
    assert resp.status_code == 200
    assert "API không phản hồi" in resp.get_data(as_text=True)


def test_index_handles_api_error_status():
    http = FakeHttp(FakeResponse({"error": "redis unavailable"}, status=503))
    resp = create_app(http=http).test_client().get("/")
    assert resp.status_code == 200
    assert "API không phản hồi" in resp.get_data(as_text=True)
