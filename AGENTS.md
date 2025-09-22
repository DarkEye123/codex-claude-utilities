# Repository Guidelines

## Project Structure & Module Organization
- Root scripts: `create_agents.sh` generates `AGENTS.md` siblings for discovered `CLAUDE.md` files; `create_worktree.sh` provisions Git worktrees under `worktrees/<name>`.
- Git hooks live in `hooks/`; `install.sh` installs the native `pre-push` hook, and `pre-push` orchestrates validation commands.
- No compiled sources or assets are tracked here; this repo is a toolkit intended to be executed inside other projects.

## Build, Test, and Development Commands
- `bash hooks/install.sh` — copies `hooks/pre-push` into `.git/hooks/` (handles worktrees and resets custom `core.hooksPath`).
- `bash create_agents.sh --help` — review options for mirroring `CLAUDE.md` files into `AGENTS.md` across a tree.
- `bash create_worktree.sh <worktree> [branch] [flags]` — create a worktree and copy top-level `.env*` files; use `-c` to clone `node_modules`.
- The `pre-push` hook runs `npm run format`, `npm run lint`, `npm run check`, `npm run knip`, and `npm run test:unit`; ensure these scripts exist in the host project.

## Coding Style & Naming Conventions
- Shell scripts use Bash with 2-space indentation and lowercase, dash-separated filenames (`create_agents.sh`).
- Prefer descriptive function names; keep comments focused on non-obvious logic.
- Hooks expect projects to follow conventional npm script naming for linting, formatting, and testing.

## Testing Guidelines
- Validation relies on the host project's tooling: prettier, eslint, TypeScript, knip, and unit tests invoked through npm scripts.
- Keep tests colocated with the project that consumes these utilities; verify `npm run test:unit` passes before pushing.
- Pre-push failures drop logs in `/tmp/` (e.g., `format_output_<timestamp>.log`); inspect them via the interactive viewer or `less`.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`chore:`, `docs:`, `feat:`) observed in history (`chore: add native git hooks`).
- Group related script and documentation updates in a single commit; run the pre-push hook locally before opening a PR.
- Pull requests should describe impacted scripts, include reproduction steps for automation changes, and note any required environment variables or npm script additions.
