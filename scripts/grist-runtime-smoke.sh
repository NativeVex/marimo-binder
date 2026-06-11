#!/usr/bin/env bash
set -euo pipefail

IMAGE=${GRIST_IMAGE:-gristlabs/grist:1.7.14}
PORT=${GRIST_PORT:-8484}

cid=""
cleanup() {
  if [ -n "${cid}" ]; then
    docker rm -f "${cid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cid=$(docker run -d --rm --entrypoint /bin/bash \
  -e PORT="${PORT}" \
  -e GRIST_IN_SERVICE=true \
  -e GRIST_DEFAULT_EMAIL=jovyan@example.invalid \
  -e GRIST_DATA_DIR=/tmp/grist-persist/docs \
  -e TYPEORM_DATABASE=/tmp/grist-persist/home.sqlite3 \
  -e GRIST_INST_DIR=/tmp/grist-persist \
  -e GRIST_HOST=0.0.0.0 \
  -e GRIST_ORG_IN_PATH=true \
  -e GRIST_SINGLE_ORG=docs \
  -e GRIST_SINGLE_PORT=true \
  -e GRIST_SERVE_SAME_ORIGIN=true \
  -e GRIST_SESSION_COOKIE=grist_binder \
  -e NODE_OPTIONS=--no-deprecation \
  -e APP_HOME_URL="https://jupyterhub-internal.example.invalid/user/test/proxy/${PORT}/o/docs" \
  -e APP_HOME_INTERNAL_URL="http://127.0.0.1:${PORT}" \
  -e APP_STATIC_URL="http://127.0.0.1:${PORT}" \
  "${IMAGE}" -lc 'mkdir -p "${GRIST_DATA_DIR}" "${GRIST_INST_DIR}" && cd /grist && ./sandbox/run.sh')

for _ in $(seq 1 90); do
  if docker exec "${cid}" node - <<'NODE'
const http = require("http");
const port = process.env.PORT;
const pageUrl = "http://127.0.0.1:" + port + "/o/docs/";
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
  if (!homeUrl.endsWith("/proxy/" + port + "/o/docs")) {
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
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
NODE
  then
    echo "Grist runtime smoke passed for ${IMAGE} on port ${PORT}"
    exit 0
  fi
  sleep 1
done

echo "Grist runtime did not become ready for ${IMAGE} on port ${PORT}" >&2
docker logs "${cid}" 2>&1 | sed -E 's/(BOOT KEY: )[[:alnum:]]+/\1[REDACTED]/g' >&2
exit 1
