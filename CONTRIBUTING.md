# Contributing to Cowork Bridge

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch (`git checkout -b feature/amazing-feature`)
4. Make your changes
5. Test your changes
6. Commit with a clear message
7. Push to your fork
8. Open a Pull Request

## Development Setup

### Prerequisites

- macOS (primary supported platform)
- Bash 4.0+
- `jq` for JSON processing
- `curl` for HTTP requests
- Docker (optional, for containerized deployment)

### Local Development

```bash
# Clone the repository
git clone https://github.com/yourusername/cowork-bridge.git
cd cowork-bridge

# Make scripts executable
chmod +x scripts/*.sh
chmod +x skills/cli-bridge/*.sh

# Run the installer
./scripts/install.sh
```

## Code Style

### Shell Scripts

- Use `#!/bin/bash` shebang for bash-specific features
- Use `#!/bin/sh` for POSIX-compatible scripts
- Indent with 2 spaces
- Use meaningful variable names in `UPPER_CASE` for constants, `lower_case` for locals
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals in bash
- Add comments for non-obvious logic

### Commit Messages

Follow conventional commits format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, no code change
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance tasks

Examples:
```
feat(watcher): add support for file operations
fix(scripts): handle spaces in session paths
docs(readme): add troubleshooting section
```

## Testing

### ShellCheck

All shell scripts should pass ShellCheck:

```bash
# Install shellcheck
brew install shellcheck

# Run on all scripts
shellcheck scripts/*.sh skills/*/*.sh
```

### Manual Testing

1. Start a Cowork session
2. Run the installer: `./scripts/install.sh --full`
3. Verify bridge initialization
4. Test request/response flow

## Pull Request Process

1. **Update documentation** if you change functionality
2. **Add tests** if applicable
3. **Update CHANGELOG.md** with your changes
4. **Ensure ShellCheck passes** on all modified scripts
5. **Request review** from maintainers

### PR Checklist

- [ ] Code follows the project style guidelines
- [ ] ShellCheck passes without errors
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated
- [ ] Tested locally

## Reporting Issues

### Bug Reports

Please include:
- macOS version
- Shell version (`bash --version`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs from `.bridge/logs/`

### Feature Requests

- Describe the use case
- Explain the expected behavior
- Consider if it fits the project scope

## Questions?

Open an issue with the `question` label or start a discussion.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
