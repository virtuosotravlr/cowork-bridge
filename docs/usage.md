# Usage

Most of the time you just talk to Cowork. The `cowork-bridge` skill writes request JSON files to the shared folder and waits for a response.

For manual testing or debugging, you can write requests yourself.

## Request types

| Type   | Description                      |
|--------|----------------------------------|
| `http` | HTTP requests                    |
| `exec` | Shell commands                   |
| `git`  | Git operations                   |
| `node` | node/npm/npx/yarn/pnpm commands  |
| `docker` | Docker commands                |
| `prompt` | Claude CLI prompts             |
| `env`  | Inject env vars into Cowork      |
| `file` | Read/write/list host files       |

See `docs/protocol-spec.md` for the full schema.

## Example: exec

```json
{
  "id": "job-001",
  "timestamp": "2026-02-01T03:14:15Z",
  "type": "exec",
  "command": "bash",
  "args": ["-lc", "curl -s https://api.example.com/data | jq ."],
  "timeout": 30,
  "cwd": "~/projects/my-app"
}
```

## Example: prompt delegation

```json
{
  "id": "job-002",
  "type": "prompt",
  "prompt": "Analyze ~/projects/myapp and summarize security risks",
  "options": {
    "agent": "security-auditor",
    "model": "opus"
  },
  "timeout": 300
}
```

## Streaming

Set `"stream": true` on `exec` or `prompt` requests to receive streaming output.

Response (immediate):

```json
{
  "status": "streaming",
  "stream_file": "streams/job-001.log"
}
```

Tail the stream from Cowork:

```bash
tail -f /mnt/outputs/.bridge/streams/job-001.log
```

When complete, the watcher appends `__STREAM_END__`. Responses larger than 50KB auto-stream.

## Logs

Bridge logs are written to `outputs/.bridge/logs/bridge.log`.
