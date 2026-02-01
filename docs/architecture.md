# Architecture

The bridge uses a shared folder between the Cowork VM and your host. Cowork writes requests; the host watcher reads them, executes with full permissions, then writes responses.

```
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM (sandboxed)                                          │
│                                                                 │
│  "Need to call api.example.com"                                │
│                           │                                     │
│                           ▼                                     │
│            /mnt/outputs/.bridge/requests/job-001.json           │
└───────────────────────────┬─────────────────────────────────────┘
                            │  (mounted folder)
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│  HOST MAC (unrestricted)                                          │
│                                                                   │
│  watcher.sh executes request                                      │
│                           │                                       │
│                           ▼                                       │
│            outputs/.bridge/responses/job-001.json                 │
└───────────────────────────┬───────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  COWORK VM                                                       │
│                                                                 │
│  "Got the response, continuing..."                              │
└─────────────────────────────────────────────────────────────────┘
```

## Bridge directory layout

```
outputs/.bridge/
├── requests/    # Cowork writes requests here
├── responses/   # Host watcher writes responses here
├── streams/     # Optional streaming output files
├── logs/        # Audit trail
└── status.json  # Bridge status
```

## File locations

Inside the Cowork VM:

```
/sessions/<session-name>/mnt/outputs/.bridge/
```

On the host:

```
~/Library/Application Support/Claude/local-agent-mode-sessions/
  <account-id>/<workspace-id>/local_<session-id>/outputs/.bridge/
```
