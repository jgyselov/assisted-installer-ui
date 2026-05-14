#!/bin/bash
# Branch chain processing library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse BRANCHES.md to extract branch chain for target
# Args: $1=target_name (OCM, ACM/CIM, or OVE/ABI), $2=branches_md_path
# Returns: 0 on success, 1 on error
# Stdout: JSON array of branches (newest to oldest, excluding master)
parse_branch_chain() {
    local target="$1"
    local branches_md="$2"

    if [[ ! -f "$branches_md" ]]; then
        error "BRANCHES.md not found: $branches_md"
        return $EXIT_ERROR
    fi

    # Normalize target name for matching
    local normalized_target="$target"
    if [[ "$target" == "OVE" ]] || [[ "$target" == "OVE/ABI" ]] || [[ "$target" == "OVE/ABI/Disconnected" ]]; then
        normalized_target="OVE/ABI/Disconnected"
    fi

    local awk_script='
    BEGIN { in_section=0; FS="|" }

    # Detect section start
    /^## OCM/ {
        in_section=(target == "OCM") ? 1 : 0
        next
    }
    /^## ACM\/CIM/ {
        in_section=(target == "ACM/CIM") ? 1 : 0
        next
    }
    /^## OVE\/ABI/ {
        in_section=(target == "OVE/ABI/Disconnected") ? 1 : 0
        next
    }

    # Section ended
    /^##/ && !/^## (OCM|ACM\/CIM|OVE\/ABI)/ {
        in_section=0
        next
    }
    /^---$/ { next }

    # Parse table rows
    in_section && /^\|/ && !/^\| Branch/ {
        # Extract second column (branch name in backticks)
        if (match($2, /`([^`]+)`/, arr)) {
            branch = arr[1]
            # Skip master
            if (branch != "master" && branch != "main" && branch != "" && branch != "Branch") {
                print branch
            }
        }
    }
    '

    local branches
    branches=$(awk -v target="$normalized_target" "$awk_script" "$branches_md")

    if [[ -z "$branches" ]]; then
        error "No branches found for target: $target"
        return $EXIT_ERROR
    fi

    # Convert to JSON array
    echo "$branches" | jq -R . | jq -s .
    return $EXIT_SUCCESS
}

# Determine branch type and construct full ref
# Args: $1=branch_name
# Returns: 0 on success, 1 on error
# Stdout: JSON {name: string, type: string, full_ref: string}
get_branch_info() {
    local branch="$1"
    local type=""
    local full_ref=""

    # ============================================================================
    # TEMPORARY: Testing with origin instead of upstream - REVERT BEFORE COMMIT
    # ============================================================================
    local base_remote="origin"  # TEMPORARY: Change back to "upstream"
    # ============================================================================

    if [[ "$branch" == "master" ]] || [[ "$branch" == "main" ]]; then
        type="master"
        full_ref="${base_remote}/$branch"  # TEMPORARY: was upstream/$branch
    elif [[ "$branch" =~ ^releases/ ]]; then
        type="release"
        full_ref="${base_remote}/$branch"  # TEMPORARY: was upstream/$branch
    elif [[ "$branch" =~ ^release- ]]; then
        type="release"
        full_ref="${base_remote}/$branch"  # TEMPORARY: was upstream/$branch
    elif [[ "$branch" =~ ^v[0-9]+\.[0-9]+ ]]; then
        # Handle branches like v2.52 without releases/ prefix
        type="release"
        full_ref="${base_remote}/releases/$branch"  # TEMPORARY: was upstream/releases/$branch
    else
        error "Unknown branch type: $branch"
        return $EXIT_ERROR
    fi

    jq -nc \
        --arg name "$branch" \
        --arg type "$type" \
        --arg ref "$full_ref" \
        '{name: $name, type: $type, full_ref: $ref}'

    return $EXIT_SUCCESS
}

# Generate branch name for upgrade PR
# Args: $1=dep_name, $2=version, $3=base_branch
# Stdout: branch name
generate_branch_name() {
    local dep="$1"
    local version
    version=$(sanitize_version "$2")
    local base="$3"

    # Replace / with - in base branch name
    local safe_base
    safe_base=$(echo "$base" | sed 's/\//-/g')

    echo "bump_${dep}_${version}_${safe_base}"
}

# Parse comma-separated branch list from user input
# Args: $1=comma_separated_string
# Returns: 0 on success
# Stdout: JSON array of branch names (trimmed, deduplicated)
parse_branch_list() {
    local branch_string="$1"

    # Split on commas, trim whitespace, remove duplicates
    echo "$branch_string" | tr ',' '\n' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -v '^$' | \
        sort -u | \
        jq -R . | jq -s .

    return $EXIT_SUCCESS
}

# Validate that branches exist in upstream remote
# Args: $1=JSON array of branch names, $2=remote (default: upstream)
# Returns: 0 if all exist, 1 if any missing
# JSON: {all_exist: bool, existing: [string], missing: [string]}
validate_branches_exist() {
    local branches_json="$1"
    # ============================================================================
    # TEMPORARY: Testing with origin - REVERT BEFORE COMMIT
    # ============================================================================
    local remote="${2:-origin}"  # TEMPORARY: Change back to "upstream"
    # ============================================================================

    local existing=()
    local missing=()

    # Parse JSON array
    local branches
    branches=$(echo "$branches_json" | jq -r '.[]')

    # Get all remote branches once (more efficient than multiple ls-remote calls)
    local remote_branches
    remote_branches=$(git ls-remote --heads --tags "$remote" 2>/dev/null | awk '{print $2}')

    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue

        # Check if this branch exists in remote (with any standard prefix)
        if echo "$remote_branches" | grep -q -E "^refs/(heads|tags)/${branch}$"; then
            existing+=("$branch")
        else
            missing+=("$branch")
        fi
    done <<< "$branches"

    # Build JSON arrays
    local existing_json
    if [[ ${#existing[@]} -gt 0 ]]; then
        existing_json=$(printf '%s\n' "${existing[@]}" | jq -R . | jq -s .)
    else
        existing_json="[]"
    fi

    local missing_json
    if [[ ${#missing[@]} -gt 0 ]]; then
        missing_json=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)
    else
        missing_json="[]"
    fi

    local all_exist=false
    [[ ${#missing[@]} -eq 0 ]] && all_exist=true

    # Emit result
    jq -nc \
        --argjson all_exist "$all_exist" \
        --argjson existing "$existing_json" \
        --argjson missing "$missing_json" \
        '{all_exist: $all_exist, existing: $existing, missing: $missing}'

    [[ ${#missing[@]} -eq 0 ]] && return $EXIT_SUCCESS
    return $EXIT_ERROR
}
