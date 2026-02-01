#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Session Finder
# Locates active Cowork sessions on macOS
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

# ─────────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────────

list_sessions() {
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Cowork Sessions"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""

  if [ ! -d "$CLAUDE_SESSIONS" ]; then
    echo "  No sessions directory found."
    echo "  Expected: $CLAUDE_SESSIONS"
    exit 1
  fi

  local COUNT=0

  # Use process substitution to avoid subshell (fixes counter bug)
  while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      COUNT=$((COUNT + 1))
      local MTIME
      local SESSION_ID
      local BRIDGE_STATUS
      MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$dir" 2>/dev/null || stat -c "%y" "$dir" 2>/dev/null | cut -d. -f1)
      SESSION_ID=$(basename "$dir")
      BRIDGE_STATUS="no bridge"

      if [ -f "$dir/outputs/.bridge/status.json" ]; then
        BRIDGE_STATUS=$(jq -r '.status // "unknown"' "$dir/outputs/.bridge/status.json" 2>/dev/null || echo "unknown")
      fi

      echo "  [$COUNT] $SESSION_ID"
      echo "      Modified: $MTIME"
      echo "      Bridge:   $BRIDGE_STATUS"
      echo "      Path:     $dir"
      echo ""
    fi
  done < <(find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null)

  if [ $COUNT -eq 0 ]; then
    echo "  No active sessions found."
  fi
}

find_latest() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      # Output modification time and path
      stat -f "%m %N" "$dir" 2>/dev/null || stat -c "%Y %n" "$dir" 2>/dev/null
    fi
  done | sort -rn | head -1 | cut -d' ' -f2-
}

show_session_info() {
  local SESSION_PATH="$1"

  if [ ! -d "$SESSION_PATH" ]; then
    echo "Session not found: $SESSION_PATH"
    exit 1
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Session Info"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Path: $SESSION_PATH"
  echo ""
  echo "  Structure:"
  ls -la "$SESSION_PATH" 2>/dev/null | sed 's/^/    /'
  echo ""

  if [ -d "$SESSION_PATH/.claude" ]; then
    echo "  .claude/ contents:"
    ls -la "$SESSION_PATH/.claude" 2>/dev/null | sed 's/^/    /'
    echo ""
  fi

  if [ -f "$SESSION_PATH/.claude/settings.json" ]; then
    echo "  settings.json:"
    jq '.' "$SESSION_PATH/.claude/settings.json" 2>/dev/null | sed 's/^/    /'
    echo ""
  fi

  echo "  Bridge paths:"
  echo "    Requests:  $SESSION_PATH/outputs/.bridge/requests/"
  echo "    Responses: $SESSION_PATH/outputs/.bridge/responses/"
  echo "    Logs:      $SESSION_PATH/outputs/.bridge/logs/"
  echo ""

  echo "  Env injection:"
  echo "    $SESSION_PATH/.claude/settings.json"
  echo ""
  echo "    Example:"
  echo "    echo '{\"env\": {\"MY_VAR\": \"value\"}}' > \"$SESSION_PATH/.claude/settings.json\""
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --list|-l)
    list_sessions
    ;;
  --latest|-L)
    LATEST=$(find_latest)
    if [ -n "$LATEST" ]; then
      echo "$LATEST"
    else
      echo "No sessions found" >&2
      exit 1
    fi
    ;;
  --info|-i)
    if [ -n "${2:-}" ]; then
      show_session_info "$2"
    else
      LATEST=$(find_latest)
      if [ -n "$LATEST" ]; then
        show_session_info "$LATEST"
      else
        echo "No sessions found" >&2
        exit 1
      fi
    fi
    ;;
  --help|-h)
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --list, -l      List all Cowork sessions"
    echo "  --latest, -L    Print path to most recent session (for scripting)"
    echo "  --info, -i      Show detailed info about latest (or specified) session"
    echo "  --help, -h      Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --list"
    echo "  $(basename "$0") --latest"
    echo "  $(basename "$0") --info /path/to/session"
    echo "  SESSION=\$($(basename "$0") --latest) && echo \"\$SESSION\""
    ;;
  *)
    # Default: show latest session info
    LATEST=$(find_latest)
    if [ -n "$LATEST" ]; then
      show_session_info "$LATEST"
    else
      echo "No Cowork sessions found."
      echo "Run with --help for usage."
      exit 1
    fi
    ;;
esac
