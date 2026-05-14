#!/bin/bash
# Yarn operations library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Upgrade dependency
# Args: $1=package_name, $2=version
# Returns: 0 on success, 1 on error
# JSON: {package: string, version: string, changes: [string]}
yarn_upgrade() {
    local package="$1"
    local version="$2"

    log "Upgrading $package to $version..."
    local output
    output=$(yarn up "${package}@${version}" 2>&1)
    local result=$?

    if [[ $result -ne 0 ]]; then
        error "Failed to upgrade $package: $output"
        emit_json "error" "Yarn upgrade failed" \
            "{\"package\": \"$package\", \"version\": \"$version\"}"
        return $EXIT_ERROR
    fi

    # Extract changed files
    local changes
    changes=$(git diff --name-only | jq -R . | jq -s .)

    local data_json
    data_json=$(jq -nc --arg package "$package" --arg version "$version" --argjson changes "$changes" \
        '{package: $package, version: $version, changes: $changes}')
    emit_json "success" "Upgraded $package to $version" "$data_json"
    return $EXIT_SUCCESS
}

# Install dependencies
# Returns: 0 on success, 1 on error
# JSON: {duration_seconds: float}
yarn_install() {
    log "Running yarn install..."
    local start_time
    start_time=$(date +%s)

    local output
    output=$(yarn install 2>&1)
    local result=$?

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $result -ne 0 ]]; then
        error "Yarn install failed: $output"
        emit_json "error" "Yarn install failed" "{}"
        return $EXIT_ERROR
    fi

    emit_json "success" "Dependencies installed" \
        "{\"duration_seconds\": $duration}"
    return $EXIT_SUCCESS
}
