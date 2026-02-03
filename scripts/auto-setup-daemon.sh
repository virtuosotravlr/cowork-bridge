#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Bridge Auto-Setup Daemon
# Watches for new Cowork sessions and automatically initializes the bridge
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_BASE="$HOME/Library/Application Support/Claude"
CLAUDE_SESSIONS="$CLAUDE_BASE/local-agent-mode-sessions"
LOG_PREFIX="[auto-setup]"
POLL_INTERVAL=2
KNOWN_SESSIONS_FILE="$HOME/.claude/.bridge-known-sessions"

# Skills source (installed to ~/.claude/skills/ by install.sh)
COWORK_SKILL_SOURCE="$HOME/.claude/skills/cowork-bridge"
COWORK_SKILL_FALLBACK="$REPO_DIR/skills/cowork-bridge"

# ─────────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────────

log() {
  local LEVEL="$1"
  shift
  echo "$LOG_PREFIX [$LEVEL] $(date -Iseconds) - $*"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

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

  if [ ! -f "$MANIFEST_FILE" ]; then
    jq -n --argjson skill "$COWORK_BRIDGE_SKILL_ENTRY" --argjson now "$NOW_MS" --arg updated "$NOW" '
      {lastUpdated: $now, skills: [$skill | .updatedAt = $updated]}
    ' > "$MANIFEST_FILE"
    return
  fi

  # Check if cowork-bridge already exists in manifest
  if jq -e '.skills // [] | .[] | select(.skillId == "cowork-bridge")' "$MANIFEST_FILE" > /dev/null 2>&1; then
    # Update existing entry
    jq --argjson now "$NOW_MS" --arg updated "$NOW" '
      .lastUpdated = $now |
      .skills = ((.skills // []) | map(if .skillId == "cowork-bridge" then .updatedAt = $updated else . end))
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  else
    # Add new entry
    jq --argjson now "$NOW_MS" --arg updated "$NOW" --argjson skill "$COWORK_BRIDGE_SKILL_ENTRY" '
      .lastUpdated = $now |
      .skills = ((.skills // []) + [$skill | .updatedAt = $updated])
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  fi
}

get_plugin_base() {
  local SESSION_PATH="$1"
  local SESSION_DIR
  local INNER_ID
  local OUTER_ID
  SESSION_DIR="$(dirname "$SESSION_PATH")"
  INNER_ID="$(basename "$SESSION_DIR")"
  OUTER_ID="$(basename "$(dirname "$SESSION_DIR")")"

  local BASE_PRIMARY="$CLAUDE_BASE/local-agent-mode-sessions/skills-plugin/$INNER_ID/$OUTER_ID"
  local BASE_SECONDARY="$CLAUDE_BASE/local-agent-mode-sessions/skills-plugin/$OUTER_ID/$INNER_ID"
  local BASE_LEGACY="$CLAUDE_BASE/skills-plugin/$OUTER_ID/$INNER_ID/.claude-plugin"

  if [ -d "$BASE_PRIMARY" ]; then
    echo "$BASE_PRIMARY"
    return
  fi

  if [ -d "$BASE_SECONDARY" ]; then
    echo "$BASE_SECONDARY"
    return
  fi

  if [ -d "$BASE_LEGACY" ]; then
    echo "$BASE_LEGACY"
    return
  fi

  echo "$BASE_PRIMARY"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Session Setup
# ─────────────────────────────────────────────────────────────────────────────────

setup_session() {
  local SESSION_PATH="$1"
  local SESSION_ID
  SESSION_ID=$(basename "$SESSION_PATH")

  log_info "Setting up new session: $SESSION_ID"

  # Create bridge directories
  local BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  mkdir -p "$BRIDGE_DIR/requests"
  mkdir -p "$BRIDGE_DIR/responses"
  mkdir -p "$BRIDGE_DIR/streams"
  mkdir -p "$BRIDGE_DIR/logs"

  # Write status
  cat > "$BRIDGE_DIR/status.json" << EOF
{
  "status": "ready",
  "initialized": "$(date -Iseconds)",
  "auto_setup": true,
  "version": "1.0.0"
}
EOF

  local PLUGIN_BASE
  PLUGIN_BASE=$(get_plugin_base "$SESSION_PATH")
  local SKILL_TARGET="$PLUGIN_BASE/skills/cowork-bridge"
  local MANIFEST_FILE="$PLUGIN_BASE/manifest.json"

  if [ -d "$COWORK_SKILL_SOURCE" ]; then
    mkdir -p "$SKILL_TARGET"
    cp -r "$COWORK_SKILL_SOURCE"/* "$SKILL_TARGET/"
    log_info "  ✓ Installed cowork-bridge skill to skills-plugin"
    update_manifest "$MANIFEST_FILE"
  elif [ -d "$COWORK_SKILL_FALLBACK" ]; then
    mkdir -p "$SKILL_TARGET"
    cp -r "$COWORK_SKILL_FALLBACK"/* "$SKILL_TARGET/"
    log_info "  ✓ Installed cowork-bridge skill to skills-plugin (repo source)"
    update_manifest "$MANIFEST_FILE"
  else
    log_warn "  ! Skill source not found at $COWORK_SKILL_SOURCE or $COWORK_SKILL_FALLBACK"
  fi

  # Set up default env vars if settings.json doesn't exist
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"
  if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "env": {
    "BRIDGE_ENABLED": "true"
  }
}
EOF
    log_info "  ✓ Created settings.json with BRIDGE_ENABLED"
  else
    # Add BRIDGE_ENABLED to existing settings
    local SETTINGS
    SETTINGS=$(cat "$SETTINGS_FILE")
    if ! echo "$SETTINGS" | jq -e '.env.BRIDGE_ENABLED' > /dev/null 2>&1; then
      echo "$SETTINGS" | jq '.env.BRIDGE_ENABLED = "true"' > "$SETTINGS_FILE"
      log_info "  ✓ Added BRIDGE_ENABLED to existing settings.json"
    fi
  fi

  log_info "  ✓ Bridge initialized for $SESSION_ID"

  # Record as known
  echo "$SESSION_PATH" >> "$KNOWN_SESSIONS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Session Discovery
# ─────────────────────────────────────────────────────────────────────────────────

get_all_sessions() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      echo "$dir"
    fi
  done
}

is_known_session() {
  local SESSION_PATH="$1"
  if [ -f "$KNOWN_SESSIONS_FILE" ]; then
    grep -qF "$SESSION_PATH" "$KNOWN_SESSIONS_FILE" 2>/dev/null
  else
    return 1
  fi
}

is_setup() {
  local SESSION_PATH="$1"
  [ -f "$SESSION_PATH/outputs/.bridge/status.json" ]
}

# ─────────────────────────────────────────────────────────────────────────────────
# Watch Loop
# ─────────────────────────────────────────────────────────────────────────────────

watch_loop() {
  log_info "═══════════════════════════════════════════════════════════════"
  log_info "  Cowork Bridge Auto-Setup Daemon"
  log_info "═══════════════════════════════════════════════════════════════"
  log_info "Watching: $CLAUDE_SESSIONS"
  log_info "Poll interval: ${POLL_INTERVAL}s"
  log_info ""

  # Initialize known sessions file
  mkdir -p "$(dirname "$KNOWN_SESSIONS_FILE")"
  touch "$KNOWN_SESSIONS_FILE"

  # No-op: per-session skills are installed during setup_session

  while true; do
    # Find all sessions
    while IFS= read -r session; do
      [ -z "$session" ] && continue

      # Check if already set up
      if ! is_setup "$session"; then
        setup_session "$session"
      elif ! is_known_session "$session"; then
        # Already set up but not in our list (maybe manual setup)
        echo "$session" >> "$KNOWN_SESSIONS_FILE"
        log_info "Registered existing setup: $(basename "$session")"
      fi
    done <<< "$(get_all_sessions)"

    sleep "$POLL_INTERVAL"
  done
}

# ─────────────────────────────────────────────────────────────────────────────────
# FSWatch Mode (faster, if available)
# ─────────────────────────────────────────────────────────────────────────────────

watch_fswatch() {
  if ! command -v fswatch &> /dev/null; then
    log_warn "fswatch not found, falling back to polling mode"
    log_warn "Install with: brew install fswatch"
    watch_loop
    return
  fi

  log_info "═══════════════════════════════════════════════════════════════"
  log_info "  Cowork Bridge Auto-Setup Daemon (fswatch mode)"
  log_info "═══════════════════════════════════════════════════════════════"
  log_info "Watching: $CLAUDE_SESSIONS"
  log_info ""

  mkdir -p "$(dirname "$KNOWN_SESSIONS_FILE")"
  touch "$KNOWN_SESSIONS_FILE"

  # Initial scan
  while IFS= read -r session; do
    [ -z "$session" ] && continue
    if ! is_setup "$session"; then
      setup_session "$session"
    fi
  done <<< "$(get_all_sessions)"

  # Watch for new directories
  fswatch -0 --event Created "$CLAUDE_SESSIONS" | while IFS= read -r -d '' event; do
    # Check if it's a local_ session directory
    if [[ "$event" == *"/local_"* ]] && [ -d "$event" ]; then
      # Wait a moment for .claude folder to be created
      sleep 1
      if [ -d "$event/.claude" ] && ! is_setup "$event"; then
        setup_session "$event"
      fi
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --fswatch|-f)
    watch_fswatch
    ;;
  --once|-o)
    # One-time setup of all sessions (for testing)
    log_info "Running one-time setup for all sessions..."
    while IFS= read -r session; do
      [ -z "$session" ] && continue
      if ! is_setup "$session"; then
        setup_session "$session"
      else
        log_info "Already set up: $(basename "$session")"
      fi
    done <<< "$(get_all_sessions)"
    log_info "Done."
    ;;
  --help|-h)
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --fswatch, -f   Use fswatch for faster detection (requires: brew install fswatch)"
    echo "  --once, -o      One-time setup of all existing sessions, then exit"
    echo "  --help, -h      Show this help"
    echo ""
    echo "Without options, runs in polling mode (checks every ${POLL_INTERVAL}s)"
    ;;
  *)
    watch_loop
    ;;
esac
