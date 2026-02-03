#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Cowork CLI Bridge Installer
# Installs the bridge skills, scripts, and optional auto-setup daemon
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

CLAUDE_DIR="$HOME/.claude"
CLAUDE_APP_DIR="$HOME/Library/Application Support/Claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
GLOBAL_SKILLS_DIR="$CLAUDE_APP_DIR/skills"
GLOBAL_MANIFEST="$CLAUDE_APP_DIR/manifest.json"
BIN_DIR="$HOME/.local/bin"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"

AUTO_SETUP="false"
SETUP_EXISTING="false"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto|-a)
      AUTO_SETUP="true"
      shift
      ;;
    --setup-existing|-e)
      SETUP_EXISTING="true"
      shift
      ;;
    --full|-f)
      AUTO_SETUP="true"
      SETUP_EXISTING="true"
      shift
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --auto, -a           Install and start auto-setup daemon"
      echo "  --setup-existing, -e Set up bridge for all existing sessions"
      echo "  --full, -f           Full install (auto-setup + existing sessions)"
      echo "  --help, -h           Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "═══════════════════════════════════════════════════════════════════"
echo "  Cowork CLI Bridge Installer"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check dependencies
echo "Checking dependencies..."
MISSING_DEPS=""

if ! command -v jq &>/dev/null; then
  MISSING_DEPS="$MISSING_DEPS jq"
fi

if ! command -v curl &>/dev/null; then
  MISSING_DEPS="$MISSING_DEPS curl"
fi

# timeout is optional but recommended
if ! command -v timeout &>/dev/null && ! command -v gtimeout &>/dev/null; then
  echo "  Warning: 'timeout' not found - install coreutils for timeout support"
  echo "    brew install coreutils"
fi

if [ -n "$MISSING_DEPS" ]; then
  echo ""
  echo "ERROR: Missing required dependencies:$MISSING_DEPS"
  echo ""
  echo "Install with:"
  echo "  brew install$MISSING_DEPS"
  exit 1
fi
echo "  ✓ All required dependencies found"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$SKILLS_DIR/cli-bridge"
mkdir -p "$SKILLS_DIR/cowork-bridge"
mkdir -p "$GLOBAL_SKILLS_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$LAUNCHD_DIR"
echo "  ✓ $SKILLS_DIR/cli-bridge"
echo "  ✓ $SKILLS_DIR/cowork-bridge"
echo "  ✓ $GLOBAL_SKILLS_DIR"
echo "  ✓ $BIN_DIR"
echo ""

# Copy skills
echo "Installing skills..."
cp "$REPO_DIR/skills/cli-bridge/SKILL.md" "$SKILLS_DIR/cli-bridge/"
cp "$REPO_DIR/skills/cli-bridge/watcher.sh" "$SKILLS_DIR/cli-bridge/"
cp "$REPO_DIR/skills/cowork-bridge/SKILL.md" "$SKILLS_DIR/cowork-bridge/"
chmod +x "$SKILLS_DIR/cli-bridge/watcher.sh"
echo "  ✓ cli-bridge skill + watcher"
echo "  ✓ cowork-bridge skill"
cp -r "$REPO_DIR/skills/cowork-bridge" "$GLOBAL_SKILLS_DIR/" 2>/dev/null || true
echo "  ✓ cowork-bridge skill -> Claude skills"
echo ""

# Copy scripts to bin
echo "Installing CLI tools..."
cp "$REPO_DIR/scripts/session-finder.sh" "$BIN_DIR/cowork-session"
cp "$REPO_DIR/scripts/bridge-init.sh" "$BIN_DIR/cowork-bridge-init"
cp "$REPO_DIR/scripts/bridge-uninstall.sh" "$BIN_DIR/cowork-bridge-uninstall"
cp "$REPO_DIR/scripts/setup-all-sessions.sh" "$BIN_DIR/cowork-bridge-setup-all"
cp "$REPO_DIR/scripts/auto-setup-daemon.sh" "$BIN_DIR/cowork-bridge-daemon"
cp "$REPO_DIR/scripts/inject-prompt.sh" "$BIN_DIR/cowork-inject-prompt"
cp "$REPO_DIR/scripts/inject-session.sh" "$BIN_DIR/cowork-session-config"
chmod +x "$BIN_DIR/cowork-session"
chmod +x "$BIN_DIR/cowork-bridge-init"
chmod +x "$BIN_DIR/cowork-bridge-uninstall"
chmod +x "$BIN_DIR/cowork-bridge-setup-all"
chmod +x "$BIN_DIR/cowork-bridge-daemon"
chmod +x "$BIN_DIR/cowork-inject-prompt"
chmod +x "$BIN_DIR/cowork-session-config"
echo "  ✓ cowork-session"
echo "  ✓ cowork-bridge-init"
echo "  ✓ cowork-bridge-uninstall"
echo "  ✓ cowork-bridge-setup-all"
echo "  ✓ cowork-bridge-daemon"
echo "  ✓ cowork-inject-prompt"
echo "  ✓ cowork-session-config"
echo ""

# Copy prompt presets
echo "Installing prompt presets..."
mkdir -p "$CLAUDE_DIR/prompts"
cp "$REPO_DIR/prompts/"*.json "$CLAUDE_DIR/prompts/"
echo "  ✓ power-user-prompt.json"
echo "  ✓ cli-mode-prompt.json"
echo "  ✓ minimal-prompt.json"
echo "  ✓ unrestricted-prompt.json"
echo ""

update_manifest() {
  local MANIFEST_FILE="$1"
  local NOW
  local NOW_MS
  NOW=$(date -Iseconds)
  NOW_MS=$(date +%s000)

  local ENTRY='{
    "skillId": "cowork-bridge",
    "name": "cowork-bridge",
    "description": "**CLI Bridge**: Enables sandboxed Cowork sessions to delegate commands to an unrestricted host-side Claude CLI.\n  - MANDATORY TRIGGERS: bridge, delegate, host, unrestricted, sandbox escape\n",
    "creatorType": "user",
    "enabled": true
  }'

  if [ ! -f "$MANIFEST_FILE" ]; then
    jq -n --argjson skill "$ENTRY" --argjson now "$NOW_MS" --arg updated "$NOW" '
      {lastUpdated: $now, skills: [$skill | .updatedAt = $updated]}
    ' > "$MANIFEST_FILE"
    return
  fi

  if jq -e '.skills // [] | .[] | select(.skillId == "cowork-bridge")' "$MANIFEST_FILE" >/dev/null 2>&1; then
    jq --argjson now "$NOW_MS" --arg updated "$NOW" '
      .lastUpdated = $now |
      .skills = ((.skills // []) | map(if .skillId == "cowork-bridge" then .updatedAt = $updated else . end))
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  else
    jq --argjson now "$NOW_MS" --arg updated "$NOW" --argjson skill "$ENTRY" '
      .lastUpdated = $now |
      .skills = ((.skills // []) + [$skill | .updatedAt = $updated])
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  fi
}

echo "Updating Claude skills manifest..."
update_manifest "$GLOBAL_MANIFEST"
echo "  ✓ Updated Claude manifest.json"
echo ""

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Note: $BIN_DIR is not in your PATH"
  echo "Add this to your ~/.zshrc or ~/.bashrc:"
  echo ""
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

# Setup existing sessions if requested
if [ "$SETUP_EXISTING" = "true" ]; then
  echo "Setting up existing sessions..."
  "$BIN_DIR/cowork-bridge-setup-all"
  echo ""
fi

# Install auto-setup daemon if requested
if [ "$AUTO_SETUP" = "true" ]; then
  echo "Installing auto-setup daemon..."

  # Create launchd plist
  cat > "$LAUNCHD_DIR/com.claude.bridge-auto-setup.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.bridge-auto-setup</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/cowork-bridge-daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/cowork-bridge-auto-setup.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cowork-bridge-auto-setup.err</string>
</dict>
</plist>
EOF

  # Load the daemon
  launchctl unload "$LAUNCHD_DIR/com.claude.bridge-auto-setup.plist" 2>/dev/null || true
  launchctl load "$LAUNCHD_DIR/com.claude.bridge-auto-setup.plist"
  echo "  ✓ Auto-setup daemon installed and started"
  echo "  ✓ Log: /tmp/cowork-bridge-auto-setup.log"
  echo ""
fi

echo "═══════════════════════════════════════════════════════════════════"
echo "  Installation Complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Available commands:"
echo ""
echo "    cowork-session           Find/list Cowork sessions"
echo "    cowork-session-config    Modify session config (model, tools, paths)"
echo "    cowork-inject-prompt     Inject custom system prompts"
echo "    cowork-bridge-init       Initialize bridge for a session"
echo "    cowork-bridge-setup-all  Setup all existing sessions"
echo "    cowork-bridge-daemon     Run auto-setup daemon"
echo "    cowork-bridge-uninstall  Remove bridge from session(s)"
echo ""
echo "  Session config commands:"
echo ""
echo "    cowork-session-config show           View current config"
echo "    cowork-session-config model sonnet   Switch model"
echo "    cowork-session-config approve ~/dir  Pre-approve path"
echo "    cowork-session-config list-tools     Show MCP tools"
echo ""
echo "  Prompt presets:"
echo ""
echo "    power-user    Developer mode, bridge-aware"
echo "    cli-mode      Claude Code CLI behavior"
echo "    minimal       Bare minimum, max freedom"
echo "    unrestricted  Full sandbox escape"
echo ""
echo "  Quick start:"
echo ""
if [ "$AUTO_SETUP" = "true" ]; then
  echo "    Auto-setup is running! New sessions will be configured automatically."
  echo ""
  echo "    To start the watcher for request processing:"
  echo "      ~/.claude/skills/cli-bridge/watcher.sh"
  echo ""
else
  echo "    1. Set up all existing sessions:"
  echo "       cowork-bridge-setup-all"
  echo ""
  echo "    2. (Optional) Enable auto-setup for new sessions:"
  echo "       cowork-bridge-daemon &"
  echo ""
  echo "    3. Start the watcher to process requests:"
  echo "       ~/.claude/skills/cli-bridge/watcher.sh"
  echo ""
fi
echo "  For full auto mode, reinstall with:"
echo "    ./install.sh --full"
echo ""
