#!/bin/bash
set -euo pipefail

MARIMO_PORT="${MARIMO_PORT:-2718}"
MARIMO_NOTEBOOK="${MARIMO_NOTEBOOK:-notebook.py}"

SERVICE_PREFIX="${JUPYTERHUB_SERVICE_PREFIX:-/}"
SERVICE_PREFIX="${SERVICE_PREFIX%/}/"

MARIMO_BASE_URL="${SERVICE_PREFIX}proxy/${MARIMO_PORT}/"
MARIMO_DEFAULT_URL="/proxy/${MARIMO_PORT}/"

marimo edit "${MARIMO_NOTEBOOK}" \
  --host 0.0.0.0 \
  --port "${MARIMO_PORT}" \
  --headless \
  --no-token \
  --base-url "${MARIMO_BASE_URL}" &

for _ in $(seq 1 100); do
  if python3 - <<PY
import socket, sys
port = int("${MARIMO_PORT}")
s = socket.socket()
try:
    sys.exit(0 if s.connect_ex(("127.0.0.1", port)) == 0 else 1)
finally:
    s.close()
PY
  then
    break
  fi
  sleep 0.1
done

args=()
replaced=0
for arg in "$@"; do
  case "$arg" in
    --NotebookApp.default_url=*|--ServerApp.default_url=*)
      args+=("--ServerApp.default_url=${MARIMO_DEFAULT_URL}")
      replaced=1
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

if [ "${replaced}" -eq 0 ]; then
  args+=("--ServerApp.default_url=${MARIMO_DEFAULT_URL}")
fi

exec "${args[@]}"
