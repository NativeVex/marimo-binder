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
  test "$(node -p "require(\"/grist/package.json\").version")" = "1.7.14"
  echo "gristlabs/grist 1.7.14"
'

echo "== Smoke: entrypoint starts marimo and embedded Grist"
docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc '
  set -euo pipefail
  /home/jovyan/.binder/start true

  for i in $(seq 1 60); do
    if ps aux | grep -F "node _build/stubs/app/server/server.js" | grep -v grep >/dev/null; then
      break
    fi
    if [ "${i}" = "60" ]; then
      echo "Grist process did not start" >&2
      ps aux >&2
      exit 1
    fi
    sleep 1
  done

  ps aux | grep -F "marimo run notebooks/algorithms/visualizing-embeddings.py" | grep -v grep
  ps aux | grep -F "marimo edit notebooks/algorithms/visualizing-embeddings.py" | grep -v grep
  ps aux | grep -F "node _build/stubs/app/server/server.js" | grep -v grep

  for i in $(seq 1 60); do
    if python3 -c "import urllib.request; resp=urllib.request.urlopen(\"http://127.0.0.1:8484\", timeout=2); print(\"grist http status\", resp.status); raise SystemExit(0 if resp.status < 500 else 1)"; then
      break
    fi
    if [ "${i}" = "60" ]; then
      echo "Grist HTTP endpoint did not become ready at http://127.0.0.1:8484" >&2
      exit 1
    fi
    sleep 1
  done
'
