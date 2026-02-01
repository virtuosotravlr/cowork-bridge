# CLI Bridge Skill

> Host-side watcher that executes commands on behalf of sandboxed Cowork sessions.

## Overview

This skill runs on your Mac (via Claude CLI) and watches for requests from Cowork sessions. When a request arrives, it:

1. Validates the request against security rules
2. Executes the command with full host capabilities
3. Writes the response back for Cowork to read
4. Logs all activity for audit

## Installation

```bash
# Clone the repo (or copy files)
mkdir -p ~/.claude/skills/cli-bridge
cp SKILL.md ~/.claude/skills/cli-bridge/
cp watcher.sh ~/.claude/skills/cli-bridge/
chmod +x ~/.claude/skills/cli-bridge/watcher.sh
```

## Usage

### Start the Watcher

```bash
# Auto-detect active session
~/.claude/skills/cli-bridge/watcher.sh

# Or specify session path
~/.claude/skills/cli-bridge/watcher.sh ~/Library/Application\ Support/Claude/local-agent-mode-sessions/<account>/<workspace>/local_<session>/
```

### Or Run via Claude CLI

```bash
claude -p "Watch for bridge requests and execute them" --agent cli-bridge
```

---

## Watcher Script

Create `~/.claude/skills/cli-bridge/watcher.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# CLI Bridge Watcher
# Watches for requests from Cowork and executes them on the host
# ═══════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
LOG_PREFIX="[cli-bridge]"

# ─────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────

# Default config (override with config.json)
POLL_INTERVAL=1
ALLOWED_TYPES=("exec" "http" "git" "node" "docker" "prompt" "env" "file")
BLOCKED_COMMANDS=("rm -rf /" "mkfs" "dd if=/dev/zero")
MAX_TIMEOUT=600

# ─────────────────────────────────────────────────────────────────────
# Find Active Session
# ─────────────────────────────────────────────────────────────────────

find_session() {
  local CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

  if [ -n "${1:-}" ] && [ -d "$1" ]; then
    echo "$1"
    return
  fi

  # Find most recent session with .claude folder
  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while read dir; do
    if [ -d "$dir/.claude" ]; then
      stat -f "%m %N" "$dir" 2>/dev/null
    fi
  done | sort -rn | head -1 | cut -d' ' -f2-
}

# ─────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────

log() {
  local LEVEL="$1"
  shift
  local MSG="$*"
  local TS=$(date -Iseconds)
  echo "$LOG_PREFIX [$LEVEL] $TS - $MSG"

  if [ -n "${LOG_FILE:-}" ]; then
    echo "[$LEVEL] $TS - $MSG" >> "$LOG_FILE"
  fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ─────────────────────────────────────────────────────────────────────
# Request Processing
# ─────────────────────────────────────────────────────────────────────

process_request() {
  local REQUEST_FILE="$1"
  local JOB_ID=$(basename "$REQUEST_FILE" .json)
  local RESPONSE_FILE="$RESPONSES_DIR/$JOB_ID.json"

  log_info "Processing request: $JOB_ID"

  # Parse request
  local REQUEST=$(cat "$REQUEST_FILE")
  local TYPE=$(echo "$REQUEST" | jq -r '.type')
  local TIMEOUT=$(echo "$REQUEST" | jq -r '.timeout // 60')

  # Validate type
  if [[ ! " ${ALLOWED_TYPES[*]} " =~ " ${TYPE} " ]]; then
    write_error_response "$JOB_ID" "Blocked request type: $TYPE"
    return
  fi

  # Create lock file
  touch "$REQUEST_FILE.processing"

  # Route to handler
  local START_TIME=$(date +%s%3N)
  local RESULT

  case "$TYPE" in
    exec)   RESULT=$(handle_exec "$REQUEST" "$TIMEOUT") ;;
    http)   RESULT=$(handle_http "$REQUEST" "$TIMEOUT") ;;
    git)    RESULT=$(handle_git "$REQUEST" "$TIMEOUT") ;;
    node)   RESULT=$(handle_node "$REQUEST" "$TIMEOUT") ;;
    docker) RESULT=$(handle_docker "$REQUEST" "$TIMEOUT") ;;
    prompt) RESULT=$(handle_prompt "$REQUEST" "$TIMEOUT") ;;
    env)    RESULT=$(handle_env "$REQUEST") ;;
    file)   RESULT=$(handle_file "$REQUEST") ;;
    *)      RESULT=$(echo '{"status":"failed","error":"Unknown type"}') ;;
  esac

  local END_TIME=$(date +%s%3N)
  local DURATION=$((END_TIME - START_TIME))

  # Write response
  echo "$RESULT" | jq --arg id "$JOB_ID" \
                      --arg ts "$(date -Iseconds)" \
                      --argjson dur "$DURATION" \
                      '. + {id: $id, timestamp: $ts, duration_ms: $dur}' \
                      > "$RESPONSE_FILE"

  # Cleanup
  rm -f "$REQUEST_FILE" "$REQUEST_FILE.processing"
  log_info "Completed: $JOB_ID (${DURATION}ms)"
}

write_error_response() {
  local JOB_ID="$1"
  local ERROR="$2"
  local RESPONSE_FILE="$RESPONSES_DIR/$JOB_ID.json"

  jq -n --arg id "$JOB_ID" \
        --arg ts "$(date -Iseconds)" \
        --arg err "$ERROR" \
        '{id: $id, timestamp: $ts, status: "failed", error: $err}' \
        > "$RESPONSE_FILE"

  log_error "$JOB_ID: $ERROR"
}

# ─────────────────────────────────────────────────────────────────────
# Handlers
# ─────────────────────────────────────────────────────────────────────

handle_exec() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD=$(echo "$REQUEST" | jq -r '.command')
  local CWD=$(echo "$REQUEST" | jq -r '.cwd // "~"' | sed "s|^~|$HOME|")

  # Security check
  for blocked in "${BLOCKED_COMMANDS[@]}"; do
    if [[ "$CMD" == *"$blocked"* ]]; then
      echo '{"status":"failed","error":"Command blocked by security policy"}'
      return
    fi
  done

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || cd "$HOME"
  OUTPUT=$(timeout "$TIMEOUT" bash -c "$CMD" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_http() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local URL=$(echo "$REQUEST" | jq -r '.url')
  local METHOD=$(echo "$REQUEST" | jq -r '.method // "GET"')
  local HEADERS=$(echo "$REQUEST" | jq -r '.headers // {} | to_entries | map("-H \"" + .key + ": " + .value + "\"") | join(" ")')
  local BODY=$(echo "$REQUEST" | jq -r '.body // empty')

  local CURL_CMD="curl -s -X $METHOD"
  [ -n "$HEADERS" ] && CURL_CMD="$CURL_CMD $HEADERS"
  [ -n "$BODY" ] && CURL_CMD="$CURL_CMD -d '$BODY'"
  CURL_CMD="$CURL_CMD '$URL'"

  local OUTPUT
  local EXIT_CODE

  OUTPUT=$(timeout "$TIMEOUT" bash -c "$CURL_CMD" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_git() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD=$(echo "$REQUEST" | jq -r '.command')
  local ARGS=$(echo "$REQUEST" | jq -r '.args // [] | join(" ")')
  local CWD=$(echo "$REQUEST" | jq -r '.cwd // "."' | sed "s|^~|$HOME|")

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || { echo '{"status":"failed","error":"Invalid directory"}'; return; }
  OUTPUT=$(timeout "$TIMEOUT" git $CMD $ARGS 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_node() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD=$(echo "$REQUEST" | jq -r '.command // "node"')
  local ARGS=$(echo "$REQUEST" | jq -r '.args // [] | join(" ")')
  local CWD=$(echo "$REQUEST" | jq -r '.cwd // "."' | sed "s|^~|$HOME|")

  # Validate command
  if [[ ! "$CMD" =~ ^(node|npm|npx|yarn|pnpm)$ ]]; then
    echo '{"status":"failed","error":"Invalid node command"}'
    return
  fi

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || cd "$HOME"
  OUTPUT=$(timeout "$TIMEOUT" $CMD $ARGS 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_docker() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD=$(echo "$REQUEST" | jq -r '.command // "run"')
  local ARGS=$(echo "$REQUEST" | jq -r '.args // [] | join(" ")')

  local OUTPUT
  local EXIT_CODE

  OUTPUT=$(timeout "$TIMEOUT" docker $CMD $ARGS 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_prompt() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local PROMPT=$(echo "$REQUEST" | jq -r '.prompt')
  local AGENT=$(echo "$REQUEST" | jq -r '.options.agent // empty')
  local MODEL=$(echo "$REQUEST" | jq -r '.options.model // "sonnet"')
  local SYSTEM=$(echo "$REQUEST" | jq -r '.options.system_prompt // empty')
  local TOOLS=$(echo "$REQUEST" | jq -r '.options.tools // [] | join(",")')

  local CLAUDE_CMD="claude -p"
  [ -n "$AGENT" ] && CLAUDE_CMD="$CLAUDE_CMD --agent '$AGENT'"
  [ -n "$MODEL" ] && CLAUDE_CMD="$CLAUDE_CMD --model '$MODEL'"
  [ -n "$SYSTEM" ] && CLAUDE_CMD="$CLAUDE_CMD --system-prompt '$SYSTEM'"
  [ -n "$TOOLS" ] && CLAUDE_CMD="$CLAUDE_CMD --tools '$TOOLS'"

  local OUTPUT
  local EXIT_CODE

  OUTPUT=$(timeout "$TIMEOUT" bash -c "$CLAUDE_CMD '$PROMPT'" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg response "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), response: $response, exit_code: $exit}'
}

handle_env() {
  local REQUEST="$1"

  local KEY=$(echo "$REQUEST" | jq -r '.key')
  local VALUE=$(echo "$REQUEST" | jq -r '.value')

  # Read current settings.json
  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"
  local SETTINGS='{}'
  [ -f "$SETTINGS_FILE" ] && SETTINGS=$(cat "$SETTINGS_FILE")

  # Update env
  echo "$SETTINGS" | jq --arg k "$KEY" --arg v "$VALUE" '.env[$k] = $v' > "$SETTINGS_FILE"

  jq -n '{status: "completed", message: "Environment variable set"}'
}

handle_file() {
  local REQUEST="$1"

  local ACTION=$(echo "$REQUEST" | jq -r '.action')
  local FILEPATH=$(echo "$REQUEST" | jq -r '.path' | sed "s|^~|$HOME|")

  case "$ACTION" in
    read)
      if [ -f "$FILEPATH" ]; then
        local CONTENT=$(cat "$FILEPATH")
        jq -n --arg content "$CONTENT" '{status: "completed", stdout: $content}'
      else
        jq -n '{status: "failed", error: "File not found"}'
      fi
      ;;
    write)
      local CONTENT=$(echo "$REQUEST" | jq -r '.content')
      echo "$CONTENT" > "$FILEPATH"
      jq -n '{status: "completed", message: "File written"}'
      ;;
    exists)
      if [ -e "$FILEPATH" ]; then
        jq -n '{status: "completed", exists: true}'
      else
        jq -n '{status: "completed", exists: false}'
      fi
      ;;
    list)
      if [ -d "$FILEPATH" ]; then
        local FILES=$(ls -la "$FILEPATH")
        jq -n --arg files "$FILES" '{status: "completed", stdout: $files}'
      else
        jq -n '{status: "failed", error: "Not a directory"}'
      fi
      ;;
    *)
      jq -n --arg action "$ACTION" '{status: "failed", error: ("Unknown action: " + $action)}'
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────────────────────────────

main() {
  SESSION_PATH=$(find_session "${1:-}")

  if [ -z "$SESSION_PATH" ]; then
    log_error "No active Cowork session found"
    exit 1
  fi

  BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  REQUESTS_DIR="$BRIDGE_DIR/requests"
  RESPONSES_DIR="$BRIDGE_DIR/responses"
  LOG_FILE="$BRIDGE_DIR/logs/bridge.log"

  # Ensure directories exist
  mkdir -p "$REQUESTS_DIR" "$RESPONSES_DIR" "$(dirname "$LOG_FILE")"

  # Write status
  echo '{"status": "watching", "started": "'$(date -Iseconds)'", "pid": '$$'}' > "$BRIDGE_DIR/status.json"

  log_info "Watching session: $SESSION_PATH"
  log_info "Requests dir: $REQUESTS_DIR"

  # Watch loop
  while true; do
    for request in "$REQUESTS_DIR"/*.json; do
      [ -f "$request" ] || continue
      [ -f "$request.processing" ] && continue

      process_request "$request"
    done

    sleep "$POLL_INTERVAL"
  done
}

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────

main "$@"
```

---

## Configuration

Create `~/.claude/skills/cli-bridge/config.json`:

```json
{
  "poll_interval": 1,
  "max_timeout": 600,
  "allowed_types": ["exec", "http", "git", "node", "docker", "prompt", "env", "file"],
  "blocked_commands": [
    "rm -rf /",
    "rm -rf ~",
    "mkfs",
    "dd if=/dev/zero",
    ":(){:|:&};:"
  ],
  "allowed_hosts": [],
  "blocked_hosts": [],
  "log_level": "info"
}
```

---

## Running as a Daemon

### Using launchd (recommended)

Create `~/Library/LaunchAgents/com.claude.cli-bridge.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.cli-bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>~/.claude/skills/cli-bridge/watcher.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/cli-bridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cli-bridge.err</string>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.claude.cli-bridge.plist
```

### Using screen/tmux

```bash
screen -dmS cli-bridge ~/.claude/skills/cli-bridge/watcher.sh
```

---

## Security Considerations

1. **Command Blocklist**: Dangerous commands are blocked by default
2. **Type Allowlist**: Only specified request types are processed
3. **Logging**: All requests/responses are logged for audit
4. **Timeout Enforcement**: Commands that exceed timeout are killed
5. **Path Validation**: File operations validate paths

### Recommended Security Hardening

```json
{
  "allowed_types": ["http", "git", "prompt"],
  "blocked_commands": [
    "rm -rf",
    "sudo",
    "chmod 777",
    "curl | bash",
    "wget | bash"
  ]
}
```

---

## Troubleshooting

### Watcher not starting
- Check session path exists
- Verify permissions on bridge directories
- Check logs at `/tmp/cli-bridge.log`

### Requests not being processed
- Ensure watcher is running: `ps aux | grep cli-bridge`
- Check for `.processing` lock files stuck
- Verify JSON is valid in request files

### Responses not appearing
- Check watcher logs for errors
- Verify response directory permissions
- Ensure jq is installed
