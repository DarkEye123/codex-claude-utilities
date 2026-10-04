#!/usr/bin/env bash

set -euo pipefail

BASE_REF="origin/develop"
MATCH_RULE="missing-remote"
REPORT_PATH="report.md"
DRY_RUN=0
NON_INTERACTIVE=0
AUTO_YES=0
FETCH_REMOTE=1
GH_AVAILABLE=0

declare -a EXCLUDE_PATHS=()
declare -a EXCLUDE_BRANCHES=()
PRIMARY_WORKTREE_PATH=""
CURRENT_WORKTREE_PATH=""

usage() {
  cat <<'EOF'
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
Worktrees with uncommitted or untracked changes, or with .env* files that are
missing or different in the main checkout, are never selected or removed.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

contains_exact() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

parse_args() {
  local value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --match)
        value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
          echo "Missing value for --match" >&2
          exit 1
        fi
        MATCH_RULE="$value"
        shift 2
        ;;
      --base-ref)
        value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
          echo "Missing value for --base-ref" >&2
          exit 1
        fi
        BASE_REF="$value"
        shift 2
        ;;
      --exclude-path)
        value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
          echo "Missing value for --exclude-path" >&2
          exit 1
        fi
        EXCLUDE_PATHS+=("$value")
        shift 2
        ;;
      --exclude-branch)
        value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
          echo "Missing value for --exclude-branch" >&2
          exit 1
        fi
        EXCLUDE_BRANCHES+=("$value")
        shift 2
        ;;
      --report)
        value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
          echo "Missing value for --report" >&2
          exit 1
        fi
        REPORT_PATH="$value"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --no-fetch)
        FETCH_REMOTE=0
        shift
        ;;
      --yes)
        AUTO_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

validate_match_rule() {
  case "$MATCH_RULE" in
    missing-remote|missing-remote-not-merged|missing-remote-merged|all-non-protected) ;;
    *)
      echo "Unsupported --match rule: $MATCH_RULE" >&2
      exit 1
      ;;
  esac
}

declare -a PATHS=()
declare -a BRANCHES=()
declare -a HEADS=()
declare -a UPS=()
declare -a REMOTE_EXISTS=()
declare -a BEHIND=()
declare -a AHEAD=()
declare -a BRANCH_MERGED=()
declare -a HEAD_IN_BASE=()
declare -a PROTECTED=()
declare -a ON_DISK=()
declare -a CLEAN=()
declare -a DEFAULT_SELECTED=()

resolve_primary_worktree_path() {
  local git_common_dir=""
  git_common_dir="$(git rev-parse --git-common-dir)"
  PRIMARY_WORKTREE_PATH="$(cd "${git_common_dir}/.." && pwd -P)"
}

resolve_current_worktree_path() {
  CURRENT_WORKTREE_PATH="$(pwd -P)"
}

load_worktrees() {
  local wt="" head="" branch_ref=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        if [[ -n "$wt" && -n "$head" ]]; then
          append_worktree_row "$wt" "$head" "$branch_ref"
        fi
        wt="${line#worktree }"
        head=""
        branch_ref=""
        ;;
      HEAD\ *)
        head="${line#HEAD }"
        ;;
      branch\ *)
        branch_ref="${line#branch }"
        ;;
      *)
        ;;
    esac
  done < <(git worktree list --porcelain)

  if [[ -n "$wt" && -n "$head" ]]; then
    append_worktree_row "$wt" "$head" "$branch_ref"
  fi
}

should_exclude() {
  local wt="$1"
  local branch="$2"

  if (( ${#EXCLUDE_PATHS[@]} > 0 )); then
    if contains_exact "$wt" "${EXCLUDE_PATHS[@]}"; then
      return 0
    fi
  fi

  if (( ${#EXCLUDE_BRANCHES[@]} > 0 )); then
    if contains_exact "$branch" "${EXCLUDE_BRANCHES[@]}"; then
      return 0
    fi
  fi

  return 1
}

is_default_selected() {
  local remote_exists="$1"
  local branch_merged="$2"
  local head_in_base="$3"
  local clean="$4"

  [[ "$clean" == "yes" ]] || return 1

  case "$MATCH_RULE" in
    missing-remote)
      [[ "$remote_exists" == "no" ]]
      ;;
    missing-remote-not-merged)
      [[ "$remote_exists" == "no" && "$branch_merged" == "no" && "$head_in_base" == "no" ]]
      ;;
    missing-remote-merged)
      [[ "$remote_exists" == "no" && ( "$branch_merged" == "yes" || "$head_in_base" == "yes" ) ]]
      ;;
    all-non-protected)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Squash and rebase merges leave the branch out of the base; a merged PR with this exact head proves the merge.
is_merged_pr_head() {
  local branch="$1"
  local head="$2"

  (( GH_AVAILABLE == 1 )) || return 1
  gh pr list --state merged --head "$branch" --json headRefOid --jq '.[].headRefOid' 2>/dev/null | grep -qx "$head"
}

# Prints why removing the worktree could lose work; prints nothing when it is safe.
worktree_dirty_reason() {
  local wt="$1"
  local status env_file name

  if ! status="$(git -C "$wt" status --porcelain 2>/dev/null)"; then
    echo "git status failed"
    return
  fi
  if [[ -n "$status" ]]; then
    echo "uncommitted or untracked changes"
    return
  fi

  for env_file in "$wt"/.env*; do
    [[ -f "$env_file" ]] || continue
    name="${env_file##*/}"
    if ! cmp -s "$env_file" "$PRIMARY_WORKTREE_PATH/$name"; then
      echo "$name missing or different in main checkout"
      return
    fi
  done
}

append_worktree_row() {
  local wt="$1"
  local head="$2"
  local branch_ref="$3"
  local branch upstream remote_exists behind ahead branch_merged head_in_base protected on_disk clean reason selected

  branch="${branch_ref#refs/heads/}"
  if [[ -z "$branch" || "$branch" == "$branch_ref" ]]; then
    branch="(detached)"
  fi

  if [[ -n "$PRIMARY_WORKTREE_PATH" && "$wt" == "$PRIMARY_WORKTREE_PATH" ]]; then
    return
  fi

  if [[ -n "$CURRENT_WORKTREE_PATH" && "$wt" == "$CURRENT_WORKTREE_PATH" ]]; then
    return
  fi

  if [[ "$branch" == "(detached)" ]]; then
    return
  fi

  protected="no"
  if [[ "$branch" == "develop" || "$branch" == "main" || "$branch" == "master" ]]; then
    protected="yes"
  fi

  if should_exclude "$wt" "$branch"; then
    return
  fi

  if [[ "$protected" == "yes" ]]; then
    return
  fi

  upstream="-"
  remote_exists="no"
  behind="-"
  ahead="-"
  branch_merged="no"
  head_in_base="no"
  on_disk="yes"
  clean="yes"
  selected="no"

  if [[ ! -d "$wt" ]]; then
    on_disk="no"
  else
    reason="$(worktree_dirty_reason "$wt")"
    [[ -z "$reason" ]] || clean="$reason"
  fi

  upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch")"
  [[ -n "$upstream" ]] || upstream="-"

  if [[ "$upstream" != "-" ]]; then
    if git show-ref --verify --quiet "refs/remotes/$upstream"; then
      remote_exists="yes"
    fi
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    remote_exists="yes"
  fi

  read -r behind ahead < <(git rev-list --left-right --count "$BASE_REF...$branch")

  if git merge-base --is-ancestor "$branch" "$BASE_REF"; then
    branch_merged="yes"
  fi

  if git merge-base --is-ancestor "$head" "$BASE_REF"; then
    head_in_base="yes"
  fi

  if [[ "$branch_merged" == "no" ]] && is_merged_pr_head "$branch" "$head"; then
    branch_merged="yes"
  fi

  if is_default_selected "$remote_exists" "$branch_merged" "$head_in_base" "$clean"; then
    selected="yes"
  fi

  PATHS+=("$wt")
  BRANCHES+=("$branch")
  HEADS+=("$head")
  UPS+=("$upstream")
  REMOTE_EXISTS+=("$remote_exists")
  BEHIND+=("$behind")
  AHEAD+=("$ahead")
  BRANCH_MERGED+=("$branch_merged")
  HEAD_IN_BASE+=("$head_in_base")
  PROTECTED+=("$protected")
  ON_DISK+=("$on_disk")
  CLEAN+=("$clean")
  DEFAULT_SELECTED+=("$selected")
}

print_candidates() {
  echo
  printf '%-5s %-9s %-4s %-4s %-6s %-6s %-5s %-5s %s\n' "Idx" "Selected" "Rmt" "Mrg" "Behind" "Ahead" "Disk" "Clean" "Path [branch]"
  printf '%-5s %-9s %-4s %-4s %-6s %-6s %-5s %-5s %s\n' "---" "--------" "---" "---" "------" "-----" "----" "-----" "-------------"

  local i marker clean_marker
  for ((i = 0; i < ${#PATHS[@]}; i++)); do
    marker="[ ]"
    if [[ "${DEFAULT_SELECTED[$i]}" == "yes" ]]; then
      marker="[x]"
    fi
    clean_marker="yes"
    if [[ "${CLEAN[$i]}" != "yes" ]]; then
      clean_marker="no"
    fi
    printf '%-5s %-9s %-4s %-4s %-6s %-6s %-5s %-5s %s [%s]\n' \
      "$((i + 1))" \
      "$marker" \
      "${REMOTE_EXISTS[$i]}" \
      "${BRANCH_MERGED[$i]}" \
      "${BEHIND[$i]}" \
      "${AHEAD[$i]}" \
      "${ON_DISK[$i]}" \
      "$clean_marker" \
      "${PATHS[$i]}" \
      "${BRANCHES[$i]}"
    if [[ "$clean_marker" == "no" ]]; then
      echo "      not removable: ${CLEAN[$i]}"
    fi
  done
  echo
}

declare -a FINAL_SELECTED=()

final_selected_count() {
  local count=0
  local idx
  for idx in "${FINAL_SELECTED[@]-}"; do
    if [[ -n "$idx" ]]; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

collect_default_selection() {
  FINAL_SELECTED=()
  local i
  for ((i = 0; i < ${#PATHS[@]}; i++)); do
    if [[ "${DEFAULT_SELECTED[$i]}" == "yes" ]]; then
      FINAL_SELECTED+=("$i")
    fi
  done
}

is_selected_index() {
  local needle="$1"
  local idx
  for idx in "${FINAL_SELECTED[@]-}"; do
    if [[ -z "$idx" ]]; then
      continue
    fi
    if [[ "$idx" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

add_selected_index() {
  local idx="$1"
  if ! is_selected_index "$idx"; then
    FINAL_SELECTED+=("$idx")
  fi
}

remove_selected_index() {
  local idx="$1"
  local tmp=()
  local item
  for item in "${FINAL_SELECTED[@]-}"; do
    if [[ -z "$item" ]]; then
      continue
    fi
    if [[ "$item" != "$idx" ]]; then
      tmp+=("$item")
    fi
  done
  FINAL_SELECTED=("${tmp[@]}")
}

apply_selection_input() {
  local input="$1"
  local normalized token sign num n

  normalized="${input// /}"
  if [[ -z "$normalized" ]]; then
    return
  fi

  if [[ "$normalized" == "all" ]]; then
    FINAL_SELECTED=()
    for ((n = 0; n < ${#PATHS[@]}; n++)); do
      FINAL_SELECTED+=("$n")
    done
    return
  fi

  if [[ "$normalized" == "none" ]]; then
    FINAL_SELECTED=()
    return
  fi

  if [[ "$normalized" == *"+"* || "$normalized" == *"-"* ]]; then
    :
  else
    FINAL_SELECTED=()
  fi

  IFS=',' read -r -a tokens <<<"$normalized"
  for token in "${tokens[@]}"; do
    if [[ -z "$token" ]]; then
      continue
    fi

    sign=""
    num="$token"
    if [[ "$token" == +* || "$token" == -* ]]; then
      sign="${token:0:1}"
      num="${token:1}"
    fi

    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
      echo "Invalid token in selection: $token" >&2
      exit 1
    fi

    if (( num < 1 || num > ${#PATHS[@]} )); then
      echo "Selection index out of range: $num" >&2
      exit 1
    fi

    local zero_based=$((num - 1))
    if [[ "$sign" == "-" ]]; then
      remove_selected_index "$zero_based"
    else
      add_selected_index "$zero_based"
    fi
  done
}

manual_selection_prompt() {
  if (( NON_INTERACTIVE == 1 )); then
    return
  fi

  echo "Selection controls:"
  echo "  Enter      keep defaults"
  echo "  all        select all listed worktrees"
  echo "  none       unselect all"
  echo "  1,3,5      select exact indices"
  echo "  +2,-4,+8   adjust default selection"
  echo

  local input
  read -r -p "Selection input: " input
  apply_selection_input "$input"
}

write_report() {
  {
    echo "# Worktree Cleanup Report"
    echo
    echo "Base branch: \`$BASE_REF\`"
    echo "Match rule: \`$MATCH_RULE\`"
    echo "Generated on: \`$(date '+%Y-%m-%d %H:%M:%S %Z')\`"
    echo
    echo "## Candidates"
    echo
    echo "| Idx | Default Selected | On Disk | Clean | Remote Exists | Branch Merged | Head In Base | Behind | Ahead | Branch | Path |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|"

    local i default_marker
    for ((i = 0; i < ${#PATHS[@]}; i++)); do
      default_marker="no"
      if [[ "${DEFAULT_SELECTED[$i]}" == "yes" ]]; then
        default_marker="yes"
      fi
      printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | `%s` | `%s` |\n' \
        "$((i + 1))" \
        "$default_marker" \
        "${ON_DISK[$i]}" \
        "${CLEAN[$i]}" \
        "${REMOTE_EXISTS[$i]}" \
        "${BRANCH_MERGED[$i]}" \
        "${HEAD_IN_BASE[$i]}" \
        "${BEHIND[$i]}" \
        "${AHEAD[$i]}" \
        "${BRANCHES[$i]}" \
        "${PATHS[$i]}"
    done

    echo
    echo "## Final Selection"
    echo
    if [[ "$(final_selected_count)" -eq 0 ]]; then
      echo "- No worktrees selected."
    else
      local idx
      for idx in "${FINAL_SELECTED[@]-}"; do
        if [[ -z "$idx" ]]; then
          continue
        fi
        printf -- '- `%s` [%s]\n' "${PATHS[$idx]}" "${BRANCHES[$idx]}"
      done
    fi
  } >"$REPORT_PATH"
}

print_final_selection() {
  echo
  echo "Final selection ($(final_selected_count)):"
  local idx
  if [[ "$(final_selected_count)" -eq 0 ]]; then
    echo "  (none)"
    return
  fi
  for idx in "${FINAL_SELECTED[@]-}"; do
    if [[ -z "$idx" ]]; then
      continue
    fi
    echo "  - ${PATHS[$idx]} [${BRANCHES[$idx]}]"
  done
}

confirm_action() {
  if (( AUTO_YES == 1 )); then
    return 0
  fi

  local answer
  read -r -p "Delete selected worktrees? Type 'yes' to continue: " answer
  [[ "$answer" == "yes" ]]
}

delete_selected() {
  local removed=0 missing=0 skipped=0 failed=0 idx path reason

  for idx in "${FINAL_SELECTED[@]-}"; do
    if [[ -z "$idx" ]]; then
      continue
    fi
    path="${PATHS[$idx]}"

    if [[ ! -d "$path" ]]; then
      echo "MISSING $path"
      missing=$((missing + 1))
      continue
    fi

    # Check again: the worktree can change while the user reviews the selection.
    reason="$(worktree_dirty_reason "$path")"
    if [[ -n "$reason" ]]; then
      echo "SKIPPED $path ($reason)"
      skipped=$((skipped + 1))
      continue
    fi

    if git worktree remove -f "$path"; then
      echo "REMOVED $path"
      removed=$((removed + 1))
    else
      echo "FAILED $path"
      failed=$((failed + 1))
    fi
  done

  git worktree prune
  echo "SUMMARY removed=$removed missing=$missing skipped=$skipped failed=$failed"
}

main() {
  require_cmd git
  parse_args "$@"
  validate_match_rule

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Current directory is not a git repository." >&2
    exit 1
  fi

  resolve_primary_worktree_path
  resolve_current_worktree_path

  if (( FETCH_REMOTE == 1 )); then
    if ! git fetch --prune origin >/dev/null 2>&1; then
      echo "Warning: 'git fetch --prune origin' failed; continuing with local refs." >&2
    fi
  fi

  # One probe covers a missing gh, no login, no repo access and an old gh without headRefOid.
  if command -v gh >/dev/null 2>&1 && gh pr list --limit 1 --json headRefOid >/dev/null 2>&1; then
    GH_AVAILABLE=1
  else
    echo "Warning: gh is missing, not logged in, cannot read this repo, or is too old for headRefOid; squash-merged branches are not detected as merged." >&2
  fi

  if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    echo "Base ref not found locally: $BASE_REF" >&2
    exit 1
  fi

  load_worktrees

  if [[ ${#PATHS[@]} -eq 0 ]]; then
    echo "No non-protected worktree candidates found."
    write_report
    echo "Report written to $REPORT_PATH"
    exit 0
  fi

  collect_default_selection
  print_candidates
  manual_selection_prompt
  print_final_selection
  write_report
  echo "Report written to $REPORT_PATH"

  if (( DRY_RUN == 1 )); then
    echo "Dry run enabled. No deletions performed."
    exit 0
  fi

  if [[ "$(final_selected_count)" -eq 0 ]]; then
    echo "No selected worktrees to delete."
    exit 0
  fi

  if ! confirm_action; then
    echo "Aborted by user."
    exit 0
  fi

  delete_selected
}

main "$@"
