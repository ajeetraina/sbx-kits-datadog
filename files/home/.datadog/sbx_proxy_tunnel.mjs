// Route Node's default HTTPS agent through the Docker Sandboxes forward proxy.
//
// Shipped by the datadog-ai-guard sbx kit. Node's http/https core (which
// dd-trace's AI Guard client uses via https.globalAgent) does NOT honor
// HTTPS_PROXY, so without this the sbx credential-injecting proxy never sees the
// request and the DD-API-KEY placeholder reaches Datadog unswapped -> HTTP 401.
//
// Import this module ONCE, before dd-trace makes any call:
//     import '<path>/.datadog/sbx_proxy_tunnel.mjs';
//
// It installs a CONNECT-tunnelling https.globalAgent. No-op when no proxy is
// configured; honors NO_PROXY; never throws on import.
import http from 'node:http';
import tls from 'node:tls';
import https from 'node:https';

try {
  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy;
  if (proxyUrl) {
    const proxy = new URL(proxyUrl);
    const noProxy = (process.env.NO_PROXY || process.env.no_proxy || '')
      .split(',')
      .map((s) => s.trim().replace(/^\./, '').toLowerCase())
      .filter(Boolean);
    const bypass = (host) => {
      host = (host || '').toLowerCase();
      return (
        host === proxy.hostname.toLowerCase() ||
        noProxy.some((s) => host === s || host.endsWith('.' + s))
      );
    };

    class TunnelAgent extends https.Agent {
      createConnection(opts, cb) {
        if (bypass(opts.host)) return super.createConnection(opts, cb);
        const req = http.request({
          host: proxy.hostname,
          port: proxy.port || 3128,
          method: 'CONNECT',
          path: `${opts.host}:${opts.port || 443}`,
        });
        req.once('connect', (res, socket) => {
          if (res.statusCode !== 200) {
            cb(new Error(`sbx proxy CONNECT failed: ${res.statusCode}`));
            return;
          }
          cb(null, tls.connect({ socket, servername: opts.host }));
        });
        req.once('error', cb);
        req.end();
      }
    }

    https.globalAgent = new TunnelAgent();
  }
} catch {
  // never break the app because of proxy wiring
}
