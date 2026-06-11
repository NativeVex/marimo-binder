#!/usr/bin/env bash
set -euo pipefail

IMAGE=${IMAGE:-marimo-binder:local}
DOCKERFILE=${DOCKERFILE:-.binder/Dockerfile}

# Build the Binder/repo2docker Dockerfile (matches CI and BinderHub semantics).
docker build -f "${DOCKERFILE}" -t "${IMAGE}" .
