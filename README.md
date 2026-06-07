# marimo-binder

Binder (launch directly into marimo UI):

  mybinder.org (generic):
    https://mybinder.org/v2/gh/<OWNER>/<REPO>/<REF>?urlpath=proxy%2F2718%2F

  binderhub.saucy.haus (NativeVex):
    app: https://binderhub.saucy.haus/v2/gh/NativeVex/marimo-binder/<REF>?urlpath=proxy%2F2718%2F
    dev: https://binderhub.saucy.haus/v2/gh/NativeVex/marimo-binder/<REF>?urlpath=proxy%2F2719%2F
    grist: https://binderhub.saucy.haus/v2/gh/NativeVex/marimo-binder/<REF>?urlpath=proxy%2F8484%2F

  NOTE: BinderHub "gh" URLs take <ORG>/<REPO>/<REF>. Do NOT use an SSH-style remote like
    /v2/gh/git@github.com:NativeVex/marimo-binder.git/<REF>
  (that form is not resolvable on binderhub.saucy.haus).

A minimal Binder / JupyterHub-compatible repo that launches JupyterLab and auto-starts a lightweight marimo app (`marimo_app.py`) in app mode, with dev/editor mode and an optional heavyweight embeddings demo kept out of the default image path.

This repo intentionally uses the **advanced repo2docker path**: the Binder-visible Dockerfile lives at `.binder/Dockerfile`. When a `.binder/` directory exists, repo2docker looks there for its Dockerfile; a root-level Dockerfile alone is not enough for BinderHub. The root `Dockerfile` is kept as an exact local compatibility mirror, and CI builds `.binder/Dockerfile` explicitly.

## How it works (high level)

- `.binder/Dockerfile` (mirrored by root `Dockerfile`)
  - starts from the pinned `gristlabs/grist:1.7.14` image as a build stage and embeds the Grist runtime into the final image
  - prunes Grist build/dev/debug artifacts before the final copy (`pyodide`, TypeScript compiler/cache, source maps, declaration files, test directories) so the default Binder image stays smaller while preserving the embedded Grist runtime smoke contract
  - builds the final runtime from `quay.io/jupyterhub/jupyterhub:5.4.6`
  - bakes Python deps into the image (from lightweight `requirements.txt`; pinned for reproducibility)
  - sets:
    - `ENTRYPOINT ["/home/jovyan/.binder/start"]`
    - `CMD ["jupyterhub-singleuser"]`

- `.binder/start`
  - SHOULD be network-free and fast (deps are installed at image build time)
    - note: optional heavy demos may fetch datasets at runtime, but they are not on the default path
  - exports `PYTHONPATH="$PWD:$PYTHONPATH"` so `marimo_redirect.py` is importable
  - starts TWO marimo instances behind the JupyterHub proxy:
    - app mode (default): `marimo run ...` on port 2718
    - dev/editor: `marimo edit ...` on port 2719
    - default app: `marimo_app.py`
    - optional heavy demo: `notebooks/algorithms/visualizing-embeddings.py` (install `requirements-heavy.txt` and set `MARIMO_APP` explicitly)
  - starts embedded Grist on port 8484 with Binder-safe single-user defaults and persistent data under `/home/jovyan/grist-persist`
  - with the `marimo_redirect` Jupyter Server extension enabled, `/` redirects to the app, `/dev` redirects to the editor, and `/grist` redirects to Grist
  - ends with `exec "$@"` so the image default CMD still runs

- `.jupyter/jupyter_server_config.py`
  - enables `marimo_redirect` as a Jupyter Server extension
  - note: `marimo_jupyter_extension` is installed (see `requirements.txt`) but is not required for the root-redirect behavior

- `marimo_redirect.py`
  - redirects `/` to `${JUPYTERHUB_SERVICE_PREFIX}proxy/2718/` (JupyterHub proxy path)
  - redirects `/dev` to `${JUPYTERHUB_SERVICE_PREFIX}proxy/2719/`
  - redirects `/grist` to `${JUPYTERHUB_SERVICE_PREFIX}proxy/8484/`

NOTE: the marimo app file is intentionally NOT named `notebook.py`, because that name shadows the `notebook` python package that `jupyter notebook` imports (breaking repo2docker local runs).

## Local validation (no real JupyterHub required)

Build the image from `.binder/Dockerfile` (same semantics as CI/BinderHub):

  ./scripts/docker-build.sh

Smoke check (builds, then runs the same checks as CI):

  ./scripts/docker-smoke.sh

Notes:
- Override the image tag with `IMAGE=...` (default: `marimo-binder:local`).
- The default image intentionally does not install `requirements-heavy.txt`; use that file only for explicit heavy-demo builds/runs.

## Important limitation (expected)

Running `jupyterhub-singleuser` outside a real JupyterHub/Binder context can fail due to missing Hub environment variables (example observed: `Missing required environment $JUPYTERHUB_SERVICE_URL`).

For local development, prefer the smoke check above unless you have a real Hub environment to point at.

## CI

GitHub Actions runs two jobs:

- `docker-build`: builds `.binder/Dockerfile`
- `docker-smoke`: runs smoke checks against the built image
  - prints shipped versions (`marimo`, `marimo_jupyter_extension`, pinned `gristlabs/grist`)
  - asserts `.binder/start` actually starts marimo and embedded Grist (process-level + Grist HTTP check)
  - suppresses `.binder/start` service logs on success and redacts Grist one-time boot keys from failure logs
