# Utilities

Bash helpers for managing worktrees, Git hooks, and repository housekeeping.

## Use as a submodule

Repository: `git@github.com:DarkEye123/codex-claude-utilities.git`

```bash
git submodule add git@github.com:DarkEye123/codex-claude-utilities.git utilities/codex-claude-utilities
```

## Scripts

### create_agents.sh

Finds every selected instruction file under a root directory and symbolically links the other two names to it. `AGENTS.md` is the default target; use `--target` to select `CLAUDE.md` or `GEMINI.md`. The script uses a single `find` invocation, always excludes `node_modules`, and supports repeatable additional exclude patterns.

```
$ bash create_agents.sh --help
Usage: create_agents.sh [--target <file>] [--exclude <pattern>]... [root]

Options:
  -t, --target <file>      Target file: AGENTS.md, CLAUDE.md, or GEMINI.md (default: AGENTS.md)
  -x, --exclude <pattern>   Exclude additional paths matching pattern (repeatable)
  -h, --help                Show this help and exit

Examples:
  create_agents.sh
  create_agents.sh --target CLAUDE.md
  create_agents.sh --exclude worktrees
  create_agents.sh -x worktrees -x dist ./
```

### create_worktree.sh

Creates a Git worktree at `./worktrees/<worktree_name>`, copies every top-level `./.env*` file into it, runs its sibling `create_agents.sh` against the new worktree, and optionally copies `./node_modules`. If the target branch already exists locally it reuses it, if `origin/<branch>` exists it creates a local branch from that remote, otherwise it creates a new branch from the current `HEAD`, or from `--base` when you give it.

The usual call gives only one name. The script uses it for the worktree and for the branch:

```bash
./create_worktree.sh my-new-change
```

The script pushes a new branch to `origin` right away, so its upstream is `origin/<branch>`, not the `--base` branch. This push skips the `pre-push` hook. Later pushes run it. If the push fails, the branch has no upstream. Then run `git push -u origin <branch>` yourself.

When you give `--base` and `origin/<branch>` already exists, the script warns you. In a terminal, it asks you to use the existing branch, enter a new name, or abort. Without a terminal, it uses the existing branch.

```
$ bash create_worktree.sh --help
create_worktree.sh (v2.0.1 (2025-09-12))

Usage: create_worktree.sh <worktree_name> [branch_name] [options]

Creates a git worktree and copies all top-level .env* files. Optional node_modules copy (-c).

Positional:
    worktree_name          Name for the new worktree (required)
    branch_name            Existing or new branch (defaults to worktree_name), not its base

Options:
    -c                     Copy node_modules directory recursively
    --base <branch>        Base branch for newly created branch (if target doesn't exist)
    --no-fetch             Skip 'git fetch' (default is to fetch)
    --help                 Show this help and exit

Behavior:
    - A new branch starts from the current HEAD, or from --base when given
    - Fails if worktree path exists or branch already attached elsewhere
    - Copies every file matching ./.env* (no filtering) as requested
    - Pushes a new branch to origin right away (no pre-push hook), so its upstream is origin/<branch>
    - Asks before it reuses an existing origin/<branch> when --base is given

Examples:
    create_worktree.sh feature-x
    create_worktree.sh feature-x fix/feature-x
    create_worktree.sh feature-x -c --base origin/main
```

### clear-worktrees.sh

Analyzes existing Git worktrees, excludes the primary worktree, the current worktree, detached HEAD worktrees, and protected branches (`main`, `master`, `develop`), then produces a candidate table and a Markdown report. By default it auto-selects worktrees whose remote branch no longer exists, lets you adjust the selection interactively, and removes the final selection with `git worktree remove -f` followed by `git worktree prune`.

A branch counts as merged when it is in the base ref, or when its tip is the head commit of a merged PR. The PR check uses `gh`, so it also finds squash and rebase merges. Without `gh`, the script does only the first check and prints a warning.

The table marks a worktree as not clean, with the reason, when it has one of these:

- uncommitted or untracked changes
- a top-level `.env*` file that is missing in the main checkout or is different there

In interactive mode, this is information only. You decide what to remove. With `--non-interactive`, the script does not select a matching worktree that is not clean. It marks the worktree `[!]`, prints a `MANUAL CHECK` line, and lists it in the `Manual Check` section of the report. Check these worktrees yourself.

Supported match rules:

- `missing-remote`
- `missing-remote-not-merged`
- `missing-remote-merged`
- `all-non-protected`

```
$ bash clear-worktrees.sh --help
Usage: ./clear-worktrees.sh [options]

Interactive worktree cleanup with auto-selection + confirmation.

Options:
  --match <rule>            Auto-selection rule (default: missing-remote)
                            Rules:
                              missing-remote
                              missing-remote-not-merged
                              missing-remote-merged
                              all-non-protected
  --base-ref <ref>          Base ref for merge/ahead/behind checks (default: origin/develop)
  --exclude-path <path>     Exclude a worktree path (can be passed multiple times)
  --exclude-branch <name>   Exclude a branch name (can be passed multiple times)
  --report <path>           Output report path (default: report.md)
  --dry-run                 Do not delete, only report/preview
  --non-interactive         Skip manual selection prompt (use auto-selected set)
  --no-fetch                Skip `git fetch --prune origin` before analysis
  --yes                     Skip final confirmation prompt
  -h, --help                Show this help

Merged: the branch is in the base ref, or its tip is the head of a merged PR
(found with gh, so squash merges count). Without gh, only the first check runs.
With --non-interactive, a matching worktree with uncommitted or untracked
changes, or with .env* files that are missing or different in the main
checkout, is not selected. It is listed for a manual check instead.
```

Example:

```
bash clear-worktrees.sh --match missing-remote-merged --dry-run --report worktree-report.md
```

### clear-empty-worktree-dirs.sh

Deletes empty directories under `./worktrees` from the bottom up. This is useful after removing nested worktrees or after `git worktree prune` leaves empty parent directories behind. The script exits with an error if `./worktrees` does not exist.

```
$ bash clear-empty-worktree-dirs.sh
```

### remove_old_branches.sh

Deletes local Git branches whose upstream was removed from the remote. The script uses `git branch -vv`, filters entries marked `: gone]`, and deletes them with `git branch -D`.

```
$ bash remove_old_branches.sh
```

## Hooks

### hooks/install.sh

Installs the native `pre-push` hook into the current repository's real Git hooks directory. When run inside a worktree it resolves the shared Git dir with `git rev-parse --git-common-dir`, removes any custom `core.hooksPath`, skips installation if the current hook already matches the utility's `hooks/pre-push`, and otherwise copies the hook and makes it executable.

```
$ bash path/to/codex-claude-utilities/hooks/install.sh
```

### hooks/pre-push

Native Git pre-push hook that reads the refs being pushed, computes the files reachable from commits that are not yet on the destination remote, and excludes paths under `worktrees/`. It then runs `npm run format`, `npm run lint`, `npm run check`, `npm run knip`, and `npm run test:unit` in parallel, writing logs to `/tmp/*_output_<timestamp>.log`.

If formatting introduces new changes in files that are part of the push, the hook fails even when `npm run format` exits successfully. Single failures open the relevant log in `less` when a TTY is available; multiple failures show a small menu, and non-interactive environments print logs directly.

## Requirements

- Bash
- Git
- `find`, `awk`, `sort`, `grep`, and standard Unix utilities
- Node.js and npm in repositories that use `hooks/pre-push`
- Repository npm scripts for `format`, `lint`, `check`, `knip`, and `test:unit` when using the pre-push hook

## Contributing

Test script changes locally, verify the documented commands still match `--help` output and observed behavior, and open a pull request with the script changes and README updates together.
