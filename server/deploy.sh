#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
python3 -m pip install -r requirements.txt
mkdir -p asset_cache/meshes asset_cache/textures asset_cache/raw asset_cache/jobs

uvicorn rbxl_import_server:app \
  --host 0.0.0.0 \
  --port 7821 \
  --workers "${UVICORN_WORKERS:-2}" \
  --log-level info
