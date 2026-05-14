#!/bin/bash
# Git operations library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Fetch from remote
# Args: $1=remote_name
# Returns: 0 on success, 1 on error
# JSON: {remote: string, refs_updated: int}
git_fetch() {
    local remote="$1"

    log "Fetching from $remote..."
    local output
    output=$(git fetch "$remote" 2>&1) || {
        error "Failed to fetch from $remote: $output"
        emit_json "error" "Git fetch failed" "{\"remote\": \"$remote\"}"
        return $EXIT_ERROR
    }

    local refs_count
    refs_count=$(echo "$output" | grep -c '^\s*\*' || true)
    # grep -c always outputs a count (including 0), but exits 1 if count is 0
    # Use || true to prevent exit code from failing in set -e mode

    local data_json
    data_json=$(jq -nc --arg remote "$remote" --argjson refs "$refs_count" \
        '{remote: $remote, refs_updated: $refs}')
    emit_json "success" "Fetched from $remote" "$data_json"
    return $EXIT_SUCCESS
}

# Checkout branch (creates detached HEAD or switches to branch)
# Args: $1=ref (branch, tag, commit)
# Returns: 0 on success, 1 on error
# JSON: {ref: string, commit: string}
git_checkout() {
    local ref="$1"

    log "Checking out $ref..."
    git checkout "$ref" &>/dev/null || {
        error "Failed to checkout $ref"
        emit_json "error" "Git checkout failed" "{\"ref\": \"$ref\"}"
        return $EXIT_ERROR
    }

    local commit
    commit=$(git rev-parse HEAD)

    emit_json "success" "Checked out $ref" \
        "{\"ref\": \"$ref\", \"commit\": \"$commit\"}"
    return $EXIT_SUCCESS
}

# Create new branch from current HEAD
# Args: $1=branch_name, $2=force (optional, default false)
# Returns: 0 on success, 1 on error
# JSON: {branch: string, commit: string, existed: bool}
git_create_branch() {
    local branch_name="$1"
    local force="${2:-false}"
    local existed=false

    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        existed=true
        if [[ "$force" == "true" ]]; then
            log "Branch $branch_name exists, deleting..."
            git branch -D "$branch_name" &>/dev/null || return $EXIT_ERROR
        else
            error "Branch already exists: $branch_name"
            emit_json "error" "Branch exists" "{\"branch\": \"$branch_name\"}"
            return $EXIT_ERROR
        fi
    fi

    log "Creating branch $branch_name..."
    git checkout -b "$branch_name" &>/dev/null || {
        error "Failed to create branch $branch_name"
        emit_json "error" "Branch creation failed" "{\"branch\": \"$branch_name\"}"
        return $EXIT_ERROR
    }

    local commit
    commit=$(git rev-parse HEAD)

    emit_json "success" "Created branch $branch_name" \
        "{\"branch\": \"$branch_name\", \"commit\": \"$commit\", \"existed\": $existed}"
    return $EXIT_SUCCESS
}

# Cherry-pick commit(s)
# Args: $1=commit_or_range
# Returns: 0 on success, 2 on conflict, 1 on other error
# JSON: {commit: string, conflicts: [string], status: string}
git_cherry_pick() {
    local commit="$1"

    log "Cherry-picking $commit..."
    local output
    output=$(git cherry-pick "$commit" 2>&1)
    local result=$?

    if [[ $result -eq 0 ]]; then
        emit_json "success" "Cherry-pick succeeded" "{\"commit\": \"$commit\"}"
        return $EXIT_SUCCESS
    fi

    # Check for conflicts
    if echo "$output" | grep -q "CONFLICT"; then
        local conflicts
        conflicts=$(git diff --name-only --diff-filter=U | jq -R . | jq -s .)

        local data_json
        data_json=$(jq -nc --arg commit "$commit" --argjson conflicts "$conflicts" \
            '{commit: $commit, conflicts: $conflicts}')
        emit_json "conflict" "Cherry-pick has conflicts" "$data_json"
        return $EXIT_CONFLICT
    fi

    error "Cherry-pick failed: $output"
    emit_json "error" "Cherry-pick failed" "{\"commit\": \"$commit\"}"
    return $EXIT_ERROR
}

# Abort cherry-pick in progress
# Returns: 0 on success, 1 on error
git_cherry_pick_abort() {
    log "Aborting cherry-pick..."
    git cherry-pick --abort &>/dev/null || {
        error "Failed to abort cherry-pick"
        return $EXIT_ERROR
    }
    return $EXIT_SUCCESS
}

# Commit staged changes
# Args: $1=message
# Returns: 0 on success, 1 on error
# JSON: {commit: string, message: string}
git_commit() {
    local message="$1"

    log "Committing changes..."
    git add -u || {
        error "Failed to stage changes"
        emit_json "error" "Git add failed" "{}"
        return $EXIT_ERROR
    }

    git commit -m "$message" &>/dev/null || {
        error "Failed to commit"
        emit_json "error" "Git commit failed" "{}"
        return $EXIT_ERROR
    }

    local commit
    commit=$(git rev-parse HEAD)

    emit_json "success" "Committed changes" \
        "{\"commit\": \"$commit\", \"message\": $(json_escape "$message")}"
    return $EXIT_SUCCESS
}

# Push branch to remote
# Args: $1=remote, $2=branch, $3=force (optional, default false)
# Returns: 0 on success, 1 on error
git_push() {
    local remote="$1"
    local branch="$2"
    local force="${3:-false}"

    local push_args=()
    [[ "$force" == "true" ]] && push_args+=("--force")

    log "Pushing $branch to $remote..."
    git push "$remote" "$branch" "${push_args[@]}" &>/dev/null || {
        error "Failed to push $branch to $remote"
        emit_json "error" "Git push failed" \
            "{\"remote\": \"$remote\", \"branch\": \"$branch\"}"
        return $EXIT_ERROR
    }

    emit_json "success" "Pushed $branch to $remote" \
        "{\"remote\": \"$remote\", \"branch\": \"$branch\"}"
    return $EXIT_SUCCESS
}

# Reset to commit (hard)
# Args: $1=ref
# Returns: 0 on success, 1 on error
git_reset_hard() {
    local ref="$1"

    log "Resetting to $ref (hard)..."
    git reset --hard "$ref" &>/dev/null || {
        error "Failed to reset to $ref"
        return $EXIT_ERROR
    }
    return $EXIT_SUCCESS
}

# Get last commit SHA on current branch
# Returns: 0 on success, 1 on error
# Stdout: commit SHA
git_get_head_commit() {
    git rev-parse HEAD 2>/dev/null || return $EXIT_ERROR
}
