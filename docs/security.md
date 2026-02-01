# Security notes

This bridge can execute arbitrary commands on your host. Treat it like a local RPC daemon with full permissions.

Recommendations:
- Use a dedicated machine or user account.
- Keep the watcher running only when needed.
- Review and tighten allowed/blocked lists.
- Prefer Docker mode if you want clearer isolation.
- Audit `outputs/.bridge/logs/bridge.log` regularly.

This project is not affiliated with Anthropic and may break if Cowork internals change.
