#!/bin/sh
set -e

echo "⏳ Starting FastAPI Backend on port 8000..."

uvicorn src.api.main:app \
  --host 0.0.0.0 \
  --port 8000 &

API_PID=$!

echo "⏳ Waiting for FastAPI to become ready..."

while ! curl -fsS http://127.0.0.1:8000/openapi.json >/dev/null 2>&1; do
  if ! kill -0 "$API_PID" 2>/dev/null; then
    echo "❌ FastAPI failed to start."
    wait "$API_PID"
    exit 1
  fi
  sleep 3
done

echo "✅ FastAPI is ready and listening on port 8000."
echo "🚀 Starting Streamlit Clinical Console on port 8501..."

exec streamlit run src/ui/app.py \
  --server.address=0.0.0.0 \
  --server.port=8501 \
  --server.headless=true
