#!/usr/bin/env bash
set -euo pipefail

IMAGE=${IMAGE:-marimo-binder:local}

repo_root() {
  local here
  here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  cd -- "${here}/.." && pwd
}

ROOT=$(repo_root)
cd -- "${ROOT}"

# Build first (same as CI)
docker build -t "${IMAGE}" .

echo "== Smoke: shipped versions (informational)"
docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc '
  set -euo pipefail
  python3 -c "import marimo, marimo_jupyter_extension; print(\"marimo\", getattr(marimo, \"__version__\", \"?\")); print(\"marimo_jupyter_extension\", getattr(marimo_jupyter_extension, \"__version__\", \"?\"))"
'

echo "== Smoke: entrypoint starts marimo"
docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc '
  set -euo pipefail
  /home/jovyan/.binder/start true
  sleep 1
  ps aux | grep -F "marimo run notebooks/algorithms/visualizing-embeddings.py" | grep -v grep
'
