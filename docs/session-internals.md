# Session internals

This project relies on files inside Cowork session directories. These locations can change over time, so treat them as implementation details.

## Session layout on host

```
~/Library/Application Support/Claude/local-agent-mode-sessions/
  <account-id>/<workspace-id>/local_<session-id>/
```

Key files:
- `cowork_settings.json` (system prompt, model, tools, mounts)
- `.claude/settings.json` (env injection into the VM)
- `outputs/.bridge/` (request/response queue)

## System prompt injection

Use `cowork-inject-prompt` to swap prompts:

```bash
cowork-inject-prompt --list
cowork-inject-prompt --backup power-user
cowork-inject-prompt --restore
```

Prompt presets live in `prompts/` and are installed to `~/.claude/prompts/`.

## Session config injection

Use `cowork-session-config` to edit `cowork_settings.json`:

```bash
cowork-session-config show
cowork-session-config model sonnet
cowork-session-config approve-path ~/projects
cowork-session-config mount ~/Documents
cowork-session-config list-tools
```

Supported commands include `show`, `model`, `prompt`, `approve-path`, `mount`, `enable-tool`, `disable-tool`, `list-tools`, `backup`, `restore`, and `edit`.

## Env var injection

Write to `.claude/settings.json` in the session directory:

```bash
echo '{"env": {"MY_VAR": "value"}}' > "<session>/.claude/settings.json"
```

Changes apply on the next Cowork message.

## Skills plugin path

Skills are registered under:

```
~/Library/Application Support/Claude/skills-plugin/
  <workspace-id>/<account-id>/.claude-plugin/
```

Note the order: workspace id, then account id.
