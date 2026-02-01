#!/bin/bash
# NOTE: We use 'set -u' but NOT 'set -e' to avoid crashing on malformed requests
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════
# CLI Bridge Watcher
# Watches for requests from Cowork and executes them on the host
# ═══════════════════════════════════════════════════════════════════

LOG_PREFIX="[cli-bridge]"

# ─────────────────────────────────────────────────────────────────────
# Configuration (can be overridden by environment variables)
# ─────────────────────────────────────────────────────────────────────

POLL_INTERVAL="${POLL_INTERVAL:-1}"
MAX_TIMEOUT="${MAX_TIMEOUT:-600}"
STREAM_THRESHOLD="${STREAM_THRESHOLD:-51200}"  # 50KB default

# ─────────────────────────────────────────────────────────────────────
# Dependency Checks
# ─────────────────────────────────────────────────────────────────────

# Find timeout command (gtimeout on macOS via coreutils)
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
else
  echo "WARNING: 'timeout' command not found. Install coreutils (brew install coreutils) or commands may hang."
  TIMEOUT_CMD=""
fi

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "ERROR: 'jq' is required but not installed."
  exit 1
fi

# Wrapper for timeout that falls back to no-timeout if unavailable
run_with_timeout() {
  local timeout_secs="$1"
  shift
  if [ -n "$TIMEOUT_CMD" ]; then
    "$TIMEOUT_CMD" "$timeout_secs" "$@"
  else
    "$@"
  fi
}

# Parse allowed types from env or use defaults
if [ -n "${ALLOWED_TYPES_ENV:-}" ]; then
  IFS=',' read -ra ALLOWED_TYPES <<< "$ALLOWED_TYPES_ENV"
else
  ALLOWED_TYPES=("exec" "http" "git" "node" "docker" "prompt" "env" "file")
fi

# Parse blocked commands from env or use defaults
if [ -n "${BLOCKED_COMMANDS_ENV:-}" ]; then
  IFS=',' read -ra BLOCKED_COMMANDS <<< "$BLOCKED_COMMANDS_ENV"
else
  BLOCKED_COMMANDS=("rm -rf /" "rm -rf ~" "mkfs" "dd if=/dev/zero" ":(){:|:&};:")
fi

# ─────────────────────────────────────────────────────────────────────
# Find Active Session
# ─────────────────────────────────────────────────────────────────────

find_session() {
  local CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

  if [ -n "${1:-}" ] && [ -d "$1" ]; then
    echo "$1"
    return
  fi

  find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 2>/dev/null | while IFS= read -r dir; do
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
  local TS
  TS=$(date -Iseconds)
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
  local JOB_ID
  JOB_ID=$(basename "$REQUEST_FILE" .json)
  local RESPONSE_FILE="$RESPONSES_DIR/$JOB_ID.json"

  log_info "Processing request: $JOB_ID"

  # Safely read and parse JSON - don't crash on malformed input
  local REQUEST
  if ! REQUEST=$(cat "$REQUEST_FILE" 2>/dev/null); then
    write_error_response "$JOB_ID" "Failed to read request file"
    rm -f "$REQUEST_FILE"
    return
  fi

  # Validate JSON before processing
  if ! echo "$REQUEST" | jq -e '.' >/dev/null 2>&1; then
    write_error_response "$JOB_ID" "Invalid JSON in request"
    rm -f "$REQUEST_FILE"
    return
  fi

  local TYPE TIMEOUT STREAM_REQUESTED
  TYPE=$(echo "$REQUEST" | jq -r '.type // "unknown"')
  TIMEOUT=$(echo "$REQUEST" | jq -r '.timeout // 60')
  STREAM_REQUESTED=$(echo "$REQUEST" | jq -r '.stream // false')

  # Clamp timeout to MAX_TIMEOUT
  if [ "$TIMEOUT" -gt "$MAX_TIMEOUT" ]; then
    log_warn "Timeout $TIMEOUT exceeds MAX_TIMEOUT $MAX_TIMEOUT, clamping"
    TIMEOUT="$MAX_TIMEOUT"
  fi

  # shellcheck disable=SC2076 # We want literal match, not regex
  if [[ ! " ${ALLOWED_TYPES[*]} " =~ " ${TYPE} " ]]; then
    write_error_response "$JOB_ID" "Blocked request type: $TYPE"
    rm -f "$REQUEST_FILE"
    return
  fi

  touch "$REQUEST_FILE.processing"

  local START_TIME
  START_TIME=$(gdate +%s%3N 2>/dev/null || date +%s000)
  local RESULT

  # Check if streaming requested for supported types
  if [ "$STREAM_REQUESTED" = "true" ]; then
    case "$TYPE" in
      exec)   RESULT=$(handle_streaming_exec "$REQUEST" "$TIMEOUT" "$JOB_ID") ;;
      prompt) RESULT=$(handle_streaming_prompt "$REQUEST" "$TIMEOUT" "$JOB_ID") ;;
      *)      RESULT='{"status":"failed","error":"Streaming not supported for type: '"$TYPE"'"}' ;;
    esac
  else
    case "$TYPE" in
      exec)   RESULT=$(handle_exec "$REQUEST" "$TIMEOUT") ;;
      http)   RESULT=$(handle_http "$REQUEST" "$TIMEOUT") ;;
      git)    RESULT=$(handle_git "$REQUEST" "$TIMEOUT") ;;
      node)   RESULT=$(handle_node "$REQUEST" "$TIMEOUT") ;;
      docker) RESULT=$(handle_docker "$REQUEST" "$TIMEOUT") ;;
      prompt) RESULT=$(handle_prompt "$REQUEST" "$TIMEOUT") ;;
      env)    RESULT=$(handle_env "$REQUEST") ;;
      file)   RESULT=$(handle_file "$REQUEST") ;;
      *)      RESULT='{"status":"failed","error":"Unknown type"}' ;;
    esac

    # Auto-stream if response is too large
    local STDOUT_SIZE
    STDOUT_SIZE=$(echo "$RESULT" | jq -r '.stdout // ""' | wc -c | tr -d ' ')
    if [ "$STDOUT_SIZE" -gt "$STREAM_THRESHOLD" ] && [[ "$TYPE" = "exec" || "$TYPE" = "prompt" ]]; then
      log_info "Auto-streaming: response size $STDOUT_SIZE > threshold $STREAM_THRESHOLD"
      local STREAM_FILE="$STREAMS_DIR/$JOB_ID.log"
      echo "$RESULT" | jq -r '.stdout // .response // ""' > "$STREAM_FILE"
      echo "__STREAM_END__" >> "$STREAM_FILE"
      RESULT=$(echo "$RESULT" | jq --arg sf "streams/$JOB_ID.log" --argjson bytes "$STDOUT_SIZE" \
        'del(.stdout, .response) + {stream_file: $sf, auto_streamed: true, bytes_written: $bytes}')
    fi
  fi

  local END_TIME
  END_TIME=$(gdate +%s%3N 2>/dev/null || date +%s000)
  local DURATION=$((END_TIME - START_TIME))

  # Only write final response if not already written by streaming handler
  if [ "$STREAM_REQUESTED" != "true" ] || ! [ -f "$RESPONSE_FILE" ]; then
    echo "$RESULT" | jq --arg id "$JOB_ID" \
                        --arg ts "$(date -Iseconds)" \
                        --argjson dur "$DURATION" \
                        '. + {id: $id, timestamp: $ts, duration_ms: $dur}' \
                        > "$RESPONSE_FILE"
  else
    # Update streaming response with final info
    echo "$RESULT" | jq --arg id "$JOB_ID" \
                        --arg ts "$(date -Iseconds)" \
                        --argjson dur "$DURATION" \
                        '. + {id: $id, timestamp: $ts, duration_ms: $dur}' \
                        > "$RESPONSE_FILE"
  fi

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
# Streaming Support
# ─────────────────────────────────────────────────────────────────────

handle_streaming_exec() {
  local REQUEST="$1"
  local TIMEOUT="$2"
  local JOB_ID="$3"

  local CMD CWD
  CMD=$(echo "$REQUEST" | jq -r '.command')
  CWD=$(echo "$REQUEST" | jq -r '.cwd // "~"' | sed "s|^~|$HOME|")
  local STREAM_FILE="$STREAMS_DIR/$JOB_ID.log"

  # Check blocked commands
  for blocked in "${BLOCKED_COMMANDS[@]}"; do
    if [[ "$CMD" == *"$blocked"* ]]; then
      echo "BLOCKED: Command blocked by security policy" > "$STREAM_FILE"
      echo "__STREAM_END__" >> "$STREAM_FILE"
      jq -n '{status: "failed", error: "Command blocked by security policy"}'
      return
    fi
  done

  # Write initial streaming response
  local RESPONSE_FILE="$RESPONSES_DIR/$JOB_ID.json"
  jq -n --arg id "$JOB_ID" \
        --arg ts "$(date -Iseconds)" \
        --arg sf "streams/$JOB_ID.log" \
        '{id: $id, timestamp: $ts, status: "streaming", stream_file: $sf, exit_code: null}' \
        > "$RESPONSE_FILE"

  log_info "Streaming: $JOB_ID -> $STREAM_FILE"

  # Execute with output to stream file
  cd "$CWD" 2>/dev/null || cd "$HOME" || true
  local EXIT_CODE
  run_with_timeout "$TIMEOUT" bash -c "$CMD" >> "$STREAM_FILE" 2>&1 && EXIT_CODE=0 || EXIT_CODE=$?

  # Write end sentinel
  echo "__STREAM_END__" >> "$STREAM_FILE"

  local BYTES_WRITTEN
  BYTES_WRITTEN=$(wc -c < "$STREAM_FILE" | tr -d ' ')

  # Return completion result
  jq -n --arg sf "streams/$JOB_ID.log" \
        --argjson exit "$EXIT_CODE" \
        --argjson bytes "$BYTES_WRITTEN" \
        '{status: (if $exit == 0 then "completed" else "failed" end), stream_file: $sf, exit_code: $exit, bytes_written: $bytes}'
}

handle_streaming_prompt() {
  local REQUEST="$1"
  local TIMEOUT="$2"
  local JOB_ID="$3"

  local PROMPT AGENT MODEL SYSTEM
  PROMPT=$(echo "$REQUEST" | jq -r '.prompt')
  AGENT=$(echo "$REQUEST" | jq -r '.options.agent // empty')
  MODEL=$(echo "$REQUEST" | jq -r '.options.model // "sonnet"')
  SYSTEM=$(echo "$REQUEST" | jq -r '.options.system_prompt // empty')
  local STREAM_FILE="$STREAMS_DIR/$JOB_ID.log"

  # Write initial streaming response
  local RESPONSE_FILE="$RESPONSES_DIR/$JOB_ID.json"
  jq -n --arg id "$JOB_ID" \
        --arg ts "$(date -Iseconds)" \
        --arg sf "streams/$JOB_ID.log" \
        '{id: $id, timestamp: $ts, status: "streaming", stream_file: $sf, response_type: "claude_prompt"}' \
        > "$RESPONSE_FILE"

  log_info "Streaming prompt: $JOB_ID -> $STREAM_FILE"

  # Build args array safely (no shell injection)
  local -a CLAUDE_ARGS=("-p")
  [ -n "$AGENT" ] && CLAUDE_ARGS+=("--agent" "$AGENT")
  [ -n "$MODEL" ] && CLAUDE_ARGS+=("--model" "$MODEL")
  [ -n "$SYSTEM" ] && CLAUDE_ARGS+=("--system-prompt" "$SYSTEM")

  # Execute with output to stream file - feed prompt via stdin
  local EXIT_CODE
  printf '%s' "$PROMPT" | run_with_timeout "$TIMEOUT" claude "${CLAUDE_ARGS[@]}" >> "$STREAM_FILE" 2>&1 && EXIT_CODE=0 || EXIT_CODE=$?

  # Write end sentinel
  echo "__STREAM_END__" >> "$STREAM_FILE"

  local BYTES_WRITTEN
  BYTES_WRITTEN=$(wc -c < "$STREAM_FILE" | tr -d ' ')

  jq -n --arg sf "streams/$JOB_ID.log" \
        --argjson exit "$EXIT_CODE" \
        --argjson bytes "$BYTES_WRITTEN" \
        '{status: (if $exit == 0 then "completed" else "failed" end), stream_file: $sf, exit_code: $exit, bytes_written: $bytes, response_type: "claude_prompt"}'
}

# ─────────────────────────────────────────────────────────────────────
# Handlers
# ─────────────────────────────────────────────────────────────────────

handle_exec() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD CWD
  CMD=$(echo "$REQUEST" | jq -r '.command')
  CWD=$(echo "$REQUEST" | jq -r '.cwd // "~"' | sed "s|^~|$HOME|")

  for blocked in "${BLOCKED_COMMANDS[@]}"; do
    if [[ "$CMD" == *"$blocked"* ]]; then
      jq -n '{status: "failed", error: "Command blocked by security policy"}'
      return
    fi
  done

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || cd "$HOME" || true
  # Note: exec type intentionally uses bash -c since user provides full command
  OUTPUT=$(run_with_timeout "$TIMEOUT" bash -c "$CMD" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_http() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local URL METHOD BODY
  URL=$(echo "$REQUEST" | jq -r '.url')
  METHOD=$(echo "$REQUEST" | jq -r '.method // "GET"')
  BODY=$(echo "$REQUEST" | jq -r '.body // empty')

  # Build curl args array safely
  local -a CURL_ARGS=("-s" "-X" "$METHOD")

  # Add headers safely
  while IFS= read -r header; do
    [ -n "$header" ] && CURL_ARGS+=("-H" "$header")
  done < <(echo "$REQUEST" | jq -r '.headers // {} | to_entries | map(.key + ": " + .value) | .[]')

  # Add body if present
  [ -n "$BODY" ] && CURL_ARGS+=("-d" "$BODY")

  # Add URL
  CURL_ARGS+=("$URL")

  local OUTPUT
  local EXIT_CODE

  OUTPUT=$(run_with_timeout "$TIMEOUT" curl "${CURL_ARGS[@]}" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_git() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD CWD
  CMD=$(echo "$REQUEST" | jq -r '.command')
  CWD=$(echo "$REQUEST" | jq -r '.cwd // "."' | sed "s|^~|$HOME|")

  # Read args into array safely
  local -a ARGS=()
  while IFS= read -r arg; do
    [ -n "$arg" ] && ARGS+=("$arg")
  done < <(echo "$REQUEST" | jq -r '.args // [] | .[]')

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || { jq -n '{status: "failed", error: "Invalid directory"}'; return; }
  OUTPUT=$(run_with_timeout "$TIMEOUT" git "$CMD" "${ARGS[@]}" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_node() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD CWD
  CMD=$(echo "$REQUEST" | jq -r '.command // "node"')
  CWD=$(echo "$REQUEST" | jq -r '.cwd // "."' | sed "s|^~|$HOME|")

  # Read args into array safely
  local -a ARGS=()
  while IFS= read -r arg; do
    [ -n "$arg" ] && ARGS+=("$arg")
  done < <(echo "$REQUEST" | jq -r '.args // [] | .[]')

  if [[ ! "$CMD" =~ ^(node|npm|npx|yarn|pnpm)$ ]]; then
    jq -n '{status: "failed", error: "Invalid node command"}'
    return
  fi

  local OUTPUT
  local EXIT_CODE

  cd "$CWD" 2>/dev/null || cd "$HOME" || true
  OUTPUT=$(run_with_timeout "$TIMEOUT" "$CMD" "${ARGS[@]}" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_docker() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local CMD
  CMD=$(echo "$REQUEST" | jq -r '.command // "run"')

  # Read args into array safely
  local -a ARGS=()
  while IFS= read -r arg; do
    [ -n "$arg" ] && ARGS+=("$arg")
  done < <(echo "$REQUEST" | jq -r '.args // [] | .[]')

  local OUTPUT
  local EXIT_CODE

  OUTPUT=$(run_with_timeout "$TIMEOUT" docker "$CMD" "${ARGS[@]}" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg stdout "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), exit_code: $exit, stdout: $stdout, stderr: ""}'
}

handle_prompt() {
  local REQUEST="$1"
  local TIMEOUT="$2"

  local PROMPT AGENT MODEL SYSTEM TOOLS
  PROMPT=$(echo "$REQUEST" | jq -r '.prompt')
  AGENT=$(echo "$REQUEST" | jq -r '.options.agent // empty')
  MODEL=$(echo "$REQUEST" | jq -r '.options.model // "sonnet"')
  SYSTEM=$(echo "$REQUEST" | jq -r '.options.system_prompt // empty')
  TOOLS=$(echo "$REQUEST" | jq -r '.options.tools // [] | join(",")')

  # Build args array safely (no shell injection)
  local -a CLAUDE_ARGS=("-p")
  [ -n "$AGENT" ] && CLAUDE_ARGS+=("--agent" "$AGENT")
  [ -n "$MODEL" ] && CLAUDE_ARGS+=("--model" "$MODEL")
  [ -n "$SYSTEM" ] && CLAUDE_ARGS+=("--system-prompt" "$SYSTEM")
  [ -n "$TOOLS" ] && CLAUDE_ARGS+=("--tools" "$TOOLS")

  local OUTPUT
  local EXIT_CODE

  # Feed prompt via stdin to avoid shell injection
  OUTPUT=$(printf '%s' "$PROMPT" | run_with_timeout "$TIMEOUT" claude "${CLAUDE_ARGS[@]}" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

  jq -n --arg response "$OUTPUT" \
        --argjson exit "$EXIT_CODE" \
        '{status: (if $exit == 0 then "completed" else "failed" end), response: $response, exit_code: $exit}'
}

handle_env() {
  local REQUEST="$1"

  local KEY VALUE
  KEY=$(echo "$REQUEST" | jq -r '.key')
  VALUE=$(echo "$REQUEST" | jq -r '.value')

  local SETTINGS_FILE="$SESSION_PATH/.claude/settings.json"
  local SETTINGS='{}'
  [ -f "$SETTINGS_FILE" ] && SETTINGS=$(cat "$SETTINGS_FILE")

  echo "$SETTINGS" | jq --arg k "$KEY" --arg v "$VALUE" '.env[$k] = $v' > "$SETTINGS_FILE"

  jq -n '{status: "completed", message: "Environment variable set"}'
}

handle_file() {
  local REQUEST="$1"

  local ACTION FILEPATH
  ACTION=$(echo "$REQUEST" | jq -r '.action')
  FILEPATH=$(echo "$REQUEST" | jq -r '.path' | sed "s|^~|$HOME|")

  case "$ACTION" in
    read)
      if [ -f "$FILEPATH" ]; then
        local CONTENT
        CONTENT=$(cat "$FILEPATH")
        jq -n --arg content "$CONTENT" '{status: "completed", stdout: $content}'
      else
        jq -n '{status: "failed", error: "File not found"}'
      fi
      ;;
    write)
      local CONTENT
      CONTENT=$(echo "$REQUEST" | jq -r '.content')
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
        local FILES
        FILES=$(ls -la "$FILEPATH")
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
  local ARG="${1:-}"

  # Check if argument is a direct bridge path (Docker mode)
  # or a session path (local mode)
  if [ -n "$ARG" ] && [ -d "$ARG/requests" ]; then
    # Direct bridge path (e.g., /bridge in Docker)
    BRIDGE_DIR="$ARG"
    SESSION_PATH=""
    log_info "Running in direct bridge mode"
  elif [ -n "$ARG" ] && [ -d "$ARG" ]; then
    # Session path provided
    SESSION_PATH="$ARG"
    BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  else
    # Auto-detect session
    SESSION_PATH=$(find_session "$ARG")
    if [ -z "$SESSION_PATH" ]; then
      log_error "No active Cowork session found"
      exit 1
    fi
    BRIDGE_DIR="$SESSION_PATH/outputs/.bridge"
  fi

  REQUESTS_DIR="$BRIDGE_DIR/requests"
  RESPONSES_DIR="$BRIDGE_DIR/responses"
  STREAMS_DIR="$BRIDGE_DIR/streams"
  LOG_FILE="$BRIDGE_DIR/logs/bridge.log"

  mkdir -p "$REQUESTS_DIR" "$RESPONSES_DIR" "$STREAMS_DIR" "$(dirname "$LOG_FILE")"

  echo '{"status": "watching", "started": "'"$(date -Iseconds)"'", "pid": '$$', "mode": "'"$([ -z "$SESSION_PATH" ] && echo "docker" || echo "local")"'"}' > "$BRIDGE_DIR/status.json"

  log_info "═══════════════════════════════════════════════════════════════"
  log_info "  CLI Bridge Watcher"
  log_info "═══════════════════════════════════════════════════════════════"
  [ -n "$SESSION_PATH" ] && log_info "Session: $SESSION_PATH"
  log_info "Bridge: $BRIDGE_DIR"
  log_info "Requests: $REQUESTS_DIR"
  log_info "Responses: $RESPONSES_DIR"
  log_info "Waiting for requests..."

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
