"""Route Python stdlib HTTPS through the Docker Sandboxes forward proxy.

Installed by the datadog-ai-guard sbx kit. Datadog's ddtrace AI Guard client
(ddtrace.internal.utils.http.get_connection) opens a *direct* HTTPSConnection
and ignores HTTPS_PROXY, so the sbx credential-injecting proxy never sees the
request and the DD-API-KEY placeholder reaches Datadog unswapped -> HTTP 401.

This shim makes http.client.HTTPSConnection tunnel through HTTPS_PROXY (honoring
NO_PROXY) so the proxy can swap the placeholder for the real key. It is a no-op
when no proxy is configured, and never raises on import.
"""
import os


def _install():
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    if not proxy:
        return
    from urllib.parse import urlparse

    parsed = urlparse(proxy if "://" in proxy else "http://" + proxy)
    proxy_host, proxy_port = parsed.hostname, parsed.port or 3128
    if not proxy_host:
        return

    no_proxy = os.environ.get("NO_PROXY") or os.environ.get("no_proxy") or ""
    skip = {h.strip().lstrip(".").lower() for h in no_proxy.split(",") if h.strip()}

    import http.client

    if getattr(http.client.HTTPSConnection, "_sbx_proxy_patched", False):
        return
    _orig_connect = http.client.HTTPSConnection.connect

    def _bypass(host):
        host = (host or "").lower()
        return host == proxy_host.lower() or any(
            host == s or host.endswith("." + s) for s in skip
        )

    def connect(self):
        # Leave already-tunneled connections and proxy/no_proxy hosts untouched.
        if getattr(self, "_tunnel_host", None) or _bypass(self.host):
            return _orig_connect(self)
        target_host, target_port = self.host, self.port
        self.host, self.port = proxy_host, proxy_port
        self.set_tunnel(target_host, target_port)
        return _orig_connect(self)

    http.client.HTTPSConnection.connect = connect
    http.client.HTTPSConnection._sbx_proxy_patched = True


try:
    _install()
except Exception:
    pass
