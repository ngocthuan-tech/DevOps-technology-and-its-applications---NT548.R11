"""
Service "frontend": trang web gọi sang service "api" qua HTTP nội bộ.

Endpoint:
  GET /        -> trang HTML hiển thị lượt truy cập + phiên bản frontend/api
  GET /health  -> liveness/readiness cho Kubernetes
"""
import os

import requests
from flask import Flask, render_template_string

# Trong Kubernetes/docker-compose, "api" là tên Service -> DNS nội bộ tự phân giải ra IP
API_URL = os.getenv("API_URL", "http://api:5000")
APP_VERSION = os.getenv("APP_VERSION", "dev")
API_TIMEOUT = 2  # giây: api chậm/chết thì frontend không bị treo theo

PAGE = """<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <title>NT548 – DevSecOps + GitOps demo</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 48px auto; padding: 0 16px; color: #222; }
    .card { border: 1px solid #ddd; border-radius: 12px; padding: 24px; }
    .big { font-size: 48px; font-weight: 700; margin: 8px 0; }
    .err { color: #b00020; }
    code { background: #f4f4f4; padding: 2px 6px; border-radius: 4px; }
  </style>
</head>
<body>
  <h1>NT548 – Microservices trên EKS</h1>
  <div class="card">
    {% if visits is not none %}
      <div>Số lượt truy cập</div>
      <div class="big">{{ visits }}</div>
    {% else %}
      <p class="err">API không phản hồi: {{ error }}</p>
    {% endif %}
    <p>Phiên bản frontend: <code>{{ frontend_version }}</code></p>
    <p>Phiên bản api: <code>{{ api_version }}</code></p>
  </div>
</body>
</html>"""


def create_app(http=requests):
    """App factory: test có thể truyền vào đối tượng HTTP giả thay cho thư viện requests."""
    app = Flask(__name__)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.get("/")
    def index():
        visits, api_version, error = None, "không rõ", None
        try:
            resp = http.get(f"{API_URL}/api/visits", timeout=API_TIMEOUT)
            resp.raise_for_status()
            data = resp.json()
            visits = data.get("visits")
            api_version = data.get("version", "không rõ")
        except requests.RequestException as exc:
            # Suy giảm có kiểm soát (graceful degradation): api lỗi thì vẫn hiện trang, chỉ báo lỗi
            error = type(exc).__name__
        return render_template_string(
            PAGE,
            visits=visits,
            error=error,
            frontend_version=APP_VERSION,
            api_version=api_version,
        )

    return app


app = create_app()
