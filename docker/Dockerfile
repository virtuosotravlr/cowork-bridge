# Cowork CLI Bridge - Host-side Container
# Runs the watcher and Claude CLI with full network access

FROM node:20-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Create app directory
WORKDIR /app

# Copy watcher script
COPY skills/cli-bridge/watcher.sh /app/watcher.sh
RUN chmod +x /app/watcher.sh

# Create bridge mount point
RUN mkdir -p /bridge

# Environment variables (override at runtime)
# Note: ANTHROPIC_API_KEY should be passed at runtime, not in Dockerfile
ENV BRIDGE_DIR="/bridge"
ENV POLL_INTERVAL="1"
ENV LOG_LEVEL="info"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD test -f /bridge/status.json && cat /bridge/status.json | jq -e '.status == "watching"' || exit 1

# Run watcher
CMD ["/app/watcher.sh", "/bridge"]
