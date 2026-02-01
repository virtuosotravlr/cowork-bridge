# Quickstart

## Requirements
- macOS host with Cowork sessions
- For Docker: Docker Desktop and an ANTHROPIC_API_KEY
- For local: jq and curl (required), coreutils (optional, for timeout), Claude CLI installed

## Option A: Docker (recommended)

```bash
git clone <repo-url>
cd cowork-bridge/docker

# Auto-detect session, create .env
./setup.sh

# Start the bridge
docker compose up -d

# Watch logs
docker compose logs -f
```

If you start a new Cowork session, the session path changes. Re-run `./setup.sh` or update `SESSION_PATH` in `.env`, then:

```bash
docker compose restart
```

## Option B: Local install

```bash
git clone <repo-url>
cd cowork-bridge
./scripts/install.sh --full
```

This installs:
- `cowork-session`, `cowork-bridge-init`, and other CLI tools into `~/.local/bin`
- Skills into `~/.claude/skills/`
- Prompt presets into `~/.claude/prompts/`

Start the watcher:

```bash
~/.claude/skills/cli-bridge/watcher.sh
```

## Initialize a session (if needed)

```bash
cowork-session --latest
cowork-bridge-init
```

To set up all existing sessions:

```bash
cowork-bridge-setup-all
```

## Verify

Check for `status.json` in your session:

```
.../outputs/.bridge/status.json
```

If it says `"status": "ready"`, the bridge is set up.
