#!/bin/bash
set -e

# Get base directory
BASE_DIR="$(dirname "$0")"

# Load functions
source "${BASE_DIR}/scripts/functions/print_message.sh"

# Soba CLI application setup
print_section "Soba CLI Application Setup"

# Navigate to workspace root directory
# BASE_DIR is .devcontainer/setup, so project root is 2 levels up
PROJECT_ROOT="$(cd "${BASE_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"
print_processing "Working directory: ${PROJECT_ROOT}"

# Load .envrc if it exists
if [[ -f ".envrc" ]]; then
    print_processing "Loading environment variables..."
    source .envrc
fi

# Install Ruby dependencies
print_subsection "Installing Ruby dependencies..."

if [[ -f "Gemfile" ]]; then
    print_processing "Installing gems..."
    if bundle install; then
        print_success "Gems installed successfully"
    else
        print_error "Error occurred during gem installation"
        exit 1
    fi
else
    print_warning "Gemfile not found"
fi

# Setup development tools
print_subsection "Setting up development tools..."

# Run Rubocop to check code style
if command -v rubocop &> /dev/null; then
    print_processing "Checking code style with Rubocop..."
    if bundle exec rubocop --auto-gen-config 2>/dev/null; then
        print_success "Rubocop configuration generated"
    else
        print_info "Rubocop configuration generation skipped"
    fi
fi

# Setup RSpec test framework
if [[ -f "spec/spec_helper.rb" ]] || [[ -f ".rspec" ]]; then
    print_processing "RSpec test framework detected"
    print_success "Ready to run tests with 'bundle exec rspec'"
fi

# Check for CLI executable
if [[ -f "bin/soba" ]]; then
    print_processing "Making CLI executable..."
    chmod +x bin/soba
    print_success "CLI executable ready at bin/soba"
fi

print_success "Soba CLI application setup completed"