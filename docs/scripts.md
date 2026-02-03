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

- `scripts/bridge-uninstall.sh` -> `cowork-bridge-uninstall`
  - `--all`, `--global`, `--full`, `--dry-run`

## Prompt and session tools

- `scripts/inject-prompt.sh` -> `cowork-inject-prompt`
  - `--list`, `--backup`, `--restore`, `--show`

- `scripts/inject-session.sh` -> `cowork-session-config`
  - `show`, `model`, `prompt`, `approve-path`, `mount`, `enable-tool`, `disable-tool`, `list-tools`, `backup`, `restore`, `edit`

## Watcher

- `skills/cli-bridge/watcher.sh`
  - Main host-side daemon that processes requests

## UI

- `scripts/bridge-ui.sh`
  - Local HTMX-style dashboard for sessions and jobs
