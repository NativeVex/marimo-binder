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
  -e APP_HOME_URL="https://jupyterhub-internal.example.invalid/user/test/proxy/${PORT}" \
  "${IMAGE}" -lc 'mkdir -p "${GRIST_DATA_DIR}" "${GRIST_INST_DIR}" && cd /grist && ./sandbox/run.sh')

for _ in $(seq 1 90); do
  if docker exec "${cid}" node - <<'NODE'
const http = require("http");
const port = process.env.PORT;
const opts = {
  hostname: "127.0.0.1",
  port,
  path: "/o/docs/",
  headers: {
    Host: "public-binderhub.example.invalid",
    "X-Forwarded-Proto": "https,http",
  },
};
http.get(opts, (r) => {
  let body = "";
  r.setEncoding("utf8");
  r.on("data", chunk => { body += chunk; });
  r.on("end", () => {
    const ok = r.statusCode === 200 && body.toLowerCase().includes("grist");
    console.log("grist http status", r.statusCode, "contains_grist", body.toLowerCase().includes("grist"));
    process.exit(ok ? 0 : 1);
  });
}).on("error", () => process.exit(1));
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
