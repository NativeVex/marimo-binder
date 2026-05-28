#!/usr/bin/env bash
set -euo pipefail

# E2E check: prove that a Hub-authenticated user lands on the marimo UI
# (served under JupyterHub's /user/<name>/proxy/2718/ path) without any manual URL munging.
#
# This is a local approximation of BinderHub behavior.

repo_root() {
  local here
  here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  cd -- "${here}/.." && pwd
}

ROOT=$(repo_root)
cd -- "${ROOT}"

# Start the local hub harness
# NOTE: this is long-lived; keep it idempotent.
docker compose up -d --build

# Wait for hub login to come up
python3 - <<'PY'
import time
import urllib.request
import urllib.error

URL = 'http://127.0.0.1:8000/hub/login'

t0 = time.time()
while True:
    try:
        req = urllib.request.Request(URL, method='GET')
        with urllib.request.urlopen(req, timeout=2) as resp:
            if int(getattr(resp, 'status', 0) or 0) == 200:
                print('E2E: hub login is up')
                break
    except Exception:
        pass

    if time.time() - t0 > 120:
        raise SystemExit('E2E: TIMEOUT waiting for hub login')
    time.sleep(1)
PY

# Login + assert the landing URL serves marimo
python3 - <<'PY'
import urllib.request
import urllib.parse
import http.cookiejar
import re

BASE='http://127.0.0.1:8000'
LOGIN=BASE+'/hub/login'

USER='test'
PW='dev'

cj=http.cookiejar.CookieJar()
opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

html=opener.open(LOGIN, timeout=10).read().decode('utf-8','replace')
m=re.search(r'name="_xsrf"\s+value="([^"]+)"', html)
if not m:
    raise SystemExit('E2E: failed to find _xsrf in login page')
xsrf=m.group(1)

post=urllib.parse.urlencode({'username':USER,'password':PW,'_xsrf':xsrf}).encode('utf-8')
opener.open(LOGIN, data=post, timeout=20).read(200)

# Request the user root; our server extension should redirect it to /proxy/2718/
resp=opener.open(BASE+f'/user/{USER}/', timeout=30)
body=resp.read(60000).decode('utf-8','replace').lower()
final=resp.geturl()

if '/proxy/2718/' not in final:
    raise SystemExit(f'E2E: expected redirect into /proxy/2718/, got final_url={final}')
if 'marimo' not in body:
    raise SystemExit('E2E: expected marimo HTML to be served under /proxy/2718/')

print('E2E: PASS; final_url='+final)
PY

echo "E2E: PASS"
