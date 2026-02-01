# Cowork ↔ CLI Bridge Protocol Spec

## Overview

A bidirectional interop system that allows a sandboxed Cowork VM to request command execution from an unrestricted Claude CLI running on the host Mac, with structured request/response handling and logging.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM (sandboxed)                                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  cowork-bridge skill                                     │    │
│  │  - bridge:request(cmd, args, timeout)                   │    │
│  │  - bridge:poll(job_id)                                  │    │
│  │  - bridge:log(message)                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│            /mnt/outputs/.bridge/                                │
│            ├── requests/     (write)                            │
│            ├── responses/    (read)                             │
│            └── logs/         (write)                            │
└─────────────────────────────────────────────────────────────────┘
                            │
          ══════════════════╪══════════════════  (mounted folder)
                            │
┌─────────────────────────────────────────────────────────────────┐
│  HOST MAC (unrestricted)                                        │
│            ~/.../<session>/outputs/.bridge/                     │
│            ├── requests/     (watch)                            │
│            ├── responses/    (write)                            │
│            └── logs/         (read)                             │
│                           │                                      │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  cli-bridge skill                                        │    │
│  │  - watches requests/ via fswatch/inotify                │    │
│  │  - executes commands (curl, docker, git push, etc)      │    │
│  │  - writes responses + injects env vars                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Locations

### Inside Cowork VM
```
/sessions/<session-name>/mnt/outputs/.bridge/
├── requests/
│   └── <job-id>.json
├── responses/
│   └── <job-id>.json
├── logs/
│   └── bridge.log
└── status.json          # current bridge status
```

### On Host Mac
```
~/Library/Application Support/Claude/local-agent-mode-sessions/
  <account-id>/<workspace-id>/local_<session-id>/
  └── outputs/.bridge/
      └── (same structure)
```

---

## Request Format

**File:** `requests/<job-id>.json`

```json
{
  "id": "job-20260131-001",
  "timestamp": "2026-01-31T22:45:00Z",
  "type": "exec",
  "command": "curl",
  "args": ["-s", "https://api.example.com/data"],
  "timeout": 30,
  "env": {
    "API_KEY": "$HOST_API_KEY"
  },
  "cwd": "/path/on/host",
  "callback": {
    "type": "file",
    "path": "responses/<job-id>.json"
  },
  "metadata": {
    "requester": "cowork-session",
    "purpose": "fetch external API data"
  }
}
```

### Request Types

| Type | Description |
|------|-------------|
| `exec` | Execute a shell command |
| `http` | Make an HTTP request (simpler than exec curl) |
| `docker` | Run a docker command |
| `node` | Run node/npm/npx commands |
| `git` | Run git commands (push, pull, clone, etc.) |
| `prompt` | Send a prompt to host-side Claude CLI (full agent capabilities) |
| `env` | Inject env var into settings.json |
| `file` | Read/write a file on host filesystem |

---

## Prompt Request Type (Claude-to-Claude)

The `prompt` type is the most powerful — it sends a full prompt to the unrestricted Claude CLI on the host, which has access to:
- All network endpoints
- Docker
- Your custom agents
- Full filesystem
- Any MCP servers configured on host

**Request:**
```json
{
  "id": "job-20260131-002",
  "type": "prompt",
  "prompt": "Fetch the latest issues from github.com/anthropics/claude-code and summarize them",
  "options": {
    "agent": "my-github-agent",
    "model": "sonnet",
    "max_tokens": 4096,
    "tools": ["Bash", "Read", "Write"],
    "system_prompt": "You are helping a sandboxed Cowork session. Return concise results."
  },
  "timeout": 120
}
```

**Response:**
```json
{
  "id": "job-20260131-002",
  "status": "completed",
  "response": "Here are the latest 5 issues:\n1. ...\n2. ...",
  "usage": {
    "input_tokens": 523,
    "output_tokens": 1204
  },
  "duration_ms": 8432
}
```

**CLI execution:**
```bash
claude -p "${prompt}" \
  --agent "${options.agent}" \
  --model "${options.model}" \
  --tools "${options.tools}" \
  --system-prompt "${options.system_prompt}"
```

This effectively gives Cowork a "call-out" to an unrestricted Claude that can do anything.

---

## Node Request Type

**Request:**
```json
{
  "id": "job-003",
  "type": "node",
  "command": "npx",
  "args": ["create-react-app", "my-app"],
  "cwd": "~/projects",
  "timeout": 300
}
```

Supported commands: `node`, `npm`, `npx`, `yarn`, `pnpm`

---

## Git Request Type

**Request:**
```json
{
  "id": "job-004",
  "type": "git",
  "command": "push",
  "args": ["origin", "main"],
  "cwd": "~/projects/my-repo",
  "env": {
    "GIT_SSH_COMMAND": "ssh -i ~/.ssh/github_key"
  }
}
```

Supported commands: `clone`, `pull`, `push`, `fetch`, `checkout`, `branch`, `merge`, `rebase`, `status`, `log`, `diff`, `add`, `commit`, `stash`, `tag`

---

## Response Format

**File:** `responses/<job-id>.json`

```json
{
  "id": "job-20260131-001",
  "timestamp": "2026-01-31T22:45:02Z",
  "status": "completed",
  "exit_code": 0,
  "stdout": "{ \"data\": \"response from api\" }",
  "stderr": "",
  "duration_ms": 1523,
  "error": null
}
```

### Status Values

| Status | Description |
|--------|-------------|
| `pending` | Request received, not started |
| `running` | Currently executing |
| `completed` | Finished successfully |
| `failed` | Finished with error |
| `timeout` | Exceeded timeout |
| `streaming` | Output is being streamed to a file |

---

## Streaming Protocol

For long-running commands or large outputs, the bridge supports streaming mode. Instead of waiting for the full output and returning it inline, the host writes output incrementally to a stream file that Cowork can `tail -f`.

### When Streaming is Used

1. **Explicit request:** Client sets `"stream": true` in the request
2. **Auto-trigger:** Response exceeds `STREAM_THRESHOLD` bytes (default: 50KB)
3. **Long-running:** Commands that produce continuous output (logs, watch, etc.)

### Stream Request

**Request:**
```json
{
  "id": "job-stream-001",
  "type": "exec",
  "command": "docker logs -f my-container",
  "timeout": 300,
  "stream": true
}
```

### Stream Response

When streaming, the response includes a `stream_file` path instead of inline `stdout`:

```json
{
  "id": "job-stream-001",
  "timestamp": "2026-01-31T23:00:00Z",
  "status": "streaming",
  "stream_file": "streams/job-stream-001.log",
  "pid": 12345,
  "exit_code": null,
  "error": null
}
```

### Reading the Stream (Cowork side)

```bash
# The stream file is at:
# /mnt/outputs/.bridge/streams/job-stream-001.log

# Tail the file to get streaming output
tail -f /mnt/outputs/.bridge/streams/job-stream-001.log

# Or read incrementally with offset tracking
OFFSET=0
while true; do
  NEW_CONTENT=$(tail -c +$OFFSET /mnt/outputs/.bridge/streams/job-stream-001.log)
  if [ -n "$NEW_CONTENT" ]; then
    echo "$NEW_CONTENT"
    OFFSET=$((OFFSET + ${#NEW_CONTENT}))
  fi
  sleep 0.5
done
```

### Stream Completion

When the command finishes, the host:
1. Writes final response with `status: "completed"` or `status: "failed"`
2. Sets `exit_code` to the actual exit code
3. Writes a sentinel line `__STREAM_END__` to the stream file

**Final response:**
```json
{
  "id": "job-stream-001",
  "timestamp": "2026-01-31T23:05:00Z",
  "status": "completed",
  "stream_file": "streams/job-stream-001.log",
  "exit_code": 0,
  "duration_ms": 300000,
  "bytes_written": 1048576
}
```

### Stream File Lifecycle

| Stage | Action |
|-------|--------|
| Request received | Create empty stream file |
| Command running | Append output incrementally |
| Command exits | Write `__STREAM_END__` sentinel |
| Response written | Update status to completed/failed |
| Cleanup (optional) | Delete stream files older than 1 hour |

### Auto-Streaming for Large Responses

Even without `"stream": true`, if a response would exceed the threshold:

1. Host detects output size > `STREAM_THRESHOLD`
2. Switches to streaming mode mid-execution
3. Returns response with `"auto_streamed": true`

```json
{
  "id": "job-big-001",
  "status": "completed",
  "stream_file": "streams/job-big-001.log",
  "auto_streamed": true,
  "bytes_written": 2097152,
  "exit_code": 0
}
```

### Streaming Prompt Responses

For `prompt` type requests that produce long Claude responses:

```json
{
  "id": "job-prompt-001",
  "type": "prompt",
  "prompt": "Write a comprehensive analysis of the entire codebase",
  "stream": true
}
```

The host Claude CLI streams its response to the file, allowing Cowork to read it incrementally:

```json
{
  "id": "job-prompt-001",
  "status": "streaming",
  "stream_file": "streams/job-prompt-001.log",
  "response_type": "claude_prompt"
}
```

### Stream Directory Structure

```
.bridge/
├── requests/
├── responses/
├── streams/           # NEW: Stream output files
│   ├── job-001.log
│   ├── job-002.log
│   └── .cleanup       # Timestamp file for cleanup daemon
└── logs/
```

---

## Cowork Skill: `cowork-bridge`

### Location
`~/.claude/skills/cowork-bridge/SKILL.md` (injected into Cowork session)

### Commands

#### `bridge:request`
Submit a request to the host CLI.

```bash
# Usage in Cowork
bridge:request exec "curl -s https://api.example.com/data"
bridge:request http GET https://api.example.com/data
bridge:request docker run --rm alpine echo hello
bridge:request node "npx prettier --write ."
bridge:request git push origin main
bridge:request prompt "Analyze the codebase at ~/projects/myapp and suggest improvements" --agent code-reviewer
```

#### `bridge:prompt`
Shorthand for sending a prompt to host-side Claude (most common use case).

```bash
# These are equivalent:
bridge:prompt "Fetch latest HN posts and summarize"
bridge:request prompt "Fetch latest HN posts and summarize"

# With options:
bridge:prompt "Review this PR" --agent pr-reviewer --model opus
```

#### `bridge:poll`
Check status of a pending request.

#### `bridge:await`
Block until response is ready (with timeout).

#### `bridge:log`
Write to the shared log file.

### Implementation
- Generates unique job ID
- Writes request JSON to `requests/`
- Polls `responses/` for result
- Returns parsed response

---

## CLI Skill: `cli-bridge`

### Location
`~/.claude/skills/cli-bridge/SKILL.md` (on host Mac)

### Behavior
- Runs as a watcher daemon or on-demand
- Uses `fswatch` or polling to detect new requests
- Validates requests (allowlist/denylist commands)
- Executes with appropriate sandboxing/limits
- Writes response JSON
- Optionally injects result into `settings.json` env

### Security Considerations
- Command allowlist (configurable)
- Timeout enforcement
- No arbitrary code execution without explicit approval
- Log all executions for audit

---

## Session Discovery Script

**Purpose:** Find the active Cowork session path on the host Mac.

```bash
#!/bin/bash
# cowork-session-finder.sh

CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

# Find most recent session
LATEST=$(find "$CLAUDE_SESSIONS" -type d -name "local_*" -maxdepth 3 | while read dir; do
  if [ -d "$dir/.claude" ]; then
    stat -f "%m %N" "$dir" 2>/dev/null || stat -c "%Y %n" "$dir" 2>/dev/null
  fi
done | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$LATEST" ]; then
  echo "No active Cowork session found"
  exit 1
fi

echo "Active session: $LATEST"
echo ""
echo "Bridge paths:"
echo "  Requests:  $LATEST/outputs/.bridge/requests/"
echo "  Responses: $LATEST/outputs/.bridge/responses/"
echo "  Logs:      $LATEST/outputs/.bridge/logs/"
echo ""
echo "Settings injection:"
echo "  $LATEST/.claude/settings.json"
```

---

## Init Script

**Purpose:** Initialize bridge folders for a session.

```bash
#!/bin/bash
# cowork-bridge-init.sh

SESSION_PATH="$1"

if [ -z "$SESSION_PATH" ]; then
  # Auto-detect
  SESSION_PATH=$(cowork-session-finder.sh | grep "Active session:" | cut -d: -f2 | xargs)
fi

mkdir -p "$SESSION_PATH/outputs/.bridge/requests"
mkdir -p "$SESSION_PATH/outputs/.bridge/responses"
mkdir -p "$SESSION_PATH/outputs/.bridge/logs"

echo '{"status": "ready", "initialized": "'$(date -Iseconds)'"}' > "$SESSION_PATH/outputs/.bridge/status.json"

echo "Bridge initialized at: $SESSION_PATH/outputs/.bridge/"
```

---

## Example Workflows

### Workflow 1: Claude-to-Claude Prompt Delegation

**Scenario:** Cowork needs to analyze a private GitHub repo but can't access the network.

```
Me (Cowork): I need to analyze the issues in a private repo.
             Let me delegate to the host Claude.

[Writes to requests/job-001.json]
{
  "id": "job-001",
  "type": "prompt",
  "prompt": "Fetch all open issues from github.com/acme/private-repo, categorize them by severity, and return a summary with the top 5 priorities.",
  "options": {
    "agent": "github-analyst",
    "model": "sonnet"
  }
}
```

**Host CLI picks it up:**
```
CLI: Detected prompt request job-001
     Running: claude -p "Fetch all open issues..." --agent github-analyst
     [Host Claude has full network, runs gh commands, analyzes]
     Writing response...
```

**Cowork receives:**
```json
{
  "id": "job-001",
  "status": "completed",
  "response": "## Issue Analysis for acme/private-repo\n\n### Critical (2)\n1. #142 - Auth bypass in /api/admin...\n2. #138 - Data loss on concurrent writes...\n\n### High (5)\n...",
  "usage": {"input_tokens": 892, "output_tokens": 2341}
}
```

**Cowork continues:**
```
Me: Got the analysis back from the host Claude.
    Based on the priorities, I'll draft a project plan...
```

---

### Workflow 2: Cowork needs to fetch from blocked API

```
Me (Cowork): I need to fetch data from api.example.com but it's blocked.
             Let me use the bridge.

[Writes to requests/job-001.json]
{
  "id": "job-001",
  "type": "http",
  "method": "GET",
  "url": "https://api.example.com/users/123"
}
```

### 2. CLI watcher picks it up

```
CLI: Detected new request job-001
     Executing: curl -s https://api.example.com/users/123
     Writing response...
```

### 3. Cowork reads response

```
Me (Cowork): [Polls responses/job-002.json]
             Got it! The user data is: {...}
             [Continues with task]
```

---

### Workflow 3: Git Operations

**Scenario:** Cowork wrote some code and needs to push it.

```
Me (Cowork): I've finished the feature. Let me push it.

[Writes to requests/job-003.json]
{
  "id": "job-003",
  "type": "git",
  "command": "push",
  "args": ["origin", "feature/new-auth"],
  "cwd": "~/projects/my-app"
}
```

**Host CLI:**
```
CLI: Detected git request job-003
     Running: git -C ~/projects/my-app push origin feature/new-auth
     Writing response...
```

**Response:**
```json
{
  "id": "job-003",
  "status": "completed",
  "stdout": "Enumerating objects: 15, done.\n...branch 'feature/new-auth' set up to track 'origin/feature/new-auth'.",
  "exit_code": 0
}
```

---

## Repo Structure

```
cowork-cli-bridge/
├── README.md
├── LICENSE
├── docs/
│   └── protocol-spec.md
├── skills/
│   ├── cowork-bridge/
│   │   ├── SKILL.md
│   │   └── templates/
│   └── cli-bridge/
│       ├── SKILL.md
│       └── watcher.sh
├── scripts/
│   ├── session-finder.sh
│   ├── bridge-init.sh
│   └── install.sh
└── examples/
    ├── http-request.md
    ├── docker-exec.md
    └── env-injection.md
```

---

## Next Steps

1. [ ] Finalize protocol spec (this doc)
2. [ ] Implement `cowork-bridge` skill
3. [ ] Implement `cli-bridge` skill with watcher
4. [ ] Write session discovery script
5. [ ] Test end-to-end flow
6. [ ] Create repo with install script
7. [ ] Write blog post walkthrough

