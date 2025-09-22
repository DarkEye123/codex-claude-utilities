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

## Requirements
- Bash 4+
- GNU or BSD `find`
- Git (for `create_worktree.sh`)

## Contributing
Fork or branch the repository, test the scripts locally, and open a pull request.
