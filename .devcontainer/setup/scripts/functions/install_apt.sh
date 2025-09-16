#!/bin/bash

# Load message output functions
# Get the actual path of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/print_message.sh"

# Function to install apt packages
# Usage: install_apt_package "jq" "JSON processor"
install_apt_package() {
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
    if dpkg -l | grep -q "^ii  $package_name "; then
        print_success "${description} is already installed"
        return 0
    fi
    
    # Install package
    if sudo apt-get install -y "$package_name" > /dev/null 2>&1; then
        print_success "${description} installation completed"
        return 0
    else
        print_error "Failed to install ${description}"
        return 1
    fi
}

# Function to install multiple apt packages at once
# Usage: install_apt_packages ("jq:JSON processor" "curl:HTTP client")
install_apt_packages() {
    local packages=("$@")
    local failed_packages=()
    
    # Execute apt update
    print_processing "Updating package list..."
    if ! sudo apt-get update > /dev/null 2>&1; then
        print_warning "Failed to update package list"
    fi
    
    # Install each package
    for package_info in "${packages[@]}"; do
        # Separate package name and description
        local package_name="${package_info%%:*}"
        local description="${package_info#*:}"
        
        # Use package name if description is not specified
        if [[ "$package_name" == "$description" ]]; then
            description="$package_name"
        fi
        
        if ! install_apt_package "$package_name" "$description"; then
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