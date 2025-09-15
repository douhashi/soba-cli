#!/bin/bash
# Setup script for Git hooks

echo "Setting up Git hooks for soba project..."

# Create hooks directory if it doesn't exist
mkdir -p .git/hooks

# Create pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
# pre-commit hook for soba project
# Run RuboCop with auto-correct before every commit

# Check if we're in the correct directory
if [ ! -f "Gemfile" ]; then
  echo "Error: Gemfile not found. Are you in the project root?"
  exit 1
fi

echo "🔍 Running RuboCop..."

# Get list of staged Ruby files
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.rb$\|\.rake$\|Rakefile$\|Gemfile$' | tr '\n' ' ')

if [ -z "$staged_files" ]; then
  echo "No Ruby files to check."
  exit 0
fi

# First, run RuboCop without auto-correct to check for offenses
bundle exec rubocop $staged_files > /tmp/rubocop_output.txt 2>&1
initial_exit_code=$?

if [ $initial_exit_code -eq 0 ]; then
  echo "✅ RuboCop check passed!"
  exit 0
fi

# If there are offenses, try auto-correct
echo "🔧 Running RuboCop with auto-correct..."
bundle exec rubocop --autocorrect-all $staged_files > /tmp/rubocop_autocorrect.txt 2>&1
autocorrect_exit_code=$?

# Check if files were modified by auto-correct
modified_files=$(git diff --name-only $staged_files)

if [ -n "$modified_files" ]; then
  echo ""
  echo "📝 RuboCop has automatically fixed some issues in the following files:"
  echo "$modified_files" | sed 's/^/   - /'
  echo ""
  echo "⚠️  These fixes have NOT been staged for commit."
  echo ""
  echo "To include these fixes in your commit, please:"
  echo "  1. Review the changes: git diff"
  echo "  2. Stage the fixed files: git add $modified_files"
  echo "  3. Commit again: git commit"
  echo ""
  exit 1
fi

# If auto-correct couldn't fix everything, show remaining issues
if [ $autocorrect_exit_code -ne 0 ]; then
  echo ""
  echo "❌ RuboCop found issues that couldn't be auto-fixed:"
  cat /tmp/rubocop_autocorrect.txt
  echo ""
  echo "Please fix these issues manually before committing."
  exit 1
fi

echo "✅ All RuboCop issues were auto-corrected and no changes needed!"
exit 0
EOF

# Make hook executable
chmod +x .git/hooks/pre-commit

echo "✅ Git hooks setup complete!"
echo ""
echo "The pre-commit hook will:"
echo "  - Run RuboCop on staged Ruby files before each commit"
echo "  - Automatically fix correctable issues"
echo "  - Prompt you to stage auto-fixed files if changes were made"
echo "  - Block commits only for issues that can't be auto-fixed"
echo ""
echo "To bypass the hook (not recommended), use: git commit --no-verify"