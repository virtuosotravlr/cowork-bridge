#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork System Prompt Injector
# Override the default Cowork system prompt with a custom one
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
# Look for prompts in installed location first, then repo location
if [ -d "$HOME/.claude/prompts" ]; then
  PROMPTS_DIR="$HOME/.claude/prompts"
else
  PROMPTS_DIR="$(dirname "$SCRIPT_DIR")/prompts"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $(basename "$0") [OPTIONS] [PROMPT_FILE]"
  echo ""
  echo "Inject a custom system prompt into a Cowork session."
  echo ""
  echo "Options:"
  echo "  --session PATH    Target specific session (default: latest)"
  echo "  --list            List available prompt presets"
  echo "  --backup          Backup original prompt before replacing"
  echo "  --restore         Restore original prompt from backup"
  echo "  --show            Show current prompt (truncated)"
  echo "  --dry-run         Preview changes without applying"
  echo "  -h, --help        Show this help"
  echo ""
  echo "Prompt Presets:"
  echo "  power-user        Developer mode: reduced restrictions, bridge-aware"
  echo "  minimal           Bare minimum prompt for maximum freedom"
  echo "  cli-mode          Mimic Claude Code CLI behavior"
  echo "  custom            Use a custom JSON file"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") power-user              # Use power-user preset"
  echo "  $(basename "$0") --backup power-user     # Backup first, then inject"
  echo "  $(basename "$0") --restore               # Restore original"
  echo "  $(basename "$0") /path/to/custom.json    # Use custom prompt file"
}

find_latest_session() {
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
    if [ -d "$dir/.claude" ]; then
      stat -f "%m %N" "$dir" 2>/dev/null || stat -c "%Y %n" "$dir" 2>/dev/null
    fi
  done | sort -rn | head -1 | cut -d' ' -f2-
}

prompt_paths() {
  local SESSION_PATH="$1"
  local SETTINGS_FILE="$SESSION_PATH/cowork_settings.json"
  local META_FILE
  META_FILE="$(dirname "$SESSION_PATH")/$(basename "$SESSION_PATH").json"
  echo "$SETTINGS_FILE" "$META_FILE"
}

resolve_prompt_target() {
  local SESSION_PATH="$1"
  local SETTINGS_FILE
  local META_FILE
  read -r SETTINGS_FILE META_FILE <<< "$(prompt_paths "$SESSION_PATH")"

  if [ -f "$SETTINGS_FILE" ]; then
    if jq -e '.systemPrompt?' "$SETTINGS_FILE" >/dev/null 2>&1; then
      echo "$SETTINGS_FILE"
      return
    fi
  fi

  if [ -f "$META_FILE" ]; then
    if jq -e '.systemPrompt?' "$META_FILE" >/dev/null 2>&1; then
      echo "$META_FILE"
      return
    fi
  fi

  if [ -f "$META_FILE" ]; then
    echo "$META_FILE"
    return
  fi

  echo "$SETTINGS_FILE"
}

get_prompt_file() {
  local PRESET="$1"
  case "$PRESET" in
    power-user|power)
      echo "$PROMPTS_DIR/power-user-prompt.json"
      ;;
    minimal|min)
      echo "$PROMPTS_DIR/minimal-prompt.json"
      ;;
    cli-mode|cli)
      echo "$PROMPTS_DIR/cli-mode-prompt.json"
      ;;
    *)
      # Assume it's a file path
      if [ -f "$PRESET" ]; then
        echo "$PRESET"
      else
        echo ""
      fi
      ;;
  esac
}

list_presets() {
  echo "Available Prompt Presets:"
  echo ""
  echo -e "${GREEN}power-user${NC} (alias: power)"
  echo "  Developer mode with reduced restrictions and bridge integration."
  echo "  - Skips TodoWrite/AskUserQuestion overhead"
  echo "  - Bridge-aware for sandbox escape"
  echo "  - Direct communication style"
  echo ""
  echo -e "${GREEN}minimal${NC} (alias: min)"
  echo "  Bare minimum system prompt."
  echo "  - Maximum freedom, minimal guidance"
  echo "  - Use with caution"
  echo ""
  echo -e "${GREEN}cli-mode${NC} (alias: cli)"
  echo "  Mimics Claude Code CLI behavior."
  echo "  - Terse responses"
  echo "  - Assumes developer context"
  echo "  - Git-aware defaults"
  echo ""
  echo "Custom prompts: Provide a JSON file path with {\"systemPrompt\": \"...\"}"
}

backup_prompt() {
  local SESSION_PATH="$1"
  local SETTINGS_FILE
  local META_FILE
  read -r SETTINGS_FILE META_FILE <<< "$(prompt_paths "$SESSION_PATH")"

  local TARGET
  TARGET=$(resolve_prompt_target "$SESSION_PATH")

  if [ -f "$TARGET" ]; then
    local BACKUP_FILE="${TARGET}.original"
    local TS_BACKUP
    TS_BACKUP="${TARGET}.backup.$(date +%Y%m%d-%H%M%S)"
    if [ ! -f "$BACKUP_FILE" ]; then
      cp "$TARGET" "$BACKUP_FILE"
      echo -e "${GREEN}✓${NC} Backed up original prompt to: $BACKUP_FILE"
    else
      echo -e "${YELLOW}!${NC} Backup already exists, skipping: $BACKUP_FILE"
    fi
    cp "$TARGET" "$TS_BACKUP"
    echo -e "${GREEN}✓${NC} Timestamped backup: $TS_BACKUP"
  else
    echo -e "${YELLOW}!${NC} Target file not found for backup: $TARGET"
  fi
}

restore_prompt() {
  local SESSION_PATH="$1"
  local SETTINGS_FILE
  local META_FILE
  read -r SETTINGS_FILE META_FILE <<< "$(prompt_paths "$SESSION_PATH")"

  local TARGET
  TARGET=$(resolve_prompt_target "$SESSION_PATH")
  local BACKUP_FILE="${TARGET}.original"

  if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$TARGET"
    echo -e "${GREEN}✓${NC} Restored original prompt"
    return
  fi

  local LATEST_BACKUP
  LATEST_BACKUP=$(find "$(dirname "$TARGET")" -maxdepth 1 -name "$(basename "$TARGET").backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [ -n "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP" "$TARGET"
    echo -e "${GREEN}✓${NC} Restored prompt from: $LATEST_BACKUP"
  else
    echo -e "${RED}✗${NC} No backup found at $BACKUP_FILE"
    exit 1
  fi
}

show_prompt() {
  local SESSION_PATH="$1"
  local SETTINGS_FILE
  SETTINGS_FILE=$(resolve_prompt_target "$SESSION_PATH")

  if [ -f "$SETTINGS_FILE" ]; then
    echo "Current prompt (first 2000 chars):"
    echo "─────────────────────────────────────"
    jq -r '.systemPrompt // empty' "$SETTINGS_FILE" 2>/dev/null | head -c 2000
    echo ""
    echo "─────────────────────────────────────"
    local TOTAL
    TOTAL=$(jq -r '(.systemPrompt // "") | length' "$SETTINGS_FILE" 2>/dev/null)
    echo "Total length: $TOTAL characters"
  else
    echo -e "${RED}✗${NC} No settings file found"
  fi
}

inject_prompt() {
  local SESSION_PATH="$1"
  local PROMPT_FILE="$2"
  local DRY_RUN="${3:-false}"

  local SETTINGS_FILE
  SETTINGS_FILE=$(resolve_prompt_target "$SESSION_PATH")

  if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}✗${NC} Prompt file not found: $PROMPT_FILE"
    exit 1
  fi

  # Read new prompt
  local NEW_PROMPT
  NEW_PROMPT=$(jq -r '.systemPrompt' "$PROMPT_FILE")

  if [ -z "$NEW_PROMPT" ] || [ "$NEW_PROMPT" = "null" ]; then
    echo -e "${RED}✗${NC} Invalid prompt file (missing systemPrompt key)"
    exit 1
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN${NC} - Would inject prompt from: $PROMPT_FILE"
    echo "Target: $SETTINGS_FILE"
    echo ""
    echo "New prompt preview (first 1000 chars):"
    echo "$NEW_PROMPT" | head -c 1000
    echo "..."
    return
  fi

  if [ -f "$SETTINGS_FILE" ]; then
    if ! jq -e '.' "$SETTINGS_FILE" >/dev/null 2>&1; then
      echo -e "${RED}✗${NC} Target file has invalid JSON: $SETTINGS_FILE"
      exit 1
    fi
  fi

  # Read existing settings (if any)
  if [ -f "$SETTINGS_FILE" ]; then
    # Merge: keep other settings, replace systemPrompt
    jq --arg prompt "$NEW_PROMPT" '.systemPrompt = $prompt' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  else
    # Create new settings file
    jq -n --arg prompt "$NEW_PROMPT" '{systemPrompt: $prompt}' > "$SETTINGS_FILE"
  fi

  echo -e "${GREEN}✓${NC} Injected prompt from: $(basename "$PROMPT_FILE")"
  echo "  Target: $SETTINGS_FILE"
  echo ""
  echo -e "${YELLOW}Note:${NC} Changes take effect on next Cowork message (no restart needed)"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

SESSION_PATH=""
DO_BACKUP=false
DO_RESTORE=false
DO_SHOW=false
DO_LIST=false
DRY_RUN=false
PROMPT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)
      SESSION_PATH="$2"
      shift 2
      ;;
    --backup)
      DO_BACKUP=true
      shift
      ;;
    --restore)
      DO_RESTORE=true
      shift
      ;;
    --show)
      DO_SHOW=true
      shift
      ;;
    --list)
      DO_LIST=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PROMPT_ARG="$1"
      shift
      ;;
  esac
done

# List presets
if [ "$DO_LIST" = "true" ]; then
  list_presets
  exit 0
fi

# Find session if not specified
if [ -z "$SESSION_PATH" ]; then
  SESSION_PATH=$(find_latest_session)
  if [ -z "$SESSION_PATH" ]; then
    echo -e "${RED}✗${NC} No active Cowork session found"
    exit 1
  fi
fi

echo "Session: $SESSION_PATH"
echo ""

# Show current prompt
if [ "$DO_SHOW" = "true" ]; then
  show_prompt "$SESSION_PATH"
  exit 0
fi

# Restore backup
if [ "$DO_RESTORE" = "true" ]; then
  restore_prompt "$SESSION_PATH"
  exit 0
fi

# Need a prompt argument for injection
if [ -z "$PROMPT_ARG" ]; then
  usage
  exit 1
fi

# Resolve prompt file
PROMPT_FILE=$(get_prompt_file "$PROMPT_ARG")
if [ -z "$PROMPT_FILE" ]; then
  echo -e "${RED}✗${NC} Unknown preset or file not found: $PROMPT_ARG"
  echo "Run with --list to see available presets"
  exit 1
fi

# Backup if requested
  if [ "$DO_BACKUP" = "true" ]; then
    backup_prompt "$SESSION_PATH"
  fi

  if [ "$DO_BACKUP" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    echo -e "${YELLOW}!${NC} No backup requested. Creating a safety backup."
    backup_prompt "$SESSION_PATH"
  fi

  # Inject
  inject_prompt "$SESSION_PATH" "$PROMPT_FILE" "$DRY_RUN"
