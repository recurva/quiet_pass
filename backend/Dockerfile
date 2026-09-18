# Production image for Cloud Run: gunicorn supervising uvicorn workers.
# Single stage is enough here — no compiled deps beyond what pip's wheels
# already provide (asyncpg, PyJWT[crypto] ship manylinux wheels).
FROM python:3.12-slim

# Belt-and-braces against building against a stale layer cache pulling in an
# out-of-date pip.
RUN pip install --no-cache-dir --upgrade pip

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn==23.0.0

COPY . .

RUN useradd --create-home --uid 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Cloud Run injects $PORT (defaults to 8080) and expects the container to
# listen on it — not a fixed port. Shell form so $PORT expands; workers=2 is
# a reasonable default for Cloud Run's default 1 vCPU / 512Mi, adjust with
# the service's CPU allocation.
CMD exec gunicorn app.main:app \
    --workers 2 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:${PORT:-8080} \
    --timeout 0 \
    --access-logfile - \
    --error-logfile -
