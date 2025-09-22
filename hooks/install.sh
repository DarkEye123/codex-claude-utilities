#!/bin/bash

# Install git hooks for the project (install if needed, skip if already installed)
# Run this script after cloning or to update hooks

# Handle worktrees properly - hooks should be in main repository
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Check if we're in a worktree
  if [ -f .git ] && grep -q "gitdir:" .git; then
    # We're in a worktree - use main repository's hooks directory
    MAIN_GIT_DIR=$(git rev-parse --git-common-dir)
    GIT_DIR="$MAIN_GIT_DIR"
    LOCATION_MSG="worktree - installing hooks in main repository"
  else
    # We're in main repository
    GIT_DIR=$(git rev-parse --git-dir)
    LOCATION_MSG="main repository"
  fi
else
  echo "❌ Not in a Git repository"
  exit 1
fi

HOOK_PATH="$GIT_DIR/hooks/pre-push"

# Ensure Git uses default hooks path (not husky's custom path)
if [ "$(git config core.hooksPath)" != "" ]; then
  echo "🔧 Resetting Git to use default hooks path (removing husky configuration)"
  git config --unset core.hooksPath
fi

# Check if hook already exists and is up to date
if [ -f "$HOOK_PATH" ]; then
  # Compare with our version to see if update is needed
  if cmp -s "hooks/pre-push" "$HOOK_PATH" 2>/dev/null; then
    echo "✅ Git hooks already up to date (skipping installation)"
    exit 0
  else
    echo "🔄 Updating existing git hooks..."
  fi
else
  echo "📦 Installing git hooks..."
  echo "📁 Detected $LOCATION_MSG"
fi

# Create hooks directory if it doesn't exist
mkdir -p "$GIT_DIR/hooks"

# Copy and make executable
cp hooks/pre-push "$HOOK_PATH"
chmod +x "$HOOK_PATH"

echo "🔗 Hook installed at: $HOOK_PATH"

echo "✅ Git hooks installed successfully!"
echo "The pre-push hook will now run comprehensive validation in parallel on every push:"
echo "   • Code formatting (prettier)"  
echo "   • Linting (eslint)"
echo "   • TypeScript compilation"
echo "   • Unit tests (vitest)"
echo "   • Code health analysis (knip)"