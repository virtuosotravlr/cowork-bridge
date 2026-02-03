# Local UI (HTMX-style)

This repo includes a lightweight, server-rendered UI that watches bridge sessions and job queues in real time. It uses a small local HTMX-style script for polling HTML fragments (no CDN required).

## Start

```bash
scripts/bridge-ui.sh
```

Default address: `http://127.0.0.1:8787`

## Docker / direct bridge mode

If you have a bridge folder mounted directly (for example `/bridge` in Docker):

```bash
scripts/bridge-ui.sh --bridgeDir /bridge
```

## Security

The UI binds to `127.0.0.1` by default. For extra protection, enable a token:

```bash
scripts/bridge-ui.sh --token my-secret
```

Then include the header `X-Bridge-Token: my-secret` in requests. You can also open the UI once with `?token=my-secret` to set a local cookie.

## Session Tools

The UI exposes the existing maintenance scripts:

- Prompt injection (`inject-prompt.sh`)
- Session config updates (`inject-session.sh`)
- Bridge setup/uninstall per session (`bridge-init.sh`, `bridge-uninstall.sh`)
- Global setup/uninstall (`setup-all-sessions.sh`, `bridge-uninstall.sh`)
- Auto-setup daemon (launchd start/stop/status)

Actions run the same scripts found in `scripts/` and display stdout/stderr for inspection.

## Global Pages

- ` /global` for install/uninstall and bulk setup actions
- ` /daemon` for launchd auto-setup daemon controls

## Notes

- The UI reads from `outputs/.bridge` and does not persist data.
- Polling intervals are 2–5 seconds by default.
- The HTMX-style script supports `hx-get`, `hx-trigger="load"`, and `hx-trigger="every Ns"`.
- If you prefer the full HTMX library, replace `ui/public/htmx-lite.js` with the official file.
