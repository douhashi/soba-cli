#!/bin/bash
set -e

# Get base directory
BASE_DIR="$(dirname "$0")"

# Load functions
source "${BASE_DIR}/scripts/functions/print_message.sh"

# Rails application setup
print_section "Rails Application Setup"

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

# Execute Rails initial setup
print_subsection "Running Rails initial setup..."

if [[ -f "bin/setup" ]]; then
    # Execute bin/setup if it exists
    if bin/setup --skip-server; then
        print_success "Rails setup completed"
    else
        print_error "Error occurred during Rails setup"
        exit 1
    fi
else
    print_warning "bin/setup not found"
    
    # Alternative setup procedure
    print_subsection "Running alternative setup..."
    
    # Install bundle
    if [[ -f "Gemfile" ]]; then
        print_processing "Installing gems..."
        bundle install
    fi
    
    # Database setup
    if [[ -f "config/database.yml" ]]; then
        print_processing "Setting up database..."
        bin/rails db:create
        bin/rails db:migrate
    fi
    
    print_success "Alternative setup completed"
fi

print_success "Rails application setup completed"