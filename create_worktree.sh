#!/usr/bin/env bash
# shellcheck shell=bash

# create_worktree.sh – create a git worktree plus copy all top-level .env* files.
# Optional: -c copies node_modules. Supports --base for new branches and --no-fetch.
# For full usage details and examples run: ./create_worktree.sh --help

set -euo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="v2.0.1 (2025-09-12)"

# Color support (TTY + basic capability detection)
if [ -t 1 ]; then
    if command -v tput >/dev/null 2>&1 && tput setaf 2 >/dev/null 2>&1; then
        C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"; C_RED="$(tput setaf 1)"; C_BOLD="$(tput bold)"; C_RESET="$(tput sgr0)"
    else
        C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
    fi
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

cleanup_on_error() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        echo "${C_RED}ERROR:${C_RESET} Script failed (exit $status). Partial worktree at '$WORKTREE_PATH' may need manual cleanup." >&2
    fi
}
trap cleanup_on_error EXIT

# Ensure we're inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "${C_RED}Error:${C_RESET} Not inside a git repository." >&2
    exit 1
fi

SCRIPT_NAME="$(basename "$0")"

show_help() {
    cat <<EOF
${SCRIPT_NAME} (${SCRIPT_VERSION})

Usage: $SCRIPT_NAME <worktree_name> [branch_name] [options]

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
    $SCRIPT_NAME feature-x
    $SCRIPT_NAME feature-x origin/develop
    $SCRIPT_NAME feature-x -c --base origin/main
EOF
}

COPY_NODE_MODULES=false
WORKTREE_NAME=""
BRANCH_NAME=""
BASE_BRANCH="" # Only used when creating a new branch and provided via --base
DO_FETCH=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help; exit 0 ;;
        -c)
            COPY_NODE_MODULES=true; shift ;;
        --base)
            if [[ $# -lt 2 ]]; then echo "${C_RED}Error:${C_RESET} --base requires an argument" >&2; exit 1; fi
            BASE_BRANCH="$2"; shift 2 ;;
        --no-fetch)
            DO_FETCH=false; shift ;;
        --*)
            echo "${C_RED}Error:${C_RESET} Unknown option: $1" >&2; exit 1 ;;
        -*)
            echo "${C_RED}Error:${C_RESET} Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [[ -z $WORKTREE_NAME ]]; then
                WORKTREE_NAME="$1"
            elif [[ -z $BRANCH_NAME ]]; then
                BRANCH_NAME="$1"
            else
                echo "${C_YELLOW}Warning:${C_RESET} Ignoring extra positional argument: $1" >&2
            fi
            shift ;;
    esac
done

if [ -z "$WORKTREE_NAME" ]; then
    echo "${C_RED}Error:${C_RESET} Worktree name is required" >&2
    echo
    show_help
    exit 1
fi

if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="$WORKTREE_NAME"
fi

WORKTREE_PATH="./worktrees/$WORKTREE_NAME"

# Validation for worktree name (no leading slash, no .. segments, approved chars)
if [[ "$WORKTREE_NAME" == /* ]]; then
    echo "${C_RED}Error:${C_RESET} Worktree name must be relative (no leading /)." >&2
    exit 1
fi
if [[ "$WORKTREE_NAME" == *..* ]]; then
    echo "${C_RED}Error:${C_RESET} Worktree name must not contain '..'." >&2
    exit 1
fi
if [[ "$WORKTREE_NAME" =~ [^a-zA-Z0-9._/-] ]]; then
    echo "${C_RED}Error:${C_RESET} Invalid characters in worktree name. Allowed: letters, numbers, ., -, _, /." >&2
    exit 1
fi

if [ -e "$WORKTREE_PATH" ]; then
    echo "${C_RED}Error:${C_RESET} Path '$WORKTREE_PATH' already exists. Remove it first or choose a different name." >&2
    exit 1
fi

# Fetch updates unless disabled
if $DO_FETCH; then
    echo "Fetching remote refs..."
    git fetch --prune --quiet || echo "${C_YELLOW}Warning:${C_RESET} git fetch failed (network issue or auth?). Continuing with local refs only; remote branch detection may be stale. Use --no-fetch to suppress this step."
fi

# Abort if branch already checked out in another worktree
if git worktree list --porcelain | grep -q "^branch refs/heads/$BRANCH_NAME$"; then
    echo "${C_RED}Error:${C_RESET} Branch '$BRANCH_NAME' already has an attached worktree." >&2
    git worktree list
    exit 1
fi

echo "${C_BOLD}Creating worktree${C_RESET} '$WORKTREE_NAME' at '$WORKTREE_PATH'..."

if [[ ! -d "./worktrees" ]]; then
    mkdir -p ./worktrees
    echo "INFO: Created worktrees directory"
fi

BRANCH_STATUS="" # existing-local | from-remote | new
BASE_USED=""
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "Using existing local branch: $BRANCH_NAME"
    BRANCH_STATUS="existing-local"
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
    echo "Creating local branch from remote: origin/$BRANCH_NAME"
    BRANCH_STATUS="from-remote"
    BASE_USED="origin/$BRANCH_NAME"
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "origin/$BRANCH_NAME"
else
    # New branch scenario
    if [ -n "$BASE_BRANCH" ]; then
        echo "Creating new branch '$BRANCH_NAME' from base '$BASE_BRANCH'"
        BRANCH_STATUS="new"
        BASE_USED="$BASE_BRANCH"
        git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
    else
        echo "Creating new branch: $BRANCH_NAME"
        BRANCH_STATUS="new"
        git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"
    fi
fi

echo "Copying .env files..."
ENV_COUNT=0
while IFS= read -r env_file; do
    cp "$env_file" "$WORKTREE_PATH/"
    echo "Copied $env_file"
    ENV_COUNT=$((ENV_COUNT+1))
done <<EOF
$(find . -maxdepth 1 -name ".env*" -type f | sort)
EOF
echo "Copied $ENV_COUNT .env file(s)."

NODE_MODULES_COPIED=false
if [[ "$COPY_NODE_MODULES" == "true" ]]; then
    if [[ -d "./node_modules" ]]; then
        echo "Copying node_modules (this may take a moment)..."
        cp -R "./node_modules" "$WORKTREE_PATH/"
        echo "Copied node_modules to $WORKTREE_PATH/"
        echo "INFO: This worktree now has an isolated dependency tree (changes here won't affect root)."
        NODE_MODULES_COPIED=true
    else
        echo "${C_YELLOW}WARNING:${C_RESET} node_modules directory not found - cannot copy with -c flag"
        echo "INFO: Run 'npm install' at repository root or inside the worktree to generate dependencies, then retry if needed."
    fi
else
    echo "INFO: Skipping node_modules copy (use -c to create an isolated copy)"
    echo "INFO: Node will fall back to the repository root 'node_modules' via upward module resolution."
    echo "INFO: Only run 'npm install' inside this worktree if you change dependencies and want a separate install."
fi

echo
echo "${C_GREEN}Worktree created successfully${C_RESET}" \
    "(branch: $BRANCH_NAME | status: $BRANCH_STATUS | base: ${BASE_USED:-n/a})"
echo "Location: $WORKTREE_PATH"
echo "Env files copied: $ENV_COUNT"
echo "node_modules copied: $NODE_MODULES_COPIED"
echo
echo "Next: cd $WORKTREE_PATH"
echo "Remove later: git worktree remove $WORKTREE_PATH"