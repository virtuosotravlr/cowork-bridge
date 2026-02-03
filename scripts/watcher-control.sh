#!/bin/bash
# Cowork Bridge Watcher Control

set -euo pipefail

WATCHER="$HOME/.claude/skills/cli-bridge/watcher.sh"
LOG_FILE="/tmp/cowork-bridge-watcher.log"

usage() {
  echo "Usage: $(basename "$0") <start|stop|restart|status>"
}

is_running() {
  pgrep -f "cli-bridge/watcher.sh" >/dev/null 2>&1
}

status() {
  if is_running; then
    local PIDS
    PIDS=$(pgrep -f "cli-bridge/watcher.sh" | tr '\n' ' ')
    echo "running: $PIDS"
  else
    echo "stopped"
  fi
}

start() {
  if [ ! -x "$WATCHER" ]; then
    echo "Watcher not found: $WATCHER" >&2
    exit 1
  fi

  if is_running; then
    status
    return 0
  fi

  nohup "$WATCHER" > "$LOG_FILE" 2>&1 &
  sleep 1
  status
}

stop() {
  if is_running; then
    pkill -f "cli-bridge/watcher.sh" || true
    sleep 1
  fi
  status
}

restart() {
  stop
  start
}

case "${1:-}" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  status)
    status
    ;;
  *)
    usage
    exit 1
    ;;
esac
