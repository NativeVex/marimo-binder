# Minimal local JupyterHub that spawns our singleuser image via DockerSpawner.
#
# Goal: remote-faithful local loop without BinderHub.
# - Users authenticate via the Hub (not Jupyter token URLs)
# - Singleuser server is proxied under /user/<name>/
# - Our image ENTRYPOINT starts marimo and relies on Hub auth upstream

from __future__ import annotations

import os

c = get_config()  # noqa: F821

# Bind
c.JupyterHub.bind_url = "http://:8000"

# Hub API bind/connect addresses
#
# We run the hub container with host networking (docker-compose network creation
# is broken in this environment). Spawned user containers run on Docker's
# built-in `bridge` network.
#
# Therefore:
# - the Hub must bind its internal API on 0.0.0.0
# - user containers must connect to the host via the bridge gateway (172.17.0.1)
c.JupyterHub.hub_bind_url = "http://0.0.0.0:8081"
c.JupyterHub.hub_connect_url = "http://172.17.0.1:8081"

# Auth: no external deps (local-only)
# This is the standard “known-good” pattern for local dev.
# Auth: no external deps (local-only)
# This is the standard “known-good” pattern for local dev.
c.JupyterHub.authenticator_class = "dummy"
c.DummyAuthenticator.password = "dev"
# JupyterHub 5 defaults to *not* allowing anyone unless configured.
c.Authenticator.allow_all = True

# Spawner: DockerSpawner
c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"

# Image to spawn. Default matches our local build tag.
# Override by setting HUB_SINGLEUSER_IMAGE.
c.DockerSpawner.image = os.environ.get("HUB_SINGLEUSER_IMAGE", "marimo-binder:local")

# CRITICAL: this environment cannot create *user-defined* docker bridge networks
# (iptables DOCKER-FORWARD chain missing). We therefore attach user containers to
# Docker's built-in `bridge` network (which already exists) instead of creating
# a compose-scoped network.
#
# Use container internal IPs (no port_bindings), because port publishing can
# fail in this environment.
c.DockerSpawner.use_internal_ip = True
c.DockerSpawner.network_name = "bridge"

# Ensure containers are cleaned up after stop.
c.DockerSpawner.remove = True

# The user inside the singleuser container.
# Our Dockerfile creates user `jovyan` uid 1000.
c.DockerSpawner.user = "jovyan"

# Notebook dir inside the singleuser container.
c.DockerSpawner.notebook_dir = "/home/jovyan"

# Use the image’s default CMD (jupyterhub-singleuser) and ENTRYPOINT (.binder/start).
# i.e. do NOT set c.DockerSpawner.cmd here.

# Persist hub state in /data (inside hub container)
# NOTE: do NOT set JupyterHub.data_files_path here; that controls where JupyterHub
# looks for its *installed templates/static files* (e.g. login.html). Overriding
# it breaks the UI.
c.JupyterHub.db_url = "sqlite:////data/jupyterhub.sqlite"
c.JupyterHub.cookie_secret_file = "/data/jupyterhub_cookie_secret"

# Security: keep this local-only; we bind hub to host port 8000.
