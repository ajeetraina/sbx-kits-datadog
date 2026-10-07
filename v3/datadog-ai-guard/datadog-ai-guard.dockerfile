# syntax=docker/dockerfile:1
#
# Overlay recipe for the datadog-ai-guard MIXIN.
#
# v2 shipped a `files/` tree that `sbx kit push` bundled into the kit and the
# runtime dropped into the sandbox home. v3 ships the same tree as a scratch
# OVERLAY: content only, landing on whatever base the mixin is composed onto.
#
# DUPLICATION NOTE: this `files/` is a COPY of the repo-root `files/` (which the
# v2 kit still uses). A v3 build context is rooted at the kit directory and a
# recipe cannot COPY from outside it, so the overlay cannot reach ../../files and
# the tree has to live here too. The two copies must move together — edit the
# source once and mirror into both; `diff -rq files v3/datadog-ai-guard/files`
# (run from the repo root) must come back empty.
#
# The install/startup hooks in datadog-ai-guard.yaml read these files from
# /home/agent/.datadog/ (the proxy shim source, the Node proxy helper, the
# runnable examples, and start-agent.sh) and the runbook from
# /home/agent/runbooks/.
#
# Ownership (the one thing an overlay must get right): an overlay's directory
# entries OVERRIDE the base's, so /home must stay root-owned and /home/agent
# (the agent user, uid 1000) and everything under it must be uid 1000. BuildKit
# COPY lands files as root:root; the chown below starts EXACTLY at /out/home/agent
# so /out/home stays root and the agent's home subtree becomes 1000:1000.

FROM busybox:stable AS build

# Lands under a staging root mirroring the target home layout. COPY (no --chown)
# writes these as root:root; parents /out, /out/home, /out/home/agent are created
# root:root too.
COPY files/home/.datadog   /out/home/agent/.datadog
COPY files/home/runbooks   /out/home/agent/runbooks

# Start the chown at the agent's home, not /out and not a level deeper: /out/home
# keeps root ownership, /out/home/agent and all shipped files become uid 1000.
# start-agent.sh must be executable (v2 chmod +x'd it in a hook; bake it here).
RUN chown -R 1000:1000 /out/home/agent \
 && chmod 0755 /out/home/agent/.datadog/start-agent.sh

# The overlay: pure content on scratch, plus the env-config merge.
FROM scratch
COPY --from=build /out /

# Static DD_* env from v2 environment.variables. (The arg-driven ones — DD_SITE,
# DD_ENV, DD_SERVICE, DD_APM_TRACING_ENABLED — resolve at create via each arg's
# `env:` field in the descriptor, not here.) A mixin's ENV is an additive
# image-config field that merges at assembly, so these reach the composed image;
# it must sit on the recipe's FINAL stage, since a build stage's config is
# discarded.
ENV DD_AI_GUARD_ENABLED=true
ENV DD_INSTRUMENTATION_TELEMETRY_ENABLED=false
ENV IS_SANDBOX=1
