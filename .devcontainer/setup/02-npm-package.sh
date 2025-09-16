#!/bin/bash
set -e

# Get base directory
BASE_DIR="$(dirname "$0")"

# Load functions
source "${BASE_DIR}/scripts/functions/print_message.sh"
source "${BASE_DIR}/scripts/functions/install_npm.sh"

# Install NPM packages
print_section "Installing NPM Packages"

# Install npm global packages
print_subsection "Installing npm global packages"

# Claude-related packages
install_npm_globals \
    "@anthropic-ai/claude-code:Claude Code" \
    "ccmanager:Claude Code Manager"

print_success "NPM packages installation completed"