#!/usr/bin/env bash
#
# Update the Docker Hub repository overview (full_description) + short
# description via the Docker Hub API. No Docker daemon required, so this runs on
# any runner (incl. macOS). Needs `curl` and `jq`.
#
# Usage:
#   DOCKERHUB_TOKEN=... ./scripts/update-dockerhub-readme.sh [README_FILE]
#
# Env:
#   DOCKERHUB_USER   namespace + login user   (default: ajeetraina777)
#   REPO             repository name          (default: datadog-ai-guard-kit)
#   DOCKERHUB_TOKEN  Docker Hub access token / password (never echoed)
#   SHORT            short description (<=100 chars)

set -euo pipefail

DOCKERHUB_USER="${DOCKERHUB_USER:-ajeetraina777}"
REPO="${REPO:-datadog-ai-guard-kit}"
README="${1:-docs/DOCKERHUB.md}"
SHORT="${SHORT:-Docker Sandboxes mixin: Datadog AI Guard for sandboxed AI agents}"
TOKEN="${DOCKERHUB_TOKEN:-${DOCKER_TOKEN:-}}"

[ -n "$TOKEN" ] || { echo "ERROR: set DOCKERHUB_TOKEN" >&2; exit 1; }
[ -f "$README" ] || { echo "ERROR: README file not found: $README" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

echo "== Docker Hub login as $DOCKERHUB_USER =="
jwt=$(curl -fsS -H "Content-Type: application/json" \
  -d "$(jq -n --arg u "$DOCKERHUB_USER" --arg p "$TOKEN" '{username:$u,password:$p}')" \
  https://hub.docker.com/v2/users/login/ | jq -r '.token // empty')
[ -n "$jwt" ] || { echo "ERROR: Docker Hub login failed (check token scope)" >&2; exit 1; }

echo "== update $DOCKERHUB_USER/$REPO overview from $README =="
body=$(jq -n --rawfile fd "$README" --arg sd "$SHORT" '{full_description:$fd, description:$sd}')
code=$(curl -sS -o /tmp/dhresp -w '%{http_code}' -X PATCH \
  -H "Authorization: JWT $jwt" -H "Content-Type: application/json" \
  -d "$body" \
  "https://hub.docker.com/v2/repositories/${DOCKERHUB_USER}/${REPO}/")

if [ "$code" = "200" ]; then
  echo "Updated Docker Hub overview for ${DOCKERHUB_USER}/${REPO}"
else
  echo "ERROR: Docker Hub API returned HTTP $code" >&2
  cat /tmp/dhresp >&2 || true
  exit 1
fi
