#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Bridge Uninstaller
# Removes bridge files from a session or all sessions
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

CLAUDE_BASE="$HOME/Library/Application Support/Claude"
CLAUDE_SESSIONS="$CLAUDE_BASE/local-agent-mode-sessions"
SKILLS_PLUGIN_DIR="$CLAUDE_BASE/skills-plugin"
KNOWN_SESSIONS_FILE="$HOME/.claude/.bridge-known-sessions"

# ─────────────────────────────────────────────────────────────────────────────────
# Manifest Management
# ─────────────────────────────────────────────────────────────────────────────────

remove_from_manifest() {
  local MANIFEST_FILE="$1"
  local NOW_MS
  NOW_MS=$(date +%s000)

  if [ -f "$MANIFEST_FILE" ]; then
    if jq -e '.skills[] | select(.skillId == "cowork-bridge")' "$MANIFEST_FILE" > /dev/null 2>&1; then
      jq --argjson now "$NOW_MS" '
        .lastUpdated = $now |
        .skills = [.skills[] | select(.skillId != "cowork-bridge")]
      ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
      return 0
    fi
  fi
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────────
# Session Discovery
# ─────────────────────────────────────────────────────────────────────────────────

find_latest_session() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      stat -f "%m %N" "$dir" 2>/dev/null
    fi
  done | sort -rn | head -1 | cut -d' ' -f2-
}

get_all_sessions() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      echo "$dir"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────────
# Uninstall Functions
# ─────────────────────────────────────────────────────────────────────────────────

uninstall_session() {
  local SESSION_PATH="$1"
  local SESSION_ID
  SESSION_ID=$(basename "$SESSION_PATH")
  local DRY_RUN="${2:-false}"

  echo "Uninstalling bridge from: $SESSION_ID"

  local BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"

  # Extract workspace and account IDs from session path
  local WORKSPACE_ID
  local ACCOUNT_ID
  WORKSPACE_ID=$(basename "$(dirname "$SESSION_PATH")")
  ACCOUNT_ID=$(basename "$(dirname "$(dirname "$SESSION_PATH")")")
  local PLUGIN_BASE="$SKILLS_PLUGIN_DIR/$WORKSPACE_ID/$ACCOUNT_ID/.claude-plugin"
  local SKILL_PLUGIN_DIR="$PLUGIN_BASE/skills/cowork-bridge"
  local MANIFEST_FILE="$PLUGIN_BASE/manifest.json"

  # Remove bridge directory
  if [ -d "$BRIDGE_DIR" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would remove: $BRIDGE_DIR"
    else
      rm -rf "$BRIDGE_DIR"
      echo "  ✓ Removed .bridge directory"
    fi
  else
    echo "  - No .bridge directory found"
  fi

  # Remove injected skill from skills-plugin
  if [ -d "$SKILL_PLUGIN_DIR" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would remove: $SKILL_PLUGIN_DIR"
    else
      rm -rf "$SKILL_PLUGIN_DIR"
      echo "  ✓ Removed cowork-bridge skill from skills-plugin"
    fi
  else
    echo "  - No cowork-bridge skill found in skills-plugin"
  fi

  # Remove from manifest.json
  if [ -f "$MANIFEST_FILE" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would remove cowork-bridge from manifest.json"
    else
      if remove_from_manifest "$MANIFEST_FILE"; then
        echo "  ✓ Removed cowork-bridge from manifest.json"
      fi
    fi
  fi

  # Remove BRIDGE_ENABLED from settings.json (but keep the file)
  if [ -f "$SETTINGS_FILE" ]; then
    local SETTINGS
    SETTINGS=$(cat "$SETTINGS_FILE")
    if echo "$SETTINGS" | jq -e '.env.BRIDGE_ENABLED' > /dev/null 2>&1; then
      if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would remove BRIDGE_ENABLED from settings.json"
      else
        echo "$SETTINGS" | jq 'del(.env.BRIDGE_ENABLED)' > "$SETTINGS_FILE"
        echo "  ✓ Removed BRIDGE_ENABLED from settings.json"
      fi
    fi
  fi

  # Remove from known sessions
  if [ -f "$KNOWN_SESSIONS_FILE" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would remove from known sessions list"
    else
      grep -vF "$SESSION_PATH" "$KNOWN_SESSIONS_FILE" > "${KNOWN_SESSIONS_FILE}.tmp" 2>/dev/null || true
      mv "${KNOWN_SESSIONS_FILE}.tmp" "$KNOWN_SESSIONS_FILE"
    fi
  fi

  echo ""
}

uninstall_global() {
  local DRY_RUN="${1:-false}"

  echo "═══════════════════════════════════════════════════════════════"
  echo "  Uninstalling Cowork Bridge Globally"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # Stop any running daemons
  echo "Stopping daemons..."
  pkill -f "auto-setup-daemon.sh" 2>/dev/null && echo "  ✓ Stopped auto-setup daemon" || echo "  - No auto-setup daemon running"
  pkill -f "cli-bridge/watcher.sh" 2>/dev/null && echo "  ✓ Stopped bridge watcher" || echo "  - No bridge watcher running"
  echo ""

  # Remove launchd job if exists
  local LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.claude.bridge-auto-setup.plist"
  if [ -f "$LAUNCHD_PLIST" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "[DRY RUN] Would unload and remove: $LAUNCHD_PLIST"
    else
      launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
      rm -f "$LAUNCHD_PLIST"
      echo "✓ Removed launchd job"
    fi
  fi

  # Remove skills
  local CLI_SKILL="$HOME/.claude/skills/cli-bridge"
  local COWORK_SKILL="$HOME/.claude/skills/cowork-bridge"

  if [ -d "$CLI_SKILL" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "[DRY RUN] Would remove: $CLI_SKILL"
    else
      rm -rf "$CLI_SKILL"
      echo "✓ Removed cli-bridge skill"
    fi
  fi

  if [ -d "$COWORK_SKILL" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "[DRY RUN] Would remove: $COWORK_SKILL"
    else
      rm -rf "$COWORK_SKILL"
      echo "✓ Removed cowork-bridge skill"
    fi
  fi

  # Remove CLI tools
  local BIN_DIR="$HOME/.local/bin"
  for tool in cowork-session cowork-bridge-init cowork-bridge-uninstall; do
    if [ -f "$BIN_DIR/$tool" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY RUN] Would remove: $BIN_DIR/$tool"
      else
        rm -f "$BIN_DIR/$tool"
        echo "✓ Removed $tool"
      fi
    fi
  done

  # Remove known sessions file
  if [ -f "$KNOWN_SESSIONS_FILE" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "[DRY RUN] Would remove: $KNOWN_SESSIONS_FILE"
    else
      rm -f "$KNOWN_SESSIONS_FILE"
      echo "✓ Removed known sessions list"
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  Global uninstall complete"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Note: Bridge directories in existing sessions were NOT removed."
  echo "To remove from all sessions, run:"
  echo "  $(basename "$0") --all"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --session|-s)
    # Uninstall from specific session
    SESSION_PATH="${2:-}"
    if [ -z "$SESSION_PATH" ]; then
      SESSION_PATH=$(find_latest_session)
    fi
    if [ -z "$SESSION_PATH" ]; then
      echo "Error: No session found"
      exit 1
    fi
    uninstall_session "$SESSION_PATH" "${3:-false}"
    ;;

  --all|-a)
    # Uninstall from ALL sessions
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Uninstalling bridge from ALL sessions"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    DRY_RUN="${2:-false}"

    while IFS= read -r session; do
      [ -z "$session" ] && continue
      uninstall_session "$session" "$DRY_RUN"
    done <<< "$(get_all_sessions)"

    echo "Done."
    ;;

  --global|-g)
    # Uninstall global components (skills, tools, daemons)
    uninstall_global "${2:-false}"
    ;;

  --full|-F)
    # Full uninstall: global + all sessions
    echo "═══════════════════════════════════════════════════════════════"
    echo "  FULL UNINSTALL"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "This will remove:"
    echo "  - All bridge directories from all sessions"
    echo "  - Global skills and tools"
    echo "  - Daemons and launchd jobs"
    echo ""
    read -r -p "Are you sure? [y/N] " -n 1 REPLY
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      uninstall_global "false"
      echo ""
      while IFS= read -r session; do
        [ -z "$session" ] && continue
        uninstall_session "$session" "false"
      done <<< "$(get_all_sessions)"
      echo ""
      echo "Full uninstall complete."
    else
      echo "Aborted."
    fi
    ;;

  --dry-run|-n)
    # Dry run - show what would be removed
    echo "═══════════════════════════════════════════════════════════════"
    echo "  DRY RUN - No changes will be made"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    echo "Global components:"
    uninstall_global "true"

    echo ""
    echo "Sessions:"
    while IFS= read -r session; do
      [ -z "$session" ] && continue
      uninstall_session "$session" "true"
    done <<< "$(get_all_sessions)"
    ;;

  --help|-h)
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --session, -s [PATH]   Uninstall from specific session (default: latest)"
    echo "  --all, -a              Uninstall from ALL sessions"
    echo "  --global, -g           Uninstall global components (skills, tools, daemons)"
    echo "  --full, -F             Full uninstall (global + all sessions)"
    echo "  --dry-run, -n          Show what would be removed without making changes"
    echo "  --help, -h             Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --session              # Uninstall from latest session"
    echo "  $(basename "$0") --all                  # Uninstall from all sessions"
    echo "  $(basename "$0") --global               # Remove skills/tools/daemons"
    echo "  $(basename "$0") --full                 # Complete removal"
    echo "  $(basename "$0") --dry-run              # Preview changes"
    ;;

  *)
    # Default: uninstall from latest session
    SESSION_PATH=$(find_latest_session)
    if [ -z "$SESSION_PATH" ]; then
      echo "Error: No session found"
      echo "Run with --help for usage"
      exit 1
    fi
    uninstall_session "$SESSION_PATH" "false"
    ;;
esac
