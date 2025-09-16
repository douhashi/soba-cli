#!/bin/bash

# Load message output functions
# Get the actual path of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/print_message.sh"

# Function to install npm global packages
# Usage: install_npm_global "ccmanager" "Claude Code Manager"
install_npm_global() {
    local package_name="$1"
    local description="$2"
    
    if [[ -z "$package_name" ]]; then
        print_error "Package name not specified"
        return 1
    fi
    
    # Set default description
    if [[ -z "$description" ]]; then
        description="$package_name"
    fi
    
    print_processing "Installing ${description}..."
    
    # Check if package is already installed
    if npm list -g "$package_name" > /dev/null 2>&1; then
        print_success "${description} is already installed"
        return 0
    fi
    
    # Install package
    if npm install -g "$package_name" > /dev/null 2>&1; then
        print_success "${description} installation completed"
        return 0
    else
        print_error "Failed to install ${description}"
        return 1
    fi
}

# Function to install multiple npm global packages at once
# Usage: install_npm_globals ("ccmanager:Claude Code Manager" "typescript:TypeScript")
install_npm_globals() {
    local packages=("$@")
    local failed_packages=()
    
    # Install each package
    for package_info in "${packages[@]}"; do
        # Separate package name and description
        local package_name="${package_info%%:*}"
        local description="${package_info#*:}"
        
        # Use package name if description is not specified
        if [[ "$package_name" == "$description" ]]; then
            description="$package_name"
        fi
        
        if ! install_npm_global "$package_name" "$description"; then
            failed_packages+=("$package_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_packages[@]} -eq 0 ]]; then
        return 0
    else
        print_error "Failed to install the following packages: ${failed_packages[*]}"
        return 1
    fi
}