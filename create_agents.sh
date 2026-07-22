#!/usr/bin/env bash
set -euo pipefail

# create_agents.sh
#
# Finds every selected target file in the given root (default '.') and creates
# symbolic links for the other instruction-file names. Implemented as a single `find`
# invocation using -exec. node_modules is always excluded; optional repeated
# --exclude patterns prune additional matching paths.
#
# Usage:
#   ./create_agents.sh                  # use AGENTS.md as the target
#   ./create_agents.sh --target CLAUDE.md # use CLAUDE.md as the target
#   ./create_agents.sh <root>           # process a specific root directory
#   ./create_agents.sh --exclude worktrees            # exclude a directory
#   ./create_agents.sh -x worktrees -x dist          # multiple excludes
#   ./create_agents.sh -x worktrees <root>           # exclude + root
#
# Notes:
# - Replaces the two non-target instruction files at the same level.
# - Uses a single find invocation with -exec and optional -prune sections.

print_usage() {
  cat <<USAGE
Usage: $0 [--target <file>] [--exclude <pattern>]... [root]

Options:
  -t, --target <file>      Target file: AGENTS.md, CLAUDE.md, or GEMINI.md (default: AGENTS.md)
  -x, --exclude <pattern>   Exclude additional paths matching pattern (repeatable)
  -h, --help                Show this help and exit

Examples:
  $0
  $0 --target CLAUDE.md
  $0 --exclude worktrees
  $0 -x worktrees -x dist ./
USAGE
}

ROOT_DIR=$(pwd)
EXCLUDES=(node_modules)
TARGET=AGENTS.md

while (($#)); do
  case "$1" in
    --exclude|-x)
      [ "$#" -gt 1 ] || { echo "Missing argument for --exclude" >&2; exit 1; }
      shift
      EXCLUDES+=("${1%/}")
      ;;
    --target|-t)
      [ "$#" -gt 1 ] || { echo "Missing argument for --target" >&2; exit 1; }
      shift
      TARGET="$1"
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

case "$TARGET" in
  AGENTS.md|CLAUDE.md|GEMINI.md) ;;
  *) echo "Invalid target: $TARGET (expected AGENTS.md, CLAUDE.md, or GEMINI.md)" >&2; exit 1 ;;
esac

ROOT_DIR=$(cd "$ROOT_DIR" && pwd)

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

FIND_ARGS+=( -type f -name "$TARGET" -exec sh -c 'src="$1"; selected="$2"; dir="${src%/*}"; for target in AGENTS.md CLAUDE.md GEMINI.md; do [ "$target" = "$selected" ] || ln -sfn "$src" "$dir/$target"; done' sh {} "$TARGET" \; )

# Execute single find invocation
find "${FIND_ARGS[@]}"

echo "Symlinks to $TARGET created/updated under: $ROOT_DIR"
