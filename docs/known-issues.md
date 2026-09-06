# Known issues

Findings from end-to-end testing on **sbx v0.42.0-rc4 / rc5** (macOS arm64).
Two are sbx-side bugs the kit works around; one is a Datadog account
requirement.

## 1. Hyphenated credential service names are dropped silently (sbx)

**Symptom.** A kit `credentials[].service` containing a hyphen (e.g.
`datadog-api`) never attaches: no `SBX_CRED_<SERVICE>_MODE` env var, no
injection, and **no error** at `sbx run`.

**Cause.** sbx derives an `SBX_CRED_<SERVICE>_MODE` environment variable from
the service name. A hyphen produces an invalid env var name
(`SBX_CRED_datadog-api_MODE`), so the credential is dropped.

**Evidence.** Renaming the services to `datadogapi` / `datadogapp` (no other
change) flips the container env from *nothing* to:

```
SBX_CRED_DATADOGAPI_MODE=apikey
SBX_CRED_DATADOGAPP_MODE=apikey
```

**Workaround (applied in this kit).** Use hyphen-free service names:
`datadogapi`, `datadogapp`.

## 2. Kit-declared `credentials[].apiKey` sentinel-swap does not inject (sbx)

**Symptom.** Even with attachment working (issue #1 fixed, `mode=apikey`), the
declared `apiKey.name` (`DD_API_KEY` / `DD_APP_KEY`) is **never set** to the
`proxy-managed` sentinel in the container, and the proxy does **not** swap the
sentinel on outbound calls. The AI Guard SDK then aborts with:

```
ValueError: Authentication credentials required: provide DD_API_KEY and DD_APP_KEY
```

**Isolation.**

- The key is valid — sending it directly host-side to
  `https://api.datadoghq.com/api/v1/validate` returns `200 {"valid":true}`.
- The proxy *is* MITM-intercepting `api.datadoghq.com` (server cert issuer is
  "Docker Sandboxes Proxy CA"), so header rewriting is possible in principle.
- Sending the literal `proxy-managed` in the `DD-API-KEY` header from inside the
  sandbox still 403s — the swap does not fire for the declarative path.

**Workaround (documented, proven).** Wire the keys with `sbx secret set-custom`,
which uses a unique per-credential placeholder and **does** swap correctly:

```bash
sbx secret set-custom --host api.datadoghq.com --env DD_API_KEY --value <api-key>
sbx secret set-custom --host api.datadoghq.com --env DD_APP_KEY --value <app-key>
```

Verified end-to-end inside the sandbox:

```
# DD_API_KEY is the placeholder (e.g. sbx-cs-VityWSwJ0954wfcf)
curl -H "DD-API-KEY: $DD_API_KEY" https://api.datadoghq.com/api/v1/validate
# => {"valid":true}  HTTP 200

# both keys swap (endpoint requires DD-API-KEY + DD-APPLICATION-KEY)
curl -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
     "https://api.datadoghq.com/api/v2/users?page[size]=1"
# => 200 with user data
```

Keep the declarative `credentials:` block in `spec.yaml` — it is correct per the
sbx spec and will work once this is fixed upstream — but prefer `set-custom`
today.

## 3. AI Guard `evaluate()` returns 401 — Datadog account requirement

Once the keys inject (issue #2 worked around), `evaluate()` can still 401. This
is **not** an sbx/kit problem — both keys inject and validate. AI Guard requires:

- an **Application key with the `ai_guard_evaluate` scope** (the user creating it
  needs the *AI Guard Evaluate* permission), and
- **AI Guard enabled** on the org.

A scoped app key that works for general API calls (e.g. `/api/v2/users`) will
still 401 on `evaluate()` if it lacks `ai_guard_evaluate`.

Docs: <https://docs.datadoghq.com/security/ai_guard/setup/>

## Note on the e2e test's credential check

`scripts/test-kit-e2e.sh` verifies the sentinel via `sbx exec printenv
DD_API_KEY`. The `apiKey.name` sentinel is **not** visible to `sbx exec`
sessions even for a working credential (e.g. anthropic's `ANTHROPIC_API_KEY`
isn't either — only `SBX_CRED_ANTHROPIC_MODE` is). A functional check (a request
that the proxy authenticates, as above) is the reliable signal.
