# marimo-binder

Binder (launch directly into marimo UI):

  https://mybinder.org/v2/gh/<OWNER>/<REPO>/<REF>?urlpath=proxy%2F2718%2F

A minimal Binder / JupyterHub-compatible repo that launches JupyterLab and auto-starts a marimo app (`marimo_app.py`).

This repo intentionally uses the **advanced repo2docker path**: it contains a `Dockerfile`. In repo2docker/Binder semantics, that means other config mechanisms (e.g. `.binder/*`) are *not* auto-wired unless the Dockerfile wires them explicitly.

## How it works (high level)

- `Dockerfile`
  - builds from `quay.io/jupyterhub/jupyterhub:5.4.6`
  - bakes Python deps into the image (from `requirements.txt`; pinned for reproducibility)
  - sets:
    - `ENTRYPOINT ["/home/jovyan/.binder/start"]`
    - `CMD ["jupyterhub-singleuser"]`

- `.binder/start`
  - SHOULD be network-free and fast (deps are installed at image build time)
    - note: the demo notebook itself may fetch datasets at runtime
  - exports `PYTHONPATH="$PWD:$PYTHONPATH"` so `marimo_redirect.py` is importable
  - starts marimo headless on port 2718 in *dev/editor view* (`marimo edit ... --headless --no-token &`)
    - default notebook: `notebooks/algorithms/visualizing-embeddings.py`
  - ends with `exec "$@"` so the image default CMD still runs

- `.jupyter/jupyter_server_config.py`
  - enables `marimo_redirect` as a Jupyter Server extension
  - note: `marimo_jupyter_extension` is installed (see `requirements.txt`) but is not required for the root-redirect behavior

- `marimo_redirect.py`
  - redirects `/` to `${JUPYTERHUB_SERVICE_PREFIX}proxy/2718/` (JupyterHub proxy path)

NOTE: the marimo app file is intentionally NOT named `notebook.py`, because that name shadows the `notebook` python package that `jupyter notebook` imports (breaking repo2docker local runs).

## Local validation (no real JupyterHub required)

Build the image (same semantics as CI):

  ./scripts/docker-build.sh

Smoke check (builds, then runs the same checks as CI):

  ./scripts/docker-smoke.sh

Notes:
- Override the image tag with `IMAGE=...` (default: `marimo-binder:local`).

## Important limitation (expected)

Running `jupyterhub-singleuser` outside a real JupyterHub/Binder context can fail due to missing Hub environment variables (example observed: `Missing required environment $JUPYTERHUB_SERVICE_URL`).

For local development, prefer the smoke check above unless you have a real Hub environment to point at.

## CI

GitHub Actions runs two jobs:

- `docker-build`: builds the Dockerfile
- `docker-smoke`: runs smoke checks against the built image
  - prints shipped versions (`marimo`, `marimo_jupyter_extension`)
  - asserts `.binder/start` actually starts marimo (process-level check)
