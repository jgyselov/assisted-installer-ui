---
name: review-deps
description:
  Analyze dependency upgrade PRs for breaking changes, identify root causes, and propose/apply fixes
version: 1.0.0
---

# Dependency Upgrade Review Skill

Analyzes dependency upgrade PRs that fail CI checks, identifies root causes, proposes fixes, and
applies them when appropriate.

## Invocation

```
/review-deps              # Analyze current branch vs master
/review-deps 3710         # Analyze PR #3710 (if gh CLI available)
/review-deps --verbose    # Show detailed analysis with full error logs
```

## Workflow

Follow these phases sequentially. Be methodical and thorough in your analysis.

### Phase 1: Identify Dependency Changes

**Step 1.1: Determine context and get changes**

Check if PR number was provided in args:

- If yes and `gh` CLI is available: `gh pr view <PR> --json headRefName,statusCheckRollup`
- If gh available, checkout the PR branch: `gh pr checkout <PR>`
- Otherwise: work from current branch

Get dependency changes:

```bash
git diff origin/master...HEAD -- '**/package.json' 'yarn.lock'
```

**Step 1.2: Parse dependency changes**

Identify:

- Which packages changed (name, old version, new version)
- Change type: major, minor, or patch (use semver)
- Which workspace packages are affected (root, libs/ui-lib, apps/\*, etc.)

**Step 1.3: Flag high-risk changes**

Mark as high-risk:

- Major version bumps (X.0.0 → (X+1).0.0)
- Packages commonly causing breaks: React, TypeScript, Redux, PatternFly, i18next, Vite, webpack,
  babel
- Any change to build tools or test frameworks

Output a summary like:

```
Changed Dependencies:
- axios: 1.15.1 → 1.15.2 (patch) ✅
- redux: 4.2.1 → 5.0.0 (major) ⚠️  HIGH RISK
- @types/react: 18.0.0 → 18.2.0 (minor) ✅
```

---

### Phase 2: Identify Failures

**Step 2.1: Check CI status (if applicable)**

If `gh` CLI available and PR provided:

```bash
gh pr checks <PR>
```

Identify which checks failed: lint, format, circular-deps, check_types, tests

**Step 2.2: Ensure dependencies are installed**

**IMPORTANT:** Before running any checks, ensure node_modules is up-to-date:

```bash
yarn install
```

This is critical when dependencies have changed - running checks with stale node_modules will
produce false failures.

**Step 2.3: Run local checks**

Run the CI checks locally to reproduce failures:

```bash
yarn lint:all 2>&1 | tee /tmp/lint-output.log
yarn format:all 2>&1 | tee /tmp/format-output.log
yarn check:circular_deps:all 2>&1 | tee /tmp/circular-deps-output.log
yarn check:types:all 2>&1 | tee /tmp/types-output.log
yarn test:unit 2>&1 | tee /tmp/test-output.log
```

For each failed check, capture:

- Exit code
- Error messages
- File paths with errors
- Line numbers if available

**Step 2.4: Parse error patterns**

Match errors to known patterns:

| Error Pattern                            | Meaning             | Likely Cause                                   |
| ---------------------------------------- | ------------------- | ---------------------------------------------- |
| `ERESOLVE unable to resolve`             | Dependency conflict | Transitive dependency version mismatch         |
| `Cannot find module` / `TS2307`          | Missing export      | Renamed/removed API, import path changed       |
| `Type 'X' is not assignable to type 'Y'` | Type mismatch       | API signature changed, @types version mismatch |
| `peer dependency warning`                | Peer version issue  | Need to update peer or add resolution          |
| `xxx is not a function`                  | Runtime error       | Function removed/renamed                       |
| `Circular dependency detected`           | Import cycle        | Package restructured imports                   |

---

### Phase 3: Analyze & Diagnose

**Step 3.1: Fetch release notes for changed dependencies**

For each major version bump or high-risk change:

```bash
# Try npm view first
npm view <package>@<new-version> --json | jq -r '.description, .homepage'

# Check for repository
npm view <package> repository.url
```

If it's a GitHub repo, try to fetch release notes:

- Extract owner/repo from URL
- Use WebFetch to get `https://github.com/<owner>/<repo>/releases/tag/v<version>`
- Look for CHANGELOG.md: `https://github.com/<owner>/<repo>/blob/master/CHANGELOG.md`

**Step 3.2: Identify breaking changes**

In release notes, search for:

- "BREAKING CHANGE" or "BREAKING:"
- "Migration guide"
- "Upgrade guide"
- "Deprecated" / "Removed"
- API changes, renamed exports

Extract specific changes like:

- "Removed `oldFunction`, use `newFunction` instead"
- "Changed prop `value` to `inputValue`"
- "Requires peer dependency react@^18.0.0"

**Step 3.3: Scan codebase for affected usage**

For packages with breaking changes:

```bash
# Find imports
git grep -n "from ['\"]<package-name>" -- '*.ts' '*.tsx' '*.js' '*.jsx'

# Find requires
git grep -n "require(['\"]<package-name>" -- '*.ts' '*.tsx' '*.js' '*.jsx'

# For specific APIs mentioned in breaking changes
git grep -n "<deprecated-function>" -- '*.ts' '*.tsx'
```

Read the relevant files to understand usage context.

**Step 3.4: Correlate failures to dependency changes**

For each error from Phase 2, determine which dependency change caused it:

- Match package names from error messages to changed deps
- Match file paths to where packages are used
- Connect error types to known breaking changes

Create a mapping:

```
Error: TS2307 Cannot find module 'redux'
→ Caused by: redux 4.2.1 → 5.0.0
→ Breaking change: Removed createStore export
→ Affects: 8 files in libs/ui-lib/lib/*/store/
```

---

### Phase 4: Propose Fixes

For each identified issue, propose a specific fix using this decision table:

| Issue Type                       | Fix Strategy                                 | Complexity     |
| -------------------------------- | -------------------------------------------- | -------------- |
| Transitive dependency conflict   | Add explicit resolution to root package.json | Simple ✅      |
| Simple import rename             | Update import statements                     | Simple ✅      |
| @types version mismatch          | Update @types package to match runtime       | Simple ✅      |
| Downgrade needed                 | Revert to previous compatible version        | Simple ✅      |
| API signature change (1-3 files) | Update function calls                        | Simple ✅      |
| API refactor (4+ files)          | Refactor usage across files                  | **Complex** 🎯 |
| New patterns required            | Migrate to new API patterns                  | **Complex** 🎯 |
| Config migration                 | Update build/test config                     | **Complex** 🎯 |
| Translation format change        | Update i18n files                            | **Complex** 🎯 |

**Simple fix examples:**

- Add `"follow-redirects": "^1.16.0"` to resolutions
- Change `import { OldAPI }` to `import { NewAPI }`
- Update `@types/react` to `^18.2.0`

**Complex fix indicators:**

- Affects >5 files
- Requires logic changes, not just renames
- Involves architectural decisions
- Migration guides suggest multi-step process
- Behavioral changes with side effects

---

### Phase 5: Present Findings & Apply Fixes

**Step 5.1: Generate report**

Create a structured markdown report using this template:

```markdown
# Dependency Review - Branch: <branch-name>

## Changed Dependencies

[List with risk levels]

## CI Check Results

[Which passed/failed]

## Root Cause Analysis

### Issue 1: <Title>

**Package:** <package> <old> → <new> **Failure type:** <type> **Evidence:**
<error message or log excerpt>

**Proposed Fix:** <specific fix description> **Complexity:** [Simple/Complex] [If simple: exact code
changes] [If complex: high-level approach]

[Repeat for each issue]

---

## Recommended Actions

[Summary of what to do]
```

**Step 5.2: Assess overall complexity**

Count:

- Simple fixes: can apply directly
- Complex fixes: need plan mode

**Step 5.3: Interactive decision**

If ALL fixes are simple:

- Use AskUserQuestion: "I found X issues with simple fixes. Should I apply them? [Yes/Show
  details/Skip]"
- If approved, proceed to Step 5.4

If ANY fix is complex:

- State: "Some fixes require extensive changes (affecting X files). I recommend entering plan mode
  to design the migration properly."
- Use EnterPlanMode with context about what needs to change
- Stop here; plan mode will handle implementation

If unclear or no correlation found:

- Present logs and analysis
- Recommend manual investigation
- Do not attempt automatic fixes

**Step 5.4: Apply simple fixes (if approved)**

For each simple fix:

**A. Package.json changes:**

```bash
# Read current state
# Use Edit tool to add/update resolutions or dependencies
# Example: Add resolution to root package.json
```

**B. Source code changes:**

```bash
# Use Edit tool to update imports, function calls
# Make precise, targeted changes only
```

**C. Install dependencies:**

```bash
yarn install
```

**Step 5.5: Verify fixes**

Re-run the previously failing checks:

```bash
yarn check:types:all
yarn lint:all
yarn test:unit
# (only run what failed initially)
```

**Step 5.6: Report results**

If all checks pass:

```
✅ All fixes applied successfully!
✅ All CI checks now passing
```

If some still fail:

```
⚠️  Applied fixes, but X checks still failing:
[Show remaining errors]

Recommendation: [Revert and use plan mode / Manual investigation needed]
```

---

## Error Pattern Reference

Common errors and their solutions:

**TypeScript Errors:**

- `TS2307: Cannot find module` → Import path changed or package not installed
- `TS2339: Property does not exist` → API changed, property removed/renamed
- `TS2345: Argument of type X is not assignable` → Function signature changed

**Build Errors:**

- `ERESOLVE unable to resolve dependency tree` → Add resolution to package.json
- `Module not found: Error: Can't resolve` → Import path changed
- `peer dependency warning` → Update peer or add resolution

**Runtime Errors (from tests):**

- `xxx is not a function` → Function removed/renamed
- `Cannot read property 'yyy' of undefined` → API structure changed
- Test failures → Behavior changed, mocks need updating

**Lint Errors:**

- Usually not caused by deps unless ESLint/Prettier upgraded
- If ESLint upgraded, may need to update config or rules

---

## Project-Specific Context

**Critical dependencies to watch:**

- **PatternFly** (`@patternfly/*`): UI component library, breaking changes affect all components
- **React**: Core framework, major versions have significant changes
- **Redux/Redux Toolkit**: State management, API changes break stores
- **i18next**: Translation library, format changes affect all locale files
- **TypeScript**: Stricter checks can surface new errors
- **Vite**: Build tool, config changes affect dev/build
- **@testing-library/\***: Test APIs change between majors

**Workspace structure:**

- Root `package.json` has `resolutions` field for version pinning
- `libs/ui-lib` is the core shared library (highest impact)
- `apps/*` are consuming applications
- Changes in `libs/` affect all consuming apps

**CI checks (from .github/workflows/pull-request.yaml):**

- lint: `yarn lint:all`
- format: `yarn format:all`
- circular-deps: `yarn check:circular_deps:all`
- unit-tests: `yarn test:unit`
- translation-files: `yarn workspace @openshift-assisted/locales run validate_translation_files`
- tests: Cypress integration tests

---

## Tips

- **Be methodical:** Don't rush to conclusions. Verify correlation between changes and failures.
- **Be conservative:** When in doubt, use plan mode or recommend manual review.
- **Be specific:** Propose exact code changes, not vague suggestions.
- **Check release notes:** They often contain migration guides with exact steps.
- **Test incrementally:** If multiple fixes needed, consider applying and testing one at a time.
- **Preserve user's work:** Never make destructive changes. Simple edits only.
- **Communicate clearly:** Explain WHY a change is needed, not just WHAT to change.

---

## Example Scenarios

**Scenario 1: Simple transitive conflict**

- axios upgraded, brings incompatible follow-redirects
- `yarn install` shows ERESOLVE error
- Fix: Add `"follow-redirects": "^1.16.0"` to resolutions
- Verify: `yarn install` succeeds
- Apply directly ✅

**Scenario 2: Major version with breaking API**

- redux 4 → 5, removes `createStore`
- TypeScript errors in 8 files importing `createStore`
- Fix: Migrate to `configureStore` from @reduxjs/toolkit
- Affects store setup across multiple packages
- Use plan mode 🎯

**Scenario 3: Minor version, no issues**

- lodash 4.17.20 → 4.17.21 (patch)
- All checks pass
- Fix: None needed
- Report: ✅ Safe to merge The assisted-installer-ui is a complex, data-heavy React application that
  interfaces with a mission-critical REST API to manage infrastructure. Because it involves deep
  "domain-specific" logic (networking, storage, and Kubernetes hardware requirements), it is a
  perfect candidate for AI Agents.
