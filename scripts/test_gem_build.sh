#!/usr/bin/env bash

# Test script for gem build, install, and uninstall process
# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
success() {
  echo -e "${GREEN}✓${NC} $1"
}

error() {
  echo -e "${RED}✗${NC} $1"
  exit 1
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# Header
echo "=================================="
echo "Soba Gem Build & Install Test"
echo "=================================="
echo ""

# Store current directory
CURRENT_DIR=$(pwd)

# Check if we're in the project root
if [[ ! -f "soba.gemspec" ]]; then
  error "soba.gemspec not found. Please run this script from the project root."
fi

# Clean up any existing gem files
info "Cleaning up existing gem files..."
rm -f soba-*.gem
success "Cleanup completed"
echo ""

# Step 1: Build the gem
info "Building soba gem..."
if gem build soba.gemspec; then
  success "Gem built successfully"
else
  error "Failed to build gem"
fi
echo ""

# Find the built gem file
GEM_FILE=$(ls soba-*.gem 2>/dev/null | head -n 1)
if [[ -z "$GEM_FILE" ]]; then
  error "No gem file found after build"
fi
info "Built gem: $GEM_FILE"
echo ""

# Step 2: Install the gem locally
info "Installing soba gem locally..."
if gem install "./$GEM_FILE"; then
  success "Gem installed successfully"
else
  error "Failed to install gem"
fi
echo ""

# Step 3: Verify installation
info "Verifying installation..."

# Check if soba command is available
if which soba > /dev/null 2>&1; then
  success "soba command found at: $(which soba)"
else
  error "soba command not found in PATH"
fi

# Check version
info "Checking soba version..."
if soba --version; then
  success "Version command executed successfully"
else
  error "Failed to execute version command"
fi
echo ""

# Check help
info "Checking soba help..."
if soba --help > /dev/null 2>&1; then
  success "Help command executed successfully"
else
  error "Failed to execute help command"
fi
echo ""

# Step 4: Test basic commands (without side effects)
info "Testing basic commands..."

# Test config show (read-only command)
if soba config show > /dev/null 2>&1; then
  success "config show command executed successfully"
else
  # This might fail if config doesn't exist, which is OK
  info "config show command failed (this is expected if config doesn't exist)"
fi
echo ""

# Step 5: List installed gems
info "Listing installed soba gem..."
if gem list | grep -q "soba"; then
  gem list | grep soba
  success "Gem appears in installed list"
else
  error "Gem not found in installed list"
fi
echo ""

# Step 6: Uninstall the gem
info "Uninstalling soba gem..."
if gem uninstall soba -x; then
  success "Gem uninstalled successfully"
else
  error "Failed to uninstall gem"
fi
echo ""

# Step 7: Verify uninstallation
info "Verifying uninstallation..."
if which soba > /dev/null 2>&1; then
  error "soba command still found after uninstall"
else
  success "soba command removed successfully"
fi

if gem list | grep -q "soba"; then
  error "Gem still appears in installed list"
else
  success "Gem removed from installed list"
fi
echo ""

# Summary
echo "=================================="
echo "Test Results Summary"
echo "=================================="
success "All tests passed!"
echo ""
info "The following operations were verified:"
echo "  • Gem build from gemspec"
echo "  • Local gem installation"
echo "  • Command availability in PATH"
echo "  • Version and help commands"
echo "  • Basic command execution"
echo "  • Gem uninstallation"
echo "  • Cleanup verification"
echo ""
success "Soba gem is ready for distribution!"