#!/usr/bin/env bash
set -euo pipefail

WORKTREES_DIR="./worktrees"

if [[ ! -d "$WORKTREES_DIR" ]]; then
  echo "worktrees directory not found at $WORKTREES_DIR" >&2
  exit 1
fi

WORKTREES_DIR="$(cd "$WORKTREES_DIR" && pwd -P)"
worktree_list="$(git worktree list --porcelain)"

# Skip active worktrees: an uninitialized submodule in one is an empty directory that Git tracks.
declare -a prune=()
while IFS= read -r line; do
  [[ "$line" == worktree\ * ]] || continue
  wt="$(cd "${line#worktree }" 2>/dev/null && pwd -P)" || continue
  # -path takes a glob pattern; escape it so the path matches literally.
  prune+=(-path "$(printf '%s' "$wt" | sed 's/[][\\*?]/\\&/g')" -prune -o)
done <<<"$worktree_list"

# -delete implies -depth, which disables -prune, so remove one level of empty directories per pass.
while :; do
  empty=()
  while IFS= read -r -d '' dir; do
    empty+=("$dir")
  done < <(find "$WORKTREES_DIR" -mindepth 1 "${prune[@]}" -type d -empty -print0)
  ((${#empty[@]})) || break
  rmdir -- "${empty[@]}"
done
