#!/usr/bin/env node

const http = require("http");
const { execFile } = require("child_process");
const fs = require("fs");
const fsp = fs.promises;
const path = require("path");
const os = require("os");
const { layout } = require("./templates/layout");
const {
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
} = require("./templates/pages");

const args = parseArgs(process.argv.slice(2));
const bind = args.bind || "127.0.0.1";
const port = Number(args.port || 8787);
const repoRoot = path.resolve(__dirname, "..");
const sessionsDir =
  args.sessionsDir ||
  path.join(os.homedir(), "Library", "Application Support", "Claude", "local-agent-mode-sessions");
const claudeBase = path.dirname(sessionsDir);
const bridgeDir = args.bridgeDir ? path.resolve(args.bridgeDir) : null;
const authToken = args.token || "";
const launchdPlist = path.join(os.homedir(), "Library", "LaunchAgents", "com.claude.bridge-auto-setup.plist");

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.replace(/^--/, "");
    const value = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : true;
    result[key] = value;
    if (value !== true) i += 1;
  }
  return result;
}

function sendHtml(res, body, status = 200) {
  res.writeHead(status, { "Content-Type": "text/html; charset=utf-8" });
  res.end(body);
}

function sendText(res, body, status = 200) {
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" });
  res.end(body);
}

function sendJson(res, body, status = 200) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

function forbidden(res) {
  sendText(res, "Forbidden", 403);
}

function notFound(res) {
  sendText(res, "Not found", 404);
}

function formatDate(ts) {
  if (!ts) return "";
  try {
    const date = new Date(ts);
    return date.toLocaleString();
  } catch (err) {
    return String(ts);
  }
}

function isAuthorized(req) {
  if (!authToken) return true;
  const header = req.headers["x-bridge-token"] || "";
  if (header === authToken) return true;
  const cookies = parseCookies(req.headers.cookie || "");
  return cookies.bridge_token === authToken;
}

function parseCookies(header) {
  return header.split(";").reduce((acc, part) => {
    const [key, ...rest] = part.trim().split("=");
    if (!key) return acc;
    acc[key] = decodeURIComponent(rest.join("="));
    return acc;
  }, {});
}

function setAuthCookie(res) {
  if (!authToken) return;
  res.setHeader("Set-Cookie", `bridge_token=${encodeURIComponent(authToken)}; Path=/; SameSite=Lax; HttpOnly`);
}

function resolveSessionPath(inputPath) {
  if (!inputPath) return null;
  const resolved = path.resolve(inputPath);

  if (bridgeDir && resolved === bridgeDir) return resolved;

  const base = path.resolve(sessionsDir);
  if (resolved.startsWith(base)) return resolved;

  return null;
}

function getBridgeDir(sessionPath) {
  if (bridgeDir && sessionPath === bridgeDir) return bridgeDir;
  return path.join(sessionPath, "outputs", ".bridge");
}

async function safeReadDir(dirPath) {
  try {
    return await fsp.readdir(dirPath);
  } catch (err) {
    return [];
  }
}

async function safeStat(filePath) {
  try {
    return await fsp.stat(filePath);
  } catch (err) {
    return null;
  }
}

async function readJsonFile(filePath) {
  try {
    const raw = await fsp.readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch (err) {
    return null;
  }
}

async function getSessionConfigInfo(sessionPath) {
  const sessionConfig = path.join(sessionPath, "cowork_settings.json");
  if (await safeStat(sessionConfig)) {
    return { exists: true, path: sessionConfig, dir: sessionPath, scope: "session" };
  }

  const workspaceDir = path.dirname(sessionPath);
  const workspaceConfig = path.join(workspaceDir, "cowork_settings.json");
  if (await safeStat(workspaceConfig)) {
    return { exists: true, path: workspaceConfig, dir: workspaceDir, scope: "workspace" };
  }

  return { exists: false, path: sessionConfig, dir: sessionPath, scope: "missing" };
}

async function listPromptPresets() {
  const homePrompts = path.join(os.homedir(), ".claude", "prompts");
  const repoPrompts = path.join(repoRoot, "prompts");
  const baseDir = (await safeStat(homePrompts)) ? homePrompts : repoPrompts;
  const entries = await safeReadDir(baseDir);
  const presets = entries
    .filter((file) => file.endsWith(".json"))
    .map((file) => {
      const raw = file.replace(/\.json$/, "");
      const label = raw.replace(/-prompt$/, "");
      return {
        label,
        value: label,
        filePath: path.join(baseDir, file)
      };
    })
    .sort((a, b) => a.label.localeCompare(b.label));

  return presets;
}

function getSessionIdsFromPath(sessionPath) {
  const sessionDir = path.dirname(sessionPath);
  const innerId = path.basename(sessionDir);
  const outerId = path.basename(path.dirname(sessionDir));
  return { innerId, outerId };
}

function getPluginBaseForSession(sessionPath) {
  const { innerId, outerId } = getSessionIdsFromPath(sessionPath);
  const basePrimary = path.join(sessionsDir, "skills-plugin", innerId, outerId);
  const baseSecondary = path.join(sessionsDir, "skills-plugin", outerId, innerId);
  const baseLegacy = path.join(claudeBase, "skills-plugin", outerId, innerId, ".claude-plugin");

  if (fs.existsSync(basePrimary)) return basePrimary;
  if (fs.existsSync(baseSecondary)) return baseSecondary;
  if (fs.existsSync(baseLegacy)) return baseLegacy;
  return basePrimary;
}

function resolvePromptArg(presets, presetValue, promptFile) {
  if (promptFile) return expandHome(promptFile);
  if (!presetValue) return "";
  const known = new Set(["power-user", "power", "minimal", "min", "cli-mode", "cli"]);
  if (known.has(presetValue)) return presetValue;
  const match = presets.find((preset) => preset.value === presetValue);
  return match ? match.filePath : expandHome(presetValue);
}

function expandHome(value) {
  if (!value) return value;
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function execFileAsync(command, args, options = {}) {
  return new Promise((resolve) => {
    execFile(command, args, options, (error, stdout, stderr) => {
      const cleanStdout = stripAnsi(stdout || "");
      const cleanStderr = stripAnsi(stderr || "");
      resolve({
        ok: !error,
        code: error && typeof error.code === "number" ? error.code : 0,
        signal: error && error.signal ? error.signal : "",
        stdout: cleanStdout,
        stderr: cleanStderr || (error && error.message ? error.message : "")
      });
    });
  });
}

function stripAnsi(value) {
  return value.replace(
    /[\u001b\u009b][[\]()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g,
    ""
  );
}

async function runScript(scriptName, args, timeoutMs = 60000) {
  const scriptPath = path.join(repoRoot, "scripts", scriptName);
  return execFileAsync(scriptPath, args, { timeout: timeoutMs });
}

async function runLaunchctl(args, timeoutMs = 15000) {
  return execFileAsync("launchctl", args, { timeout: timeoutMs });
}

async function listSessions() {
  if (bridgeDir) {
    return [
      {
        id: "direct-bridge",
        path: bridgeDir,
        workspaceId: "direct",
        accountId: "direct",
        bridgeStatus: (await readJsonFile(path.join(bridgeDir, "status.json")))?.status || "unknown",
        modified: formatDate((await safeStat(bridgeDir))?.mtime)
      }
    ];
  }

  const accounts = await safeReadDir(sessionsDir);
  const sessions = [];

  for (const accountId of accounts) {
    const accountPath = path.join(sessionsDir, accountId);
    const workspaces = await safeReadDir(accountPath);

    for (const workspaceId of workspaces) {
      const workspacePath = path.join(accountPath, workspaceId);
      const locals = await safeReadDir(workspacePath);

      for (const local of locals) {
        if (!local.startsWith("local_")) continue;
        const sessionPath = path.join(workspacePath, local);
        const claudePath = path.join(sessionPath, ".claude");
        const hasClaude = await safeStat(claudePath);
        if (!hasClaude) continue;

        const bridgeStatus = (await readJsonFile(path.join(sessionPath, "outputs", ".bridge", "status.json")))?.status;
        const metaPath = path.join(workspacePath, `${local}.json`);
        const metaExists = Boolean(await safeStat(metaPath));
        const meta = metaExists ? await readJsonFile(metaPath) : null;
        const title = meta?.title || meta?.sessionTitle || meta?.name || "";
        const stat = await safeStat(sessionPath);

        sessions.push({
          id: local,
          path: sessionPath,
          workspaceId,
          accountId,
          metaPath,
          metaFile: `${local}.json`,
          metaExists,
          title,
          bridgeStatus: bridgeStatus || "missing",
          modified: formatDate(stat?.mtime)
        });
      }
    }
  }

  return sessions.sort((a, b) => (a.modified < b.modified ? 1 : -1));
}

async function summaryForSession(sessionPath) {
  const bridgeDir = getBridgeDir(sessionPath);
  const statusJson = await readJsonFile(path.join(bridgeDir, "status.json"));
  const requestsDir = path.join(bridgeDir, "requests");
  const responsesDir = path.join(bridgeDir, "responses");
  const streamsDir = path.join(bridgeDir, "streams");

  const requests = await safeReadDir(requestsDir);
  const responses = await safeReadDir(responsesDir);
  const streams = await safeReadDir(streamsDir);

  const lastActivity = await getLastActivity([responsesDir, requestsDir]);

  return {
    bridgeDir,
    status: statusJson?.status || "unknown",
    counts: {
      requests: requests.filter((f) => f.endsWith(".json")).length,
      responses: responses.filter((f) => f.endsWith(".json")).length,
      streams: streams.filter((f) => f.endsWith(".log")).length
    },
    lastActivity: lastActivity ? formatDate(lastActivity) : ""
  };
}

async function hasSessionConfig(sessionPath) {
  const configPath = path.join(sessionPath, "cowork_settings.json");
  return Boolean(await safeStat(configPath));
}

async function getDaemonStatus() {
  const plistExists = Boolean(await safeStat(launchdPlist));
  if (!plistExists) return "missing";
  const result = await runLaunchctl(["list"]);
  if (!result.ok) return "error";
  const lines = result.stdout.split(/\r?\n/);
  const label = "com.claude.bridge-auto-setup";
  return lines.some((line) => line.includes(label)) ? "loaded" : "unloaded";
}

async function getWatcherStatus() {
  const result = await execFileAsync("pgrep", ["-f", "cli-bridge/watcher.sh"]);
  if (!result.ok) {
    return { status: "stopped", pids: "" };
  }
  const pids = result.stdout.trim();
  return { status: pids ? "running" : "stopped", pids };
}

async function getLastActivity(dirs) {
  let latest = null;
  for (const dir of dirs) {
    const entries = await safeReadDir(dir);
    for (const entry of entries) {
      const stat = await safeStat(path.join(dir, entry));
      if (!stat) continue;
      if (!latest || stat.mtime > latest) {
        latest = stat.mtime;
      }
    }
  }
  return latest;
}

function deriveSummary(payload) {
  if (!payload) return "";
  if (payload.command) return truncate(payload.command, 64);
  if (payload.url) return truncate(payload.url, 64);
  if (payload.prompt) return truncate(payload.prompt, 64);
  if (payload.action && payload.path) return truncate(`${payload.action} ${payload.path}`, 64);
  if (payload.key) return truncate(`env ${payload.key}`, 64);
  return "";
}

function truncate(value, max) {
  if (!value) return "";
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}…`;
}

async function listJobs(sessionPath) {
  const bridgeDir = getBridgeDir(sessionPath);
  const requestsDir = path.join(bridgeDir, "requests");
  const responsesDir = path.join(bridgeDir, "responses");

  const requestFiles = (await safeReadDir(requestsDir)).filter((f) => f.endsWith(".json"));
  const responseFiles = (await safeReadDir(responsesDir)).filter((f) => f.endsWith(".json"));

  const ids = new Set();
  requestFiles.forEach((file) => ids.add(file.replace(/\.json$/, "")));
  responseFiles.forEach((file) => ids.add(file.replace(/\.json$/, "")));

  const jobs = [];
  for (const id of ids) {
    const requestPath = path.join(requestsDir, `${id}.json`);
    const responsePath = path.join(responsesDir, `${id}.json`);
    const processingPath = `${requestPath}.processing`;

    const requestJson = await readJsonFile(requestPath);
    const responseJson = await readJsonFile(responsePath);
    const isProcessing = await safeStat(processingPath);

    const status = responseJson?.status || (isProcessing ? "running" : requestJson ? "pending" : "unknown");
    const type = requestJson?.type || responseJson?.response_type || "";
    const updatedAtRaw = responseJson?.timestamp || requestJson?.timestamp || "";
    const summary = deriveSummary(requestJson || responseJson);

    jobs.push({
      id,
      status,
      type,
      updatedAt: updatedAtRaw ? formatDate(updatedAtRaw) : "",
      updatedAtMs: updatedAtRaw ? new Date(updatedAtRaw).getTime() : 0,
      summary,
      sessionPath
    });
  }

  return jobs.sort((a, b) => b.updatedAtMs - a.updatedAtMs);
}

async function getJobDetail(sessionPath, id) {
  const bridgeDir = getBridgeDir(sessionPath);
  const requestPath = path.join(bridgeDir, "requests", `${id}.json`);
  const responsePath = path.join(bridgeDir, "responses", `${id}.json`);

  const requestRaw = await safeReadFile(requestPath);
  const responseRaw = await safeReadFile(responsePath);
  const responseJson = await readJsonFile(responsePath);
  const requestJson = await readJsonFile(requestPath);

  return {
    id,
    status: responseJson?.status || (requestJson ? "pending" : "unknown"),
    type: requestJson?.type || responseJson?.response_type || "",
    requestPath: requestRaw ? requestPath : "",
    responsePath: responseRaw ? responsePath : "",
    requestJson: requestRaw,
    responseJson: responseRaw
  };
}

async function safeReadFile(filePath) {
  try {
    return await fsp.readFile(filePath, "utf8");
  } catch (err) {
    return "";
  }
}

async function tailFile(filePath, lines) {
  const content = await safeReadFile(filePath);
  if (!content) return "";
  const allLines = content.split(/\r?\n/);
  return allLines.slice(Math.max(0, allLines.length - lines)).join("\n");
}

function generateJobId() {
  const now = new Date();
  const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}-${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}${String(now.getSeconds()).padStart(2, "0")}`;
  const rand = Math.random().toString(16).slice(2, 6);
  return `job-${stamp}-${rand}`;
}

async function createRequest(sessionPath, form) {
  const bridgeDir = getBridgeDir(sessionPath);
  const requestsDir = path.join(bridgeDir, "requests");
  await fsp.mkdir(requestsDir, { recursive: true });

  const type = form.get("type") || "exec";
  const payloadRaw = form.get("payload") || "";
  const quick = form.get("quick") || "";
  const timeout = form.get("timeout");
  const cwd = form.get("cwd");

  let payload = {};

  if (payloadRaw.trim()) {
    payload = JSON.parse(payloadRaw);
  } else {
    if (quick) {
      if (type === "http") {
        payload.url = quick;
        payload.method = "GET";
      } else if (type === "prompt") {
        payload.prompt = quick;
      } else if (type === "env") {
        payload.key = quick;
        payload.value = "";
      } else if (type === "file") {
        payload.action = "read";
        payload.path = quick;
      } else {
        payload.command = quick;
      }
    }

    if (timeout) payload.timeout = Number(timeout);
    if (cwd) payload.cwd = cwd;
  }

  const id = generateJobId();
  const request = {
    ...payload,
    id,
    timestamp: new Date().toISOString(),
    type
  };

  const requestPath = path.join(requestsDir, `${id}.json`);
  await fsp.writeFile(requestPath, JSON.stringify(request, null, 2));

  return id;
}

async function handleRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  if (!isAuthorized(req)) {
    const token = url.searchParams.get("token");
    if (token && token === authToken) {
      setAuthCookie(res);
    } else {
      return forbidden(res);
    }
  }

  if (pathname.startsWith("/public/")) {
    const filePath = path.join(__dirname, pathname);
    if (!filePath.startsWith(path.join(__dirname, "public"))) return forbidden(res);
    const ext = path.extname(filePath);
    const contentType = ext === ".css" ? "text/css" : "application/javascript";
    const content = await safeReadFile(filePath);
    if (!content) return notFound(res);
    res.writeHead(200, { "Content-Type": `${contentType}; charset=utf-8` });
    return res.end(content);
  }

  if (pathname === "/") {
    const sessions = await listSessions();
    const body = renderSessions(sessions);
    return sendHtml(res, layout({ title: "Cowork Bridge UI", body, activeNav: "sessions" }));
  }

  if (pathname === "/global") {
    const body = `
      <div class="grid cols-2">
        <div hx-get="/global/details" hx-trigger="load, every 5s" hx-swap="innerHTML"></div>
        ${renderGlobalMaintenance()}
      </div>
    `;
    return sendHtml(res, layout({ title: "Global Maintenance", body, activeNav: "global" }));
  }

  if (pathname === "/global/details") {
    const sessions = await listSessions();
    const latest = sessions[0];
    let details = null;
    if (latest) {
      const ids = getSessionIdsFromPath(latest.path);
      const pluginBase = getPluginBaseForSession(latest.path);
      const installPath = path.join(pluginBase, "skills", "cowork-bridge");
      details = {
        sessionId: latest.id,
        sessionPath: latest.path,
        accountId: ids.outerId,
        workspaceId: ids.innerId,
        installPath,
        installExists: Boolean(await safeStat(installPath))
      };
    }
    return sendHtml(res, renderGlobalDetails(details));
  }

  if (pathname === "/daemon") {
    const body = `
      <div class="grid cols-2">
        <div hx-get="/daemon/auto-setup" hx-trigger="load, every 10s" hx-swap="innerHTML"></div>
        <div hx-get="/daemon/watcher" hx-trigger="load, every 5s" hx-swap="innerHTML"></div>
      </div>
    `;
    return sendHtml(res, layout({ title: "Daemon Management", body, activeNav: "daemon" }));
  }

  if (pathname === "/daemon/auto-setup") {
    const daemonStatus = await getDaemonStatus();
    return sendHtml(res, renderDaemonTools({ daemonStatus, daemonPlist: launchdPlist }));
  }

  if (pathname === "/daemon/watcher") {
    const watcher = await getWatcherStatus();
    const watcherLog = await tailFile("/tmp/cowork-bridge-watcher.log", 60);
    return sendHtml(
      res,
      renderWatcherTools({
        watcherStatus: watcher.status,
        watcherPids: watcher.pids,
        watcherLog
      })
    );
  }

  if (pathname === "/session") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    if (!sessionPath) return notFound(res);

    const presets = await listPromptPresets();
    const configInfo = await getSessionConfigInfo(sessionPath);
    const body = `
      <div class="tab-group" data-tab-group="session-${encodeURIComponent(sessionPath)}">
        <div class="tabs">
          <button class="tab-button" data-tab="overview" type="button">Overview</button>
          <button class="tab-button" data-tab="tools" type="button">Tools</button>
          <button class="tab-button" data-tab="jobs" type="button">Jobs</button>
          <button class="tab-button" data-tab="logs" type="button">Logs</button>
        </div>
        <div class="tab-panels">
          <section class="tab-panel" data-tab-panel="overview">
            <div class="grid cols-2">
              <div hx-get="/session/summary?path=${encodeURIComponent(sessionPath)}" hx-trigger="load, every 3s" hx-swap="innerHTML"></div>
              ${renderRequestForm(sessionPath)}
            </div>
          </section>
          <section class="tab-panel" data-tab-panel="tools">
            <div class="grid cols-2">
              ${renderSessionTools({
                sessionPath,
                presets,
                hasSessionConfig: configInfo.exists,
                configPath: configInfo.path,
                configScope: configInfo.scope,
                isDirectBridge: Boolean(bridgeDir)
              })}
            </div>
          </section>
          <section class="tab-panel" data-tab-panel="jobs">
            <div hx-get="/session/jobs?path=${encodeURIComponent(sessionPath)}" hx-trigger="load, every 3s" hx-swap="innerHTML"></div>
          </section>
          <section class="tab-panel" data-tab-panel="logs">
            <div hx-get="/session/logs?path=${encodeURIComponent(sessionPath)}" hx-trigger="load, every 5s" hx-swap="innerHTML"></div>
          </section>
        </div>
      </div>
    `;

    const page = layout({ title: "Session", body, activeNav: "sessions" });
    return sendHtml(res, page);
  }

  if (pathname === "/session/meta") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    if (!sessionPath) return notFound(res);
    const sessionId = path.basename(sessionPath);
    const metaPath = path.join(path.dirname(sessionPath), `${sessionId}.json`);
    const metaJson = await safeReadFile(metaPath);
    const metaParsed = await readJsonFile(metaPath);
    const title = metaParsed?.title || metaParsed?.sessionTitle || metaParsed?.name || "";
    let prettyJson = "";
    let systemPrompt = "";
    if (metaParsed) {
      const display = { ...metaParsed };
      if (display.systemPrompt) {
        systemPrompt = display.systemPrompt;
        display.systemPrompt = "(see System Prompt below)";
      }
      prettyJson = JSON.stringify(display, null, 2);
    }

    const body = renderSessionMeta({
      sessionId,
      title,
      metaPath: { filePath: metaPath, sessionPath },
      metaJson,
      prettyJson,
      systemPrompt
    });
    return sendHtml(res, layout({ title: `Session ${sessionId}`, body, activeNav: "sessions" }));
  }

  if (pathname === "/session/summary") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    if (!sessionPath) return notFound(res);
    const summary = await summaryForSession(sessionPath);
    return sendHtml(res, renderSummary(summary));
  }

  if (pathname === "/session/jobs") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    if (!sessionPath) return notFound(res);
    const jobs = await listJobs(sessionPath);
    return sendHtml(res, renderJobs(jobs));
  }

  if (pathname === "/session/job") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    const id = url.searchParams.get("id");
    if (!sessionPath || !id) return notFound(res);
    const detail = await getJobDetail(sessionPath, id);

    const body = `
      <a class="tag" href="/session?path=${encodeURIComponent(sessionPath)}">← Back to session</a>
      ${renderJobDetail(detail)}
      <div hx-get="/session/stream?path=${encodeURIComponent(sessionPath)}&id=${encodeURIComponent(id)}" hx-trigger="load, every 2s" hx-swap="innerHTML"></div>
      <div hx-get="/session/logs?path=${encodeURIComponent(sessionPath)}" hx-trigger="load, every 5s" hx-swap="innerHTML"></div>
    `;

    const page = layout({ title: `Job ${id}`, body, activeNav: "sessions" });
    return sendHtml(res, page);
  }

  if (pathname === "/session/stream") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    const id = url.searchParams.get("id");
    if (!sessionPath || !id) return notFound(res);
    const stream = await tailFile(path.join(getBridgeDir(sessionPath), "streams", `${id}.log`), 200);
    return sendHtml(res, renderStream(stream));
  }

  if (pathname === "/session/logs") {
    const sessionPath = resolveSessionPath(url.searchParams.get("path"));
    if (!sessionPath) return notFound(res);
    const logs = await tailFile(path.join(getBridgeDir(sessionPath), "logs", "bridge.log"), 200);
    return sendHtml(res, renderLogs(logs));
  }

  return notFound(res);
}

async function handlePost(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const body = await readBody(req);
  const form = new URLSearchParams(body);

  if (!isAuthorized(req)) {
    const token = form.get("token");
    if (token && token === authToken) {
      setAuthCookie(res);
    } else {
      return forbidden(res);
    }
  }

  if (url.pathname !== "/session/job") {
    if (url.pathname === "/actions/session") {
      return handleSessionAction(res, form);
    }
    if (url.pathname === "/actions/global") {
      return handleGlobalAction(res, form);
    }
    return notFound(res);
  }

  const sessionPath = resolveSessionPath(form.get("path"));
  if (!sessionPath) return notFound(res);

  try {
    const id = await createRequest(sessionPath, form);
    res.writeHead(302, { Location: `/session/job?path=${encodeURIComponent(sessionPath)}&id=${encodeURIComponent(id)}` });
    return res.end();
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create request";
    const bodyHtml = layout({
      title: "Error",
      body: `<div class="panel"><h2>Error</h2><pre>${message}</pre><a href="/session?path=${encodeURIComponent(sessionPath)}">Back</a></div>`,
      activeNav: "sessions"
    });
    return sendHtml(res, bodyHtml, 400);
  }
}

async function handleSessionAction(res, form) {
  const action = form.get("action");
  const sessionPath = resolveSessionPath(form.get("path"));
  if (!sessionPath || !action) return notFound(res);

  const configInfo = await getSessionConfigInfo(sessionPath);
  if (!configInfo.exists) {
    const body = renderActionResult({
      title: "Session Tools Unavailable",
      output: "",
      error: `This action requires cowork_settings.json. Looked for: ${configInfo.path}`,
      code: 1,
      backLink: "/"
    });
    return sendHtml(res, layout({ title: "Session Tools Unavailable", body, activeNav: "sessions" }));
  }

  const presets = await listPromptPresets();
  const configDir = configInfo.dir;
  let result;
  let title = "Action Result";
  let backLink = `/session?path=${encodeURIComponent(sessionPath)}`;

  try {
    switch (action) {
      case "prompt-show":
        title = "Show Prompt";
        result = await runScript("inject-prompt.sh", ["--session", sessionPath, "--show"], 15000);
        break;
      case "prompt-restore":
        title = "Restore Prompt";
        result = await runScript("inject-prompt.sh", ["--session", sessionPath, "--restore"], 15000);
        break;
      case "prompt-inject": {
        title = "Inject Prompt";
        const preset = form.get("preset");
        const promptFile = form.get("promptFile");
        const backup = form.get("backup") === "true";
        const dryRun = form.get("dryRun") === "true";
        const promptArg = resolvePromptArg(presets, preset, promptFile);
        if (!promptArg) throw new Error("Select a preset or provide a prompt file path.");
        const args = ["--session", sessionPath];
        if (backup) args.push("--backup");
        if (dryRun) args.push("--dry-run");
        args.push(promptArg);
        result = await runScript("inject-prompt.sh", args, 20000);
        break;
      }
      case "config-show":
        title = "Show Config";
        result = await runScript("inject-session.sh", ["--session", configDir, "show"], 15000);
        break;
      case "config-model": {
        title = "Update Model";
        const model = form.get("model") || "sonnet";
        result = await runScript("inject-session.sh", ["--session", configDir, "model", model], 15000);
        break;
      }
      case "config-approve-path": {
        title = "Approve Path";
        const value = form.get("value");
        if (!value) throw new Error("Provide a path to approve.");
        result = await runScript("inject-session.sh", ["--session", configDir, "approve-path", value], 15000);
        break;
      }
      case "config-mount": {
        title = "Mount Folder";
        const value = form.get("value");
        if (!value) throw new Error("Provide a folder path to mount.");
        result = await runScript("inject-session.sh", ["--session", configDir, "mount", value], 15000);
        break;
      }
      case "config-list-tools":
        title = "List MCP Tools";
        result = await runScript("inject-session.sh", ["--session", configDir, "list-tools"], 20000);
        break;
      case "config-enable-tool": {
        title = "Enable Tool";
        const value = form.get("value");
        if (!value) throw new Error("Provide a tool hash to enable.");
        result = await runScript("inject-session.sh", ["--session", configDir, "enable-tool", value], 15000);
        break;
      }
      case "config-disable-tool": {
        title = "Disable Tool";
        const value = form.get("value");
        if (!value) throw new Error("Provide a tool hash to disable.");
        result = await runScript("inject-session.sh", ["--session", configDir, "disable-tool", value], 15000);
        break;
      }
      case "config-backup":
        title = "Backup Config";
        result = await runScript("inject-session.sh", ["--session", configDir, "backup"], 15000);
        break;
      case "config-restore":
        title = "Restore Config";
        result = await runScript("inject-session.sh", ["--session", configDir, "restore"], 15000);
        break;
      case "bridge-init":
        title = "Initialize Bridge";
        result = await runScript("bridge-init.sh", [sessionPath], 30000);
        break;
      case "bridge-env": {
        title = "Inject Env Var";
        const key = form.get("envKey");
        const value = form.get("envValue");
        if (!key) throw new Error("Provide an env key.");
        result = await runScript("bridge-init.sh", ["--env", sessionPath, `${key}=${value || ""}`], 15000);
        break;
      }
      case "bridge-uninstall": {
        title = "Uninstall Bridge (Session)";
        const confirmed = form.get("confirmed") === "true";
        if (!confirmed) throw new Error("Confirmation required.");
        const dryRun = form.get("dryRun") === "true";
        const args = ["--session", sessionPath];
        if (dryRun) args.push("true");
        result = await runScript("bridge-uninstall.sh", args, 30000);
        break;
      }
      default:
        throw new Error(`Unknown action: ${action}`);
    }
  } catch (err) {
    result = {
      ok: false,
      code: 1,
      stdout: "",
      stderr: err instanceof Error ? err.message : String(err)
    };
  }

  const body = renderActionResult({
    title,
    output: result.stdout,
    error: result.stderr,
    code: result.code,
    backLink
  });
  return sendHtml(res, layout({ title, body, activeNav: "sessions" }));
}

async function handleGlobalAction(res, form) {
  const action = form.get("action");
  const origin = form.get("origin");
  let result;
  let title = "Global Action";
  let backLink = origin === "/daemon" || origin === "/global" ? origin : "/";

  try {
    switch (action) {
      case "setup-all": {
        title = "Setup All Sessions";
        const args = [];
        if (form.get("force") === "true") args.push("--force");
        if (form.get("dryRun") === "true") args.push("--dry-run");
        result = await runScript("setup-all-sessions.sh", args, 60000);
        break;
      }
      case "uninstall-all": {
        title = "Uninstall All Sessions";
        const confirmed = form.get("confirmed") === "true";
        if (!confirmed) throw new Error("Confirmation required.");
        const args = ["--all"];
        if (form.get("dryRun") === "true") args.push("true");
        result = await runScript("bridge-uninstall.sh", args, 60000);
        break;
      }
      case "uninstall-global": {
        title = "Uninstall Global Components";
        const confirmed = form.get("confirmed") === "true";
        if (!confirmed) throw new Error("Confirmation required.");
        const args = ["--global"];
        if (form.get("dryRun") === "true") args.push("true");
        result = await runScript("bridge-uninstall.sh", args, 60000);
        break;
      }
      case "install-skill": {
        title = "Install Skill (Latest Session)";
        const sessionPath = form.get("sessionPath");
        if (!sessionPath) throw new Error("Missing session path.");
        result = await runScript("bridge-init.sh", [sessionPath], 30000);
        break;
      }
      case "install-skill-all": {
        title = "Install Skill (All Sessions)";
        result = await runScript("setup-all-sessions.sh", ["--force"], 60000);
        break;
      }
      case "watcher-start":
        title = "Start Watcher";
        result = await runScript("watcher-control.sh", ["start"], 15000);
        break;
      case "watcher-stop":
        title = "Stop Watcher";
        result = await runScript("watcher-control.sh", ["stop"], 15000);
        break;
      case "watcher-restart":
        title = "Restart Watcher";
        result = await runScript("watcher-control.sh", ["restart"], 15000);
        break;
      case "daemon-start":
        title = "Start Auto-Setup Daemon";
        result = await runLaunchctl(["load", launchdPlist], 15000);
        break;
      case "daemon-stop":
        title = "Stop Auto-Setup Daemon";
        result = await runLaunchctl(["unload", launchdPlist], 15000);
        break;
      case "daemon-status":
        title = "Daemon Status";
        result = await runLaunchctl(["list"], 15000);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }
  } catch (err) {
    result = {
      ok: false,
      code: 1,
      stdout: "",
      stderr: err instanceof Error ? err.message : String(err)
    };
  }

  const body = renderActionResult({
    title,
    output: result.stdout,
    error: result.stderr,
    code: result.code,
    backLink
  });
  return sendHtml(res, layout({ title, body, activeNav: "sessions" }));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
    });
    req.on("end", () => resolve(data));
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "POST") {
      return await handlePost(req, res);
    }
    return await handleRequest(req, res);
  } catch (err) {
    const message = err instanceof Error ? err.stack : String(err);
    return sendHtml(res, layout({ title: "Error", body: `<div class="panel"><h2>Server error</h2><pre>${message}</pre></div>` }));
  }
});

server.listen(port, bind, () => {
  const mode = bridgeDir ? `direct bridge at ${bridgeDir}` : `sessions from ${sessionsDir}`;
  // eslint-disable-next-line no-console
  console.log(`Cowork Bridge UI listening on http://${bind}:${port} (${mode})`);
  if (authToken) {
    console.log("Auth enabled. Send X-Bridge-Token header.");
  }
});
