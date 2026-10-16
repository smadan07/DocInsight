<h1 align="center">⚡ DocInsights</h1>
<p align="center">
  <b>AI-powered document intelligence — upload, ask, understand.</b><br/>
  A full-stack RAG (Retrieval-Augmented Generation) platform with semantic search, multi-document chat, and explainable citations.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white"/>
  <img src="https://img.shields.io/badge/React-20232A?style=for-the-badge&logo=react&logoColor=61DAFB"/>
  <img src="https://img.shields.io/badge/FAISS-0467DF?style=for-the-badge&logo=meta&logoColor=white"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white"/>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white"/>
</p>

<p align="center">
  <a href="https://huggingface.co/spaces/aditya3526/docinsights">🚀 Live Demo on HuggingFace Spaces</a>
</p>

---

## 📌 What Is This?

**DocInsights** lets you upload a PDF, Word document, or plain text file and then:

- 💬 **Chat with it** — ask questions, get answers with exact source citations
- 🔍 **Semantic search** — find relevant sections by meaning, not just keywords
- 🧠 **Generate insights** — auto-summary, key info extraction, risk detection
- 📊 **Compare documents** — side-by-side analysis of up to 5 documents

No data leaves your browser without your consent. **No API key required** to explore — the retrieval and search pipeline works completely offline using a local embedding model.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser (React)                       │
│   Upload ──► Chat ──► Search ──► Insights ──► Compare       │
└─────────────────────┬───────────────────────────────────────┘
                       │ HTTP (REST + SSE streaming)
┌─────────────────────▼───────────────────────────────────────┐
│                   FastAPI Backend                            │
│                                                              │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │  Document   │  │  Embedding   │  │    RAG Service     │  │
│  │  Processor  │  │  Service     │  │  (ask_question,    │  │
│  │  PDF/DOCX   │  │  MiniLM-L6   │  │   summarize,       │  │
│  │  /TXT + OCR │  │  384-dim     │  │   compare)         │  │
│  └──────┬──────┘  └──────┬───────┘  └────────┬───────────┘  │
│         │                │                    │              │
│  ┌──────▼────────────────▼────────┐  ┌────────▼───────────┐  │
│  │         Vector Store           │  │    LLM Client      │  │
│  │  FAISS IndexFlatIP → IVFFlat  │  │  OpenAI-compatible │  │
│  │  Thread-safe · LRU cached     │  │  LRU cached · BYO  │  │
│  └────────────────────────────────┘  └────────────────────┘  │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  SQLite (async SQLAlchemy) — Documents + Chunks         │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 How a Document Is Processed

When you upload a file, this pipeline runs automatically:

```
1. VALIDATE   → extension ✓  file size <50MB ✓  magic bytes ✓
2. SAVE       → write to disk, create DB record
3. EXTRACT    → pull raw text (PyMuPDF / python-docx / chardet)
4. CHUNK      → split into 1000-char chunks, 200-char overlap
5. EMBED      → all-MiniLM-L6-v2 → 384-dimensional float32 vectors
6. INDEX      → add vectors to FAISS, persist to disk
                                          ↓
                              Document Status = READY ✅
```

**When you ask a question:**

```
1. EMBED query   → same model converts your question to 384 numbers
2. FAISS search  → find top-5 most similar chunks by cosine similarity
3. BUILD prompt  → inject chunks as context into LLM prompt
4. LLM call      → get grounded answer with citations
5. RETURN        → answer + source chunks + relevance scores
```

---

## ✨ Key Engineering Features

### 🔍 FAISS Auto-Upgrade: Flat → IVF
```python
# Starts as exact brute-force search
_faiss_index = faiss.IndexFlatIP(384)

# Auto-upgrades at 256+ vectors to cluster-based approximate search
nlist = min(int(np.sqrt(n_vectors)), 64)
new_index = faiss.IndexIVFFlat(quantizer, dim, nlist)
new_index.nprobe = min(nlist, 10)
```
- **< 256 vectors** → `IndexFlatIP`: exact cosine similarity, checks every vector
- **≥ 256 vectors** → `IndexIVFFlat`: groups into √n clusters (max 64), searches 10 nearest clusters per query — **sub-linear search time at scale**
- Zero data loss: all vectors are reconstructed and re-added during upgrade

### 🔒 Thread-Safe Vector Store
```python
_lock = RLock()  # Re-entrant lock for all FAISS operations
```
FAISS is not thread-safe. Every read/write acquires an `RLock` — safe for concurrent uploads.

### ⚡ Dual LRU Caches
| Cache | Size | TTL | Key |
|---|---|---|---|
| LLM Response Cache | 256 entries | 1 hour | MD5(prompt) |
| Query Embedding Cache | 512 entries | — | MD5(query text) |

Identical prompts skip the LLM call entirely. Same query text reuses the cached vector.

### 🛡️ Timeout-Safe LLM Wrapper
```python
with ThreadPoolExecutor(max_workers=1) as executor:
    future = executor.submit(ctx.run, get_llm_response, prompt)
    result = future.result(timeout=15)  # Hard 15-second limit
```
- Runs every LLM call in a worker thread with a 15s hard timeout
- On timeout or error → polite fallback message, never a 500
- Uses `contextvars.copy_context()` so the per-request BYO-key propagates to the thread

### 🔑 Bring-Your-Own-Key (Per-Request, Never Stored)
```python
@app.middleware("http")
async def apply_byo_key(request: Request, call_next):
    token = set_request_llm_override(
        api_key=request.headers.get("X-LLM-API-Key"), ...
    )
    try:
        return await call_next(request)
    finally:
        clear_request_llm_override(token)  # Always cleared
```
Key lives in a Python `ContextVar` — scoped to one request, never written to disk or logs.

### 🔄 Exponential Backoff Retry
```python
for attempt in range(max_retries + 1):
    try:
        response = _call_llm(...)
        break
    except Exception:
        time.sleep(2 ** attempt)  # 1s → 2s → 4s
```

### 📄 Smart Text Truncation
For documents exceeding the LLM context window — takes **beginning + middle + end** instead of naive head-only truncation:
```python
def _smart_truncate(text, max_chars=12000):
    return text[:third] + "[...middle...]" + text[mid] + "[...end...]" + text[-third:]
```

---

## 🌐 API Reference

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/documents/upload` | Upload + process a document |
| `GET` | `/api/documents` | List all documents |
| `GET` | `/api/documents/{id}` | Get document details |
| `DELETE` | `/api/documents/{id}` | Delete document + embeddings |
| `POST` | `/api/chat` | RAG Q&A on a single document |
| `POST` | `/api/chat/v2` | Multi-document RAG chat |
| `POST` | `/api/search` | Semantic search across documents |
| `POST` | `/api/insights/{id}` | Summary + key info + risk detection |
| `POST` | `/api/compare` | Compare up to 5 documents |
| `GET` | `/api/health` | Health check + LLM/cache status |

---

## 🚀 Running Locally

### Option 1 — Without Docker

```bash
# 1. Build the frontend
cd frontend
npm ci
npm run build
cd ..

# 2. Install Python dependencies
pip install -r requirements-docker.txt

# 3. Start the server
uvicorn backend.main:app --host 0.0.0.0 --port 7860

# Open: http://localhost:7860
```

### Option 2 — With Docker

```bash
docker build -t docinsights .
docker run -p 7860:7860 docinsights

# Open: http://localhost:7860
```

---

## ⚙️ Configuration

All config is via environment variables. The app boots with zero config set.

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY` | insecure sentinel | **Set this in production** |
| `USE_LOCAL_EMBEDDINGS` | `true` | Keep `true` — local MiniLM, no API needed |
| `USE_CELERY` | `false` | Inline processing; set `true` with Redis + worker |
| `OPENAI_API_KEY` | empty | Optional server-side key (BYO-key overrides) |
| `OPENAI_MODEL` | `gpt-3.5-turbo` | Any OpenAI-compatible chat model |
| `OPENAI_API_BASE` | unset | For OpenRouter / self-hosted endpoints |
| `DATABASE_URL` | SQLite | Swap to Postgres URL for production |
| `PORT` | `7860` | Server port |

Copy `.env.example` → `.env` to get started.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Backend** | FastAPI + Uvicorn (async Python) |
| **Frontend** | React 18 + Vite + Tailwind CSS |
| **Database** | SQLite with async SQLAlchemy (Postgres-ready) |
| **Vector Store** | FAISS (CPU) — IndexFlatIP → IndexIVFFlat |
| **Embeddings** | `all-MiniLM-L6-v2` via sentence-transformers (local, 384-dim) |
| **LLM** | LangChain + OpenAI-compatible API (OpenAI / OpenRouter / self-hosted) |
| **PDF Parsing** | PyMuPDF (fitz) + OCR fallback |
| **DOCX Parsing** | python-docx |
| **Containerization** | Docker (single container — backend + frontend) |
| **Deployment** | HuggingFace Spaces (free CPU tier) |

---

## 🤖 LLM Key — Demo Mode vs Full Mode

| Feature | No Key (Demo Mode) | With Key |
|---|---|---|
| Upload documents | ✅ | ✅ |
| Text extraction | ✅ | ✅ |
| Chunking & embeddings | ✅ | ✅ |
| FAISS semantic search | ✅ | ✅ |
| Source citations | ✅ | ✅ |
| AI-generated answers | ❌ placeholder | ✅ real LLM |

Click **"Add LLM Key"** in the sidebar to paste your OpenAI / OpenRouter key.
Works with any OpenAI-compatible API — just set the base URL.

---

## ⚠️ Known Limitations (Demo Deployment)

- **Ephemeral filesystem** — HuggingFace free tier resets on restart. All uploads, the SQLite DB, and the FAISS index are temporary.
- **No auth / multi-tenancy** — everyone shares one instance. Don't upload sensitive documents.
- **CPU only** — no GPU. Suitable for small-to-medium documents.
- **BYO-key** — real LLM answers require your own API key.

> The underlying architecture supports persistent storage, Postgres, Celery workers, and multi-tenancy — this deployment is a single-container demo of that foundation.

---

## 📁 Project Structure

```
DocInsights/
├── backend/
│   ├── main.py                 # FastAPI app + middleware
│   ├── database.py             # Async SQLAlchemy setup
│   ├── config.py               # Environment config
│   ├── api/
│   │   ├── documents.py        # Upload, list, delete endpoints
│   │   ├── chat.py             # Single + multi-doc RAG
│   │   ├── search.py           # Semantic search
│   │   └── insights.py         # Summary, risks, compare
│   ├── services/
│   │   ├── vector_store.py     # FAISS management (thread-safe)
│   │   ├── embedding_service.py # MiniLM embeddings + LRU cache
│   │   ├── llm_client.py       # LLM wrapper (cache + timeout + retry)
│   │   ├── rag_service.py      # ask_question, summarize, compare
│   │   ├── document_processor.py # PDF/DOCX/TXT extraction
│   │   └── llm_context.py      # BYO-key ContextVar management
│   └── utils/
│       └── text_utils.py       # Chunking, smart truncation
├── frontend/                   # React 18 + Vite + Tailwind
├── Dockerfile                  # Single-container build
├── requirements.txt
└── requirements-docker.txt
```

---

<p align="center">Built with ❤️ · FastAPI · React · FAISS · sentence-transformers</p>
