#!/bin/bash
set -euo pipefail

# Dependency Update Script
# Automates updating dependencies across multiple release branches

#=============================================================================
# Global Variables
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.update-deps.conf"
ORIGINAL_BRANCH=""
LOG_FILE=""
DRY_RUN=false

# Counters for summary
TOTAL_BRANCHES=0
SUCCESS_COUNT=0
FAILED_BRANCHES=()

#=============================================================================
# Helper Functions
#=============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Update dependencies across multiple release branches.

OPTIONS:
    --dry-run                    Test updates without creating branches or pushing
    --dependency-name NAME       Override dependency name from config
    --dependency-version VER     Override dependency version from config
    --config FILE               Use alternate config file (default: .update-deps.conf)
    --no-push                   Create branches but don't push to remote
    -h, --help                  Show this help message

EXAMPLES:
    $(basename "$0")                                          # Use config defaults
    $(basename "$0") --dry-run                                # Test without changes
    $(basename "$0") --dependency-name lodash --dependency-version ^4.17.21
    $(basename "$0") --no-push                                # Create branches locally only

EOF
    exit 0
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

cleanup() {
    local exit_code=$?

    if [[ -n "$ORIGINAL_BRANCH" ]] && [[ -d "${SCRIPT_DIR}/${REPO_DIR}/.git" ]]; then
        log "Cleaning up: returning to original branch"
        cd "${SCRIPT_DIR}/${REPO_DIR}"
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi

    if [[ $exit_code -ne 0 ]]; then
        error "Script failed. Check log file: $LOG_FILE"
    fi

    exit $exit_code
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Config file not found: $CONFIG_FILE"
        error "Create one or specify with --config"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    log "Loaded config from: $CONFIG_FILE"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --dependency-name)
                DEPENDENCY_NAME="$2"
                shift 2
                ;;
            --dependency-version)
                DEPENDENCY_VERSION="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --no-push)
                AUTO_PUSH=false
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

validate_config() {
    local errors=0

    [[ -z "${REPO_DIR:-}" ]] && { error "REPO_DIR not set"; ((errors++)); }
    [[ -z "${UPSTREAM_REMOTE:-}" ]] && { error "UPSTREAM_REMOTE not set"; ((errors++)); }
    [[ -z "${ORIGIN_REMOTE:-}" ]] && { error "ORIGIN_REMOTE not set"; ((errors++)); }
    [[ -z "${DEPENDENCY_NAME:-}" ]] && { error "DEPENDENCY_NAME not set"; ((errors++)); }
    [[ -z "${DEPENDENCY_VERSION:-}" ]] && { error "DEPENDENCY_VERSION not set"; ((errors++)); }
    [[ ${#BRANCHES[@]} -eq 0 ]] && { error "BRANCHES array is empty"; ((errors++)); }

    if [[ $errors -gt 0 ]]; then
        error "Configuration validation failed with $errors error(s)"
        exit 1
    fi

    log "Configuration validated successfully"
}

sanitize_version() {
    local version="$1"
    # Remove: ^ ~ < > = @ and spaces
    # Keep: alphanumeric, -, _, .
    echo "$version" | sed 's/[\^~<>=@ ]//g'
}

setup_logging() {
    local sanitized_version
    sanitized_version=$(sanitize_version "$DEPENDENCY_VERSION")
    local timestamp
    timestamp=$(date +'%Y%m%d-%H%M%S')

    LOG_FILE="${SCRIPT_DIR}/update-${DEPENDENCY_NAME}-${sanitized_version}-${timestamp}.log"

    # Redirect all output to log file while still showing on console
    exec > >(tee -a "$LOG_FILE") 2>&1

    log "Log file: $LOG_FILE"
}

pre_flight_checks() {
    log "Running pre-flight checks..."

    # Check if repo directory exists
    if [[ ! -d "${SCRIPT_DIR}/${REPO_DIR}" ]]; then
        error "Repository directory not found: ${SCRIPT_DIR}/${REPO_DIR}"
        exit 1
    fi

    cd "${SCRIPT_DIR}/${REPO_DIR}"

    # Check if it's a git repository
    if [[ ! -d .git ]]; then
        error "Not a git repository: ${SCRIPT_DIR}/${REPO_DIR}"
        exit 1
    fi

    # Check for clean working tree (only in non-dry-run mode)
    if [[ "$DRY_RUN" == false ]]; then
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            error "Working tree has uncommitted changes. Commit or stash them first."
            git status --short
            exit 1
        fi
    fi

    # Save original branch
    ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log "Original branch: $ORIGINAL_BRANCH"

    # Fetch upstream
    log "Fetching from $UPSTREAM_REMOTE..."
    git fetch "$UPSTREAM_REMOTE"

    log "Pre-flight checks passed"
}

handle_existing_branch() {
    local branch_name="$1"

    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        if [[ "$OVERWRITE_EXISTING_BRANCHES" == true ]]; then
            log "Deleting existing branch: $branch_name"
            git branch -D "$branch_name"
        else
            error "Branch already exists: $branch_name"
            error "Set OVERWRITE_EXISTING_BRANCHES=true to overwrite"
            exit 1
        fi
    fi
}

run_verifications() {
    local version="$1"
    local all_passed=true

    if [[ ${#VERIFY_COMMANDS[@]} -eq 0 ]]; then
        log "  No verification commands configured"
        return 0
    fi

    for cmd in "${VERIFY_COMMANDS[@]}"; do
        log "  Running: $cmd"
        if ! eval "$cmd" > /dev/null 2>&1; then
            error "  FAILED: $cmd"
            all_passed=false
            break
        fi
    done

    if [[ "$all_passed" == true ]]; then
        echo "✓ $version - all checks passed"
        return 0
    else
        echo "✗ $version - verification failed"
        return 1
    fi
}

process_branch_dry_run() {
    local version="$1"
    local upstream_branch

    # Special handling for master/main - no prefix
    if [[ "$version" == "master" ]] || [[ "$version" == "main" ]]; then
        upstream_branch="${UPSTREAM_REMOTE}/${version}"
    else
        upstream_branch="${UPSTREAM_REMOTE}/${BRANCH_PATH_PREFIX}${version}"
    fi

    log "Testing $version..."

    # Checkout upstream branch (detached HEAD)
    if ! git checkout "$upstream_branch" 2>/dev/null; then
        error "  Failed to checkout $upstream_branch"
        echo "✗ $version - checkout failed"
        return 1
    fi

    # Update dependency
    log "  Running: yarn up ${DEPENDENCY_NAME}@${DEPENDENCY_VERSION}"
    if ! yarn up "${DEPENDENCY_NAME}@${DEPENDENCY_VERSION}" > /dev/null 2>&1; then
        error "  Failed to update dependency"
        echo "✗ $version - yarn up failed"
        git reset --hard > /dev/null 2>&1
        return 1
    fi

    # Install dependencies
    log "  Running: yarn install"
    if ! yarn install > /dev/null 2>&1; then
        error "  Failed to install dependencies"
        echo "✗ $version - yarn install failed"
        git reset --hard > /dev/null 2>&1
        return 1
    fi

    # Run verifications
    local result=0
    run_verifications "$version" || result=$?

    # Cleanup
    git reset --hard > /dev/null 2>&1

    return $result
}

process_branch_normal() {
    local version="$1"
    local sanitized_version
    sanitized_version=$(sanitize_version "$DEPENDENCY_VERSION")
    local branch_name="bump_${DEPENDENCY_NAME}_${sanitized_version}_${version}"
    local upstream_branch

    # Special handling for master/main - no prefix
    if [[ "$version" == "master" ]] || [[ "$version" == "main" ]]; then
        upstream_branch="${UPSTREAM_REMOTE}/${version}"
    else
        upstream_branch="${UPSTREAM_REMOTE}/${BRANCH_PATH_PREFIX}${version}"
    fi

    log "Processing $version..."

    # Handle existing branch
    handle_existing_branch "$branch_name"

    # Checkout upstream branch
    log "  Checking out $upstream_branch"
    if ! git checkout "$upstream_branch"; then
        error "  Failed to checkout $upstream_branch"
        FAILED_BRANCHES+=("$version")
        return 1
    fi

    # Create new branch
    log "  Creating branch: $branch_name"
    git checkout -B "$branch_name"

    # Update dependency
    log "  Running: yarn up ${DEPENDENCY_NAME}@${DEPENDENCY_VERSION}"
    if ! yarn up "${DEPENDENCY_NAME}@${DEPENDENCY_VERSION}"; then
        error "  Failed to update dependency"
        FAILED_BRANCHES+=("$version")
        return 1
    fi

    # Install dependencies
    log "  Running: yarn install"
    if ! yarn install; then
        error "  Failed to install dependencies"
        FAILED_BRANCHES+=("$version")
        return 1
    fi

    # Stage only tracked files (excludes submodules)
    log "  Staging changes (tracked files only)"
    git add -u

    # Commit changes
    local commit_message="Upgrade ${DEPENDENCY_NAME} to ${DEPENDENCY_VERSION}"
    log "  Committing: $commit_message"
    if ! git commit -m "$commit_message"; then
        error "  Failed to commit changes"
        FAILED_BRANCHES+=("$version")
        return 1
    fi

    # Push to origin
    if [[ "$AUTO_PUSH" == true ]]; then
        log "  Pushing to $ORIGIN_REMOTE/$branch_name"
        if ! git push "$ORIGIN_REMOTE" "$branch_name"; then
            error "  Failed to push branch"
            FAILED_BRANCHES+=("$version")
            return 1
        fi
    fi

    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    log "  ✓ Successfully processed $version"
    return 0
}

print_summary() {
    echo
    echo "========================================="
    echo "Summary"
    echo "========================================="

    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run completed: $SUCCESS_COUNT/$TOTAL_BRANCHES branches ready"
    else
        echo "Successfully updated: $SUCCESS_COUNT/$TOTAL_BRANCHES branches"
    fi

    if [[ ${#FAILED_BRANCHES[@]} -gt 0 ]]; then
        echo "Failed branches: ${FAILED_BRANCHES[*]}"
    fi

    if [[ "$DRY_RUN" == false ]] && [[ "$AUTO_PUSH" == true ]] && [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo "Pushed to: $ORIGIN_REMOTE"
    fi

    echo "Log file: $LOG_FILE"
    echo "========================================="
}

main() {
    # Parse CLI arguments
    parse_args "$@"

    # Load and validate configuration
    load_config
    validate_config

    # Setup logging
    setup_logging

    # Set up cleanup trap
    trap cleanup EXIT ERR

    log "Starting dependency update script"
    log "Dependency: ${DEPENDENCY_NAME}@${DEPENDENCY_VERSION}"
    log "Mode: $([ "$DRY_RUN" == true ] && echo "DRY RUN" || echo "NORMAL")"

    # Pre-flight checks
    pre_flight_checks

    # Process each branch
    TOTAL_BRANCHES=${#BRANCHES[@]}

    if [[ "$DRY_RUN" == true ]]; then
        echo
        echo "Dry run: Testing ${DEPENDENCY_NAME}@${DEPENDENCY_VERSION} across $TOTAL_BRANCHES branches..."
        echo

        for version in "${BRANCHES[@]}"; do
            if process_branch_dry_run "$version"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
        done
    else
        for version in "${BRANCHES[@]}"; do
            process_branch_normal "$version" || true
        done

        # Return to original branch
        log "Returning to original branch: $ORIGINAL_BRANCH"
        git checkout "$ORIGINAL_BRANCH"
    fi

    # Print summary
    print_summary

    # Exit with appropriate code
    if [[ $SUCCESS_COUNT -eq $TOTAL_BRANCHES ]]; then
        exit 0
    else
        exit 1
    fi
}

#=============================================================================
# Script Entry Point
#=============================================================================

main "$@"
