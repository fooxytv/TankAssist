#!/bin/bash

# Load .env file, stripping quotes from values
if [ -f .env ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Remove carriage returns and whitespace from key
        key=$(echo "$key" | tr -d '\r' | xargs)
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove carriage returns, surrounding quotes from value
        value=$(echo "$value" | tr -d '\r')
        value="${value%\"}"
        value="${value#\"}"
        # Only export if key is a valid identifier
        if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            export "$key=$value"
        fi
    done < .env
else
    echo "Warning: .env file not found. Using defaults."
fi

image_name="${1:-tankassist-ci}"
dockerfile_path="./ci/build/Dockerfile"

# Convert Windows path to lowercase Unix style (/c/Users/... instead of /C/Users/...)
current_path=$(pwd)
if [[ "$current_path" =~ ^/([a-zA-Z])/ ]]; then
    drive_letter="${BASH_REMATCH[1],,}"  # lowercase
    path_without_drive="${current_path:2}"
    project_dir="/${drive_letter}${path_without_drive}"
else
    project_dir="$current_path"
fi

echo "Building Docker image: $image_name"
docker buildx build -t $image_name -f $dockerfile_path .

if [[ $? -ne 0 ]]; then
    echo "Docker build failed."
    exit 1
fi

# Extract unique drive letters from all paths (Windows/WSL support)
declare -A drives
extract_drive() {
    if [[ "$1" =~ ^/([a-zA-Z])/ ]]; then
        # Use lowercase to match Git Bash paths (/c/ not /C/)
        drives["${BASH_REMATCH[1],,}"]=1
    fi
}

# Add project directory drive
extract_drive "$project_dir"

# Add common WoW addon directories if set
if [[ -n "$wow_addons_dir_retail" ]]; then
    extract_drive "$wow_addons_dir_retail"
fi
if [[ -n "$wow_addons_dir_ptr" ]]; then
    extract_drive "$wow_addons_dir_ptr"
fi

# Build volume arguments for each unique drive
volume_args=""
for drive in "${!drives[@]}"; do
    volume_args="$volume_args -v /${drive}:/${drive}"
done

echo "Running Docker container and mounting project directory.."
echo "Project dir: $project_dir"
if [[ -n "${!drives[*]}" ]]; then
    echo "Mounting drives: ${!drives[*]}"
fi

# Pass Claude Code credentials
env_args=""
claude_volume=""

# Option 1: API key from environment
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    env_args="-e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
    echo "Claude Code API key detected."
# Option 2: Mount existing Claude config (from OAuth login)
elif [[ -d "$HOME/.claude" ]]; then
    claude_volume="-v $HOME/.claude:/root/.claude:ro"
    echo "Mounting Claude config from ~/.claude"
fi

docker run --rm -ti \
    $volume_args \
    $env_args \
    $claude_volume \
    -w "$project_dir" \
    $image_name bash

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to start Docker container."
    exit 1
fi
