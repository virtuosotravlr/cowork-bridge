#!/bin/bash
# Cowork Bridge UI launcher

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NODE_BIN=${NODE_BIN:-node}

if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
  echo "Error: node is required to run the UI." >&2
  exit 1
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat << 'USAGE'
Usage: scripts/bridge-ui.sh [options]

Options:
  --port <port>         Port to bind (default: 8787)
  --bind <ip>           Bind address (default: 127.0.0.1)
  --sessionsDir <path>  Override sessions root
  --bridgeDir <path>    Use a direct bridge folder (Docker mode)
  --token <token>       Require X-Bridge-Token header

Examples:
  scripts/bridge-ui.sh
  scripts/bridge-ui.sh --bridgeDir /bridge
  scripts/bridge-ui.sh --sessionsDir "$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
USAGE
  exit 0
fi

exec "$NODE_BIN" "$ROOT_DIR/ui/server.js" "$@"
