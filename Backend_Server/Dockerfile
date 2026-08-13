FROM python:3.11-slim

WORKDIR /app

# libgomp1  — required by PyTorch (OpenMP threading)
# build-essential / libffi-dev — needed by some Firebase/cryptography wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (cached layer — only re-runs when requirements.txt changes)
COPY Backend_Server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gunicorn

# Copy application source (secrets are injected at runtime, not baked in).
# Build context is the repo root (see below), since AI_Model lives there, not in Backend_Server/.
COPY Backend_Server/app/         app/
COPY Backend_Server/database/    database/
COPY Backend_Server/entrypoints/ entrypoints/
COPY AI_Model/                   AI_Model/

# Per-house fine-tuned models are written here at runtime (see model_manager.py) and
# should be backed by a mounted volume in production so they survive container recreation.
RUN mkdir -p AI_Model/trained_models

EXPOSE 5000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    AI_MODEL_DIR=/app/AI_Model

# Single worker — APScheduler runs inside the process, so multiple workers
# would create duplicate scheduled jobs.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "1", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "entrypoints.wsgi:application"]
