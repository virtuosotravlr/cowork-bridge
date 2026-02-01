# Cowork Bridge Skill

> Enables sandboxed Cowork sessions to delegate commands to an unrestricted host-side Claude CLI.

## Overview

This skill allows you (Claude in a Cowork VM) to request command execution from a host-side Claude CLI watcher. Use this when you need to:

- Make HTTP requests to blocked endpoints
- Run Docker containers
- Execute git push/pull to remotes
- Run npm/npx commands
- Delegate complex prompts to an unrestricted Claude with full network access

## Bridge Location

```
/sessions/*/mnt/outputs/.bridge/
├── requests/      # You write here
├── responses/     # You read from here
├── logs/          # Audit trail
└── status.json    # Bridge health
```

## Quick Reference

| Action | Command |
|--------|---------|
| HTTP request | `bridge_request("http", {url: "...", method: "GET"})` |
| Shell exec | `bridge_request("exec", {command: "curl -s ..."})` |
| Git operation | `bridge_request("git", {command: "push", args: ["origin", "main"]})` |
| Node/npm | `bridge_request("node", {command: "npx", args: ["prettier", "."]})` |
| Docker | `bridge_request("docker", {command: "run", args: ["--rm", "alpine", "echo", "hi"]})` |
| Claude prompt | `bridge_request("prompt", {prompt: "...", options: {agent: "..."}})` |
| Inject env var | `bridge_request("env", {key: "MY_VAR", value: "hello"})` |
| Read host file | `bridge_request("file", {action: "read", path: "~/file.txt"})` |

---

## How To Use

### Step 1: Initialize Bridge (if not already done)

```bash
# Check if bridge is ready
cat /sessions/modest-fervent-archimedes/mnt/outputs/.bridge/status.json
```

If bridge doesn't exist, inform the user they need to run `bridge-init.sh` on their Mac.

### Step 2: Write a Request

Create a JSON file in the requests folder:

```bash
JOB_ID="job-$(date +%Y%m%d-%H%M%S)-$$"
cat > "/sessions/modest-fervent-archimedes/mnt/outputs/.bridge/requests/${JOB_ID}.json" << 'EOF'
{
  "id": "JOB_ID_HERE",
  "timestamp": "TIMESTAMP_HERE",
  "type": "http",
  "method": "GET",
  "url": "https://api.example.com/data",
  "timeout": 30
}
EOF
```

### Step 3: Poll for Response

```bash
# Wait for response (poll every second)
RESPONSE_FILE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge/responses/${JOB_ID}.json"
for i in {1..60}; do
  if [ -f "$RESPONSE_FILE" ]; then
    cat "$RESPONSE_FILE"
    break
  fi
  sleep 1
done
```

---

## Request Types

### HTTP Request

```json
{
  "id": "job-001",
  "type": "http",
  "method": "GET",
  "url": "https://api.example.com/data",
  "headers": {
    "Authorization": "Bearer $HOST_API_KEY"
  },
  "body": null,
  "timeout": 30
}
```

### Shell Exec

```json
{
  "id": "job-002",
  "type": "exec",
  "command": "curl -s https://api.example.com/data | jq .",
  "cwd": "~/projects",
  "env": {"MY_VAR": "value"},
  "timeout": 60
}
```

### Git Operations

```json
{
  "id": "job-003",
  "type": "git",
  "command": "push",
  "args": ["origin", "main"],
  "cwd": "~/projects/my-repo",
  "timeout": 120
}
```

Supported: `clone`, `pull`, `push`, `fetch`, `checkout`, `branch`, `merge`, `rebase`, `status`, `log`, `diff`, `add`, `commit`, `stash`, `tag`

### Node/NPM

```json
{
  "id": "job-004",
  "type": "node",
  "command": "npx",
  "args": ["prettier", "--write", "."],
  "cwd": "~/projects/my-app",
  "timeout": 300
}
```

Supported: `node`, `npm`, `npx`, `yarn`, `pnpm`

### Docker

```json
{
  "id": "job-005",
  "type": "docker",
  "command": "run",
  "args": ["--rm", "-v", "$(pwd):/app", "node:18", "npm", "test"],
  "cwd": "~/projects/my-app",
  "timeout": 600
}
```

### Prompt (Claude-to-Claude)

**This is the most powerful type.** Sends a full prompt to the host-side Claude CLI.

```json
{
  "id": "job-006",
  "type": "prompt",
  "prompt": "Analyze the GitHub repo at ~/projects/myapp, find security issues, and create a report.",
  "options": {
    "agent": "security-auditor",
    "model": "opus",
    "tools": ["Bash", "Read", "Write", "Grep"],
    "system_prompt": "You are helping a sandboxed Cowork session. Be thorough but concise."
  },
  "timeout": 300
}
```

The host Claude has:
- Full network access
- Docker
- Your custom agents
- All MCP servers
- Full filesystem

### Environment Variable Injection

```json
{
  "id": "job-007",
  "type": "env",
  "key": "API_RESPONSE",
  "value": "data from external api"
}
```

This writes to `settings.json` so the var is available in subsequent shell commands.

### File Operations

```json
{
  "id": "job-008",
  "type": "file",
  "action": "read",
  "path": "~/Documents/secret-config.json"
}
```

Actions: `read`, `write`, `append`, `exists`, `list`

---

## Response Format

All responses follow this structure:

```json
{
  "id": "job-001",
  "timestamp": "2026-01-31T23:00:00Z",
  "status": "completed",
  "exit_code": 0,
  "stdout": "response data here",
  "stderr": "",
  "duration_ms": 1234,
  "error": null
}
```

For `prompt` type, the response includes:

```json
{
  "id": "job-006",
  "status": "completed",
  "response": "The full Claude response text...",
  "usage": {
    "input_tokens": 523,
    "output_tokens": 2341
  },
  "duration_ms": 8432
}
```

---

## Streaming Responses

For long-running commands or large outputs, use streaming mode. The host writes output to a file that you can `tail -f`.

### Request Streaming

Add `"stream": true` to your request:

```json
{
  "id": "job-stream-001",
  "type": "exec",
  "command": "docker logs -f my-container",
  "timeout": 300,
  "stream": true
}
```

### Streaming Response

Instead of inline `stdout`, you get a `stream_file` path:

```json
{
  "id": "job-stream-001",
  "status": "streaming",
  "stream_file": "streams/job-stream-001.log",
  "exit_code": null
}
```

### Reading Stream Output

```bash
BRIDGE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge"
STREAM_FILE="$BRIDGE/streams/job-stream-001.log"

# Option 1: Tail the file
tail -f "$STREAM_FILE"

# Option 2: Read until sentinel
while IFS= read -r line; do
  [ "$line" = "__STREAM_END__" ] && break
  echo "$line"
done < <(tail -f "$STREAM_FILE")

# Option 3: Check completion then read all
while [ ! -f "$BRIDGE/responses/job-stream-001.json" ]; do
  sleep 1
done
cat "$STREAM_FILE" | grep -v "__STREAM_END__"
```

### Stream Completion

When finished, the response updates to:

```json
{
  "id": "job-stream-001",
  "status": "completed",
  "stream_file": "streams/job-stream-001.log",
  "exit_code": 0,
  "bytes_written": 1048576,
  "duration_ms": 45000
}
```

The stream file ends with a `__STREAM_END__` sentinel line.

### Auto-Streaming

Responses larger than 50KB are automatically streamed:

```json
{
  "id": "job-big-001",
  "status": "completed",
  "stream_file": "streams/job-big-001.log",
  "auto_streamed": true,
  "bytes_written": 2097152
}
```

### Bridge Directory with Streams

```
.bridge/
├── requests/
├── responses/
├── streams/           # Stream output files
│   ├── job-001.log
│   └── job-002.log
└── logs/
```

---

## Helper Functions

Use these bash functions for cleaner code:

```bash
# Generate job ID
bridge_job_id() {
  echo "job-$(date +%Y%m%d-%H%M%S)-$$"
}

# Write request
bridge_request() {
  local TYPE="$1"
  local PAYLOAD="$2"
  local JOB_ID=$(bridge_job_id)
  local BRIDGE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge"

  echo "$PAYLOAD" | jq --arg id "$JOB_ID" --arg ts "$(date -Iseconds)" \
    '. + {id: $id, timestamp: $ts, type: "'"$TYPE"'"}' \
    > "$BRIDGE/requests/$JOB_ID.json"

  echo "$JOB_ID"
}

# Wait for response
bridge_await() {
  local JOB_ID="$1"
  local TIMEOUT="${2:-60}"
  local BRIDGE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge"
  local RESPONSE="$BRIDGE/responses/$JOB_ID.json"

  for i in $(seq 1 $TIMEOUT); do
    if [ -f "$RESPONSE" ]; then
      cat "$RESPONSE"
      return 0
    fi
    sleep 1
  done

  echo '{"status": "timeout", "error": "No response after '$TIMEOUT' seconds"}'
  return 1
}

# One-liner: request and wait
bridge_exec() {
  local TYPE="$1"
  local PAYLOAD="$2"
  local TIMEOUT="${3:-60}"

  local JOB_ID=$(bridge_request "$TYPE" "$PAYLOAD")
  bridge_await "$JOB_ID" "$TIMEOUT"
}

# Stream request
bridge_stream_request() {
  local TYPE="$1"
  local PAYLOAD="$2"
  local JOB_ID=$(bridge_job_id)
  local BRIDGE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge"

  echo "$PAYLOAD" | jq --arg id "$JOB_ID" --arg ts "$(date -Iseconds)" \
    '. + {id: $id, timestamp: $ts, type: "'"$TYPE"'", stream: true}' \
    > "$BRIDGE/requests/$JOB_ID.json"

  echo "$JOB_ID"
}

# Read stream output (blocks until __STREAM_END__)
bridge_read_stream() {
  local JOB_ID="$1"
  local BRIDGE="/sessions/modest-fervent-archimedes/mnt/outputs/.bridge"
  local STREAM_FILE="$BRIDGE/streams/$JOB_ID.log"

  # Wait for stream file to exist
  while [ ! -f "$STREAM_FILE" ]; do
    sleep 0.5
  done

  # Read until sentinel
  while IFS= read -r line; do
    [ "$line" = "__STREAM_END__" ] && break
    echo "$line"
  done < <(tail -f "$STREAM_FILE" 2>/dev/null)
}

# Stream exec and read
bridge_stream_exec() {
  local TYPE="$1"
  local PAYLOAD="$2"

  local JOB_ID=$(bridge_stream_request "$TYPE" "$PAYLOAD")
  bridge_read_stream "$JOB_ID"
}
```

---

## Examples

### Fetch from blocked API

```bash
JOB_ID=$(bridge_request "http" '{"url": "https://api.github.com/repos/anthropics/claude-code", "method": "GET"}')
RESPONSE=$(bridge_await "$JOB_ID" 30)
echo "$RESPONSE" | jq -r '.stdout'
```

### Push to git remote

```bash
bridge_exec "git" '{"command": "push", "args": ["origin", "main"], "cwd": "~/projects/myrepo"}' 120
```

### Delegate to host Claude

```bash
bridge_exec "prompt" '{
  "prompt": "Search Hacker News for AI news from today and summarize the top 5 stories",
  "options": {"model": "sonnet"}
}' 180
```

### Stream docker logs

```bash
# Start streaming request
JOB_ID=$(bridge_stream_request "exec" '{"command": "docker logs -f my-container"}')

# Read output in real-time
bridge_read_stream "$JOB_ID" | while read line; do
  echo "LOG: $line"
done
```

### Stream a long prompt response

```bash
bridge_stream_exec "prompt" '{
  "prompt": "Write a comprehensive 10-page analysis of microservices architecture",
  "options": {"model": "opus"}
}'
```

---

## Troubleshooting

### Bridge not responding

1. Check status: `cat /sessions/*/mnt/outputs/.bridge/status.json`
2. Verify watcher is running on host Mac
3. Check logs: `cat /sessions/*/mnt/outputs/.bridge/logs/bridge.log`

### Request timing out

- Increase timeout in request
- Check if host watcher is processing (look for `.processing` lock files)
- Verify network connectivity on host

### Permission denied

- Some commands may be blocklisted on the host side
- Check `cli-bridge` config for allowlist/denylist

---

## Security Notes

- All requests are logged in `.bridge/logs/`
- Host-side watcher can enforce allowlists
- Sensitive data in responses should be handled carefully
- The bridge is only as secure as the host Mac's security
