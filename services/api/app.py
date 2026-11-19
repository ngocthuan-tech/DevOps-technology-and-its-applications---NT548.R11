"""
Service "api": REST API đếm lượt truy cập, lưu bộ đếm trong Redis.

Endpoint:
  GET /health      -> liveness: tiến trình còn sống không (KHÔNG phụ thuộc Redis)
  GET /ready       -> readiness: đã kết nối được Redis chưa (Kubernetes chỉ gửi traffic khi 200)
  GET /api/info    -> tên service + phiên bản (APP_VERSION = image tag do CI gắn)
  GET /api/visits  -> tăng bộ đếm trong Redis và trả về giá trị mới
"""
import os

import redis
from flask import Flask, jsonify

# Cấu hình đọc từ biến môi trường (12-factor): image giống nhau, môi trường khác nhau chỉ đổi env
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
APP_VERSION = os.getenv("APP_VERSION", "dev")
VISITS_KEY = "visits"


def create_app(redis_client=None):
    """App factory: cho phép test truyền vào Redis giả thay vì Redis thật."""
    app = Flask(__name__)

    # Timeout ngắn: Redis chết thì trả lỗi nhanh thay vì treo request
    client = redis_client or redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        socket_connect_timeout=1,
        socket_timeout=1,
        decode_responses=True,
    )

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/ready")
    def ready():
        try:
            client.ping()
            return jsonify(status="ready")
        except redis.RedisError:
            return jsonify(status="redis unavailable"), 503

    @app.get("/api/info")
    def info():
        return jsonify(service="api", version=APP_VERSION)

    @app.get("/api/visits")
    def visits():
        try:
            count = client.incr(VISITS_KEY)  # INCR là atomic: nhiều Pod api cùng tăng vẫn đúng
            return jsonify(visits=count, version=APP_VERSION)
        except redis.RedisError:
            return jsonify(error="redis unavailable"), 503

    return app


# Đối tượng "app" để gunicorn chạy: gunicorn app:app
app = create_app()
