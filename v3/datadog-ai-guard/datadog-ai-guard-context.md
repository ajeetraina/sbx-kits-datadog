# Datadog AI Guard

This sandbox has the Datadog AI Guard SDKs pre-installed so any AI app or
agent you build here can screen LLM interactions in real time for **prompt
injection, jailbreaks, tool misuse, and sensitive-data exfiltration**.

Call `evaluate(...)` before you act on user input, before you run a tool the
model requested, and (optionally) on model output. Pass the full conversation
so far; AI Guard returns an action — typically ALLOW / DENY / ABORT — and with
`block=True/`{ block: true }` it raises when the interaction should be blocked.

## Already configured

- **Credentials**: `DD_API_KEY` / `DD_APP_KEY` are a proxy-managed placeholder,
  never the real value. Do **not** try to read or print them — the sbx proxy
  swaps in the real values on outbound calls to the AI Guard endpoint
  (`app.$DD_SITE` on base sites, the bare `$DD_SITE` on us3/us5/ap1). They never
  exist in the container.
- **Proxy routing**: outbound HTTPS must go through the sbx proxy for the swap
  to happen. Python is handled automatically (a `.pth` auto-imports the
  `_sbx_proxy_tunnel` shim). **Node**: `import '~/.datadog/sbx_proxy_tunnel.mjs'`
  **before** dd-trace makes any call, otherwise it bypasses the proxy and 401s.
- **Environment**: `DD_AI_GUARD_ENABLED=true`, `DD_SITE`, `DD_ENV`,
  `DD_SERVICE` are exported. APM tracing and instrumentation telemetry are
  disabled by default (agentless mode, no local Datadog Agent).
- **Trace UI (optional)**: `evaluate()` always returns the verdict for inline
  enforcement. To also see evaluations in the Datadog AI Guard UI, launch the
  kit with `--kit-arg apm=true` — it runs an in-sandbox Datadog Agent that
  forwards the evaluation spans through the proxy. Start/restart it from a
  shell with `sh ~/.datadog/start-agent.sh`. Not needed for enforcement.
- **Network**: egress is allowed to the AI Guard endpoint (`app.$DD_SITE` /
  `$DD_SITE`) plus the pip/npm registries.

## Python (ddtrace >= 3.19.0)

```python
from ddtrace.aiguard import new_ai_guard_client, Message, Options

client = new_ai_guard_client()
result = client.evaluate(
    messages=[
        Message(role="system", content="You are an AI Assistant"),
        Message(role="user", content=user_input),
    ],
    options=Options(block=True),  # raises if the interaction should be blocked
)
```

## Node.js (dd-trace >= 5.69.0)

dd-trace is installed globally. In your project either `npm install dd-trace`
(network is already allowed) or resolve the global copy. Import the proxy
helper first so dd-trace's HTTPS is routed through the injecting proxy:

```javascript
import '~/.datadog/sbx_proxy_tunnel.mjs';  // MUST be first; else 401
import tracer from 'dd-trace';

const result = await tracer.aiguard.evaluate(
  [
    { role: 'system', content: 'You are an AI Assistant' },
    { role: 'user', content: userInput },
  ],
  { block: true },
);
```

Ready-to-run examples are in `~/.datadog/`. An operational runbook is in
`~/runbooks/datadog-ai-guard.md`. Full docs:
https://docs.datadoghq.com/security/ai_guard/
