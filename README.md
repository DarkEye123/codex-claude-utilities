# Utilities

Bash helpers that automate common repository maintenance tasks.

## Scripts

### create_agents.sh
Copies every `CLAUDE.md` discovered under a root directory and writes a sibling `AGENTS.md` with identical contents. Uses a single `find` invocation and supports repeatable exclude patterns.

```
$ bash create_agents.sh --help
Usage: create_agents.sh [--exclude <pattern>]... [root]

Options:
  -x, --exclude <pattern>   Exclude paths matching pattern (repeatable)
  -h, --help                Show this help and exit

Examples:
  create_agents.sh
  create_agents.sh --exclude worktrees
  create_agents.sh -x worktrees -x node_modules ./
```

### create_worktree.sh
Creates a git worktree rooted under `./worktrees/<name>`, copies every top-level `.env*` file into the new worktree, and optionally copies `node_modules`. Handles branch creation from local refs, remotes, or a `--base` branch and supports skipping fetches.

```
$ bash create_worktree.sh --help
create_worktree.sh (v2.0.1 (2025-09-12))

Usage: create_worktree.sh <worktree_name> [branch_name] [options]

Creates a git worktree and copies all top-level .env* files. Optional node_modules copy (-c).

Positional:
    worktree_name          Name for the new worktree (required)
    branch_name            Existing or new branch (defaults to worktree_name)

Options:
    -c                     Copy node_modules directory recursively
    --base <branch>        Base branch for newly created branch (if target doesn't exist)
    --no-fetch             Skip 'git fetch' (default is to fetch)
    --help                 Show this help and exit

Behavior:
    - Fails if worktree path exists or branch already attached elsewhere
    - Copies every file matching ./.env* (no filtering) as requested

Examples:
    create_worktree.sh feature-x
    create_worktree.sh feature-x origin/develop
    create_worktree.sh feature-x -c --base origin/main
```

## Hooks

### hooks/install.sh
Installs the native Git hooks by copying `hooks/pre-push` into the repository's `.git/hooks` directory. The script detects worktrees, installs into the main repository git dir, resets any custom `core.hooksPath`, and skips copying when the hook already matches. Run it after cloning or whenever the hook changes.

```
$ bash hooks/install.sh
```

### hooks/pre-push
The native pre-push hook invoked by Git. It buffers the refs being pushed, gathers changed files, and runs the full validation suite in parallel using `npm run format`, `npm run lint`, `npm run check`, `npm run knip`, and `npm run test:unit`. Logs stream to `/tmp`, and failures open an interactive `less` viewer (or print logs when no TTY). All checks must pass before the push is allowed.

## Requirements
- Bash 4+
- GNU or BSD `find`
- Git (for `create_worktree.sh`)

## Contributing
Fork or branch the repository, test the scripts locally, and open a pull request.
