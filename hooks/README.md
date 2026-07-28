# Git Hooks

This directory contains version-controlled Git hooks for the project.

## Installation

After cloning the repository or when hooks are updated, run:

```bash
npm run install:hooks
```

Or manually:

```bash
./hooks/install.sh
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

## For New Team Members

1. Clone the repository
2. Run `npm install`
3. Run `npm run dev` (hooks will be automatically applied - installed or skipped as needed)
4. You're ready to go! The pre-push hook will automatically run on every push.

**Note:** Hooks are automatically applied when you run `npm run dev`. The script will install hooks if needed or skip if already up to date. Manual installation is optional using `npm run install:hooks`.

**Worktree Support:** The installation script automatically detects Git worktrees and installs hooks in the main repository so they work across all worktrees.

## Benefits

- **Comprehensive validation** - Format, lint, type check, test, and code health analysis
- **Quality gates** - Prevent broken code from being pushed
- **Parallel execution** - Fast validation with parallel processing
- **Team consistency** - Everyone runs the same comprehensive checks
- **Early detection** - Catch issues before CI/CD
- **Zero setup friction** - Auto-installs on first `npm run dev`
- **No external dependencies** - Uses native Git hooks (no husky required)
