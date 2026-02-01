# Docker setup

The Docker option runs the watcher and Claude CLI inside a container with full network access.

## Files

```
docker/
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── setup.sh
```

## Steps

```bash
cd docker/
./setup.sh
docker compose up -d
```

## Environment variables

From `.env.example`:
- `ANTHROPIC_API_KEY` (required)
- `SESSION_PATH` (required)
- `POLL_INTERVAL` (optional)
- `LOG_LEVEL` (optional)

The watcher also respects:
- `MAX_TIMEOUT`
- `STREAM_THRESHOLD`
- `ALLOWED_TYPES_ENV` (comma-separated)
- `BLOCKED_COMMANDS_ENV` (comma-separated)

If you want to override allowed or blocked lists, set the `*_ENV` names in your `.env`.

## Docker socket

`docker-compose.yml` mounts `/var/run/docker.sock` into the container. This enables Docker commands from Cowork, but also grants powerful host access. Remove the mount if you do not need Docker-in-Docker.

## Switching sessions

When you start a new Cowork session, update `SESSION_PATH` in `.env` and restart:

```bash
docker compose restart
```
