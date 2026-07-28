# Git Hooks

This directory contains version-controlled Git hooks for the project.

## Installation

From the repository where the hook should be installed, run its setup command or:

```bash
bash path/to/codex-claude-utilities/hooks/install.sh
```

## Available Hooks

### pre-push

Runs before every `git push` and performs comprehensive code validation:

**Step 1: Core Validation (in parallel)**

1. **📝 Code formatting** - Auto-formats code with Prettier
2. **🔍 Linting** - ESLint validation for code quality
3. **🔍 TypeScript check** - Type compilation validation

**Step 2: Testing**

4. **🧪 Unit tests** - Runs all unit tests with Vitest

**Step 3: Code Health**

5. **🧹 Knip check** - Unused dependencies & dead code detection

If any check fails, the push is blocked until issues are resolved. The core validation runs in parallel for faster execution.

## In Consuming Repositories

The consuming repository decides when to invoke the installer, such as during its setup command or before starting development.

**Note:** The installer uses Git's common directory for the repository containing the current working directory and its own directory to source `pre-push`.

**Worktree Support:** The installation script installs hooks in the common Git directory so they work across all worktrees.

## Benefits

- **Comprehensive validation** - Format, lint, type check, test, and code health analysis
- **Quality gates** - Prevent broken code from being pushed
- **Parallel execution** - Fast validation with parallel processing
- **Team consistency** - Everyone runs the same comprehensive checks
- **Early detection** - Catch issues before CI/CD
- **No external dependencies** - Uses native Git hooks (no husky required)
