#!/usr/bin/env sh
# Start a Datadog Agent inside the sandbox so AI Guard evaluations show up in the
# Datadog UI (the "AI Guard / Submit your first trace" view).
#
# Why this exists: client.evaluate() has two independent paths. (1) The evaluator
# API call returns the ALLOW/DENY verdict synchronously — this works agentless and
# is all the kit needs for inline enforcement. (2) An APM span describing the
# evaluation is flushed by the tracer to a Datadog Agent on localhost:8126, and
# THAT span is what powers the AI Guard UI. With no Agent the span is dropped
# ("dropping N traces to intake at http://localhost:8126"), so the UI stays on
# "Waiting for traces". This script runs the missing Agent.
#
# The Agent runs as a container and forwards trace intake THROUGH the sbx
# credential-injecting proxy (DD_PROXY_HTTPS), so the DD_API_KEY placeholder is
# swapped for the real key on the way out and the real key never enters the
# sandbox. Requires the datadog-ai-guard kit launched with --kit-arg apm=true.
#
# Idempotent: safe to re-run. No-op unless DD_APM_TRACING_ENABLED=true.
#
#   Usage:  sh ~/.datadog/start-agent.sh
#   Status: docker exec dd-agent agent status | sed -n '/APM/,/^$/p'
#   Stop:   docker rm -f dd-agent
set -eu

if [ "${DD_APM_TRACING_ENABLED:-false}" != "true" ]; then
  echo "datadog-agent: DD_APM_TRACING_ENABLED != true — not starting (launch the kit with --kit-arg apm=true for UI traces)."
  exit 0
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "datadog-agent: docker not available in this sandbox — cannot start the Agent."
  exit 0
fi

NAME="${DD_AGENT_CONTAINER:-dd-agent}"
IMAGE="${DD_AGENT_IMAGE:-datadog/agent:7}"
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
SITE="${DD_SITE:-datadoghq.com}"
# The sbx proxy MITMs TLS with a "Docker Sandboxes Proxy CA"; the microVM trusts
# it via this bundle, but the Agent container has its own trust store, so mount it.
CA_BUNDLE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"

if [ -z "$PROXY" ]; then
  echo "datadog-agent: no HTTPS_PROXY set — the Agent could not inject the real key and would 401; aborting."
  exit 1
fi
if [ ! -f "$CA_BUNDLE" ]; then
  echo "datadog-agent: CA bundle '$CA_BUNDLE' not found; the Agent would reject the proxy's MITM cert. Aborting."
  exit 1
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NAME"; then
  echo "datadog-agent: container '$NAME' already running."
  exit 0
fi
docker rm -f "$NAME" >/dev/null 2>&1 || true

# --network host puts the Agent in the microVM's network namespace, so it reaches
# the sbx forward proxy (gateway.docker.internal:3128) exactly as the SDK does and
# its trace receiver binds the microVM's 127.0.0.1:8126 directly. DD_PROXY_* routes
# all Agent egress (trace intake included) through the proxy. DD_API_KEY is the
# proxy placeholder; the proxy swaps in the real key on outbound calls.
# DD_APM_DD_URL pins the trace intake to the exact host the kit injects on;
# without it the Agent (v7.67+) uses the FQDN form "trace.agent.<site>." with a
# trailing dot, which would miss the credential-injection host match and 403.
docker run -d --name "$NAME" --restart unless-stopped \
  --network host \
  -e DD_API_KEY="${DD_API_KEY:-}" \
  -e DD_SITE="$SITE" \
  -e DD_APM_DD_URL="https://trace.agent.${SITE}" \
  -e DD_HOSTNAME="${DD_HOSTNAME:-sbx-sandbox}" \
  -e DD_APM_ENABLED=true \
  -e DD_PROXY_HTTPS="$PROXY" \
  -e DD_PROXY_HTTP="$PROXY" \
  -e DD_LOG_LEVEL="${DD_AGENT_LOG_LEVEL:-warn}" \
  -e DD_INSTRUMENTATION_TELEMETRY_ENABLED=false \
  -e DD_ENABLE_PAYLOADS_EVENTS=false \
  -e DD_ENABLE_PAYLOADS_SERIES=false \
  -e DD_ENABLE_PAYLOADS_SKETCHES=false \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  -v "${CA_BUNDLE}:/etc/ssl/certs/ca-certificates.crt:ro" \
  "$IMAGE" >/dev/null

echo "datadog-agent: started '$NAME' ($IMAGE); APM trace intake on 127.0.0.1:8126."
echo "datadog-agent: check delivery with -> docker exec $NAME agent status | sed -n '/APM/,/^\$/p'"
