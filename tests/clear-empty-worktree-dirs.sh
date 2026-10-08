#!/usr/bin/env bash
# Usage: bash tests/clear-empty-worktree-dirs.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/clear-empty-worktree-dirs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the user's git config; allow a local path as the submodule URL.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

git init -q "$TMP/sub"
git -C "$TMP/sub" commit -q --allow-empty -m init

git init -q "$TMP/repo"
cd "$TMP/repo"
echo worktrees/ >.gitignore
git submodule -q add "$TMP/sub" utilities/sub 2>/dev/null
git add -A
git commit -q -m init

# Add the active worktree through a symlink: git and find must agree on its path.
ln -s "$TMP/repo" "$TMP/link"
git -C "$TMP/link" worktree add -q worktrees/fix/active -b active
mkdir worktrees/fix/active/empty-dir
git worktree add -q worktrees/gone/x -b gone
git worktree remove worktrees/gone/x
mkdir -p worktrees/stale/a/b

[[ -d worktrees/fix/active/utilities/sub ]] || fail "setup: uninitialized submodule is not an empty directory"
status_before="$(git -C worktrees/fix/active status --short)"

cd "$TMP/link"
bash "$SCRIPT"
cd "$TMP/repo"

[[ -d worktrees/fix/active/utilities/sub ]] || fail "deleted the submodule directory of an active worktree"
[[ -d worktrees/fix/active/empty-dir ]] || fail "deleted an empty directory inside an active worktree"
[[ "$(git -C worktrees/fix/active status --short)" == "$status_before" ]] || fail "git status of the active worktree changed"
[[ ! -e worktrees/gone ]] || fail "kept the empty parent of a removed worktree"
[[ ! -e worktrees/stale ]] || fail "kept nested empty directories"
[[ -d worktrees ]] || fail "deleted ./worktrees itself"

# Without a worktree list the script cannot tell what is safe, so it must delete nothing.
mkdir -p "$TMP/no-git/worktrees/empty"
cd "$TMP/no-git"
if GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" 2>/dev/null; then
  fail "succeeded outside a git repository"
fi
[[ -d worktrees/empty ]] || fail "deleted directories when git worktree list failed"

if ((failures)); then
  exit 1
fi
echo "PASS"
