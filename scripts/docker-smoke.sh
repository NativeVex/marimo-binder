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
  cd /grist/sandbox/grist
  python3 -c "import iso8601; import astroid; import friendly_traceback; import actions; import codebuilder; print(\"grist sandbox imports OK\")"
  echo "gristlabs/grist 1.7.14"
'

echo "== Smoke: entrypoint starts marimo and embedded Grist"
docker run --rm --entrypoint /bin/bash \
  -e JUPYTERHUB_SERVICE_PREFIX=/user/test/ \
  -e JUPYTERHUB_SERVICE_URL=https://jupyterhub-internal.example.invalid/user/test/ \
  -e APP_STATIC_URL=http://127.0.0.1:8484 \
  -e APP_HOME_INTERNAL_URL=http://127.0.0.1:8484 \
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
const pageUrl = "http://127.0.0.1:8484/o/docs/";
const pageHeaders = {
  Host: "public-binderhub.example.invalid",
  "X-Forwarded-Proto": "https,http",
};

function get(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    if (u.protocol !== "http:") {
      reject(new Error("smoke only supports http asset probes, got " + u.protocol));
      return;
    }
    const opts = {
      hostname: u.hostname,
      port: u.port,
      path: u.pathname + u.search,
      headers,
    };
    http.get(opts, (r) => {
      let body = "";
      r.setEncoding("utf8");
      r.on("data", chunk => { body += chunk; });
      r.on("end", () => resolve({ statusCode: r.statusCode, body }));
    }).on("error", reject);
  });
}

function postJson(url, data, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    if (u.protocol !== "http:") {
      reject(new Error("smoke only supports http API probes, got " + u.protocol));
      return;
    }
    const body = JSON.stringify(data);
    const opts = {
      hostname: u.hostname,
      port: u.port,
      path: u.pathname + u.search,
      method: "POST",
      headers: {
        ...headers,
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };
    const req = http.request(opts, (r) => {
      let responseBody = "";
      r.setEncoding("utf8");
      r.on("data", chunk => { responseBody += chunk; });
      r.on("end", () => resolve({ statusCode: r.statusCode, body: responseBody }));
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  const page = await get(pageUrl, pageHeaders);
  const containsGrist = page.body.toLowerCase().includes("grist");
  const match = page.body.match(/<base\s+href="([^"]+)"/i);
  const baseHref = match && match[1];
  const configMatch = page.body.match(/window\.gristConfig\s*=\s*(\{.*?\});/s);
  const homeUrl = configMatch && JSON.parse(configMatch[1]).homeUrl;
  console.log("grist http status", page.statusCode, "contains_grist", containsGrist, "base_href", baseHref, "home_url", homeUrl);
  if (page.statusCode !== 200 || !containsGrist || !baseHref || !homeUrl) {
    process.exit(1);
  }
  if (!homeUrl.endsWith("/proxy/8484/o/docs")) {
    process.exit(1);
  }
  for (const name of ["main.bundle.js", "bundle.css"]) {
    const assetUrl = new URL(name, baseHref).href;
    const asset = await get(assetUrl);
    console.log("asset status", asset.statusCode, name, "bytes", asset.body.length);
    if (asset.statusCode !== 200 || asset.body.length < 1000) {
      process.exit(1);
    }
  }
  if (!page.body.includes("binder-url-prefix.js")) {
    process.exit(1);
  }
  const customScript = await get("http://127.0.0.1:8484/v/unknown/binder-url-prefix.js");
  console.log("custom script status", customScript.statusCode, "bytes", customScript.body.length);
  if (customScript.statusCode !== 200 || !customScript.body.includes("_urlStateLoadPage") || !customScript.body.includes("/api/worker/") || !customScript.body.includes("docWorkerUrl") || !customScript.body.includes("XMLHttpRequest") || !customScript.body.includes("WebSocket")) {
    process.exit(1);
  }

  const createDoc = await postJson("http://127.0.0.1:8484/o/docs/api/docs", {}, pageHeaders);
  console.log("document create status", createDoc.statusCode, "body", createDoc.body.slice(0, 80));
  if (createDoc.statusCode !== 200 || !/^\"new~/.test(createDoc.body)) {
    process.exit(1);
  }
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
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
