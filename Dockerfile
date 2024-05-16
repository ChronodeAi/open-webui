# syntax=docker/dockerfile:1

# Initialize device type args
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu121
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""

# WebUI frontend
FROM --platform=$BUILDPLATFORM node:21-alpine3.19 as build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# WebUI backend
FROM python:3.11-slim-bookworm as base

# Use args
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL

# Set environment variables
ENV ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL}

ENV OLLAMA_BASE_URL="/ollama" \
    OPENAI_API_BASE_URL="" \
    OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

# Model settings
ENV WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models"
ENV RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models"
ENV HF_HOME="/app/backend/data/cache/embedding/models"

# Working directory
WORKDIR /app/backend

# Setup
RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id

RUN apt-get update && \
    apt-get install -y --no-install-recommends pandoc netcat-openbsd ffmpeg libsm6 libxext6 curl && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY ./backend/requirements.txt ./requirements.txt
RUN pip3 install uv && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/${USE_CUDA_DOCKER_VER} --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"

# Copy built frontend files
COPY --from=build /app/build /app/build
COPY --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=build /app/package.json /app/package.json

# Copy backend files
COPY ./backend .

# Expose port
EXPOSE 8080

# Start the application
CMD [ "bash", "start.sh"]
