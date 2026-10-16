# ============================================
# Smart Document Insights — single-container image
# Stage 1: build the React frontend
# Stage 2: Python backend that serves the API + the built UI
# Target: Hugging Face Spaces (Docker SDK, CPU Basic, free tier)
# ============================================

# ---------- Stage 1: frontend build ----------
FROM node:20-slim AS frontend
WORKDIR /frontend

# Install deps first for better layer caching
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

# Build the SPA -> /frontend/dist
COPY frontend/ ./
RUN npm run build


# ---------- Stage 2: Python backend ----------
FROM python:3.11-slim AS backend

# Runtime env
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=7860 \
    HF_HOME=/app/.cache/huggingface \
    SENTENCE_TRANSFORMERS_HOME=/app/.cache/sentence-transformers

WORKDIR /app

# Python dependencies (CPU-only torch; no Celery/Redis — processing runs inline)
COPY requirements-docker.txt ./
RUN pip install --no-cache-dir -r requirements-docker.txt

# Application code + built frontend
COPY backend/ ./backend/
COPY --from=frontend /frontend/dist ./frontend/dist

# Non-root user (HF Spaces runs as UID 1000). Owns /app so data + model cache
# are writable at runtime.
RUN useradd -m -u 1000 user && \
    mkdir -p /app/data/uploads /app/.cache && \
    chown -R user:user /app
USER user

# Pre-download the local embedding model so the first upload is fast and does
# not require network at request time.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

EXPOSE 7860

# Shell form so ${PORT} expands. main.py also reads PORT, but we drive uvicorn
# directly here for a clean production process (no reload).
CMD uvicorn backend.main:app --host 0.0.0.0 --port ${PORT}
