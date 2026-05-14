#!/bin/bash
# Common utilities for auto-upgrade scripts

# Exit codes (only declare if not already set)
if [[ -z "${EXIT_SUCCESS:-}" ]]; then
    readonly EXIT_SUCCESS=0
    readonly EXIT_ERROR=1
    readonly EXIT_CONFLICT=2
    readonly EXIT_VERIFY_FAILED=3
fi

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
}

warn() {
    echo "[WARN] $*" >&2
}

# JSON output helpers
json_escape() {
    local str="$1"
    printf '%s' "$str" | jq -Rs .
}

emit_json() {
    local status="$1"
    local message="$2"
    local data="$3"

    # Provide default empty object if data is not provided
    if [[ -z "$data" ]]; then
        data="{}"
    fi

    jq -nc \
        --arg status "$status" \
        --arg message "$message" \
        --argjson data "$data" \
        '{status: $status, message: $message, data: $data}'
}

# Version sanitization
sanitize_version() {
    local version="$1"
    # Remove: ^ ~ < > = @ and spaces
    # Keep: alphanumeric, -, _, .
    echo "$version" | sed 's/[\^~<>=@ ]//g'
}
