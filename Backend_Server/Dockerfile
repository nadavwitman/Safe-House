FROM python:3.11-slim

WORKDIR /app

# libgomp1  — required by PyTorch (OpenMP threading)
# build-essential / libffi-dev — needed by some Firebase/cryptography wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (cached layer — only re-runs when requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gunicorn

# Copy application source (secrets are injected at runtime, not baked in)
COPY app/       app/
COPY database/  database/
COPY wsgi.py    .

EXPOSE 5000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Single worker — APScheduler runs inside the process, so multiple workers
# would create duplicate scheduled jobs.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "1", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "wsgi:application"]
