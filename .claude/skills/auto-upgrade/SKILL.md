---
name: auto-upgrade
description: Fully automate dependency upgrades across multiple release branches
version: 1.0.0
---

# Auto-Upgrade Skill

Automates dependency upgrades across all branches for a deployment target using sequential
cherry-pick strategy with fallback to independent analysis.

## Invocation

```
/auto-upgrade                         # Interactive (prompts for everything)
/auto-upgrade yup ^1.7.1              # Prompts for target selection (including custom branches option)
/auto-upgrade axios ^1.15.2 "ACM/CIM" # Explicit target
/auto-upgrade redux ^5.0.0 OCM --dry-run
```

**Note:** Custom branch selection is available through the target selection prompt by choosing
"Other" (automatically added by the system) and providing a comma-separated list in the amendable
text input.

## Workflow

### Phase 1: Target Selection & Validation

**Step 1.1: Parse arguments**

Extract dependency name, version, and target from args if provided.

If not provided:

- Dependency name: Ask user
- Version: Ask user (show latest from npm if possible)
- Target: Continue to Step 1.2

**Step 1.2: Read deployment targets (if target not provided)**

Read `/home/julie/Work/assisted-installer-ui/docs/BRANCHES.md` to get targets.

Parse the three deployment targets:

- OCM (console.redhat.com)
- ACM/CIM (Advanced Cluster Management)
- OVE/ABI/Disconnected

Count branches per target by reading the markdown tables.

**Step 1.3: Ask user to select target**

Use AskUserQuestion with 4 options (single select):

```javascript
{
  question: "Which deployment target(s) should receive the {dep} {version} upgrade?",
  header: "Target",
  multiSelect: false,
  options: [
    {
      label: "ACM/CIM",
      description: "{count} branches (master + releases/vX.Y-cim through vX.Y-cim)"
    },
    {
      label: "OCM",
      description: "{count} branches (master + releases/vX.Y, vX.Y)"
    },
    {
      label: "OVE/ABI/Disconnected",
      description: "{count} branches (master + release-X.Y through release-X.Y)"
    },
    {
      label: "All targets",
      description: "All {total} branches across OCM, ACM/CIM, and OVE/ABI"
    }
  ]
}
```

**Important:** AskUserQuestion automatically adds an "Other" option that allows amendable text
input. When the user selects "Other", they can enter specific branches in the notes field.

**Step 1.3a: Handle custom branch selection**

If user selects "Other":

1. Extract branch list from annotations:

   ```javascript
   const branch_input = annotations['Which deployment...']['notes'];
   ```

2. Parse comma-separated list (trim whitespace, filter empty):

   ```javascript
   const branches = branch_input
     .split(',')
     .map((b) => b.trim())
     .filter((b) => b.length > 0);
   ```

3. Validate branches using the script:

   ```bash
   cd /home/julie/Work/assisted-installer-ui
   source scripts/lib/branch-chain.sh
   source scripts/lib/common.sh

   # Convert to JSON array
   branches_json=$(printf '%s\n' "${branches[@]}" | jq -R . | jq -s .)

   # Validate
   validation_result=$(validate_branches_exist "$branches_json")
   all_exist=$(echo "$validation_result" | jq -r '.all_exist')
   ```

4. If validation fails, report invalid branches and ask user to try again:

   ```bash
   missing=$(echo "$validation_result" | jq -r '.missing[]')
   # Show error listing missing branches
   # Allow user to correct and re-submit
   ```

5. If validation succeeds, set mode to "custom" and store branch list:
   ```javascript
   MODE = 'custom';
   CUSTOM_BRANCHES = branches.join(','); // For passing to --branches
   ```

If user selects a deployment target (OCM, ACM/CIM, OVE/ABI, All targets):

```javascript
MODE = 'target';
TARGET = selected_option;
```

**Step 1.4: Validate dependency exists**

Check if dependency exists in codebase:

```bash
grep -r "\"${dep}\":" package.json */package.json apps/*/package.json libs/*/package.json
```

If not found: warn user that this will add a new dependency and ask for confirmation.

---

### Phase 2: Execute Auto-Upgrade Script

**Step 2.1: Prepare script invocation**

Build command based on mode:

**For target mode:**

```bash
cd /home/julie/Work/assisted-installer-ui
./scripts/auto-upgrade-runner.sh \
    --dep "${DEP_NAME}" \
    --version "${DEP_VERSION}" \
    --target "${TARGET}" \
    ${DRY_RUN:+--dry-run} \
    ${NO_PUSH:+--no-push} \
    2>&1
```

**For custom branches mode:**

```bash
cd /home/julie/Work/assisted-installer-ui
./scripts/auto-upgrade-runner.sh \
    --dep "${DEP_NAME}" \
    --version "${DEP_VERSION}" \
    --branches "${CUSTOM_BRANCHES}" \
    ${DRY_RUN:+--dry-run} \
    ${NO_PUSH:+--no-push} \
    2>&1
```

**Step 2.2: Run script and monitor progress**

Execute script via Bash tool. Parse JSON output lines in real-time.

Track state for each branch:

```typescript
type BranchResult = {
  branch: string;
  status: 'success' | 'conflict' | 'verify_failed' | 'error';
  commit?: string;
  source_commit?: string;
  method: 'cherry_pick' | 'independent';
};
```

JSON status types to watch for:

- `"status": "success"` with `"message": "Fetched from upstream"` → Log progress
- `"status": "success"` with `"message": "Upgraded ..."` → Mark branch success
- `"status": "cherry_pick_success"` → Mark as cherry-picked, note commit
- `"status": "conflict"` → Mark for review-deps analysis
- `"status": "verify_failed"` → Mark for review-deps analysis
- `"status": "error"` → Mark as failed

**Step 2.3: Handle script errors**

If script exits with non-zero code:

- Check if BRANCHES.md parsing failed
- Check if git fetch failed
- Check if any branches processed successfully
- Continue to Phase 3 for branches that need analysis

---

### Phase 3: Handle Failures with review-deps Logic

For each branch with status `verify_failed` or `conflict`:

**Step 3.1: Checkout failure branch**

```bash
cd /home/julie/Work/assisted-installer-ui
git checkout bump_${dep}_${sanitized_version}_${branch}
```

**Step 3.2: Ensure dependencies installed**

CRITICAL: Before running checks:

```bash
yarn install
```

This ensures node_modules is up-to-date after dependency changes.

**Step 3.3: Run CI checks**

Use the deterministic verify-ci.sh script:

```bash
./scripts/lib/verify-ci.sh "${branch}"
```

This script:

- Runs all CI checks (lint, format, circular_deps, types, unit_tests)
- Saves output to /tmp/auto-upgrade-verify-${branch}-${timestamp}/\*.log
- Returns structured JSON with results for each check
- Returns exit code 0 if all pass, 3 if any fail

Parse the JSON output to determine:

- Which checks failed
- Where the log files are located
- Total passed vs failed count

**Step 3.4: Analyze errors**

Use review-deps error pattern matching table:

| Error Pattern                    | Meaning             | Likely Cause                   |
| -------------------------------- | ------------------- | ------------------------------ |
| `ERESOLVE unable to resolve`     | Dependency conflict | Add resolution to package.json |
| `Cannot find module` / `TS2307`  | Missing export      | API renamed/removed            |
| `Type 'X' not assignable to 'Y'` | Type mismatch       | API signature changed          |
| `peer dependency warning`        | Peer version issue  | Update peer or add resolution  |
| `xxx is not a function`          | Runtime error       | Function removed/renamed       |
| `Circular dependency detected`   | Import cycle        | Package restructured           |

For each error, identify:

- Which check failed (lint, types, tests, etc.)
- Error message pattern
- Affected files
- Root cause (based on pattern table)

**Step 3.5: Fetch release notes**

For the dependency being upgraded, fetch release notes:

```bash
# Get package info
npm view ${DEP_NAME}@${DEP_VERSION} --json | jq -r '.description, .homepage'

# Get repository URL
REPO_URL=$(npm view ${DEP_NAME} repository.url)
```

If GitHub repo, use WebFetch to get:

- Release page: `https://github.com/{owner}/{repo}/releases/tag/v{version}`
- CHANGELOG: `https://github.com/{owner}/{repo}/blob/master/CHANGELOG.md`

Search for breaking changes keywords:

- "BREAKING CHANGE"
- "Migration guide"
- "Deprecated"
- "Removed"
- API changes

**Step 3.6: Scan codebase for affected usage**

Find where the package is used:

```bash
git grep -n "from ['\"]${DEP_NAME}" -- '*.ts' '*.tsx' '*.js' '*.jsx'
git grep -n "require(['\"]${DEP_NAME}" -- '*.ts' '*.tsx' '*.js' '*.jsx'
```

For specific APIs mentioned in breaking changes:

```bash
git grep -n "${deprecated_function}" -- '*.ts' '*.tsx'
```

Read relevant files to understand usage context.

**Step 3.7: Decide fix complexity**

Use decision table:

| Issue Type                       | Fix Strategy                        | Complexity |
| -------------------------------- | ----------------------------------- | ---------- |
| Transitive dependency conflict   | Add resolution to root package.json | Simple ✅  |
| Simple import rename             | Update import statements            | Simple ✅  |
| @types version mismatch          | Update @types package               | Simple ✅  |
| Downgrade needed                 | Revert to compatible version        | Simple ✅  |
| API signature change (1-3 files) | Update function calls               | Simple ✅  |
| API refactor (4+ files)          | Refactor usage across files         | Complex 🎯 |
| New patterns required            | Migrate to new API patterns         | Complex 🎯 |
| Config migration                 | Update build/test config            | Complex 🎯 |

**Simple fix:** Apply directly using Edit tool **Complex fix:** Enter plan mode, recommend manual
review

**Step 3.8: Apply simple fixes**

For simple fixes only:

Use Edit tool to:

- Add resolutions to root package.json
- Update import statements
- Fix API calls
- Update @types versions

Example fix patterns:

```typescript
// Add resolution
// Edit package.json, add to "resolutions" section:
"follow-redirects": "^1.16.0"

// Update import
// Change: import { OldAPI } from 'package'
// To: import { NewAPI } from 'package'

// Update @types
// Change: "@types/react": "^18.0.0"
// To: "@types/react": "^18.2.0"
```

**Step 3.9: Re-install and verify**

After applying fixes:

```bash
yarn install
```

Re-run all verification checks using the verify-ci.sh script:

```bash
./scripts/lib/verify-ci.sh "${branch}"
```

Parse the JSON result:

- If all pass (exit code 0): commit the fixes
- If still failing (exit code 3): mark as failed, recommend manual review
- Log files available in output JSON for debugging

**Step 3.10: Commit fixes**

If verification passes:

```bash
git add -u
git commit -m "Fix errors from ${DEP_NAME} upgrade

- Fixed [specific issue]
- Updated [specific change]

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Save the fix commit SHA for potential cherry-pick to next branch.

---

### Phase 4: Cherry-pick Strategy

**Step 4.1: Track commits**

Maintain commit tracker:

```typescript
type CommitTracker = {
  [branch: string]: {
    upgrade_commit: string;
    fix_commits: string[];
  };
};
```

After each branch completes:

- If cherry-picked: record source commit
- If independent upgrade: record upgrade commit
- If fixes applied: record fix commits

**Step 4.2: Sequential processing**

Process branches in order (newest → oldest):

1. master
2. Each release branch from BRANCHES.md (sorted newest first)

For each branch after master:

1. Script tries cherry-picking previous upgrade commit
2. If conflict: script falls back to independent upgrade
3. Agent checks for verification failures
4. If fixes needed: agent applies fixes
5. If previous branch had fixes: try cherry-picking those too

**Example flow:**

```
master: upgrade independently → commit A, fix errors → commit B
  Next branch tries: cherry-pick A
    Success? Done.
    Conflict? Independent upgrade → commit C, try cherry-pick B
      B applies? Done.
      B conflicts? Fix independently → commit D

releases/v2.17: try cherry-pick from master
  Previous commits: A (upgrade), B (fixes)
  Cherry-pick A: SUCCESS → commit E
  Verification: PASS → Done (no fixes needed)

releases/v2.16: try cherry-pick from v2.17
  Previous commits: E (cherry-picked A)
  Cherry-pick E: CONFLICT
  Fall back: independent upgrade → commit F
  Verification: FAIL (type errors)
  Apply fixes → commit G

releases/v2.15: try cherry-pick from v2.16
  Previous commits: F (upgrade), G (fixes)
  Cherry-pick F: SUCCESS → commit H
  Try cherry-pick G: SUCCESS → commit I
  Verification: PASS → Done
```

---

### Phase 5: Final Report

**Step 5.1: Collect statistics**

From all processed branches, count:

- Total branches attempted
- Successful (no fixes needed)
- Fixed automatically (simple fixes applied)
- Cherry-picked from previous (no independent work)
- Failed (needs manual review)

**Step 5.2: Generate markdown report**

```markdown
# Auto-Upgrade Report: ${dep} → ${version} (${target})

## Summary

- Total branches: ${total}
- Successful (no fixes): ${clean}
- Fixed automatically: ${fixed}
- Cherry-picked: ${cherry_picked}
- Failed (manual review): ${failed}

## Branch Details

${for each branch:}
${status_icon} ${branch_name} - ${description} (${commit_sha})

## Logs

Failed branch logs: ${for each failed branch:}

- /tmp/auto-upgrade-${check}-${branch}.log

## Next Steps

${next_steps_based_on_results}
```

Status icons:

- ✅ Success (clean upgrade or cherry-pick)
- ⚠️ Fixed (auto-fixed errors)
- ❌ Failed (needs manual work)

**Step 5.3: Determine next steps**

Based on results:

- All success: "All branches ready. Create PRs with gh CLI?"
- Some fixed: "Review auto-fixes before creating PRs. Check commits for correctness."
- Some failed: "Failed branches need manual review. See logs above."
- Mix: Combine recommendations

**Step 5.4: Offer PR creation**

If all branches successful or fixed (no failures):

Use AskUserQuestion:

```
All ${count} branches processed successfully. Create pull requests now?

Options:
- Yes, create all PRs
- No, I'll review first
```

If yes:

```bash
# For each successful branch
for branch in bump_${dep}_*; do
  # Extract base branch name
  base=$(echo $branch | sed 's/bump_.*_.*_//' | sed 's/-/\//g')

  # Create PR
  gh pr create \
    --base "$base" \
    --head "$branch" \
    --title "chore(deps): update ${dep} to ${version}" \
    --body "Automated dependency upgrade via /auto-upgrade skill

## Changes
- Upgraded ${dep} from ${old_version} to ${version}
${if fixes applied:}
- Fixed type errors / API changes
${endif}

## Verification
All CI checks passing locally.

---
🤖 Generated with Claude Code /auto-upgrade skill"
done
```

---

## Error Handling

### Script-level errors

**Fatal (abort):**

- BRANCHES.md not found or unparseable
- Git fetch fails
- Not in a git repository
- Invalid target specified

Report error, provide troubleshooting steps, exit.

**Non-fatal (continue):**

- Single branch cherry-pick fails → falls back automatically
- Single branch upgrade fails → mark failed, continue to next
- Verification fails → proceed to Phase 3 analysis

### Agent-level errors

**Recoverable:**

- Release notes not available → continue with error analysis only
- Git grep finds no usages → note in report, may be transitive dep
- WebFetch fails → use npm view only

**Non-recoverable:**

- Cannot apply simple fix (Edit tool fails) → mark as complex, recommend plan mode
- Cannot commit fixes (git error) → report error, recommend manual commit
- All branches fail → report issue, recommend investigation

### Cherry-pick conflicts

Handled automatically by script:

1. Script detects conflict (exit code 2)
2. Script aborts cherry-pick
3. Script falls back to independent upgrade
4. Script emits JSON with conflict status
5. Agent logs this in report as "independent upgrade (cherry-pick failed)"

---

## Options

The skill respects these flags (passed to script):

- `--dry-run`: Test without creating branches or pushing
- `--no-push`: Create branches locally, don't push to origin
- `--no-cherry-pick`: Skip all cherry-pick attempts, always upgrade independently

User can specify via args:

```
/auto-upgrade axios ^1.15.2 ACM/CIM --dry-run
```

---

## Project-Specific Context

**Critical dependencies** (from review-deps skill):

- PatternFly (`@patternfly/*`): UI components, breaking changes affect all
- React: Core framework, major versions significant
- Redux/Redux Toolkit: State management APIs
- i18next: Translation library
- TypeScript: Stricter checks surface errors
- Vite: Build tool config changes
- @testing-library/\*: Test API changes

**Workspace structure:**

- Root package.json has `resolutions` for version pinning
- libs/ui-lib is core shared library (highest impact)
- apps/\* are consuming applications
- Changes in libs/ affect all apps

**CI checks:**

- lint: `yarn lint:all`
- format: `yarn format:all`
- circular-deps: `yarn check:circular_deps:all`
- types: `yarn check:types:all`
- unit-tests: `yarn test:unit`
- translation-files: `yarn workspace @openshift-assisted/locales run validate_translation_files`

---

## Tips

**Performance:**

- Cherry-picks save significant time (minutes per branch)
- Failed cherry-picks fall back gracefully
- Serial processing ensures commit tracking works

**Reliability:**

- Always run `yarn install` before verification
- Save logs to /tmp for debugging
- Track commits carefully for cherry-pick chain

**User experience:**

- Show real-time progress from script JSON output
- Provide actionable next steps in report
- Offer PR creation when ready

**Debugging:**

- Check /tmp/auto-upgrade-\*.log files for detailed output
- Script JSON output shows exact steps taken
- Git history shows cherry-pick vs independent commits

---

## Example Session

```
User: /auto-upgrade yup ^1.7.1

Agent: Which deployment target should receive the yup ^1.7.1 upgrade?

User: ACM/CIM

Agent:
[2026-05-14 10:30:00] Fetching from upstream...
[2026-05-14 10:30:05] Processing branch: master
[2026-05-14 10:30:15] ✓ master upgraded cleanly
[2026-05-14 10:30:16] Processing branch: releases/v5.0-cim
[2026-05-14 10:30:20] ✓ releases/v5.0-cim cherry-picked from master
[2026-05-14 10:30:21] Processing branch: releases/v2.18-cim
[2026-05-14 10:30:25] ✓ releases/v2.18-cim cherry-picked from v5.0-cim
...

# Auto-Upgrade Report: yup → ^1.7.1 (ACM/CIM)

## Summary
- Total branches: 7
- Successful (no fixes): 7
- Cherry-picked: 6

## Branch Details
✅ master - Upgraded cleanly (abc123)
✅ releases/v5.0-cim - Cherry-picked from master (def456)
✅ releases/v2.18-cim - Cherry-picked from v5.0-cim (ghi789)
✅ releases/v2.17-cim - Cherry-picked from v2.18-cim (jkl012)
✅ releases/v2.16-cim - Cherry-picked from v2.17-cim (mno345)
✅ releases/v2.15-cim - Cherry-picked from v2.16-cim (pqr678)
✅ releases/v2.14-cim - Cherry-picked from v2.15-cim (stu901)

## Next Steps
All 7 branches ready for PR creation!

Create pull requests now? [Yes / No]
```
