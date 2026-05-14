#!/bin/bash
# CI verification script - runs all CI checks and outputs structured results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Run all CI verification checks
# Args: $1=branch_name (used for log file naming)
# Returns: 0 if all pass, 3 if any fail, 1 on execution error
# JSON: {total: int, passed: int, failed: int, checks: [{name, status, exit_code, log_file}]}
verify_all_checks() {
    local branch_name="${1:-unknown}"
    local timestamp
    timestamp=$(date +%s)

    log "Running all CI verification checks..."

    # Create temp directory for logs
    local log_dir="/tmp/auto-upgrade-verify-${branch_name}-${timestamp}"
    mkdir -p "$log_dir"

    local checks=()
    local total=0
    local passed=0
    local failed=0

    # Define checks to run
    local check_commands=(
        "lint:yarn lint:all"
        "format:yarn format:all"
        "circular_deps:yarn check:circular_deps:all"
        "types:yarn check:types:all"
        "unit_tests:yarn test:unit"
    )

    # Run each check
    for check_def in "${check_commands[@]}"; do
        local check_name="${check_def%%:*}"
        local check_cmd="${check_def#*:}"
        local log_file="${log_dir}/${check_name}.log"

        ((total++))

        log "  Running $check_name..."
        local output
        output=$(eval "$check_cmd" 2>&1)
        local exit_code=$?

        # Save output to log file
        echo "$output" > "$log_file"

        if [[ $exit_code -eq 0 ]]; then
            ((passed++))
            log "  ✓ $check_name passed"
            local check_json
            check_json=$(jq -nc --arg name "$check_name" --arg status "passed" --arg log "$log_file" \
                '{name: $name, status: $status, exit_code: 0, log_file: $log}')
            checks+=("$check_json")
        else
            ((failed++))
            error "  ✗ $check_name failed (exit code: $exit_code)"
            local check_json
            check_json=$(jq -nc --arg name "$check_name" --arg status "failed" --arg log "$log_file" --arg code "$exit_code" \
                '{name: $name, status: $status, exit_code: ($code|tonumber), log_file: $log}')
            checks+=("$check_json")
        fi
    done

    # Build checks JSON array (compact to avoid newline issues with --argjson)
    local checks_json
    if [[ ${#checks[@]} -gt 0 ]]; then
        # Use -c for compact output
        checks_json=$(printf '%s\n' "${checks[@]}" | jq -sc .)
        if [[ $? -ne 0 ]] || [[ -z "$checks_json" ]]; then
            error "Failed to build checks JSON array"
            checks_json="[]"
        fi
    else
        checks_json="[]"
    fi

    # Validate checks_json is valid JSON
    if ! echo "$checks_json" | jq . >/dev/null 2>&1; then
        error "checks_json is not valid JSON, using empty array"
        checks_json="[]"
    fi

    # Build data JSON properly using jq (not shell interpolation)
    # Use compact output (-c) to avoid issues
    local data_json
    data_json=$(jq -nc \
        --argjson total "$total" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson checks "$checks_json" \
        --arg log_dir "$log_dir" \
        '{total: $total, passed: $passed, failed: $failed, checks: $checks, log_dir: $log_dir}')

    if [[ $? -ne 0 ]] || [[ -z "$data_json" ]]; then
        error "Failed to build data JSON, using fallback"
        data_json='{"total": 0, "passed": 0, "failed": 0, "checks": [], "log_dir": ""}'
    fi

    # Validate data_json before using it
    if ! echo "$data_json" | jq . >/dev/null 2>&1; then
        error "data_json is not valid JSON, using fallback"
        data_json='{"total": 0, "passed": 0, "failed": 0, "checks": [], "log_dir": ""}'
    fi

    # Emit summary JSON
    emit_json "verify_complete" "Verification checks completed" "$data_json"

    if [[ $failed -gt 0 ]]; then
        error "Verification failed: $failed/$total checks failed"
        error "Logs saved to: $log_dir"
        return $EXIT_VERIFY_FAILED
    fi

    log "All $total verification checks passed"
    return $EXIT_SUCCESS
}

# Main entry point when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse args
    branch_name="${1:-current}"

    # Run verification
    verify_all_checks "$branch_name"
    exit $?
fi
