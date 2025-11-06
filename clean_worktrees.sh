#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKTREES_DIR="$SCRIPT_DIR/worktrees"

if [[ ! -d "$WORKTREES_DIR" ]]; then
  echo "worktrees directory not found at $WORKTREES_DIR" >&2
  exit 1
fi

# Remove empty directories from the bottom up so parents are deleted after their empty children.
find "$WORKTREES_DIR" -depth -mindepth 1 -type d -empty -delete
