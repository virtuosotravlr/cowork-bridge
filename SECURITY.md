# Security Policy

## Important Notice

**Cowork Bridge is a power-user tool that intentionally bypasses sandbox restrictions.** By design, it grants the sandboxed Cowork VM access to execute commands on your host machine with your user privileges.

This is not a bug—it's the core feature. Use it responsibly.

## Security Model

### What the bridge enables

- Arbitrary shell command execution on your host
- HTTP requests to any endpoint
- Git operations with your credentials
- Docker container execution
- File read/write on your host filesystem
- Claude CLI invocation with full capabilities

### Built-in safeguards

The watcher includes basic protections:

- Blocklist for obviously destructive commands
- Configurable timeout limits
- Request type allowlisting
- Audit logging to `.bridge/logs/`

These are **not** security boundaries—they're footgun prevention for common mistakes.

## Recommendations

1. **Review requests**: Check `.bridge/logs/bridge.log` periodically
2. **Limit scope**: Use the watcher only when needed, stop it when not in use
3. **Docker mode**: Run the watcher in Docker to isolate from your main system
4. **Network segmentation**: If running in Docker, limit network access as appropriate

## Reporting Vulnerabilities

If you discover a security issue, please report it by:

1. **Do not** open a public issue for sensitive vulnerabilities
2. Open a [GitHub issue](https://github.com/virtuosotravlr/cowork-bridge/issues) with the `security` label
3. Include steps to reproduce and potential impact

We will respond within 7 days and work with you on a fix.

## Scope

Security reports should focus on:

- Vulnerabilities that bypass intended safeguards
- Issues that could cause unintended data exposure
- Bugs in the blocklist or validation logic

Out of scope:

- The fundamental design (executing commands on the host is intentional)
- Social engineering the Cowork VM into making bad requests
