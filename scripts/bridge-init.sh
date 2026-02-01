#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Bridge Initializer
# Sets up the bridge directory structure for a Cowork session
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

CLAUDE_BASE="$HOME/Library/Application Support/Claude"
SKILLS_PLUGIN_DIR="$CLAUDE_BASE/skills-plugin"
COWORK_SKILL_SOURCE="$HOME/.claude/skills/cowork-bridge"

# ─────────────────────────────────────────────────────────────────────────────────
# Manifest Management
# ─────────────────────────────────────────────────────────────────────────────────

COWORK_BRIDGE_SKILL_ENTRY='{
  "skillId": "cowork-bridge",
  "name": "cowork-bridge",
  "description": "**CLI Bridge**: Enables sandboxed Cowork sessions to delegate commands to an unrestricted host-side Claude CLI.\n  - MANDATORY TRIGGERS: bridge, delegate, host, unrestricted, sandbox escape\n",
  "creatorType": "user",
  "enabled": true
}'

update_manifest() {
  local MANIFEST_FILE="$1"
  local NOW
  local NOW_MS
  NOW=$(date -Iseconds)
  NOW_MS=$(date +%s000)

  if jq -e '.skills[] | select(.skillId == "cowork-bridge")' "$MANIFEST_FILE" > /dev/null 2>&1; then
    jq --argjson now "$NOW_MS" --arg updated "$NOW" '
      .lastUpdated = $now |
      .skills = [.skills[] | if .skillId == "cowork-bridge" then .updatedAt = $updated else . end]
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  else
    jq --argjson now "$NOW_MS" --arg updated "$NOW" --argjson skill "$COWORK_BRIDGE_SKILL_ENTRY" '
      .lastUpdated = $now |
      .skills += [$skill | .updatedAt = $updated]
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Find Session
# ─────────────────────────────────────────────────────────────────────────────────

find_latest_session() {
  local CLAUDE_SESSIONS="$CLAUDE_BASE/local-agent-mode-sessions"

  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      stat -f "%m %N" "$dir" 2>/dev/null || stat -c "%Y %n" "$dir" 2>/dev/null
    fi
  done | sort -rn | head -1 | cut -d' ' -f2-
}

# ─────────────────────────────────────────────────────────────────────────────────
# Initialize Bridge
# ─────────────────────────────────────────────────────────────────────────────────

init_bridge() {
  local SESSION_PATH="$1"

  if [ ! -d "$SESSION_PATH" ]; then
    echo "Error: Session path does not exist: $SESSION_PATH"
    exit 1
  fi

  local BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"

  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Initializing Cowork Bridge"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Session: $SESSION_PATH"
  echo ""

  # Create directories
  echo "  Creating directories..."
  mkdir -p "$BRIDGE_DIR/requests"
  mkdir -p "$BRIDGE_DIR/responses"
  mkdir -p "$BRIDGE_DIR/streams"
  mkdir -p "$BRIDGE_DIR/logs"
  echo "    ✓ requests/"
  echo "    ✓ responses/"
  echo "    ✓ streams/"
  echo "    ✓ logs/"
  echo ""

  # Write status file
  echo "  Writing status.json..."
  cat > "$BRIDGE_DIR/status.json" << EOF
{
  "status": "ready",
  "initialized": "$(date -Iseconds)",
  "version": "1.0.0"
}
EOF
  echo "    ✓ status.json"
  echo ""

  # Extract workspace and account IDs from session path
  # Path format: .../local-agent-mode-sessions/<account-id>/<workspace-id>/local_<session-id>
  local WORKSPACE_ID
  local ACCOUNT_ID
  WORKSPACE_ID=$(basename "$(dirname "$SESSION_PATH")")
  ACCOUNT_ID=$(basename "$(dirname "$(dirname "$SESSION_PATH")")")

  # Inject cowork-bridge skill into skills-plugin directory
  local PLUGIN_BASE="$SKILLS_PLUGIN_DIR/$WORKSPACE_ID/$ACCOUNT_ID/.claude-plugin"
  local SKILL_TARGET="$PLUGIN_BASE/skills/cowork-bridge"
  local MANIFEST_FILE="$PLUGIN_BASE/manifest.json"

  echo "  Injecting skill..."
  if [ -d "$COWORK_SKILL_SOURCE" ]; then
    mkdir -p "$SKILL_TARGET"
    cp -r "$COWORK_SKILL_SOURCE"/* "$SKILL_TARGET/"
    echo "    ✓ cowork-bridge skill -> skills-plugin"

    # Update manifest.json
    if [ -f "$MANIFEST_FILE" ]; then
      update_manifest "$MANIFEST_FILE"
      echo "    ✓ Updated manifest.json"
    else
      echo "    ! manifest.json not found (skill may not appear until restart)"
    fi
  else
    echo "    ! Skill source not found at $COWORK_SKILL_SOURCE"
    echo "    ! Run install.sh first to install skills"
  fi
  echo ""

  # Check if settings.json exists, create template if not
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "  Creating settings.json template..."
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "env": {
    "BRIDGE_ENABLED": "true"
  }
}
EOF
    echo "    ✓ settings.json"
    echo ""
  else
    # Add BRIDGE_ENABLED if not present
    local SETTINGS
    SETTINGS=$(cat "$SETTINGS_FILE")
    if ! echo "$SETTINGS" | jq -e '.env.BRIDGE_ENABLED' > /dev/null 2>&1; then
      echo "$SETTINGS" | jq '.env.BRIDGE_ENABLED = "true"' > "$SETTINGS_FILE"
      echo "  Added BRIDGE_ENABLED to settings.json"
    else
      echo "  settings.json already configured"
    fi
    echo ""
  fi

  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Bridge Initialized Successfully!"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Bridge directory: $BRIDGE_DIR"
  echo ""
  echo "  Next steps:"
  echo "    1. Start the watcher on your Mac:"
  echo "       ~/.claude/skills/cli-bridge/watcher.sh"
  echo ""
  echo "    2. Or run it in the background:"
  echo "       nohup ~/.claude/skills/cli-bridge/watcher.sh &"
  echo ""
  echo "    3. In Cowork, requests to .bridge/requests/ will be processed"
  echo ""
  echo "  To inject environment variables:"
  echo "    echo '{\"env\": {\"MY_VAR\": \"value\"}}' > \"$SETTINGS_FILE\""
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────────
# Inject Env Vars
# ─────────────────────────────────────────────────────────────────────────────────

inject_env() {
  local SESSION_PATH="$1"
  shift
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"

  # Read existing or create new
  local SETTINGS='{}'
  if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS=$(cat "$SETTINGS_FILE")
  fi

  # Parse key=value pairs
  for pair in "$@"; do
    local KEY="${pair%%=*}"
    local VALUE="${pair#*=}"
    SETTINGS=$(echo "$SETTINGS" | jq --arg k "$KEY" --arg v "$VALUE" '.env[$k] = $v')
  done

  echo "$SETTINGS" > "$SETTINGS_FILE"
  echo "Updated $SETTINGS_FILE:"
  jq '.' "$SETTINGS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --env|-e)
    # Inject env vars: bridge-init.sh --env KEY=value KEY2=value2
    shift
    SESSION_PATH="${1:-}"
    if [ -z "$SESSION_PATH" ] || [[ "$SESSION_PATH" == *"="* ]]; then
      SESSION_PATH=$(find_latest_session)
    else
      shift
    fi

    if [ -z "$SESSION_PATH" ]; then
      echo "Error: No session found"
      exit 1
    fi

    if [ $# -eq 0 ]; then
      echo "Usage: $(basename "$0") --env [SESSION_PATH] KEY=value [KEY2=value2 ...]"
      exit 1
    fi

    inject_env "$SESSION_PATH" "$@"
    ;;

  --help|-h)
    echo "Usage: $(basename "$0") [OPTIONS] [SESSION_PATH]"
    echo ""
    echo "Options:"
    echo "  --env, -e KEY=val    Inject environment variables into session"
    echo "  --help, -h           Show this help"
    echo ""
    echo "If SESSION_PATH is not provided, the most recent session is used."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                              # Init latest session"
    echo "  $(basename "$0") /path/to/session             # Init specific session"
    echo "  $(basename "$0") --env API_KEY=xxx            # Inject env var"
    echo "  $(basename "$0") --env /path API_KEY=xxx      # Inject to specific session"
    ;;

  *)
    # Initialize bridge
    SESSION_PATH="${1:-}"
    if [ -z "$SESSION_PATH" ]; then
      SESSION_PATH=$(find_latest_session)
    fi

    if [ -z "$SESSION_PATH" ]; then
      echo "Error: No Cowork session found"
      echo "Run with --help for usage"
      exit 1
    fi

    init_bridge "$SESSION_PATH"
    ;;
esac
