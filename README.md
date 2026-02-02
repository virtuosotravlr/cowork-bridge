# Cowork Bridge

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://github.com/virtuosotravlr/cowork-bridge/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/virtuosotravlr/cowork-bridge/actions/workflows/shellcheck.yml)
[![Docker Build](https://github.com/virtuosotravlr/cowork-bridge/actions/workflows/docker-build.yml/badge.svg)](https://github.com/virtuosotravlr/cowork-bridge/actions/workflows/docker-build.yml)
[![GitHub issues](https://img.shields.io/github/issues/virtuosotravlr/cowork-bridge)](https://github.com/virtuosotravlr/cowork-bridge/issues)
[![GitHub last commit](https://img.shields.io/github/last-commit/virtuosotravlr/cowork-bridge)](https://github.com/virtuosotravlr/cowork-bridge/commits/main)

A file-based bridge between a sandboxed Cowork VM and an unrestricted Claude CLI running on your Mac (or in Docker).

Cowork writes requests to a shared folder. A host-side watcher executes them with full host access and writes responses back.

> **Note:** Not affiliated with Anthropic. Experimental; use at your own risk.

## Docs

- [docs/README.md](docs/README.md)
- [docs/quickstart.md](docs/quickstart.md)
- [docs/usage.md](docs/usage.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/protocol-spec.md](docs/protocol-spec.md)
- [docs/session-internals.md](docs/session-internals.md)
- [docs/scripts.md](docs/scripts.md)
- [docs/docker.md](docs/docker.md)
- [docs/security.md](docs/security.md)

## Features
- HTTP requests to any endpoint
- Git operations with host credentials
- Docker on your host
- Node tooling (node/npm/npx/yarn/pnpm)
- File read/write on host paths
- Environment variable injection into Cowork
- Claude-to-Claude prompt delegation
- Streaming responses for long output

## Quick start (Docker, recommended)

```bash
git clone https://github.com/virtuosotravlr/cowork-bridge.git
cd cowork-bridge/docker

# Auto-detect session, create .env
./setup.sh

# Start the bridge
docker compose up -d

# Watch logs
docker compose logs -f
```

Note: Docker requires an API key. If you want to use a Max subscription plan (no API key), use the Local install.

## Quick start (Local)

Prereqs (macOS host):
- jq and curl (required)
- coreutils (optional, for timeout)
- Claude CLI installed on the host

```bash
git clone https://github.com/virtuosotravlr/cowork-bridge.git
cd cowork-bridge
./scripts/install.sh --full
```

Start the watcher:

```bash
~/.claude/skills/cli-bridge/watcher.sh
```

## Basic usage

1) Initialize a session (if the bridge is not already set up):

```bash
cowork-session --list
cowork-bridge-init
```

2) Use Cowork normally. When a request needs host access, the `cowork-bridge` skill writes a job to `outputs/.bridge/requests/` and waits for a response.

3) For advanced request types, streaming, and manual testing, see the docs.

## Security

This bridge can execute arbitrary commands on your host. Use a dedicated machine or user, and review allowed/blocked settings. See `docs/security.md` for details.

## Contributing

PRs welcome. Please read `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.

## License

MIT
