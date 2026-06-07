#!/usr/bin/env bash
set -euo pipefail

IMAGE=${IMAGE:-marimo-binder:local}
DOCKERFILE=${DOCKERFILE:-.binder/Dockerfile}

repo_root() {
  local here
  here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  cd -- "${here}/.." && pwd
}

ROOT=$(repo_root)
cd -- "${ROOT}"

# Build first (same as CI)
docker build -f "${DOCKERFILE}" -t "${IMAGE}" .

echo "== Smoke: shipped versions (informational)"
docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc '
  set -euo pipefail
  python3 -c "import marimo, marimo_jupyter_extension; print(\"marimo\", getattr(marimo, \"__version__\", \"?\")); print(\"marimo_jupyter_extension\", getattr(marimo_jupyter_extension, \"__version__\", \"?\"))"
  test "$(node -p "require(\"/grist/package.json\").version")" = "1.7.14"
  echo "gristlabs/grist 1.7.14"
'

echo "== Smoke: entrypoint starts marimo and embedded Grist"
docker run --rm --entrypoint /bin/bash \
  -e JUPYTERHUB_SERVICE_PREFIX=/user/test/ \
  -e JUPYTERHUB_SERVICE_URL=https://jupyterhub.example.invalid/user/test/ \
  "${IMAGE}" -lc '
  set -euo pipefail
  START_LOG=/tmp/binder-start.log

  redact_start_log() {
    sed -E "s/(BOOT KEY: )[[:alnum:]]+/\\1[REDACTED]/g" "${START_LOG}" >&2 || true
  }

  /home/jovyan/.binder/start true >"${START_LOG}" 2>&1

  for i in $(seq 1 60); do
    if ps aux | grep -F "node _build/stubs/app/server/server.js" | grep -v grep >/dev/null; then
      break
    fi
    if [ "${i}" = "60" ]; then
      echo "Grist process did not start" >&2
      ps aux >&2
      redact_start_log
      exit 1
    fi
    sleep 1
  done

  assert_process() {
    local pattern="$1"
    if ! ps aux | grep -F "${pattern}" | grep -v grep; then
      echo "Process not found: ${pattern}" >&2
      ps aux >&2
      redact_start_log
      exit 1
    fi
  }

  assert_process "marimo run marimo_app.py"
  assert_process "marimo edit marimo_app.py"
  assert_process "node _build/stubs/app/server/server.js"

  for i in $(seq 1 60); do
    if node - <<'NODE'
const http = require("http");
const opts = {
  hostname: "127.0.0.1",
  port: 8484,
  path: "/o/docs/",
  headers: {
    Host: "jupyterhub.example.invalid",
    "X-Forwarded-Proto": "https,http",
  },
};
http.get(opts, (r) => {
  let body = "";
  r.setEncoding("utf8");
  r.on("data", chunk => { body += chunk; });
  r.on("end", () => {
    const containsGrist = body.toLowerCase().includes("grist");
    console.log("grist http status", r.statusCode, "contains_grist", containsGrist);
    process.exit(r.statusCode === 200 && containsGrist ? 0 : 1);
  });
}).on("error", () => process.exit(1));
NODE
    then
      break
    fi
    if [ "${i}" = "60" ]; then
      echo "Grist HTTP endpoint did not become ready at http://127.0.0.1:8484/o/docs/" >&2
      redact_start_log
      exit 1
    fi
    sleep 1
  done
'
