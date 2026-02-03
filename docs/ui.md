# Local UI Dashboard

The Cowork Bridge UI is a lightweight, server-rendered web interface for monitoring and managing bridge sessions, jobs, and maintenance tasks. Built with a minimal HTMX-style architecture, it provides real-time updates without external dependencies.

## Overview

The UI offers:

- **Session Monitoring**: View all active Cowork sessions and their bridge status
- **Job Queue Tracking**: Monitor request/response jobs with real-time updates
- **Stream Log Viewing**: Inspect streaming output from long-running operations
- **Manual Request Testing**: Create and submit bridge requests through a web form
- **Session Configuration**: Manage prompts, models, paths, and MCP tools
- **Global Maintenance**: Setup and uninstall bridge components across all sessions
- **Daemon Control**: Start/stop the auto-setup daemon via launchd
- **Watcher Management**: Control the bridge watcher process

## Getting Started

### Basic Launch

```bash
scripts/bridge-ui.sh
```

Default address: `http://127.0.0.1:8787`

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `--port <port>` | HTTP server port | 8787 |
| `--bind <ip>` | Bind address | 127.0.0.1 |
| `--sessionsDir <path>` | Override sessions directory | `~/Library/Application Support/Claude/local-agent-mode-sessions` |
| `--bridgeDir <path>` | Direct bridge folder mode (Docker) | None |
| `--token <token>` | Enable token authentication | None |

### Docker / Direct Bridge Mode

If you have a bridge folder mounted directly (e.g., `/bridge` in Docker):

```bash
scripts/bridge-ui.sh --bridgeDir /bridge
```

### Security

The UI binds to `127.0.0.1` by default, making it accessible only from localhost. For additional protection, enable token authentication:

```bash
scripts/bridge-ui.sh --token my-secret
```

Then either:
- Include the header `X-Bridge-Token: my-secret` in all requests
- Visit the UI once with `?token=my-secret` to set a cookie

## UI Pages

### Sessions Page (`/`)

The main dashboard displays all discovered Cowork sessions.

![Sessions List](images/ui-sessions.png)

**Columns:**
- **Title**: Session name/identifier
- **Session JSON**: Path to session configuration file
- **Bridge**: Status indicator (watching/ready/missing)
- **Modified**: Last modification timestamp

Click any session to view details.

### Session Detail Pages

Each session has four tabs:

#### Overview Tab (`/session?id=...`)

![Session Overview](images/ui-session-overview.png)

**Session Summary:**
- Bridge Directory path
- Status (watching/ready/error)
- Request/Response/Stream counts
- Last Activity timestamp

**Create Request Form:**
- **Type**: Select request type (curl, git, docker, node, file-read, file-write, env-inject, prompt-bridge)
- **Payload**: JSON request body
- **Quick Command**: Pre-fill payload from common commands
- **Timeout**: Execution timeout in seconds
- **Working Directory**: Optional execution directory

Submit requests directly to test bridge functionality.

#### Tools Tab (`/session/tools?id=...`)

![Session Tools](images/ui-session-tools.png)

**Prompt Injection Panel:**
- Select preset prompt templates
- Upload custom prompt file
- Backup/restore existing prompts
- Dry run mode for testing

**Session Config Panel:**
- Change Claude model
- Manage approved paths
- Configure mounted folders
- Enable/disable MCP tools
- Backup/restore session config
- View current configuration

![Config Output](images/ui-show-config.png)

**Bridge Setup Panel:**
- Initialize bridge for session
- Inject environment variables
- Uninstall bridge from session

#### Jobs Tab (`/session/jobs?id=...`)

![Jobs List](images/ui-jobs.png)

Monitor all request/response jobs for the session.

**Columns:**
- **ID**: Job identifier
- **Status**: pending/complete/error
- **Type**: Request type
- **Updated**: Last update timestamp
- **Summary**: Brief job description

Click a job to view full details.

##### Job Detail (`/session/job?id=...&jobId=...`)

![Job Detail](images/ui-job-detail.png)

**Sections:**
- **Request JSON**: Full request payload
- **Response JSON**: Complete response data
- **Stream Output**: Real-time streaming logs (if applicable)
- **Bridge Log**: Watcher processing logs

#### Logs Tab (`/session/logs?id=...`)

![Logs](images/ui-logs.png)

View the bridge watcher log for this session, showing timestamped processing events.

### Global Page (`/global`)

![Global Maintenance](images/ui-global.png)

**Global Details:**
- Account ID
- Workspace ID
- Session count
- Skill install path
- Skill presence status

**Global Maintenance Actions:**
- **Setup All Sessions**: Run `setup-all-sessions.sh` to configure bridge in all sessions
- **Uninstall Bridge (All Sessions)**: Remove bridge from all sessions
- **Uninstall Global Components**: Remove global skill and scripts

Each action supports dry run mode to preview changes.

### Daemon Page (`/daemon`)

![Daemon Control](images/ui-daemon.png)

**Auto-Setup Daemon:**
- **Start**: Launch launchd daemon to auto-configure new sessions
- **Stop**: Stop the daemon
- **Refresh**: Check daemon status
- Status display (running/stopped)

**Watcher Controls:**
- **Start**: Start the bridge watcher process
- **Stop**: Stop the watcher
- **Restart**: Restart the watcher
- PID display
- Live log output (auto-refreshing)

## API Endpoints

The UI server exposes the following endpoints:

### GET Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Sessions list page |
| `/session` | Session detail (requires `?id=...`) |
| `/session/meta` | Session metadata JSON |
| `/session/jobs` | Jobs list for session |
| `/session/job` | Job detail view |
| `/session/logs` | Bridge logs for session |
| `/global` | Global maintenance page |
| `/daemon` | Daemon control page |

### POST Endpoints

| Endpoint | Description |
|----------|-------------|
| `/actions/session` | Execute session actions (inject prompt, config changes, bridge setup) |
| `/actions/global` | Execute global actions (setup all, uninstall) |
| `/actions/daemon` | Control daemon (start/stop) |
| `/actions/watcher` | Control watcher (start/stop/restart) |
| `/session/job` | Create manual request |

### Fragment Endpoints

The UI uses HTMX-style polling for real-time updates:

| Endpoint | Poll Interval | Description |
|----------|---------------|-------------|
| `/fragments/sessions` | 2s | Session list updates |
| `/fragments/summary` | 2s | Session summary updates |
| `/fragments/jobs` | 2s | Jobs list updates |
| `/fragments/logs` | 3s | Log updates |
| `/fragments/stream` | 2s | Stream output updates |
| `/fragments/daemon-status` | 5s | Daemon status updates |
| `/fragments/watcher-status` | 3s | Watcher status updates |

## Architecture

### Server Implementation

- **Language**: Node.js (no external dependencies)
- **Port**: 8787 (configurable)
- **Rendering**: Server-side HTML generation
- **Updates**: HTMX-style polling with custom lightweight implementation

### Template System

Templates are modularized:
- `ui/templates/layout.js`: Base HTML structure and navigation
- `ui/templates/pages.js`: All page components and fragments

### Client-Side

Located in `ui/public/`:
- `htmx-lite.js`: Minimal HTMX implementation supporting `hx-get`, `hx-trigger="load"`, `hx-trigger="every Ns"`
- `styles.css`: UI styling
- `ui.js`: Client-side interactions and form handling

You can replace `htmx-lite.js` with the full HTMX library if needed.

### Data Source

The UI reads directly from:
- Session files in `sessionsDir` (or `bridgeDir` in Docker mode)
- Bridge directories at `outputs/.bridge` within each session
- Global configuration in `~/.claude/`

**Note**: The UI does not persist data. All information is read from the filesystem in real-time.

## Common Workflows

### Testing a Bridge Request

1. Navigate to a session's Overview tab
2. Select request type from dropdown
3. Either:
   - Fill in JSON payload manually
   - Use Quick Command to generate payload
4. Set timeout and working directory if needed
5. Click "Submit Request"
6. View job in Jobs tab

### Injecting a Custom Prompt

1. Go to session Tools tab
2. In Prompt Injection panel:
   - Select a preset or upload custom file
   - Enable backup if desired
   - Enable dry run to preview changes
3. Click "Inject Prompt"
4. Review action results

### Enabling an MCP Tool

1. Navigate to session Tools tab
2. In Session Config panel, click "Show Config"
3. Note the tool name you want to enable
4. Enter tool name in "Enable Tool" field
5. Click "Enable Tool"

### Setting Up All Sessions

1. Go to Global page
2. Enable "Dry Run" to preview changes
3. Click "Setup All Sessions"
4. Review output
5. If satisfied, uncheck "Dry Run" and run again

### Managing the Watcher

1. Go to Daemon page
2. Use Watcher controls:
   - **Start**: Launch watcher if not running
   - **Stop**: Terminate watcher
   - **Restart**: Restart watcher process
3. Monitor live log output below controls

## Troubleshooting

### UI Won't Start

**Issue**: `node is required to run the UI`
**Solution**: Install Node.js (any recent version)

**Issue**: Port already in use
**Solution**: Use `--port` to specify a different port:
```bash
scripts/bridge-ui.sh --port 8788
```

### No Sessions Appearing

**Issue**: Sessions list is empty
**Solution**:
- Verify sessions directory path
- Check that Cowork has created sessions
- Override path if needed: `--sessionsDir /path/to/sessions`

### Actions Not Working

**Issue**: Actions return errors
**Solution**:
- Ensure scripts have execute permissions
- Check that watcher is running
- Review script output in action results

### Token Authentication Issues

**Issue**: 403 Forbidden errors
**Solution**:
- Verify token matches in requests
- Set cookie via `?token=...` parameter
- Check `X-Bridge-Token` header is correct

### Slow Updates

**Issue**: UI not refreshing
**Solution**:
- Check browser console for errors
- Verify JavaScript is enabled
- Refresh page manually
- Check network connectivity

## Advanced Usage

### Custom Sessions Directory

```bash
scripts/bridge-ui.sh --sessionsDir /custom/path/to/sessions
```

### Binding to All Interfaces

**Warning**: Only do this in trusted networks.

```bash
scripts/bridge-ui.sh --bind 0.0.0.0 --token secure-random-token
```

### Running as a Service

You can run the UI server as a background service using launchd or systemd. Example launchd plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.bridge-ui</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/scripts/bridge-ui.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/bridge-ui.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bridge-ui.log</string>
</dict>
</plist>
```

## Performance Notes

- **Polling Intervals**: Default intervals (2-5s) balance responsiveness with resource usage
- **Concurrent Sessions**: UI handles multiple sessions efficiently
- **Memory Usage**: Minimal memory footprint (typically <50MB)
- **CPU Impact**: Negligible when idle, brief spikes during polls

## Security Considerations

- **Localhost Only**: Default binding to 127.0.0.1 prevents external access
- **Token Authentication**: Optional but recommended for sensitive environments
- **No HTTPS**: Use a reverse proxy (nginx, Caddy) if HTTPS is required
- **Script Execution**: UI can execute arbitrary scripts - restrict access accordingly
- **File Access**: UI can read session files - ensure filesystem permissions are appropriate

## Related Scripts

The UI integrates with these scripts (documented in `docs/scripts.md`):

- `scripts/inject-prompt.sh` - Prompt injection backend
- `scripts/inject-session.sh` - Session config management
- `scripts/bridge-init.sh` - Bridge initialization
- `scripts/bridge-uninstall.sh` - Uninstall operations
- `scripts/setup-all-sessions.sh` - Bulk setup
- `scripts/auto-setup-daemon.sh` - Daemon management
- `scripts/watcher-control.sh` - Watcher process control
- `skills/cli-bridge/watcher.sh` - Main watcher daemon

## Limitations

- No user authentication system (single-user design)
- No multi-tenancy support
- No persistent state (reads filesystem on each request)
- No WebSocket support (polling only)
- No mobile-optimized interface

## Future Enhancements

Potential improvements (not currently implemented):

- WebSocket support for real-time updates
- Multi-user authentication
- Request history and analytics
- Custom dashboard layouts
- Export/import configurations
- Scheduled tasks and automation

## See Also

- [Architecture Documentation](architecture.md) - System design
- [Scripts Reference](scripts.md) - All CLI tools
- [Session Internals](session-internals.md) - Session structure
- [Security Guide](security.md) - Security considerations
