# Scripts and CLI tools

The installer copies scripts into `~/.local/bin` with friendly names. You can also run them directly from `scripts/`.

## Installer

- `scripts/install.sh`
  - `--auto` to install the auto-setup daemon
  - `--setup-existing` to configure existing sessions
  - `--full` for both

## Session discovery

- `scripts/session-finder.sh` -> `cowork-session`
  - `--list`, `--latest`, `--info`

## Bridge setup

- `scripts/bridge-init.sh` -> `cowork-bridge-init`
  - Initializes the bridge in the latest session

- `scripts/setup-all-sessions.sh` -> `cowork-bridge-setup-all`
  - `--force`, `--dry-run`, `--verbose`

- `scripts/auto-setup-daemon.sh` -> `cowork-bridge-daemon`
  - Watches for new sessions and configures them
  - `install`, `uninstall`, `start`, `stop`, `status`

- `scripts/bridge-uninstall.sh` -> `cowork-bridge-uninstall`
  - `--session <path>` - Uninstall from specific session
  - `--all` - Uninstall from all sessions
  - `--global` - Remove global components
  - `--full` - Complete uninstall (all + global)
  - `--dry-run` - Preview changes without executing

## Prompt and session tools

- `scripts/inject-prompt.sh` -> `cowork-inject-prompt`
  - `--list` - List available preset prompts
  - `--backup` - Backup current prompt before injection
  - `--restore` - Restore from backup
  - `--show` - Display current prompt
  - `--file <path>` - Inject custom prompt file
  - `--preset <name>` - Inject preset prompt

- `scripts/inject-session.sh` -> `cowork-session-config`
  - `show` - Display current configuration
  - `model <name>` - Set Claude model
  - `prompt <text>` - Set custom prompt
  - `approve-path <path>` - Add approved file path
  - `mount <path>` - Add mounted folder
  - `enable-tool <name>` - Enable MCP tool
  - `disable-tool <name>` - Disable MCP tool
  - `list-tools` - List available MCP tools
  - `backup` - Backup session config
  - `restore` - Restore from backup
  - `edit` - Open config in editor

## Watcher

- `skills/cli-bridge/watcher.sh`
  - Main host-side daemon that processes requests
  - Run directly or use `watcher-control.sh` to manage

- `scripts/watcher-control.sh` -> No alias yet
  - `start` - Start the watcher process in background
  - `stop` - Stop the watcher process
  - `restart` - Restart the watcher
  - `status` - Check watcher status and PIDs

## UI

- `scripts/bridge-ui.sh` -> No alias yet
  - Local HTMX-style dashboard for sessions and jobs
  - `--port <port>` - Bind port (default: 8787)
  - `--bind <ip>` - Bind address (default: 127.0.0.1)
  - `--sessionsDir <path>` - Override sessions directory
  - `--bridgeDir <path>` - Direct bridge folder mode (Docker)
  - `--token <token>` - Enable token authentication

See `docs/ui.md` for full UI documentation.
