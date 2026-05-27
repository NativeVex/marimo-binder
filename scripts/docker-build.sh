#!/usr/bin/env bash
set -euo pipefail

IMAGE=${IMAGE:-marimo-binder:local}

# Build the repo's Dockerfile (matches CI semantics)
docker build -t "${IMAGE}" .
