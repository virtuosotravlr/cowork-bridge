#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork Session Config Injector
# Modify any field in cowork_settings.json - model, tools, paths, prompt, etc.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
  cat << 'EOF'
Usage: inject-session [OPTIONS] [COMMAND]

Modify Cowork session configuration on the fly.

COMMANDS:
  show                    Show current session config (formatted)
  model <model>           Switch model (opus/sonnet/haiku)
  prompt <preset|file>    Inject system prompt preset or custom file
  approve-path <path>     Pre-approve a file access path
  mount <path>            Pre-mount a folder
  enable-tool <hash>      Enable an MCP tool by hash
  disable-tool <hash>     Disable an MCP tool by hash
  list-tools              List all MCP tools and their status
  backup                  Backup current config
  restore                 Restore from backup
  edit                    Open config in $EDITOR

OPTIONS:
  --session PATH          Target specific session (default: latest)
  --dry-run               Preview changes without applying
  -h, --help              Show this help

EXAMPLES:
  inject-session model sonnet              # Switch to faster model
  inject-session prompt power-user         # Use power-user preset
  inject-session approve-path ~/projects   # Pre-approve path access
  inject-session mount ~/Documents         # Pre-mount a folder
  inject-session list-tools                # See available MCP tools
  inject-session show                      # View full config

MODELS:
  opus    = claude-opus-4-5-20251101      (most capable, slower)
  sonnet  = claude-sonnet-4-5-20250929    (balanced)
  haiku   = claude-haiku-4-5-20251001     (fastest, cheapest)
EOF
}

find_latest_session() {
  find "$CLAUDE_SESSIONS" -type f -name "cowork_settings.json" -maxdepth 4 2>/dev/null | while IFS= read -r f; do
    stat -f "%m %N" "$f" 2>/dev/null || stat -c "%Y %n" "$f" 2>/dev/null
  done | sort -rn | head -1 | cut -d' ' -f2-
}

get_session_dir() {
  local CONFIG_FILE="$1"
  dirname "$CONFIG_FILE"
}

resolve_model() {
  local MODEL="$1"
  case "$MODEL" in
    opus|o)   echo "claude-opus-4-5-20251101" ;;
    sonnet|s) echo "claude-sonnet-4-5-20250929" ;;
    haiku|h)  echo "claude-haiku-4-5-20251001" ;;
    claude-*) echo "$MODEL" ;;  # Already full name
    *)        echo "" ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────────

cmd_show() {
  local CONFIG="$1"
  echo -e "${CYAN}Session Config:${NC} $CONFIG"
  echo ""

  # Extract key fields
  local MODEL TITLE ARCHIVED FOLDERS APPROVED TOOLS COMMANDS PROMPT_LEN
  MODEL=$(jq -r '.model // "unknown"' "$CONFIG")
  TITLE=$(jq -r '.title // "untitled"' "$CONFIG")
  ARCHIVED=$(jq -r '.isArchived // false' "$CONFIG")
  FOLDERS=$(jq -r '(.userSelectedFolders // []) | length' "$CONFIG")
  APPROVED=$(jq -r '(.userApprovedFileAccessPaths // []) | length' "$CONFIG")
  TOOLS=$(jq -r '(.enabledMcpTools // {}) | keys | length' "$CONFIG")
  COMMANDS=$(jq -r '(.slashCommands // []) | length' "$CONFIG")
  PROMPT_LEN=$(jq -r '(.systemPrompt // "") | length' "$CONFIG")

  echo -e "${GREEN}Model:${NC}          $MODEL"
  echo -e "${GREEN}Title:${NC}          $TITLE"
  echo -e "${GREEN}Archived:${NC}       $ARCHIVED"
  echo -e "${GREEN}Mounted Folders:${NC} $FOLDERS"
  echo -e "${GREEN}Approved Paths:${NC}  $APPROVED"
  echo -e "${GREEN}MCP Tools:${NC}       $TOOLS enabled"
  echo -e "${GREEN}Slash Commands:${NC}  $COMMANDS"
  echo -e "${GREEN}Prompt Length:${NC}   $PROMPT_LEN chars"
  echo ""

  # Show mounted folders if any
  if [ "$FOLDERS" -gt 0 ]; then
    echo -e "${CYAN}Mounted Folders:${NC}"
    jq -r '(.userSelectedFolders // [])[]' "$CONFIG" | while IFS= read -r f; do
      echo "  - $f"
    done
    echo ""
  fi

  # Show approved paths if any
  if [ "$APPROVED" -gt 0 ]; then
    echo -e "${CYAN}Pre-approved Paths:${NC}"
    jq -r '(.userApprovedFileAccessPaths // [])[]' "$CONFIG" | head -5 | while IFS= read -r f; do
      echo "  - $f"
    done
    [ "$APPROVED" -gt 5 ] && echo "  ... and $((APPROVED - 5)) more"
    echo ""
  fi
}

cmd_model() {
  local CONFIG="$1"
  local MODEL="$2"
  local DRY_RUN="${3:-false}"

  local FULL_MODEL
  FULL_MODEL=$(resolve_model "$MODEL")
  if [ -z "$FULL_MODEL" ]; then
    echo -e "${RED}Unknown model:${NC} $MODEL"
    echo "Valid options: opus, sonnet, haiku"
    return 1
  fi

  local CURRENT
  CURRENT=$(jq -r '.model' "$CONFIG")

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN:${NC} Would change model from $CURRENT to $FULL_MODEL"
    return
  fi

  jq --arg model "$FULL_MODEL" '.model = $model' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"

  echo -e "${GREEN}✓${NC} Model changed: $CURRENT → $FULL_MODEL"
  echo -e "${YELLOW}Note:${NC} Takes effect on next message"
}

cmd_prompt() {
  local CONFIG="$1"
  local PRESET="$2"
  local DRY_RUN="${3:-false}"

  # Find prompt file
  local PROMPT_FILE=""
  if [ -f "$HOME/.claude/prompts/${PRESET}-prompt.json" ]; then
    PROMPT_FILE="$HOME/.claude/prompts/${PRESET}-prompt.json"
  elif [ -f "$HOME/.claude/prompts/${PRESET}.json" ]; then
    PROMPT_FILE="$HOME/.claude/prompts/${PRESET}.json"
  elif [ -f "$PRESET" ]; then
    PROMPT_FILE="$PRESET"
  else
    echo -e "${RED}Prompt not found:${NC} $PRESET"
    echo "Available presets in ~/.claude/prompts/:"
    find "$HOME/.claude/prompts/" -name "*.json" -exec basename {} .json \; 2>/dev/null | sed 's/-prompt$//'
    return 1
  fi

  local NEW_PROMPT
  NEW_PROMPT=$(jq -r '.systemPrompt' "$PROMPT_FILE")
  if [ -z "$NEW_PROMPT" ] || [ "$NEW_PROMPT" = "null" ]; then
    echo -e "${RED}Invalid prompt file${NC} (missing systemPrompt key)"
    return 1
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN:${NC} Would inject prompt from $PROMPT_FILE"
    echo "Preview (first 500 chars):"
    echo "$NEW_PROMPT" | head -c 500
    echo "..."
    return
  fi

  jq --arg prompt "$NEW_PROMPT" '.systemPrompt = $prompt' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"

  echo -e "${GREEN}✓${NC} Prompt injected from: $(basename "$PROMPT_FILE")"
}

cmd_approve_path() {
  local CONFIG="$1"
  local PATH_TO_ADD="$2"
  local DRY_RUN="${3:-false}"

  # Expand path
  PATH_TO_ADD=$(eval echo "$PATH_TO_ADD")

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN:${NC} Would add to approved paths: $PATH_TO_ADD"
    return
  fi

  # Check if already exists
  if jq -e --arg p "$PATH_TO_ADD" '(.userApprovedFileAccessPaths // []) | index($p)' "$CONFIG" > /dev/null 2>&1; then
    echo -e "${YELLOW}Already approved:${NC} $PATH_TO_ADD"
    return
  fi

  jq --arg p "$PATH_TO_ADD" '.userApprovedFileAccessPaths = ((.userApprovedFileAccessPaths // []) + [$p])' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"

  echo -e "${GREEN}✓${NC} Pre-approved path: $PATH_TO_ADD"
}

cmd_mount() {
  local CONFIG="$1"
  local FOLDER="$2"
  local DRY_RUN="${3:-false}"

  # Expand path
  FOLDER=$(eval echo "$FOLDER")

  if [ ! -d "$FOLDER" ]; then
    echo -e "${RED}Directory not found:${NC} $FOLDER"
    return 1
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN:${NC} Would mount folder: $FOLDER"
    return
  fi

  # Check if already mounted
  if jq -e --arg f "$FOLDER" '(.userSelectedFolders // []) | index($f)' "$CONFIG" > /dev/null 2>&1; then
    echo -e "${YELLOW}Already mounted:${NC} $FOLDER"
    return
  fi

  jq --arg f "$FOLDER" '.userSelectedFolders = ((.userSelectedFolders // []) + [$f])' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"

  echo -e "${GREEN}✓${NC} Pre-mounted folder: $FOLDER"
  echo -e "${YELLOW}Note:${NC} May need session restart for full effect"
}

cmd_list_tools() {
  local CONFIG="$1"

  echo -e "${CYAN}Enabled MCP Tools:${NC}"
  echo ""

  jq -r '(.enabledMcpTools // {}) | to_entries[] | "\(.value)\t\(.key)"' "$CONFIG" | while IFS=$'\t' read -r enabled hash; do
    if [ "$enabled" = "true" ]; then
      echo -e "  ${GREEN}✓${NC} $hash"
    else
      echo -e "  ${RED}✗${NC} $hash"
    fi
  done

  echo ""
  local TOTAL ENABLED
  TOTAL=$(jq '(.enabledMcpTools // {}) | length' "$CONFIG")
  ENABLED=$(jq '(.enabledMcpTools // {}) | to_entries | map(select(.value == true)) | length' "$CONFIG")
  echo "Total: $ENABLED enabled / $TOTAL configured"
}

cmd_toggle_tool() {
  local CONFIG="$1"
  local HASH="$2"
  local ENABLE="$3"  # true or false
  local DRY_RUN="${4:-false}"

  if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN:${NC} Would set $HASH to $ENABLE"
    return
  fi

  jq --arg h "$HASH" --argjson e "$ENABLE" '.enabledMcpTools = ((.enabledMcpTools // {}) + {($h): $e})' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"

  if [ "$ENABLE" = "true" ]; then
    echo -e "${GREEN}✓${NC} Enabled tool: $HASH"
  else
    echo -e "${RED}✗${NC} Disabled tool: $HASH"
  fi
}

cmd_backup() {
  local CONFIG="$1"
  local BACKUP
  BACKUP="${CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

  cp "$CONFIG" "$BACKUP"
  echo -e "${GREEN}✓${NC} Backed up to: $BACKUP"
}

cmd_restore() {
  local CONFIG="$1"

  # Find latest backup
  local BACKUP
  BACKUP=$(find "$(dirname "$CONFIG")" -maxdepth 1 -name "$(basename "$CONFIG").backup.*" -type f 2>/dev/null | sort -r | head -1)

  if [ -z "$BACKUP" ]; then
    echo -e "${RED}No backup found${NC}"
    return 1
  fi

  cp "$BACKUP" "$CONFIG"
  echo -e "${GREEN}✓${NC} Restored from: $BACKUP"
}

cmd_edit() {
  local CONFIG="$1"
  ${EDITOR:-vim} "$CONFIG"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────

SESSION_PATH=""
DRY_RUN=false
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)
      SESSION_PATH="$2"
      shift 2
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
      if [ -z "$COMMAND" ]; then
        COMMAND="$1"
      else
        ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

# Find session config
if [ -z "$SESSION_PATH" ]; then
  CONFIG_FILE=$(find_latest_session)
else
  if [ -f "$SESSION_PATH/cowork_settings.json" ]; then
    CONFIG_FILE="$SESSION_PATH/cowork_settings.json"
  elif [ -f "$SESSION_PATH" ]; then
    CONFIG_FILE="$SESSION_PATH"
  else
    echo -e "${RED}Config not found at:${NC} $SESSION_PATH"
    exit 1
  fi
fi

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}No Cowork session found${NC}"
  exit 1
fi

# Execute command
case "$COMMAND" in
  show|"")
    cmd_show "$CONFIG_FILE"
    ;;
  model)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session model <opus|sonnet|haiku>"; exit 1; }
    cmd_model "$CONFIG_FILE" "${ARGS[0]}" "$DRY_RUN"
    ;;
  prompt)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session prompt <preset|file>"; exit 1; }
    cmd_prompt "$CONFIG_FILE" "${ARGS[0]}" "$DRY_RUN"
    ;;
  approve-path|approve)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session approve-path <path>"; exit 1; }
    cmd_approve_path "$CONFIG_FILE" "${ARGS[0]}" "$DRY_RUN"
    ;;
  mount)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session mount <path>"; exit 1; }
    cmd_mount "$CONFIG_FILE" "${ARGS[0]}" "$DRY_RUN"
    ;;
  list-tools|tools)
    cmd_list_tools "$CONFIG_FILE"
    ;;
  enable-tool|enable)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session enable-tool <hash>"; exit 1; }
    cmd_toggle_tool "$CONFIG_FILE" "${ARGS[0]}" "true" "$DRY_RUN"
    ;;
  disable-tool|disable)
    [ ${#ARGS[@]} -lt 1 ] && { echo "Usage: inject-session disable-tool <hash>"; exit 1; }
    cmd_toggle_tool "$CONFIG_FILE" "${ARGS[0]}" "false" "$DRY_RUN"
    ;;
  backup)
    cmd_backup "$CONFIG_FILE"
    ;;
  restore)
    cmd_restore "$CONFIG_FILE"
    ;;
  edit)
    cmd_edit "$CONFIG_FILE"
    ;;
  *)
    echo -e "${RED}Unknown command:${NC} $COMMAND"
    usage
    exit 1
    ;;
esac
