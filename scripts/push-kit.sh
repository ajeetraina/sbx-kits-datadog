#!/usr/bin/env bash
#
# Publish the datadog-ai-guard kit to Docker Hub as an OCI artifact.
#
# Usage:
#   ./scripts/push-kit.sh [TAG]         # TAG defaults to "latest"
#
# Docker Hub auth (first that applies wins):
#   1. DOCKERHUB_TOKEN in the environment -> `docker login` as $DOCKERHUB_USER
#   2. an existing `docker login` / `sbx login` session (Docker credential store)
#
# Env overrides:
#   DOCKERHUB_USER   Docker Hub namespace/user   (default: ajeetraina777)
#   REPO             repository name             (default: datadog-ai-guard-kit)
#   TAG              image tag                   (default: latest, or $1)
#   DOCKERHUB_TOKEN  Docker Hub access token / PAT (never echoed)

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DOCKERHUB_USER="${DOCKERHUB_USER:-ajeetraina777}"
REPO="${REPO:-datadog-ai-guard-kit}"
TAG="${1:-${TAG:-latest}}"
REF="docker.io/${DOCKERHUB_USER}/${REPO}:${TAG}"

# Accept the token under a few common env var names.
TOKEN="${DOCKERHUB_TOKEN:-${DOCKER_TOKEN:-${DOCKERHUB_PASSWORD:-${DOCKER_PASSWORD:-}}}}"

echo "== validate kit =="
sbx kit validate "$KIT_DIR"

if [ -n "$TOKEN" ]; then
  echo "== docker login docker.io as $DOCKERHUB_USER =="
  printf '%s' "$TOKEN" | docker login docker.io -u "$DOCKERHUB_USER" --password-stdin
else
  echo "== no DOCKERHUB_TOKEN set — relying on existing docker/sbx session =="
fi

echo "== push $REF =="
sbx kit push "$KIT_DIR" "$REF"

echo
echo "Pushed OCI artifact: $REF"
echo "Consume with:  sbx run claude --kit $REF ."
