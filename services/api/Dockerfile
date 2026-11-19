# ===== Giai đoạn 1: builder — cài thư viện vào một virtualenv riêng =====
FROM python:3.12-slim AS builder

# Tạo virtualenv tại /opt/venv: toàn bộ thư viện nằm gọn trong 1 thư mục để copy sang giai đoạn 2
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
# Copy requirements TRƯỚC code: code đổi mà requirements không đổi thì Docker dùng lại cache lớp này
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ===== Giai đoạn 2: runtime — chỉ chứa Python + venv + code, không có pip cache, file build =====
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Chạy bằng user thường (không phải root): container bị chiếm quyền thì thiệt hại ít hơn
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app.py .

USER 10001
EXPOSE 5000

# gunicorn: web server production (Flask dev server không dùng cho production)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
