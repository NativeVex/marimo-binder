# marimo-binder

A minimal Binder / JupyterHub-compatible repo that launches JupyterLab and auto-starts a marimo app (`notebook.py`).

This repo intentionally uses the **advanced repo2docker path**: it contains a `Dockerfile`. In repo2docker/Binder semantics, that means other config mechanisms (e.g. `.binder/*`) are *not* auto-wired unless the Dockerfile wires them explicitly.

## How it works (high level)

- `Dockerfile`
  - builds from `quay.io/jupyterhub/jupyterhub:5.3.0`
  - bakes Python deps into the image (`notebook`, `jupyterlab`, plus `requirements.txt`)
  - sets:
    - `ENTRYPOINT ["/home/jovyan/.binder/start"]`
    - `CMD ["jupyterhub-singleuser"]`

- `.binder/start`
  - MUST be network-free and fast (deps are installed at image build time)
  - exports `PYTHONPATH="$PWD:$PYTHONPATH"` so `marimo_redirect.py` is importable
  - starts marimo headless on port 2718 (`marimo edit ... --headless &`)
  - ends with `exec "$@"` so the image default CMD still runs

- `.jupyter/jupyter_server_config.py`
  - enables `marimo_redirect` and `marimo_jupyter_extension`

- `marimo_redirect.py`
  - redirects `/` to `${JUPYTERHUB_SERVICE_PREFIX}proxy/2718/` (JupyterHub proxy path)

## Local validation (no real JupyterHub required)

Build the image:

  docker build -t marimo-binder:local .

Smoke check the entrypoint (asserts marimo started):

  docker run --rm --entrypoint /bin/bash marimo-binder:local -lc '
    set -euo pipefail
    /home/jovyan/.binder/start true
    sleep 1
    ps aux | grep -F "marimo edit notebook.py" | grep -v grep
  '

## Important limitation (expected)

Running `jupyterhub-singleuser` outside a real JupyterHub/Binder context can fail due to missing Hub environment variables (example observed: `Missing required environment $JUPYTERHUB_SERVICE_URL`).

For local development, prefer the smoke check above unless you have a real Hub environment to point at.

## CI

GitHub Actions builds the Dockerfile and runs a smoke check that asserts `.binder/start` actually starts marimo (process-level check).
