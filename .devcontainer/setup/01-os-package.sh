#!/bin/bash
set -e

# Get base directory
BASE_DIR="$(dirname "$0")"

# Load functions
source "${BASE_DIR}/scripts/functions/print_message.sh"
source "${BASE_DIR}/scripts/functions/install_apt.sh"

# Install OS packages
print_section "Installing OS Packages"

# Install Git LFS
print_subsection "Installing Git Large File Storage"
install_apt_packages \
    "git-lfs:Git Large File Storage"

print_success "OS packages installation completed"