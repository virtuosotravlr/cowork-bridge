const { escapeHtml } = require("./layout");

function renderBadge(status) {
  const label = status || "unknown";
  const lower = label.toLowerCase();
  let cls = "badge";
  if (["completed", "ready", "watching"].includes(lower)) cls += " ok";
  if (["failed", "error"].includes(lower)) cls += " fail";
  if (["pending", "running", "streaming"].includes(lower)) cls += " warn";
  return `<span class="${cls}">${escapeHtml(label)}</span>`;
}

function renderSessions(sessions) {
  if (!sessions.length) {
    return `
      <div class="panel">
        <h2>No sessions found</h2>
        <p class="notice">Point the UI at a bridge directory with <code>--bridge-dir</code> or ensure Cowork has an active session.</p>
      </div>`;
  }

  const rows = sessions
    .map((session) => {
      const metaLabel = escapeHtml(session.metaFile || "local_*.json");
      const metaCell = `<a href="/session/meta?path=${encodeURIComponent(session.path)}">${metaLabel}</a>${
        session.metaExists ? "" : " <span class=\"tag\">(missing)</span>"
      }`;

      return `
        <tr>
          <td><a href="/session?path=${encodeURIComponent(session.path)}">${escapeHtml(session.title || "Untitled")}</a></td>
          <td>${metaCell}</td>
          <td>${renderBadge(session.bridgeStatus || "missing")}</td>
          <td class="mono">${escapeHtml(session.modified)}</td>
        </tr>`;
    })
    .join("");

  return `
    <div class="panel">
      <h2>Sessions</h2>
      <p class="panel-subtitle">Latest Cowork sessions detected on this machine.</p>
      <table class="table">
        <thead>
          <tr>
            <th>Title</th>
            <th>Session JSON</th>
            <th>Bridge</th>
            <th>Modified</th>
          </tr>
        </thead>
        <tbody>
          ${rows}
        </tbody>
      </table>
    </div>`;
}

function renderSummary(summary) {
  return `
    <div class="panel">
      <h2>Session Summary</h2>
      <div class="grid cols-2">
        <div class="kv">
          <strong>Bridge Dir</strong>
          <span class="mono">${escapeHtml(summary.bridgeDir)}</span>
        </div>
        <div class="kv">
          <strong>Status</strong>
          <span>${renderBadge(summary.status)}</span>
        </div>
        <div class="kv">
          <strong>Requests</strong>
          <span>${summary.counts.requests}</span>
        </div>
        <div class="kv">
          <strong>Responses</strong>
          <span>${summary.counts.responses}</span>
        </div>
        <div class="kv">
          <strong>Streams</strong>
          <span>${summary.counts.streams}</span>
        </div>
        <div class="kv">
          <strong>Last Activity</strong>
          <span class="mono">${escapeHtml(summary.lastActivity || "n/a")}</span>
        </div>
      </div>
    </div>`;
}

function renderJobs(jobs) {
  if (!jobs.length) {
    return `
      <div class="panel">
        <h2>Jobs</h2>
        <p class="notice">No jobs found in this session.</p>
      </div>`;
  }

  const rows = jobs
    .map((job) => {
      return `
        <tr>
          <td><a href="/session/job?path=${encodeURIComponent(job.sessionPath)}&id=${encodeURIComponent(job.id)}">${escapeHtml(job.id)}</a></td>
          <td>${renderBadge(job.status)}</td>
          <td>${escapeHtml(job.type || "-")}</td>
          <td class="mono">${escapeHtml(job.updatedAt || "-")}</td>
          <td class="mono">${escapeHtml(job.summary || "")}</td>
        </tr>`;
    })
    .join("");

  return `
    <div class="panel">
      <h2>Jobs</h2>
      <table class="table">
        <thead>
          <tr>
            <th>ID</th>
            <th>Status</th>
            <th>Type</th>
            <th>Updated</th>
            <th>Summary</th>
          </tr>
        </thead>
        <tbody>
          ${rows}
        </tbody>
      </table>
    </div>`;
}

function renderSessionMeta({ sessionId, title, metaPath, metaJson, prettyJson, systemPrompt }) {
  const promptSection = systemPrompt
    ? `
      <div class="panel">
        <h2>System Prompt</h2>
        <p class="panel-subtitle">Rendered with line wrapping for readability.</p>
        <pre class="pre-scroll pre-wrap">${escapeHtml(systemPrompt)}</pre>
      </div>`
    : "";

  return `
    <div class="panel">
      <div class="breadcrumbs"><a href="/">Sessions</a> / <a href="/session?path=${escapeHtml(metaPath.sessionPath)}">Session</a> / Meta</div>
      <h2>Session JSON</h2>
      <p class="panel-subtitle">${escapeHtml(sessionId)} — ${escapeHtml(title || "Untitled")}</p>
      <div class="kv">
        <strong>File</strong>
        <span class="mono">${escapeHtml(metaPath.filePath)}</span>
      </div>
      <pre class="pre-scroll">${escapeHtml(prettyJson || metaJson || "(missing)")}</pre>
      <details>
        <summary class="tag">Show raw JSON</summary>
        <pre class="pre-scroll">${escapeHtml(metaJson || "(missing)")}</pre>
      </details>
    </div>
    ${promptSection}`;
}

function renderJobDetail(detail) {
  return `
    <div class="panel">
      <h2>Job ${escapeHtml(detail.id)}</h2>
      <div class="grid cols-2">
        <div class="kv"><strong>Status</strong><span>${renderBadge(detail.status)}</span></div>
        <div class="kv"><strong>Type</strong><span>${escapeHtml(detail.type || "-")}</span></div>
        <div class="kv"><strong>Request File</strong><span class="mono">${escapeHtml(detail.requestPath || "-")}</span></div>
        <div class="kv"><strong>Response File</strong><span class="mono">${escapeHtml(detail.responsePath || "-")}</span></div>
      </div>
      <div class="split">
        <div>
          <h3>Request JSON</h3>
          <pre>${escapeHtml(detail.requestJson || "(missing)")}</pre>
        </div>
        <div>
          <h3>Response JSON</h3>
          <pre>${escapeHtml(detail.responseJson || "(missing)")}</pre>
        </div>
      </div>
    </div>`;
}

function renderLogs(logs) {
  return `
    <div class="panel">
      <h2>Bridge Log</h2>
      <pre>${escapeHtml(logs || "(no logs)")}</pre>
    </div>`;
}

function renderStream(stream) {
  return `
    <div class="panel">
      <h2>Stream Output</h2>
      <pre>${escapeHtml(stream || "(no stream)")}</pre>
    </div>`;
}

function renderRequestForm(sessionPath, defaultPayload) {
  return `
    <div class="panel">
      <h2>Create Request</h2>
      <form method="post" action="/session/job">
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Type
          <select name="type">
            <option value="exec">exec</option>
            <option value="http">http</option>
            <option value="git">git</option>
            <option value="node">node</option>
            <option value="docker">docker</option>
            <option value="prompt">prompt</option>
            <option value="env">env</option>
            <option value="file">file</option>
          </select>
        </label>
        <label>
          Payload JSON (optional)
          <textarea name="payload" placeholder='{"command": "ls -la", "timeout": 30}'>${escapeHtml(defaultPayload || "")}</textarea>
        </label>
        <label>
          Quick command / URL / prompt
          <input type="text" name="quick" placeholder="command, url, or prompt" />
        </label>
        <label>
          Timeout (seconds)
          <input type="number" name="timeout" min="1" />
        </label>
        <label>
          Working directory (cwd)
          <input type="text" name="cwd" placeholder="~/projects/my-app" />
        </label>
        <button type="submit">Create Request</button>
      </form>
      <p class="notice">If payload JSON is provided, it takes precedence. Otherwise the quick field maps to <code>command</code>, <code>url</code>, or <code>prompt</code> depending on type.</p>
    </div>`;
}

function renderSessionTools({ sessionPath, presets, hasSessionConfig, configPath, configScope, isDirectBridge }) {
  if (!hasSessionConfig) {
    const reason = isDirectBridge
      ? "Session tools are unavailable in direct bridge mode. Start the UI without --bridgeDir or provide a --sessionsDir path."
      : `Missing cowork_settings.json. Looked for: ${configPath}`;
    return `
      <div class="panel">
        <h2>Session Tools</h2>
        <p class="notice">${escapeHtml(reason)}</p>
        <p class="notice">Open the session in Cowork and send one message to generate the config file.</p>
      </div>`;
  }

  const presetOptions = presets
    .map((preset) => `<option value="${escapeHtml(preset.value)}">${escapeHtml(preset.label)}</option>`)
    .join("");

  const scopeNote =
    configScope === "workspace"
      ? `<p class="panel-subtitle">Using workspace-level config: <code>${escapeHtml(configPath)}</code></p>`
      : `<p class="panel-subtitle">Using session config: <code>${escapeHtml(configPath)}</code></p>`;

  return `
    <div class="panel">
      <h2>Prompt Injection</h2>
      <p class="panel-subtitle">Swap system prompts for a single session.</p>
      ${scopeNote}
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="prompt-show" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">Show Current Prompt</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="prompt-inject" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Preset
          <select name="preset">
            <option value="">Select preset</option>
            ${presetOptions}
          </select>
        </label>
        <label>
          Or custom prompt file
          <input type="text" name="promptFile" placeholder="/path/to/prompt.json" />
        </label>
        <label class="switch">
          <span>Backup current prompt first</span>
          <input type="checkbox" name="backup" value="true" checked />
          <span class="switch-track"></span>
        </label>
        <label class="switch">
          <span>Dry run (preview only)</span>
          <input type="checkbox" name="dryRun" value="true" />
          <span class="switch-track"></span>
        </label>
        <div class="form-actions">
          <button type="submit">Inject Prompt</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="prompt-restore" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">Restore Prompt Backup</button>
        </div>
      </form>
    </div>
    <div class="panel">
      <h2>Session Config</h2>
      <p class="panel-subtitle">Model, mounts, and MCP tools for this session.</p>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-show" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">Show Config</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-model" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Model
          <select name="model">
            <option value="sonnet">sonnet</option>
            <option value="opus">opus</option>
            <option value="haiku">haiku</option>
          </select>
        </label>
        <div class="form-actions">
          <button type="submit">Update Model</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-approve-path" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Approve Path
          <input type="text" name="value" placeholder="~/projects" />
        </label>
        <div class="form-actions">
          <button type="submit">Approve Path</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-mount" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Mount Folder
          <input type="text" name="value" placeholder="~/Documents" />
        </label>
        <div class="form-actions">
          <button type="submit">Mount Folder</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-list-tools" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">List MCP Tools</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-enable-tool" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Enable Tool (hash)
          <input type="text" name="value" placeholder="tool-hash" />
        </label>
        <div class="form-actions">
          <button type="submit">Enable Tool</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-disable-tool" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Disable Tool (hash)
          <input type="text" name="value" placeholder="tool-hash" />
        </label>
        <div class="form-actions">
          <button type="submit">Disable Tool</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-backup" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">Backup Config</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="config-restore" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit" class="secondary">Restore Config</button>
        </div>
      </form>
    </div>
    <div class="panel">
      <h2>Bridge Setup</h2>
      <p class="panel-subtitle">Initialize or tear down bridge resources for this session.</p>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="bridge-init" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <div class="form-actions">
          <button type="submit">Initialize Bridge</button>
        </div>
      </form>
      <form method="post" action="/actions/session">
        <input type="hidden" name="action" value="bridge-env" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label>
          Env Key
          <input type="text" name="envKey" placeholder="API_KEY" />
        </label>
        <label>
          Env Value
          <input type="text" name="envValue" placeholder="value" />
        </label>
        <div class="form-actions">
          <button type="submit">Inject Env</button>
        </div>
      </form>
      <form method="post" action="/actions/session" data-confirm="Uninstall bridge from this session? This removes the .bridge folder and injected skill.">
        <input type="hidden" name="action" value="bridge-uninstall" />
        <input type="hidden" name="path" value="${escapeHtml(sessionPath)}" />
        <label class="switch">
          <span>Dry run</span>
          <input type="checkbox" name="dryRun" value="true" />
          <span class="switch-track"></span>
        </label>
        <div class="form-actions">
          <button type="submit" class="secondary">Uninstall Bridge (Session)</button>
        </div>
      </form>
    </div>`;
}

function renderGlobalDetails(details) {
  if (!details || !details.sessionId) {
    return `
      <div class="panel">
        <h2>Global Details</h2>
        <p class="panel-subtitle">No active sessions detected.</p>
        <p class="notice">Start a Cowork session to populate account/workspace details.</p>
      </div>`;
  }

  const installAction = `
    <div class="form-actions">
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="install-skill" />
        <input type="hidden" name="origin" value="/global" />
        <input type="hidden" name="sessionPath" value="${escapeHtml(details.sessionPath)}" />
        <button type="submit">${details.installExists ? "Reinstall Skill (Latest Session)" : "Install Skill for Latest Session"}</button>
      </form>
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="install-skill-all" />
        <input type="hidden" name="origin" value="/global" />
        <button type="submit" class="secondary">Install Skill for All Sessions</button>
      </form>
    </div>`;

  return `
    <div class="panel">
      <h2>Global Details</h2>
      <p class="panel-subtitle">Derived from the most recently modified session.</p>
      <div class="grid cols-2">
        <div class="kv">
          <strong>Account ID</strong>
          <span class="mono">${escapeHtml(details.accountId)}</span>
        </div>
        <div class="kv">
          <strong>Workspace ID</strong>
          <span class="mono">${escapeHtml(details.workspaceId)}</span>
        </div>
        <div class="kv">
          <strong>Session</strong>
          <span class="mono">${escapeHtml(details.sessionId)}</span>
        </div>
        <div class="kv">
          <strong>Skill Install Path</strong>
          <span class="mono">${escapeHtml(details.installPath)}</span>
        </div>
        <div class="kv">
          <strong>Skill Present</strong>
          <span>${details.installExists ? renderBadge("installed") : renderBadge("missing")}</span>
        </div>
      </div>
      ${installAction}
    </div>`;
}

function renderGlobalMaintenance() {
  return `
    <div class="panel">
      <h2>Global Maintenance</h2>
      <p class="panel-subtitle">Bulk setup and removal across all sessions.</p>
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="setup-all" />
        <input type="hidden" name="origin" value="/global" />
        <label class="switch">
          <span>Force re-setup of configured sessions</span>
          <input type="checkbox" name="force" value="true" />
          <span class="switch-track"></span>
        </label>
        <label class="switch">
          <span>Dry run</span>
          <input type="checkbox" name="dryRun" value="true" />
          <span class="switch-track"></span>
        </label>
        <div class="form-actions">
          <button type="submit">Setup All Sessions</button>
        </div>
      </form>
      <div class="divider"></div>
      <form method="post" action="/actions/global" data-confirm="Uninstall the bridge from ALL sessions? This removes .bridge folders and injected skills.">
        <input type="hidden" name="action" value="uninstall-all" />
        <input type="hidden" name="origin" value="/global" />
        <label class="switch">
          <span>Dry run</span>
          <input type="checkbox" name="dryRun" value="true" />
          <span class="switch-track"></span>
        </label>
        <div class="form-actions">
          <button type="submit" class="secondary">Uninstall Bridge (All Sessions)</button>
        </div>
      </form>
      <div class="divider"></div>
      <form method="post" action="/actions/global" data-confirm="Uninstall global components (skills, tools, daemon)?">
        <input type="hidden" name="action" value="uninstall-global" />
        <input type="hidden" name="origin" value="/global" />
        <label class="switch">
          <span>Dry run</span>
          <input type="checkbox" name="dryRun" value="true" />
          <span class="switch-track"></span>
        </label>
        <div class="form-actions">
          <button type="submit" class="secondary">Uninstall Global Components</button>
        </div>
      </form>
    </div>`;
}

function renderDaemonTools({ daemonStatus, daemonPlist }) {
  return `
    <div class="panel">
      <h2>Auto-Setup Daemon</h2>
      <p class="panel-subtitle">Manage the launchd service that auto-configures new sessions.</p>
      <p class="notice">Launchd plist: <code>${escapeHtml(daemonPlist)}</code></p>
      <p>Status: ${renderBadge(daemonStatus)}</p>
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="daemon-start" />
        <input type="hidden" name="origin" value="/daemon" />
        <div class="form-actions">
          <button type="submit">Start Daemon</button>
        </div>
      </form>
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="daemon-stop" />
        <input type="hidden" name="origin" value="/daemon" />
        <div class="form-actions">
          <button type="submit" class="secondary">Stop Daemon</button>
        </div>
      </form>
      <form method="post" action="/actions/global">
        <input type="hidden" name="action" value="daemon-status" />
        <input type="hidden" name="origin" value="/daemon" />
        <div class="form-actions">
          <button type="submit" class="secondary">Refresh Status</button>
        </div>
      </form>
    </div>`;
}

function renderWatcherTools({ watcherStatus, watcherPids, watcherLog }) {
  return `
    <div class="panel">
      <h2>Watcher</h2>
      <p class="panel-subtitle">Controls for the local CLI bridge watcher process.</p>
      <div class="grid cols-2">
        <div class="kv">
          <strong>Status</strong>
          <span>${renderBadge(watcherStatus)}</span>
        </div>
        <div class="kv">
          <strong>PIDs</strong>
          <span class="mono">${escapeHtml(watcherPids || "n/a")}</span>
        </div>
      </div>
      <div class="form-actions">
        <form method="post" action="/actions/global">
          <input type="hidden" name="action" value="watcher-start" />
          <input type="hidden" name="origin" value="/daemon" />
          <button type="submit">Start Watcher</button>
        </form>
        <form method="post" action="/actions/global">
          <input type="hidden" name="action" value="watcher-stop" />
          <input type="hidden" name="origin" value="/daemon" />
          <button type="submit" class="secondary">Stop Watcher</button>
        </form>
        <form method="post" action="/actions/global">
          <input type="hidden" name="action" value="watcher-restart" />
          <input type="hidden" name="origin" value="/daemon" />
          <button type="submit" class="secondary">Restart Watcher</button>
        </form>
      </div>
      ${watcherLog ? `<pre class="pre-scroll pre-wrap">${escapeHtml(watcherLog)}</pre>` : ""}
    </div>`;
}

function renderActionResult({ title, output, error, code, backLink }) {
  const crumbs = [];
  crumbs.push(`<a href="/">Sessions</a>`);
  if (backLink && backLink !== "/") {
    const label = backLink === "/global" ? "Global" : backLink === "/daemon" ? "Daemon" : "Session";
    crumbs.push(`<a href="${escapeHtml(backLink)}">${label}</a>`);
  }
  crumbs.push("Result");

  return `
    <div class="panel">
      <div class="breadcrumbs">${crumbs.join(" / ")}</div>
      <h2>${escapeHtml(title)}</h2>
      <p class="notice">Exit code: ${escapeHtml(code ?? "unknown")}</p>
      ${output ? `<h3>Output</h3><pre class="pre-scroll pre-wrap">${escapeHtml(output)}</pre>` : ""}
      ${error ? `<h3>Error</h3><pre class="pre-scroll pre-wrap">${escapeHtml(error)}</pre>` : ""}
      <p><a href="${escapeHtml(backLink)}">Back</a></p>
    </div>`;
}

module.exports = {
  renderBadge,
  renderSessions,
  renderSummary,
  renderJobs,
  renderSessionMeta,
  renderJobDetail,
  renderLogs,
  renderStream,
  renderRequestForm,
  renderSessionTools,
  renderGlobalDetails,
  renderGlobalMaintenance,
  renderDaemonTools,
  renderWatcherTools,
  renderActionResult
};
