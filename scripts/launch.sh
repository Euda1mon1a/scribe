#!/usr/bin/env bash
# Launch Scribe backend
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m uvicorn backend.main:app --host 127.0.0.1 --port 8890 --log-level info
