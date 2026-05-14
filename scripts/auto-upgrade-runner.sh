#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/common.sh"
source "$LIB_DIR/git-ops.sh"
source "$LIB_DIR/yarn-ops.sh"
source "$LIB_DIR/branch-chain.sh"

# Global state
ORIGINAL_BRANCH=""
REPO_ROOT=""
DRY_RUN=false
NO_PUSH=false
NO_CHERRY_PICK=false
STASH_CREATED=false

usage() {
    cat << EOF
Usage: $(basename "$0") --dep NAME --version VER (--target TARGET | --branches LIST) [OPTIONS]

Auto-upgrade dependencies across branch chain for deployment target or specific branches.

REQUIRED:
    --dep NAME          Dependency name (e.g., axios)
    --version VER       Version to upgrade to (e.g., ^1.15.2)
    --target TARGET     Deployment target (OCM, ACM/CIM, or OVE/ABI)
    --branches LIST     Comma-separated list of specific branches (alternative to --target)

OPTIONS:
    --dry-run           Test without creating branches or pushing
    --no-push           Create branches locally but don't push
    --no-cherry-pick    Skip cherry-pick, always use independent analysis
    --upstream REMOTE   Upstream remote name (default: upstream)
    --origin REMOTE     Origin remote name (default: origin)
    -h, --help          Show this help

EXAMPLES:
    # Upgrade axios for OCM target
    $(basename "$0") --dep axios --version ^1.15.2 --target OCM

    # Dry run for ACM/CIM
    $(basename "$0") --dep redux --version ^5.0.0 --target "ACM/CIM" --dry-run

    # Specific branches only
    $(basename "$0") --dep lodash --version ^4.17.21 --branches "releases/v2.52,releases/v2.51"

EOF
    exit 0
}

# Parse arguments
parse_args() {
    local dep_name=""
    local dep_version=""
    local target=""
    local branches_list=""
    # ============================================================================
    # TEMPORARY: Testing with origin - REVERT BEFORE COMMIT
    # ============================================================================
    local upstream="origin"  # TEMPORARY: Change back to "upstream"
    # ============================================================================
    local origin="origin"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dep) dep_name="$2"; shift 2 ;;
            --version) dep_version="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            --branches) branches_list="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-push) NO_PUSH=true; shift ;;
            --no-cherry-pick) NO_CHERRY_PICK=true; shift ;;
            --upstream) upstream="$2"; shift 2 ;;
            --origin) origin="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) error "Unknown option: $1"; usage ;;
        esac
    done

    [[ -z "$dep_name" ]] && { error "--dep required"; usage; }
    [[ -z "$dep_version" ]] && { error "--version required"; usage; }

    # Must have either --target or --branches, but not both
    if [[ -n "$target" ]] && [[ -n "$branches_list" ]]; then
        error "Cannot specify both --target and --branches"
        usage
    fi

    if [[ -z "$target" ]] && [[ -z "$branches_list" ]]; then
        error "Must specify either --target or --branches"
        usage
    fi

    # Export for use by functions
    export DEP_NAME="$dep_name"
    export DEP_VERSION="$dep_version"
    export TARGET="$target"
    export BRANCHES_LIST="$branches_list"
    export UPSTREAM_REMOTE="$upstream"
    export ORIGIN_REMOTE="$origin"
}

# Check for and handle working changes
handle_working_changes() {
    log "Checking for uncommitted changes..."

    # Check if there are any changes
    if git diff-index --quiet HEAD -- 2>/dev/null; then
        log "Working tree is clean"
        return 0
    fi

    # We have changes - ask what to do via output that agent can parse
    local changes_summary
    changes_summary=$(git status --short)

    local data_json
    data_json='{"action_needed": "stash_or_commit"}'
    emit_json "working_changes_detected" "Uncommitted changes found" "$data_json"

    # For now, automatically stash changes
    log "Stashing uncommitted changes..."
    git stash push -u -m "auto-upgrade: saved changes before upgrade at $(date)" || {
        error "Failed to stash changes"
        return $EXIT_ERROR
    }

    STASH_CREATED=true
    data_json='{"stash_ref": "stash@{0}"}'
    emit_json "working_changes_stashed" "Changes stashed successfully" "$data_json"

    return 0
}

# Restore stashed changes
restore_stashed_changes() {
    if [[ "$STASH_CREATED" == "true" ]]; then
        log "Restoring stashed changes..."
        git stash pop || {
            warn "Failed to restore stashed changes. Manual 'git stash pop' needed."
            return 1
        }
        log "Stashed changes restored successfully"
    fi
    return 0
}

# Cleanup function
cleanup() {
    local exit_code=$?

    if [[ -n "$ORIGINAL_BRANCH" ]]; then
        log "Returning to original branch: $ORIGINAL_BRANCH"
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi

    # Only restore stash if we're exiting cleanly
    if [[ $exit_code -eq 0 ]]; then
        restore_stashed_changes || true
    else
        if [[ "$STASH_CREATED" == "true" ]]; then
            warn "Changes were stashed before error occurred. Restore with: git stash pop"
        fi
    fi

    exit $exit_code
}

# Process single branch
# Args: $1=branch_name, $2=previous_commit (optional, for cherry-pick)
# Returns: 0 on success, 1 on error
# Outputs "COMMIT:<sha>" line to stdout for extraction
process_branch() {
    local branch_name="$1"
    local prev_commit="${2:-}"

    log "Processing branch: $branch_name"

    # Get branch info
    local branch_info
    branch_info=$(get_branch_info "$branch_name") || return $EXIT_ERROR
    local full_ref
    full_ref=$(echo "$branch_info" | jq -r .full_ref)

    # Checkout upstream branch
    git_checkout "$full_ref" || return $EXIT_ERROR

    # Generate PR branch name
    local pr_branch
    pr_branch=$(generate_branch_name "$DEP_NAME" "$DEP_VERSION" "$branch_name")

    # Create new branch (force if dry-run)
    local force="false"
    [[ "$DRY_RUN" == "true" ]] && force="true"
    git_create_branch "$pr_branch" "$force" || return $EXIT_ERROR

    # Try cherry-pick FIRST if previous commit provided and not disabled
    if [[ -n "$prev_commit" ]] && [[ "$NO_CHERRY_PICK" != "true" ]]; then
        log "Attempting cherry-pick from previous branch..."
        if git_cherry_pick "$prev_commit"; then
            local new_commit
            new_commit=$(git_get_head_commit)

            local data_json
            data_json=$(jq -nc --arg branch "$branch_name" --arg commit "$new_commit" --arg source "$prev_commit" \
                '{branch: $branch, commit: $commit, source_commit: $source}')
            emit_json "cherry_pick_success" "Cherry-picked from previous branch" "$data_json"

            # Output commit SHA in tagged format for extraction
            echo "COMMIT:$new_commit"
            return $EXIT_SUCCESS
        else
            local result=$?
            if [[ $result -eq $EXIT_CONFLICT ]]; then
                warn "Cherry-pick conflicts detected, falling back to independent upgrade"
                git_cherry_pick_abort
                # Fall through to independent upgrade below
            else
                error "Cherry-pick failed with unexpected error"
                return $EXIT_ERROR
            fi
        fi
    fi

    # Independent upgrade (no cherry-pick possible or cherry-pick failed)
    log "Performing independent upgrade..."
    yarn_upgrade "$DEP_NAME" "$DEP_VERSION" || return $EXIT_ERROR
    yarn_install || return $EXIT_ERROR

    # Commit changes
    local commit_msg="Upgrade ${DEP_NAME} to ${DEP_VERSION}"
    git_commit "$commit_msg" || return $EXIT_ERROR

    local new_commit
    new_commit=$(git_get_head_commit)

    local data_json
    data_json=$(jq -nc --arg branch "$branch_name" --arg commit "$new_commit" \
        '{branch: $branch, commit: $commit}')
    emit_json "upgrade_success" "Independent upgrade completed" "$data_json"

    # Output commit SHA in tagged format for extraction
    echo "COMMIT:$new_commit"
    return $EXIT_SUCCESS
}

# Main workflow
main() {
    parse_args "$@"

    # Find repo root
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
        error "Not in a git repository"
        exit 1
    }
    cd "$REPO_ROOT"

    # Save original branch
    ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # Set up cleanup trap
    trap cleanup EXIT ERR INT TERM

    # Handle any working changes
    handle_working_changes || exit 1

    # Fetch upstream
    git_fetch "$UPSTREAM_REMOTE" || exit 1

    # Determine branches to process
    local branch_chain
    if [[ -n "$BRANCHES_LIST" ]]; then
        # Custom branch list mode
        log "Using custom branch list: $BRANCHES_LIST"

        # Parse and validate branches
        local branches_json
        branches_json=$(parse_branch_list "$BRANCHES_LIST")

        # Validate all branches exist
        local validation_result
        validation_result=$(validate_branches_exist "$branches_json" "$UPSTREAM_REMOTE")
        local all_exist
        all_exist=$(echo "$validation_result" | jq -r '.all_exist')

        if [[ "$all_exist" != "true" ]]; then
            local missing
            missing=$(echo "$validation_result" | jq -r '.missing[]')
            error "The following branches do not exist in upstream:"
            echo "$missing" | while read -r branch; do
                error "  - $branch"
            done
            emit_json "error" "Invalid branches specified" "$validation_result"
            exit $EXIT_ERROR
        fi

        # Use validated branches
        branch_chain=$(echo "$validation_result" | jq '.existing')

        log "Custom branch chain:"
        echo "$branch_chain" | jq -r '.[]' | while read -r branch; do
            log "  - $branch"
        done

    elif [[ -n "$TARGET" ]]; then
        # Target-based mode
        local branches_md="$REPO_ROOT/docs/BRANCHES.md"
        branch_chain=$(parse_branch_chain "$TARGET" "$branches_md") || exit 1

        log "Branch chain for $TARGET:"
        echo "$branch_chain" | jq -r '.[]' | while read -r branch; do
            log "  - $branch"
        done
    else
        error "Neither --target nor --branches specified (should have been caught by parse_args)"
        exit $EXIT_ERROR
    fi

    # Process master first (always included for all targets)
    log "Processing master branch..."
    local master_commit
    local output
    output=$(process_branch "master") || {
        error "Failed to process master branch"
        exit 1
    }
    # Extract commit SHA from last line (it's written to FD 3, which gets captured)
    master_commit=$(echo "$output" | grep -oE '^COMMIT:[a-f0-9]{40}$' | cut -d: -f2)
    if [[ -z "$master_commit" ]]; then
        error "Failed to extract commit SHA from master branch"
        exit 1
    fi

    # Process each branch in chain sequentially
    local prev_commit="$master_commit"
    local success_count=1  # Include master
    local total_count
    total_count=$(($(echo "$branch_chain" | jq 'length') + 1))  # +1 for master
    local failed_branches=()

    while IFS= read -r branch; do
        local commit
        local output
        if output=$(process_branch "$branch" "$prev_commit"); then
            # Extract commit SHA from tagged line
            commit=$(echo "$output" | grep -oE '^COMMIT:[a-f0-9]{40}$' | cut -d: -f2)
            if [[ -n "$commit" ]]; then
                prev_commit="$commit"
                ((success_count++))
            else
                error "Failed to extract commit SHA from $branch"
                failed_branches+=("$branch")
            fi
        else
            warn "Failed to process $branch, continuing..."
            failed_branches+=("$branch")
        fi
    done < <(echo "$branch_chain" | jq -r '.[]')

    # Push if not dry-run and not no-push
    if [[ "$DRY_RUN" != "true" ]] && [[ "$NO_PUSH" != "true" ]]; then
        log "Pushing branches to $ORIGIN_REMOTE..."
        # Get sanitized version for branch pattern
        local sanitized_ver
        sanitized_ver=$(sanitize_version "$DEP_VERSION")

        # Push all created branches
        git branch --list "bump_${DEP_NAME}_${sanitized_ver}_*" | while read -r branch; do
            git_push "$ORIGIN_REMOTE" "$branch" || warn "Failed to push $branch"
        done
    fi

    # Emit final summary
    local data_json
    if [[ ${#failed_branches[@]} -gt 0 ]]; then
        local failed_json
        failed_json=$(printf '%s\n' "${failed_branches[@]}" | jq -R . | jq -s .)
        data_json=$(jq -nc \
            --argjson total "$total_count" \
            --argjson success "$success_count" \
            --argjson failed "$((total_count - success_count))" \
            --argjson failed_branches "$failed_json" \
            '{total: $total, success: $success, failed: $failed, failed_branches: $failed_branches}')
        emit_json "workflow_complete" "Auto-upgrade completed with failures" "$data_json"
    else
        data_json=$(jq -nc \
            --argjson total "$total_count" \
            --argjson success "$success_count" \
            '{total: $total, success: $success}')
        emit_json "workflow_complete" "Auto-upgrade completed successfully" "$data_json"
    fi

    log "Auto-upgrade completed: $success_count/$total_count branches"
    exit 0
}

main "$@"
