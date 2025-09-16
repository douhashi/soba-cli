#!/bin/bash
set -e

# Get base directory
BASE_DIR="$(dirname "$0")"

# Load functions
source "${BASE_DIR}/scripts/functions/print_message.sh"

# MCP server setup
print_section "MCP Server Setup"

# Install MCP servers
print_subsection "Installing MCP servers..."

# Execute MCP server setup scripts
for setup_script in "${BASE_DIR}/scripts/setup/"mcp-*.sh; do
    if [[ -f "$setup_script" ]]; then
        print_processing "Processing $(basename "$setup_script")..."
        
        # Make script executable
        chmod +x "$setup_script"
        
        # Execute script
        if "$setup_script" >&2; then
            echo -e "${GREEN}    ✓ Done${NC}"
        else
            print_warning "Failed to execute $(basename "$setup_script")"
        fi
    fi
done

print_success "MCP server setup completed"