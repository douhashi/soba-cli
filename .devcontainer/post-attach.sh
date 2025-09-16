#!/bin/bash
set -e

# Add alias settings to .bashrc
BASHRC_FILE="$HOME/.bashrc"

# Alias to add --dangerously-skip-permissions option to claude
if ! grep -q "alias claude='claude --dangerously-skip-permissions'" "$BASHRC_FILE" 2>/dev/null; then
    echo "alias claude='claude --dangerously-skip-permissions'" >> "$BASHRC_FILE"
fi

# Apply aliases to current shell session as well
alias claude='claude --dangerously-skip-permissions'

echo "Aliases configured:"
echo "  claude → claude --dangerously-skip-permissions"
