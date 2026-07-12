# Observer Dashboard Core API v0

Local-first API served by the macOS Observer app.

- Bind address: `127.0.0.1`
- Default port: `43127`
- API prefix: `/api/v1`
- OpenAPI: `/api/openapi.json`
- Production SPA: served from the same origin
- SQLite is never exposed as a network file
- Browser render path never calls an LLM
- No send/email/share/predictive-action endpoints exist in v0

## Pairing

Open the Observer menu and choose `Copy Dashboard Pairing Code`.
The code is short-lived and creates an HttpOnly `observer_session` cookie.

## Tailscale Serve

Remote private access is intended to be:

```bash
tailscale serve localhost:43127
tailscale serve status --json
```

Do not use Tailscale Funnel for v0. Tailnet access is not treated as enough by itself;
the dashboard still requires the Observer pairing/session layer.
