FROM ubuntu:latest

# Install necessary packages including dos2unix and Node.js
RUN apt-get update && apt-get install -y \
    rsync \
    zip \
    git \
    curl \
    bash \
    luarocks \
    dos2unix \
    ca-certificates \
    gnupg \
    && luarocks install luacheck

# Install Node.js (required for Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app

# Copy the scripts into the container
COPY ./ci/scripts ./ci/scripts

# Convert line endings for consistency
RUN for script in ./ci/scripts/*.sh; do dos2unix "$script"; done

# Setup CI git config
RUN git config --global user.name "CI Bot"
RUN git config --global user.email ""

# Run chmod on the scripts
RUN chmod +x ./ci/scripts/*.sh

CMD ["bash"]
