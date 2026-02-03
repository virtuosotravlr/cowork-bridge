#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Bridge - Setup All Sessions
# Retroactively sets up the bridge for all existing Cowork sessions
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_BASE="$HOME/Library/Application Support/Claude"
CLAUDE_SESSIONS="$CLAUDE_BASE/local-agent-mode-sessions"
KNOWN_SESSIONS_FILE="$HOME/.claude/.bridge-known-sessions"
COWORK_SKILL_SOURCE="$HOME/.claude/skills/cowork-bridge"
COWORK_SKILL_FALLBACK="$REPO_DIR/skills/cowork-bridge"

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

  if jq -e '.skills // [] | .[] | select(.skillId == "cowork-bridge")' "$MANIFEST_FILE" >/dev/null 2>&1; then
    jq --argjson now "$NOW_MS" --arg updated "$NOW" '
      .lastUpdated = $now |
      .skills = ((.skills // []) | map(if .skillId == "cowork-bridge" then .updatedAt = $updated else . end))
    ' "$MANIFEST_FILE" >"${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  else
    jq --argjson now "$NOW_MS" --arg updated "$NOW" --argjson skill "$COWORK_BRIDGE_SKILL_ENTRY" '
      .lastUpdated = $now |
      .skills = ((.skills // []) + [$skill | .updatedAt = $updated])
    ' "$MANIFEST_FILE" >"${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
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
# Session Discovery
# ─────────────────────────────────────────────────────────────────────────────────

get_all_sessions() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      echo "$dir"
    fi
  done
}

is_setup() {
  local SESSION_PATH="$1"
  [ -f "$SESSION_PATH/outputs/.bridge/status.json" ]
}

# ─────────────────────────────────────────────────────────────────────────────────
# Setup Function
# ─────────────────────────────────────────────────────────────────────────────────

setup_session() {
  local SESSION_PATH="$1"
  local SESSION_ID
  SESSION_ID=$(basename "$SESSION_PATH")
  local FORCE="${2:-false}"

  # Skip if already set up (unless forcing)
  if is_setup "$SESSION_PATH" && [ "$FORCE" != "true" ]; then
    echo "  [SKIP] $SESSION_ID - already set up (use --force to override)"
    return 0
  fi

  echo "  [SETUP] $SESSION_ID"

  # Create bridge directories
  local BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  mkdir -p "$BRIDGE_DIR/requests"
  mkdir -p "$BRIDGE_DIR/responses"
  mkdir -p "$BRIDGE_DIR/streams"
  mkdir -p "$BRIDGE_DIR/logs"

  # Write status
  cat >"$BRIDGE_DIR/status.json" <<EOF
{
  "status": "ready",
  "initialized": "$(date -Iseconds)",
  "retroactive_setup": true,
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
    echo "           ✓ Injected skill to skills-plugin"
    update_manifest "$MANIFEST_FILE"
    echo "           ✓ Updated manifest.json"
  elif [ -d "$COWORK_SKILL_FALLBACK" ]; then
    mkdir -p "$SKILL_TARGET"
    cp -r "$COWORK_SKILL_FALLBACK"/* "$SKILL_TARGET/"
    echo "           ✓ Injected skill to skills-plugin (repo source)"
    update_manifest "$MANIFEST_FILE"
    echo "           ✓ Updated manifest.json"
  fi

  # Add BRIDGE_ENABLED to settings.json
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"
  if [ -f "$SETTINGS_FILE" ]; then
    local SETTINGS
    SETTINGS=$(cat "$SETTINGS_FILE")
    if ! echo "$SETTINGS" | jq -e '.env.BRIDGE_ENABLED' >/dev/null 2>&1; then
      echo "$SETTINGS" | jq '.env.BRIDGE_ENABLED = "true"' >"$SETTINGS_FILE"
      echo "           ✓ Updated settings.json"
    fi
  else
    cat >"$SETTINGS_FILE" <<'EOF'
{
  "env": {
    "BRIDGE_ENABLED": "true"
  }
}
EOF
    echo "           ✓ Created settings.json"
  fi

  # Record in known sessions
  mkdir -p "$(dirname "$KNOWN_SESSIONS_FILE")"
  if ! grep -qF "$SESSION_PATH" "$KNOWN_SESSIONS_FILE" 2>/dev/null; then
    echo "$SESSION_PATH" >>"$KNOWN_SESSIONS_FILE"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

FORCE="false"
DRY_RUN="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --force | -f)
    FORCE="true"
    shift
    ;;
  --dry-run | -n)
    DRY_RUN="true"
    shift
    ;;
  --verbose | -v)
    VERBOSE="true"
    shift
    ;;
  --help | -h)
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force, -f     Re-setup sessions that are already configured"
    echo "  --dry-run, -n   Show what would be done without making changes"
    echo "  --verbose, -v   Show detailed output"
    echo "  --help, -h      Show this help"
    echo ""
    echo "This script sets up the bridge for all existing Cowork sessions."
    echo "Sessions that are already set up are skipped unless --force is used."
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    echo "Run with --help for usage"
    exit 1
    ;;
  esac
done

echo "═══════════════════════════════════════════════════════════════"
echo "  Cowork Bridge - Retroactive Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Sessions directory: $CLAUDE_SESSIONS"
echo "Force mode: $FORCE"
echo "Dry run: $DRY_RUN"
echo ""

# Count sessions
TOTAL=0
SETUP_COUNT=0
SKIP_COUNT=0

echo "Scanning for sessions..."
echo ""

while IFS= read -r session; do
  [ -z "$session" ] && continue
  TOTAL=$((TOTAL + 1))

  if [ "$DRY_RUN" = "true" ]; then
    if is_setup "$session"; then
      if [ "$FORCE" = "true" ]; then
        echo "  [DRY RUN] Would re-setup: $(basename "$session")"
        SETUP_COUNT=$((SETUP_COUNT + 1))
      else
        echo "  [DRY RUN] Would skip: $(basename "$session") (already set up)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
      fi
    else
      echo "  [DRY RUN] Would setup: $(basename "$session")"
      SETUP_COUNT=$((SETUP_COUNT + 1))
    fi
  else
    if is_setup "$session" && [ "$FORCE" != "true" ]; then
      if [ "$VERBOSE" = "true" ]; then
        echo "  [SKIP] $(basename "$session") - already set up"
      fi
      SKIP_COUNT=$((SKIP_COUNT + 1))
    else
      setup_session "$session" "$FORCE"
      SETUP_COUNT=$((SETUP_COUNT + 1))
    fi
  fi
done <<<"$(get_all_sessions)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Total sessions found: $TOTAL"
echo "  Sessions set up:      $SETUP_COUNT"
echo "  Sessions skipped:     $SKIP_COUNT"
echo ""

if [ "$DRY_RUN" = "true" ]; then
  echo "This was a dry run. No changes were made."
  echo "Run without --dry-run to apply changes."
fi
