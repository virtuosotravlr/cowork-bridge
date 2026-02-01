# Cowork Bridge

## The Problem

Claude's Cowork mode runs in a sandboxed VM with restricted network access. You can't:

- Hit arbitrary HTTP endpoints
- Run Docker containers
- Push to git remotes
- Use your custom Claude agents with full capabilities

## The Solution

This bridge creates a bidirectional channel between the sandboxed Cowork VM and an unrestricted Claude CLI running on your Mac. Cowork writes requests to a shared folder, the CLI watcher executes them with full host capabilities, and writes responses back.

```
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM (sandboxed)                                          │
│                                                                 │
│  "I need to fetch from api.example.com but it's blocked..."    │
│                           │                                     │
│                           ▼                                     │
│            /mnt/outputs/.bridge/requests/job-001.json           │
└───────────────────────────┬─────────────────────────────────────┘
                            │  (mounted folder)
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│  HOST MAC (unrestricted)                                          │
│                                                                   │
│  CLI watcher: "Got it, executing curl..."                         │
│               "Writing response..."                               │
│                           │                                       │
│                           ▼                                       │
│            outputs/.bridge/responses/job-001.json                 │
└───────────────────────────┬───────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM                                                       │
│                                                                 │
│  "Got the response! Continuing with the data..."               │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **HTTP Requests**: Hit any endpoint, bypass the allowlist
- **Git Operations**: Push, pull, clone with full SSH/credential access
- **Docker**: Run containers on your Mac from Cowork
- **Node/NPM**: Execute npm, npx, yarn commands
- **File Access**: Read/write files on your Mac's filesystem
- **Environment Injection**: Set env vars in the Cowork VM on the fly
- **Claude-to-Claude Prompts**: Delegate complex tasks to an unrestricted Claude CLI with your custom agents
- **Streaming Responses**: `tail -f` long-running output or large responses in real-time

## Quick Start

### Option A: Docker (Recommended)

No local installs — everything runs in a container:

```bash
git clone https://github.com/yourusername/cowork-cli-bridge
cd cowork-cli-bridge/docker

# Auto-detect session and create .env
./setup.sh

# Start the bridge
docker compose up -d

# View logs
docker compose logs -f
```

That's it! The Docker container:

- Has Claude CLI installed
- Has full network access
- Mounts the bridge folder from your Cowork session
- Watches for requests and processes them

### Option B: Local Install

```bash
git clone https://github.com/yourusername/cowork-cli-bridge
cd cowork-cli-bridge
./scripts/install.sh --full
```

Then start the watcher:

```bash
~/.claude/skills/cli-bridge/watcher.sh
```

---

### Initialize a Session (if needed)

```bash
# Find your active Cowork session
cowork-session --list

# Initialize the bridge
cowork-bridge-init
```

### 4. Use It in Cowork

Just talk to Claude normally! When you ask for something that requires host capabilities, Claude automatically uses the bridge:

**You:** "Can you fetch the latest issues from my private GitHub repo?"

**Claude:** _detects this needs unrestricted network access_ → _writes request to bridge_ → _host CLI executes_ → _returns results_

**You:** "Push my changes to the main branch"

**Claude:** _uses bridge to run `git push` on host_ → _returns result_

**You:** "Run my custom security-audit agent on this codebase"

**Claude:** _delegates to host Claude CLI with your custom agent_ → _returns analysis_

The bridge is invisible to you — Claude handles the request/response protocol internally using the `cowork-bridge` skill.

## Request Types

| Type     | Description        | Example                                                                  |
| -------- | ------------------ | ------------------------------------------------------------------------ |
| `http`   | HTTP requests      | `{"type": "http", "url": "...", "method": "GET"}`                        |
| `exec`   | Shell commands     | `{"type": "exec", "command": "whoami"}`                                  |
| `git`    | Git operations     | `{"type": "git", "command": "push", "args": ["origin", "main"]}`         |
| `node`   | Node/npm commands  | `{"type": "node", "command": "npx", "args": ["prettier", "."]}`          |
| `docker` | Docker commands    | `{"type": "docker", "command": "run", "args": ["alpine", "echo", "hi"]}` |
| `prompt` | Claude CLI prompts | `{"type": "prompt", "prompt": "...", "options": {"agent": "..."}}`       |
| `env`    | Inject env vars    | `{"type": "env", "key": "MY_VAR", "value": "hello"}`                     |
| `file`   | File operations    | `{"type": "file", "action": "read", "path": "~/file.txt"}`               |

## The Killer Feature: Claude-to-Claude

The `prompt` type lets Cowork delegate complex tasks to your unrestricted Claude CLI:

```json
{
  "type": "prompt",
  "prompt": "Analyze the GitHub repo at ~/projects/myapp, find security issues, and create a detailed report",
  "options": {
    "agent": "security-auditor",
    "model": "opus"
  }
}
```

The host Claude has:

- Full network access
- Docker
- Your custom agents
- All MCP servers
- Complete filesystem access

## Streaming Protocol

For long-running commands or large outputs, the bridge supports streaming. Instead of waiting for the full response, the host writes output incrementally to a file that Cowork can `tail -f`.

### When to Use Streaming

- **Docker logs**: `docker logs -f container`
- **Long Claude responses**: Multi-page analyses, code reviews
- **Watch commands**: Any command with continuous output
- **Large outputs**: Responses > 50KB auto-stream

### How It Works

**Request with streaming:**

```json
{
  "type": "exec",
  "command": "docker logs -f my-container",
  "stream": true
}
```

**Response (immediate):**

```json
{
  "status": "streaming",
  "stream_file": "streams/job-001.log"
}
```

**Read the stream:**

```bash
# Cowork can tail the stream file in real-time
tail -f /mnt/outputs/.bridge/streams/job-001.log
```

When the command finishes, a `__STREAM_END__` sentinel is written and the response updates to `"status": "completed"`.

### Auto-Streaming

Responses larger than 50KB automatically switch to streaming mode:

```json
{
  "status": "completed",
  "stream_file": "streams/job-big-001.log",
  "auto_streamed": true,
  "bytes_written": 2097152
}
```

## Session Configuration Injection (The Nuclear Option)

We discovered that `cowork_settings.json` in each session directory controls EVERYTHING — and it's **fully injectable**.

### What You Can Modify

| Field                         | What it does         | Power User Potential                      |
| ----------------------------- | -------------------- | ----------------------------------------- |
| `systemPrompt`                | Claude's brain       | Remove restrictions, add bridge awareness |
| `model`                       | Which Claude model   | Switch opus↔sonnet↔haiku on the fly       |
| `userSelectedFolders`         | Mounted directories  | Pre-mount folders without UI              |
| `userApprovedFileAccessPaths` | Permission whitelist | Skip "allow access?" prompts              |
| `enabledMcpTools`             | MCP tool toggles     | Enable/disable tools by hash              |
| `slashCommands`               | Available /commands  | Add custom slash commands                 |

### Quick Commands

```bash
# Show current session config
cowork-session-config show

# Switch to faster model for simple tasks
cowork-session-config model sonnet

# Switch back to opus for complex work
cowork-session-config model opus

# Pre-approve a path (skip permission prompts)
cowork-session-config approve-path ~/projects

# Pre-mount a folder
cowork-session-config mount ~/Documents

# List all MCP tools
cowork-session-config list-tools

# Open config in editor
cowork-session-config edit

# Backup before making changes
cowork-session-config backup
```

### The cowork_settings.json Structure

```json
{
  "sessionId": "local_fd92d159-...",
  "processName": "modest-fervent-archimedes",
  "model": "claude-opus-4-5-20251101",
  "userSelectedFolders": ["/Users/you/projects"],
  "userApprovedFileAccessPaths": ["/path/to/auto-approve"],
  "enabledMcpTools": {
    "local:playwright:browser_navigate-448099781ba173a5a216dca1b4e2a805": true
  },
  "slashCommands": ["compact", "review", "your-custom-command"],
  "systemPrompt": "..."
}
```

---

## System Prompt Injection

The `systemPrompt` field controls Claude's entire behavior. This is where you remove the guardrails.

### Why This Matters

The default Cowork prompt is optimized for "non-developers" with lots of guardrails:

- Mandatory TodoWrite for every task
- Mandatory AskUserQuestion before any work
- Blocked curl/wget/requests even via bash
- Verbose explanations and confirmations
- Required skill reading for simple tasks

For power users, this overhead is painful. Prompt injection lets you:

- Remove unnecessary restrictions
- Add bridge awareness by default
- Enable direct, CLI-style communication
- Skip the hand-holding

### Prompt Presets

| Preset         | Description                                              |
| -------------- | -------------------------------------------------------- |
| `power-user`   | Developer mode with bridge integration, reduced overhead |
| `cli-mode`     | Mimics Claude Code CLI behavior - terse, efficient       |
| `minimal`      | Bare minimum prompt, maximum freedom                     |
| `unrestricted` | Full sandbox escape, no limitations                      |

### Usage

```bash
# List available presets
./scripts/inject-prompt.sh --list

# Backup original prompt first (recommended)
./scripts/inject-prompt.sh --backup power-user

# Inject a preset
./scripts/inject-prompt.sh power-user

# Show current prompt
./scripts/inject-prompt.sh --show

# Restore original
./scripts/inject-prompt.sh --restore

# Use custom prompt file
./scripts/inject-prompt.sh /path/to/my-prompt.json
```

### Prompt File Format

```json
{
  "systemPrompt": "<your_prompt>\nTemplate vars available:\n- {{cwd}} - working directory\n- {{workspaceFolder}} - output folder\n- {{accountName}} - user's name\n- {{emailAddress}} - user's email\n- {{currentDateTime}} - current date/time\n- {{modelName}} - model being used\n- {{folderSelected}} - whether user selected a folder\n</your_prompt>"
}
```

### The cowork_settings.json Location

```
~/Library/Application Support/Claude/local-agent-mode-sessions/
  <account-id>/<workspace-id>/local_<session-id>/
  └── cowork_settings.json   # <-- THE SYSTEM PROMPT LIVES HERE
```

### Changes Take Effect Immediately

No restart needed! The prompt is read on each message, so changes apply to the next interaction.

### Example: Power User Prompt

The `power-user` preset includes:

- Bridge awareness built into the prompt
- Permission to use curl/wget via bridge
- Optional TodoWrite/AskUserQuestion (not mandatory)
- Direct communication style
- Developer assumptions (knows git, docker, etc.)

---

## Bonus: Environment Variable Injection

We discovered that Cowork reads `settings.json` from the session's `.claude/` folder and injects env vars into the VM.

### The Secret UUID Path Structure

The path to inject env vars follows this structure:

```
~/Library/Application Support/Claude/
└── local-agent-mode-sessions/
    └── <account-id>/                              # e.g. 4994e1cf-6e39-4e9d-8573-d0f070943867
        └── <workspace-id>/                        # e.g. 006c112f-a078-471d-8ec8-0c5ac3ab92d2
            └── local_<session-id>/                # e.g. local_fd92d159-d5b8-4cc3-879c-0e49c3dcacd6
                └── .claude/
                    └── settings.json              # <-- THIS gets mounted into the VM
```

**Path breakdown:**
| Segment | Description | Example |
|---------|-------------|---------|
| `local-agent-mode-sessions/` | Root dir for all Cowork sessions | — |
| `<account-id>/` | Your Anthropic account UUID | `4994e1cf-6e39-4e9d-8573-d0f070943867` |
| `<workspace-id>/` | Workspace UUID | `006c112f-a078-471d-8ec8-0c5ac3ab92d2` |
| `local_<session-id>/` | Individual session (prefixed with `local_`) | `local_fd92d159-d5b8-4cc3-879c-0e49c3dcacd6` |

### Injecting Env Vars

```bash
# Find your active session path
cowork-session --latest

# Inject env vars (they appear IMMEDIATELY in the VM - no restart needed!)
echo '{"env": {"MY_SECRET": "value", "API_KEY": "sk-..."}}' > \
  ~/Library/Application\ Support/Claude/local-agent-mode-sessions/<account>/<workspace>/local_<session>/.claude/settings.json
```

The env var is immediately available in Cowork—no restart needed!

### Skills Plugin Path

Skills are registered in a parallel structure:

```
~/Library/Application Support/Claude/
└── skills-plugin/
    └── <workspace-id>/                            # Same workspace UUID
        └── <account-id>/                          # Same account UUID (note: reversed order!)
            └── .claude-plugin/
                ├── manifest.json                  # Skill registry
                └── skills/
                    ├── docx/                      # Built-in skills
                    ├── pdf/
                    └── cowork-bridge/             # <-- Our injected skill goes here
```

**Note:** The `skills-plugin` path has workspace/account in _reversed order_ compared to `local-agent-mode-sessions`!

## Directory Structure

```
cowork-cli-bridge/
├── README.md
├── docs/
│   └── protocol-spec.md           # Full protocol specification
├── prompts/                       # System prompt presets
│   ├── power-user-prompt.json     # Developer mode, bridge-aware
│   ├── cli-mode-prompt.json       # Claude Code CLI behavior
│   ├── minimal-prompt.json        # Bare minimum prompt
│   └── unrestricted-prompt.json   # Full freedom mode
├── skills/
│   ├── cowork-bridge/             # Skill for Cowork VM (injected)
│   │   └── SKILL.md
│   └── cli-bridge/                # Skill for host Mac
│       ├── SKILL.md
│       └── watcher.sh             # Request processor daemon
├── scripts/
│   ├── install.sh                 # Main installer
│   ├── inject-prompt.sh           # System prompt injector
│   ├── session-finder.sh          # Find/list sessions
│   ├── bridge-init.sh             # Initialize single session
│   ├── setup-all-sessions.sh      # Retroactive setup for all sessions
│   ├── auto-setup-daemon.sh       # Auto-configure new sessions
│   └── bridge-uninstall.sh        # Clean removal
├── docker/                        # Docker deployment
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example
│   └── setup.sh
└── examples/
    └── ...
```

## Scripts Explained

### `install.sh` — Main Installer

**What it does:**

1. Creates `~/.claude/skills/cli-bridge/` and `~/.claude/skills/cowork-bridge/`
2. Copies skill files and watcher script
3. Installs CLI tools to `~/.local/bin/`
4. Optionally sets up the auto-setup daemon as a launchd service

**Flags:**

- `--auto, -a` — Install and start the auto-setup daemon
- `--setup-existing, -e` — Configure all existing sessions
- `--full, -f` — Both of the above (recommended)

---

### `session-finder.sh` → `cowork-session`

**What it does:**
Scans `~/Library/Application Support/Claude/local-agent-mode-sessions/` to find Cowork sessions.

**How it works:**

1. Uses `find` to locate all `local_*` directories
2. Checks each for a `.claude/` subfolder (indicates valid session)
3. Uses `stat` to get modification times for sorting
4. Returns paths with metadata (session ID, bridge status, timestamps)

**Commands:**

```bash
cowork-session --list      # List all sessions with details
cowork-session --latest    # Print path to most recent session (for scripting)
cowork-session --info      # Detailed info about latest session
```

---

### `bridge-init.sh` → `cowork-bridge-init`

**What it does:**
Initializes the bridge for a single session.

**How it works:**

1. Creates `.bridge/` directory structure in session's `outputs/` folder:
   ```
   outputs/.bridge/
   ├── requests/      # Cowork writes requests here
   ├── responses/     # CLI writes responses here
   ├── streams/       # Streaming output files
   └── logs/          # Audit trail
   ```
2. Extracts workspace/account IDs from the session path
3. Copies `cowork-bridge` skill to `skills-plugin/<workspace>/<account>/.claude-plugin/skills/`
4. Updates `manifest.json` to register the skill
5. Creates/updates `settings.json` with `BRIDGE_ENABLED=true`

---

### `setup-all-sessions.sh` → `cowork-bridge-setup-all`

**What it does:**
Retroactively sets up the bridge for ALL existing Cowork sessions.

**How it works:**

1. Calls `find` to get all sessions
2. For each session, checks if bridge is already set up (looks for `.bridge/status.json`)
3. Skips already-configured sessions (unless `--force`)
4. Runs the same setup logic as `bridge-init.sh` for each session
5. Reports summary: total found, set up, skipped

**Flags:**

```bash
cowork-bridge-setup-all              # Setup unconfigured sessions
cowork-bridge-setup-all --force      # Re-setup ALL sessions
cowork-bridge-setup-all --dry-run    # Preview without changes
```

---

### `auto-setup-daemon.sh` → `cowork-bridge-daemon`

**What it does:**
Watches for NEW Cowork sessions and automatically configures them.

**How it works:**

1. Polls `local-agent-mode-sessions/` every 2 seconds (or uses `fswatch` if available)
2. Maintains a list of known sessions in `~/.claude/.bridge-known-sessions`
3. When a new `local_*` directory appears with a `.claude/` folder:
   - Creates bridge directory structure
   - Injects `cowork-bridge` skill into `skills-plugin/`
   - Updates `manifest.json`
   - Sets `BRIDGE_ENABLED` env var
4. Logs all activity for debugging

**Running as a service:**

```bash
# Manual (foreground)
cowork-bridge-daemon

# With fswatch (faster detection)
cowork-bridge-daemon --fswatch

# As launchd service (installed by install.sh --auto)
# Runs at login, restarts on failure, logs to /tmp/
```

---

### `bridge-uninstall.sh` → `cowork-bridge-uninstall`

**What it does:**
Cleanly removes bridge components from sessions.

**How it works:**

1. Removes `.bridge/` directory from session's `outputs/`
2. Removes `cowork-bridge` skill from `skills-plugin/`
3. Removes skill entry from `manifest.json`
4. Removes `BRIDGE_ENABLED` from `settings.json`
5. Removes session from known sessions list

**Flags:**

```bash
cowork-bridge-uninstall              # Remove from latest session
cowork-bridge-uninstall --all        # Remove from ALL sessions
cowork-bridge-uninstall --global     # Remove skills, tools, daemon
cowork-bridge-uninstall --full       # Complete removal (prompts for confirmation)
cowork-bridge-uninstall --dry-run    # Preview what would be removed
```

---

### `watcher.sh` — Request Processor

**What it does:**
The heart of the bridge — processes requests from Cowork and executes them on the host.

**How it works:**

1. Finds active session and locates `.bridge/requests/` directory
2. Polls for new `.json` files every second
3. For each request:
   - Parses JSON to get type, command, args, timeout
   - Routes to appropriate handler (`exec`, `http`, `git`, `node`, `docker`, `prompt`, `env`, `file`)
   - Executes with timeout enforcement
   - Writes response JSON to `.bridge/responses/`
   - Deletes processed request file
4. Logs all activity to `.bridge/logs/bridge.log`

**Request handlers:**
| Type | Handler | What it does |
|------|---------|--------------|
| `exec` | `handle_exec` | Runs shell command via `bash -c` |
| `http` | `handle_http` | Builds and executes `curl` command |
| `git` | `handle_git` | Runs `git <command>` in specified directory |
| `node` | `handle_node` | Runs `node`/`npm`/`npx`/`yarn`/`pnpm` |
| `docker` | `handle_docker` | Runs `docker <command>` |
| `prompt` | `handle_prompt` | Runs `claude -p` with options |
| `env` | `handle_env` | Updates `settings.json` with new env var |
| `file` | `handle_file` | Read/write/list files on host |

**Streaming support:**

- Requests with `"stream": true` write output to `.bridge/streams/<job-id>.log`
- Cowork can `tail -f` the stream file for real-time output
- Auto-streams responses > 50KB (configurable via `STREAM_THRESHOLD`)
- Writes `__STREAM_END__` sentinel when complete

**Security:**

- Blocked commands list (prevents `rm -rf /`, etc.)
- Type allowlist (only processes known types)
- Timeout enforcement (kills long-running commands)
- All requests logged for audit

## Docker Setup

The cleanest way to run the bridge — no local installs, everything containerized.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM (sandboxed)                                          │
│  writes to: /mnt/outputs/.bridge/requests/                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ════════════════════╪════════════════════  (mounted folder)
                            │
┌───────────────────────────┴─────────────────────────────────────┐
│  DOCKER CONTAINER (unrestricted)                                │
│  - Claude CLI installed                                         │
│  - watcher.sh running                                           │
│  - Full network access                                          │
│  - Mounts same outputs/.bridge/ folder                          │
│  - Docker socket mounted (docker-in-docker)                     │
└─────────────────────────────────────────────────────────────────┘
```

### Files

```
docker/
├── Dockerfile          # Container with Claude CLI + watcher
├── docker-compose.yml  # Service definition
├── .env.example        # Configuration template
└── setup.sh            # Auto-detect session, create .env
```

### Usage

```bash
cd docker/

# Auto-setup (finds session, prompts for API key, creates .env)
./setup.sh

# Start
docker compose up -d

# Logs
docker compose logs -f

# Stop
docker compose down
```

### Configuration

Copy `.env.example` to `.env` and set:

| Variable            | Required | Description                                                    |
| ------------------- | -------- | -------------------------------------------------------------- |
| `ANTHROPIC_API_KEY` | Yes      | Your Anthropic API key                                         |
| `SESSION_PATH`      | Yes      | Full path to Cowork session (auto-detected by setup.sh)        |
| `POLL_INTERVAL`     | No       | How often to check for requests (default: 1s)                  |
| `BLOCKED_COMMANDS`  | No       | Comma-separated list of blocked commands                       |
| `ALLOWED_TYPES`     | No       | Comma-separated list of allowed request types                  |
| `STREAM_THRESHOLD`  | No       | Auto-stream responses larger than this (default: 51200 / 50KB) |

### Docker-in-Docker

The container mounts `/var/run/docker.sock` so it can run Docker commands. This means Cowork can request:

```json
{
  "type": "docker",
  "command": "run",
  "args": ["--rm", "python:3.11", "python", "-c", "print('hello')"]
}
```

And the container will execute it on the host's Docker daemon.

### Updating Session Path

When you start a new Cowork session, the SESSION_PATH changes. Either:

1. Run `./setup.sh` again to auto-detect the new session
2. Or manually update `.env` with the new path from `cowork-session --latest`

Then restart the container:

```bash
docker compose restart
```

---

## How We Figured This Out

This started as an exploration of Cowork's internals:

1. Discovered the VM runs via `bwrap` (bubblewrap) with network isolation
2. Found that `~/.claude/` is selectively mounted into the VM
3. Realized the `outputs/` folder is writable and shared
4. Discovered that `settings.json` with an `env` key injects environment variables
5. Confirmed live injection works without VM restart
6. Built this bridge protocol on top of the shared filesystem

## Security Considerations

- The CLI watcher has a command blocklist for dangerous operations
- All requests are logged for audit
- You control what the watcher is allowed to execute
- The bridge is only as secure as your Mac

## Contributing

PRs welcome! Some ideas:

- [ ] Web UI for monitoring bridge activity
- [ ] Request queuing and priorities
- [ ] Encrypted request/response payloads
- [ ] Multi-session support

## License

MIT
