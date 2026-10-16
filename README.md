# ⚡ DocInsights — AI Document Intelligence (RAG) Platform

Upload documents, ask questions, and get **source-cited** answers. DocInsights is a
retrieval-augmented-generation platform with **explainable retrieval** — every answer
shows exactly which chunks of which document it came from, with relevance scores.

This Space runs the **entire app in one container**: a FastAPI backend that serves both
the JSON API and the built React UI, with a local embedding model and an on-disk FAISS
index. **No API key is required to try it** — see _Bring your own key_ below.

### 🔗 Live demo

**👉 [Try it here](https://huggingface.co/spaces/aditya3526/docinsights)**

> Live demo note: this is the free **CPU Basic** tier with an **ephemeral filesystem**.
> See _Honest framing_ at the bottom before judging it as production infrastructure.

<!--
Screenshot intentionally omitted: the images in docs/ are stale (older 4-item sidebar
without Multi-Chat / Add-LLM-Key, and a data-rich dashboard that reflects a keyed state,
not the keyless demo). Drop a fresh capture of the current UI here when you have one, e.g.:
<p align="center"><img src="docs/dashboard.png" alt="DocInsights dashboard" width="100%"/></p>
-->

---

## What it actually does

- **Semantic search** over your documents using a FAISS vector index.
- **Chat (RAG)** against a single document or across several at once, with cited sources.
- **Insights** — executive summary, key-info extraction, and risk detection.
- **Compare** up to 5 documents and generate a downloadable PDF report.

Supported formats: **PDF, DOCX, TXT** (up to 50 MB). Text-based PDFs work out of the box;
scanned-PDF OCR is best-effort and disabled in this slim image.

---

## The engineering worth looking at

- **FAISS flat → IVF auto-upgrade.** Starts as an exact `IndexFlatIP` (cosine via
  normalized inner product). Once the index passes **256 vectors**, it automatically
  rebuilds into an `IndexIVFFlat` (clusters = `min(√n, 64)`, `nprobe = min(nlist, 10)`)
  for sub-linear search — without losing the existing vectors.
- **Timeout-safe LLM wrapper.** Every LLM call goes through a wrapper with an **LRU
  response cache** (256 entries, 1-hour TTL), **exponential-backoff retry** (2 retries),
  and a **hard timeout** enforced by a worker thread. On timeout or error it returns a
  graceful fallback — the request never hangs and never 500s on the model.
- **Local-embedding fallback.** Embeddings run **locally** with `all-MiniLM-L6-v2`
  (384-dim, normalized) by default, so the app is fully functional with **zero API keys**.
  Embeddings stay local even when you supply an LLM key — this keeps the FAISS index
  dimension stable and avoids a costly re-index.
- **Bounded multi-doc retrieval.** Multi-document chat over-fetches with a hard cap
  (`min(top_k×3, 50)`), deduplicates, caps per-document chunks (3), and builds a
  **token-aware, round-robin context** (≤6000 token budget across ≤10 chunks).
- **Synchronous-first processing.** Uploads are processed **inline** in the request
  (extract → chunk → embed → index) — no Celery/Redis needed. A `USE_CELERY` flag exists
  for anyone who wants to run a real worker + broker elsewhere.

---

## Bring your own key (and the keyless demo)

DocInsights is **OpenAI-compatible** (OpenAI, OpenRouter, or any `base_url` that speaks
the OpenAI chat API).

- **No key →** the app works in **demo mode**: retrieval, search, and citations are fully
  real; LLM-generated text is a clearly-labeled placeholder.
- **Your key →** click **"Add LLM Key"** in the sidebar and paste your own key (optionally a
  model and base URL). You get real LLM answers.

Your key is **never stored**: it's held in your browser tab's memory only (cleared on
refresh), sent per-request as a header, used by the server for that one request, and
never written to disk, the database, or the logs.

---

## Run it locally

```bash
# 1. Build the frontend
cd frontend && npm ci && npm run build && cd ..

# 2. Install backend deps (CPU-only) and run
pip install -r requirements-docker.txt
uvicorn backend.main:app --host 0.0.0.0 --port 7860
# open http://localhost:7860
```

Or with Docker (same image the Space uses):

```bash
docker build -t docinsights .
docker run -p 7860:7860 docinsights
```

---

## Configuration

All config is via environment variables (see `backend/config.py`). Sensible defaults make
the app boot with none set. Notable ones:

| Variable               | Default           | Notes                                                                     |
| ---------------------- | ----------------- | ------------------------------------------------------------------------- |
| `SECRET_KEY`           | insecure sentinel | **Set this in production** (HF Space → Settings → Secrets).               |
| `USE_LOCAL_EMBEDDINGS` | `true`            | Keep `true` for the keyless/CPU demo.                                     |
| `USE_CELERY`           | `false`           | Inline processing; set `true` only with a real worker + Redis.            |
| `OPENAI_API_KEY`       | empty             | Optional server-side key. Per-request BYO-key overrides it.               |
| `OPENAI_MODEL`         | `gpt-3.5-turbo`   | Any OpenAI-compatible chat model.                                         |
| `OPENAI_API_BASE`      | unset             | For OpenRouter / self-hosted OpenAI-compatible endpoints.                 |
| `CORS_ORIGINS`         | `*`               | Same-origin in this single-container setup; tighten if you split origins. |
| `PORT`                 | `7860`            | The container listens here; matches the Space `app_port`.                 |

---

## Honest framing

This is a **portfolio / demo deployment**, and it's worth being upfront about the limits:

- **Free CPU tier.** No GPU. Local embedding + small-doc processing run in a few seconds;
  large documents will be slower.
- **Bring-your-own-key for real answers.** Without a key, LLM text is a placeholder — the
  retrieval and citation machinery is real, the generation is not.
- **Ephemeral filesystem.** Uploaded files, the SQLite database, and the FAISS index all
  live on the container's disk and **reset whenever the Space restarts or rebuilds**.
  Treat anything you upload here as temporary.
- **No auth / multi-tenancy.** Everyone shares one instance. Don't upload anything sensitive.

The architecture (async FastAPI, Postgres-ready data layer, Celery-capable processing,
persistent vector store) is built to run as a real service — this particular deployment
is just the free-tier, single-container demo of it.

---

## Stack

FastAPI · React 18 + Vite + Tailwind · SQLite (async SQLAlchemy) · FAISS (CPU) ·
sentence-transformers · LangChain (OpenAI-compatible) · Docker
