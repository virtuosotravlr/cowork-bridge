# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-01

### Added
- Initial public release
- CLI Bridge watcher with support for exec, http, git, node, docker, prompt, env, and file request types
- Streaming support for long-running commands and large outputs
- Auto-streaming for responses exceeding 50KB threshold
- Docker deployment option with docker-compose
- Session discovery and auto-setup daemon
- Comprehensive documentation and protocol specification
- Skills for both Cowork (sandboxed) and CLI (host) sides
- Prompt presets: power-user, cli-mode, minimal, unrestricted
- Install/uninstall scripts with launchd integration

### Security
- Command blocklist for dangerous operations
- Request type allowlisting
- Configurable timeout limits
- Audit logging to `.bridge/logs/`
- ENV requests blocked in Docker mode (no session path available)

### Documentation
- Quick start guide
- Full protocol specification
- Architecture overview
- Security policy
- Contributing guidelines
- Code of conduct
