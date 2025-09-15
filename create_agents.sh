#!/usr/bin/env bash
set -euo pipefail

# create_agents.sh
#
# Finds every CLAUDE.md in the given root (default '.') and creates/overwrites
# a sibling AGENTS.md with identical content. Implemented as a single `find`
# invocation using -exec. Supports optional repeated --exclude patterns to prune
# matching paths.
#
# Usage:
#   ./create_agents.sh                  # process current directory
#   ./create_agents.sh <root>           # process a specific root directory
#   ./create_agents.sh --exclude worktrees            # exclude a directory
#   ./create_agents.sh -x worktrees -x node_modules  # multiple excludes
#   ./create_agents.sh -x worktrees <root>           # exclude + root
#
# Notes:
# - Overrides any existing AGENTS.md files at the same level.
# - Uses a single find invocation with -exec and optional -prune sections.

print_usage() {
  cat <<USAGE
Usage: $0 [--exclude <pattern>]... [root]

Options:
  -x, --exclude <pattern>   Exclude paths matching pattern (repeatable)
  -h, --help                Show this help and exit

Examples:
  $0
  $0 --exclude worktrees
  $0 -x worktrees -x node_modules ./
USAGE
}

ROOT_DIR="."
EXCLUDES=()

while (($#)); do
  case "$1" in
    --exclude|-x)
      shift || { echo "Missing argument for --exclude" >&2; exit 1; }
      EXCLUDES+=("${1%/}")
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      ROOT_DIR="$1"
      ;;
  esac
  shift || true
done

# Build find command parts (portable across BSD/GNU find)
FIND_ARGS=("$ROOT_DIR")

if [ ${#EXCLUDES[@]} -gt 0 ]; then
  FIND_ARGS+=("(")
  for i in "${!EXCLUDES[@]}"; do
    pat="${EXCLUDES[$i]}"
    # Match anywhere in the path
    FIND_ARGS+=( -path "*/$pat/*" )
    if [ "$i" -lt $(( ${#EXCLUDES[@]} - 1 )) ]; then
      FIND_ARGS+=( -o )
    fi
  done
  FIND_ARGS+=( ")" -prune -o )
fi

FIND_ARGS+=( -type f -name 'CLAUDE.md' -exec sh -c 'src="$1"; dir="${src%/*}"; cp -f "$src" "$dir/AGENTS.md"' sh {} \; )

# Execute single find invocation
find "${FIND_ARGS[@]}"

echo "AGENTS.md files created/updated for all CLAUDE.md files under: $ROOT_DIR"