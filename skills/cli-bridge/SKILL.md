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

The watcher script is located at `watcher.sh` in this directory. It includes:

- Streaming support for long-running commands
- Configurable timeouts and thresholds
- Docker/direct bridge mode support
- Security blocklists and type allowlists
- Comprehensive logging

See the actual [`watcher.sh`](./watcher.sh) file for the full implementation.

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
