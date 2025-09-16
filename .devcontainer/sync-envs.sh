#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Path to .tool-versions and .env files
TOOL_VERSIONS_FILE="$PROJECT_ROOT/.tool-versions"
ENV_FILE="$SCRIPT_DIR/.env"

# Check if .tool-versions exists
if [ ! -f "$TOOL_VERSIONS_FILE" ]; then
    echo "Error: .tool-versions file not found at $TOOL_VERSIONS_FILE"
    exit 1
fi

# Extract Ruby version from .tool-versions
RUBY_VERSION=$(grep "^ruby " "$TOOL_VERSIONS_FILE" | awk '{print $2}')

if [ -z "$RUBY_VERSION" ]; then
    echo "Error: Ruby version not found in .tool-versions"
    exit 1
fi

echo "Found Ruby version: $RUBY_VERSION"

# Get compose project name from directory
COMPOSE_PROJECT_NAME=$(basename "$PROJECT_ROOT")
echo "Found compose project name: $COMPOSE_PROJECT_NAME"

# Create or update .env file
if [ -f "$ENV_FILE" ]; then
    # Update existing RUBY_VERSION line or add if not exists
    if grep -q "^RUBY_VERSION=" "$ENV_FILE"; then
        sed -i "s/^RUBY_VERSION=.*/RUBY_VERSION=$RUBY_VERSION/" "$ENV_FILE"
        echo "Updated RUBY_VERSION in $ENV_FILE"
    else
        echo "RUBY_VERSION=$RUBY_VERSION" >> "$ENV_FILE"
        echo "Added RUBY_VERSION to $ENV_FILE"
    fi
    
    # Update existing COMPOSE_PROJECT_NAME line or add if not exists
    if grep -q "^COMPOSE_PROJECT_NAME=" "$ENV_FILE"; then
        sed -i "s/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME/" "$ENV_FILE"
        echo "Updated COMPOSE_PROJECT_NAME in $ENV_FILE"
    else
        echo "COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME" >> "$ENV_FILE"
        echo "Added COMPOSE_PROJECT_NAME to $ENV_FILE"
    fi
else
    # Create new .env file
    echo "RUBY_VERSION=$RUBY_VERSION" > "$ENV_FILE"
    echo "COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME" >> "$ENV_FILE"
    echo "Created $ENV_FILE with RUBY_VERSION and COMPOSE_PROJECT_NAME"
fi

echo "Environment variables synchronized successfully!"
