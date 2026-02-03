function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function layout({ title, body, activeNav }) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(title)}</title>
    <link rel="stylesheet" href="/public/styles.css" />
    <script src="/public/htmx-lite.js" defer></script>
    <script src="/public/ui.js" defer></script>
  </head>
  <body>
    <header>
      <h1>Cowork Bridge UI</h1>
      <p>Local dashboard for bridge sessions, requests, and streaming output.</p>
      <div class="nav-bar">
        <nav class="nav">
          <a href="/" class="${activeNav === "sessions" ? "active" : ""}">Sessions</a>
          <a href="/global" class="${activeNav === "global" ? "active" : ""}">Global</a>
          <a href="/daemon" class="${activeNav === "daemon" ? "active" : ""}">Daemon</a>
        </nav>
        <label class="switch theme-toggle">
          <span>Light mode</span>
          <input type="checkbox" id="theme-toggle" />
          <span class="switch-track"></span>
        </label>
      </div>
    </header>
    <main>
      ${body}
    </main>
    <dialog id="confirm-dialog">
      <div class="dialog-body">
        <h3>Confirm Action</h3>
        <p data-confirm-message>Are you sure?</p>
        <div class="dialog-actions">
          <button type="button" data-confirm-ok>Confirm</button>
          <button type="button" class="secondary" data-confirm-cancel>Cancel</button>
        </div>
      </div>
    </dialog>
  </body>
</html>`;
}

module.exports = {
  escapeHtml,
  layout
};
