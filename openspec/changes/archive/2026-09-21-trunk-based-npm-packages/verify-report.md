# Verify report: trunk-based-npm-packages (issue #84)

Latest: RE-VERIFICATION (after W3 and W4 fixes, PRs #91 and #92). Verdict: PASS WITH WARNINGS (0 CRITICAL, 4 WARNING, 4 SUGGESTION). Strict TDD: false.
The first-run report is preserved below, unchanged, under "First run".

# Re-verification (stack tip: fix/npm-publish-command-inputs)

## Commands
- bash tests/npm-dual-publish.test.sh: Passed 63, Failed 0 (was 35; +28 from W3/W4 guard tests)
- bash tests/release-train-detect.test.sh: passed 36, failed 0
- bash tests/image-tag-cleanup-select.test.sh: passed 9, failed 0
- shellcheck on all .github/actions/**/*.sh (expanded with fd, zsh has no globstar) + tests/*.sh: exit 0, no findings
- actionlint (whole repo): exit 1, single finding, pre-existing SC2086 at node-release.yml:72; nothing in trunk-npm-publish.yml or new files
- git diff main -- node-release.yml node-ci.yml release-train.yml openspec/changes/trunk-based-ci-cd: empty (byte-identical)
- Stack (gh pr view): #85 main<-feat/npm-publish-setup-inputs (+13/-0); #86 <-feat/npm-publish-pr-path (+133/-0); #87 <-feat/npm-dual-publish-action (+393/-0); #88 <-feat/npm-publish-job (+64/-4); #89 <-feat/npm-publish-readme (+74/-0); #91 <-fix/npm-publish-app-path-guard (+54/-0); #92 <-fix/npm-publish-command-inputs (+63/-9). Chain is coherent, each base is the previous head. All OPEN. Max is #87 at 393 changed lines (<= 400); none exceeds. This supersedes S3 (the ~460 estimate was wrong).

## W3 and W4 resolution
- W3 RESOLVED: "Validate app_path" is the first step of both jobs (trunk-npm-publish.yml:135 in validate, :201 in publish), before Setup (:148/:213) and Install. Value passed via env APP_PATH, never interpolated in run:. Both copies identical and equivalent to resolve_app_path; enforced by tests/npm-dual-publish.test.sh:64-95 (first-step, identical, env-only, same accept/reject set).
- W4 RESOLVED: inputs typecheck_command/test_command/build_command declared at :48-62 (defaults typecheck/test/build), steps at :161-180 (validate) and :226-245 (publish) with `if: ${{ inputs.X_command != '' }}`, env SCRIPT, `pnpm run "$SCRIPT"`. Documented in header comment :18-21 and README:539-545,558.
- Still open, unchanged: W1 (tag pushed before publishCmd; re-run cannot recover), W2 (CLI flags pass-through to plugins unverified), S1 (fork-PR permissions not in README), S2 (pack --dry-run only on the PR path, absent from publish).

## Regression checks on the W3/W4 changes
- `if: inputs.X_command != ''` vs spec: the spec (spec.md:11-20) requires install, typecheck, test, build, pack --dry-run in order on PR and that a failing step stops the job. Defaults are non-empty, so default behavior is unchanged and compliant; skipping is opt-in by the caller. The spec does not mention typecheck_command inputs, so no scenario conflicts. Trade-off: with an explicit empty value the "typecheck runs" scenario is no longer literally true for that caller. Acceptable (it resolves W4), but the spec/design were not updated to reflect the optional-skip semantics (SUGGESTION S4).
- validate PR path requirement: still satisfied; order is guard, setup, install, typecheck, test, build, pack. Skipped steps do not break `if: success()` flow of later steps.
- Explicit empty string on workflow_call: UNCONFIRMED LOCALLY, and this is the main residual risk. actionlint cannot evaluate runtime input resolution, and no run was possible. Per my recollection of GitHub behavior, a caller passing `with: typecheck_command: ""` may receive the declared default instead of an empty string for workflow_call string inputs (there are community reports of empty strings falling back to defaults); I did not verify this against current GitHub docs in this session. If that is true, the documented opt-out (`typecheck_command: ""`) would silently still run `pnpm run typecheck` and fail for packages without that script. Needs a one-off pilot run or a doc check (WARNING W5). Mitigation if confirmed: use a sentinel (e.g. "none") or boolean run_typecheck inputs, as node-ci.yml does with run_* flags.
- Validate step first in both jobs: confirmed (see W3). The publish job's checkout is inside the Setup/publish steps after it, so the inline check correctly does not need the repo.
- Injection: new inputs typecheck/test/build_command go only to env SCRIPT and the `if:` expression, then `pnpm run "$SCRIPT"` (quoted). No inline interpolation in run:. A value starting with `-` could be read by pnpm as an option (argument injection, low, caller trusted) (SUGGESTION S5 not counted separately). Residual, pre-existing: install/action.yml:22-25 still interpolates app_path and use_filter inline in run:. The new guard blocks traversal and absolute paths but not shell metacharacters (quotes, `$(`), so the guard does not fully close that pre-existing sink. Callers are trusted; low severity (SUGGESTION S5: reject or env-pass in install action, or extend guard to a safe character allowlist).

## Spec compliance matrix (delta vs first run)
No requirement regressed. "app_path on every step" now also COMPLIANT for the guard (early). PR validation order: COMPLIANT (skip is opt-in). Everything else unchanged from first run: Partial failure re-run remains PARTIAL (W1); provenance, tag/GH Release and real output wiring remain UNTESTABLE-LOCALLY.
Design conformance: the first-run Interfaces-table deviation (typecheck/test/build inputs) is now closed.

## Issues (current)
CRITICAL: none.
W1 WARNING (open): tag pushed before publishCmd; a re-run finds no releasable commits and never reaches publish.sh, so the "partial failure re-run" scenario is likely unmet. Pilot or add recovery/doc.
W2 WARNING (open): CLI-only semantic-release flags rely on unknown-option pass-through to plugins; never exercised for real.
W5 WARNING (new): explicit empty-string input for typecheck/test/build_command may not override the default on workflow_call; unverifiable locally. The documented opt-out could silently not work.
W7 WARNING (new, deferred to pilot): first real end-to-end run (stack is unmerged; workflow refs `@main` for setup/install/npm-dual-publish actions, which only exist on main after the stack merges, so the workflow cannot run on the PR branches before merge order is respected).
S1 SUGGESTION (open): README fork-PR permissions note.
S2 SUGGESTION (open): pack --dry-run not in publish path.
S3 SUGGESTION (closed): PR size, max 393 lines, no size:exception needed.
S4 SUGGESTION: update spec/design to state that empty *_command skips the step.
S5 SUGGESTION: install action inline interpolation of app_path/use_filter, guard has no character allowlist; also `-`-leading script names.

Counts: 0 CRITICAL, 4 WARNING (W1, W2, W5, W7), 4 SUGGESTION open (S1, S2, S4, S5).

## Key Learnings
1. A reusable workflow's `if: inputs.X != ''` opt-out is only reliable if GitHub honors an explicitly passed empty string over the declared default, which must be confirmed with a real run.
2. A path guard that only rejects traversal and absolute paths does not close inline shell interpolation sinks that accept quotes or command substitution.
3. Skipping a workflow step through an empty input keeps default behavior spec-compliant but makes the spec silent about the optional-skip semantics, so specs should be updated alongside such fixes.
4. Under zsh the `**` glob does not recurse without globstar, so shellcheck runs on action scripts should expand file lists with fd to avoid silently checking nothing.

---

# First run (original report, preserved)

## Original report: trunk-based-npm-packages (issue #84)

Verdict: PASS WITH WARNINGS (0 CRITICAL, 4 WARNING, 3 SUGGESTION). Strict TDD: false.

## Commands
- bash tests/npm-dual-publish.test.sh: Passed 35, Failed 0
- bash tests/release-train-detect.test.sh: passed 36, failed 0
- bash tests/image-tag-cleanup-select.test.sh: passed 9, failed 0
- shellcheck .github/actions/**/*.sh tests/*.sh: exit 0, no findings
- actionlint (repo): 1 finding, pre-existing SC2086 at node-release.yml:72 (not ours); nothing in new files
- git diff main -- node-release.yml node-ci.yml release-train.yml openspec/changes/trunk-based-ci-cd: empty (byte-identical)
- npm view semantic-release@25.0.2 / @semantic-release/exec@7.1.0 / npm@11.6.2: all exist

## Tasks
16/16 checked (1.1-1.2, 2.1-2.2, 3.1-3.11, 4.1). The "17" figure is not supported by tasks.md; 16 is correct.

## Spec compliance matrix
| Requirement / scenario | Status | Evidence |
|---|---|---|
| PR: validation order, no publish | COMPLIANT | trunk-npm-publish.yml:106-142 (validate job, no publish steps) |
| PR: failing step stops | COMPLIANT | default GH Actions step semantics, :126-128 |
| Trunk: semantic-release, no @semantic-release/git, no commit-back | COMPLIANT (static) | action.yml:94-105; guard tests in tests/npm-dual-publish.test.sh |
| Trunk: tag + GH Release, package.json in runner | UNTESTABLE-LOCALLY | action.yml:100-101, publish.sh:38-44 |
| No commit-back / 0.0.0 in git | COMPLIANT (static) | no git add/commit; set_manifest is runner-only |
| No releasable commits -> published=false | COMPLIANT (static) | action.yml:93 pre-writes published=false; publishCmd never runs |
| Stable + edge dist-tags | COMPLIANT | publish.sh:68-75, lib.sh:52-64 (tested) |
| Dual registry order, provenance npmjs only | COMPLIANT | publish.sh:50-53,68-75 |
| Both registries succeed (provenance verified) | UNTESTABLE-LOCALLY | needs pilot |
| Partial failure re-run | PARTIAL | see W1 |
| Invalid scope fails before publish | COMPLIANT | action.yml:60-66, lib.sh:33-47 (tested) |
| app_path on every step | COMPLIANT | workflow :123,127,...,187; publish.sh:24-26 |
| setup: package_json_file | COMPLIANT | setup/action.yml:13-16,39,44-45 |
| setup: full history | COMPLIANT | setup/action.yml:17-20,26; publish job :163 |
| setup: existing callers unchanged | COMPLIANT | defaults "" -> 'package.json', "1" |
| Concurrency, no cancel | COMPLIANT | workflow :99-101 |
| Permissions/secrets; PR needs no NPM_TOKEN | COMPLIANT | workflow :78-94; secret required:false |
| Missing token fails, GHP not attempted | COMPLIANT | action.yml:56-59 (preflight precedes release) |
| Outputs published/version/edge_version | COMPLIANT (static) | see wiring below |

## Real-behavior checks
- Output wiring: GITHUB_OUTPUT is an env var of the Release step, inherited by npx -> semantic-release -> exec child -> publish.sh (:77-83). Writes published=true/version/edge_version; duplicate key `published` resolves to last value (true). Composite outputs map steps.release.outputs.* (action.yml:29-38); workflow job outputs map steps.publish.outputs.* (:152-155); workflow_call outputs map jobs.publish.outputs.* (:68-77). Chain is consistent. Not exercised by a real run.
- Permissions story: consistent with D8 and README; a fork-PR caller cannot grant contents/packages/id-token write (caller startup failure). Documented limitation only (S1).
- validate with app_path ".": package_json_file becomes "./package.json", valid for pnpm/action-setup. OK. With pnpm_version set AND packageManager in package.json, pnpm/action-setup may error on conflict; identical to pre-existing behavior for the default path.
- Injection: workflow inputs go only to with:/working-directory:/env:, never inline in run:. publish.sh and action.yml use env vars and quoted bash arrays, no eval. Exception is pre-existing install/action.yml:22-23 which inlines ${{ inputs.app_path }} and use_filter in run: (see W3).

## Design conformance
D1 OK. D2 OK (plugins space-separated on CLI instead of comma, equivalent). D3 OK. D4 OK. D5 OK (npm pin + assert). D6 OK in script, but see W1. D7 OK. D8 OK. D9 OK (lib.sh, tests, test.yml job). Threat matrix: all 4 applicable rows have RED/guard tests (tasks 3.1-3.5 done). Deviation: design Interfaces table lists typecheck_command/test_command/build_command inputs; not implemented (hardcoded pnpm typecheck/test/build) (W4).

## Issues
W1 WARNING: "Partial failure re-run" likely not satisfied. semantic-release creates and pushes the git tag BEFORE the publish step (exec.publishCmd). If publish.sh fails partway, a re-run sees the tag, finds no new releasable commits, reports no release, and never invokes publish.sh, so the idempotent skip logic is never reached; the GitHub Release is also never created. Also contradicts D2 claim that the Release exists only after all publishes succeed (tag does). Confirm in the pilot; mitigation options: detect "tag at HEAD without published version" and call publish.sh directly, or document manual recovery. Not verifiable locally.
W2 WARNING: CLI-only semantic-release config (--no-success-comment/--no-fail-comment, --publish-cmd) relies on unknown-option pass-through to plugins; never run for real (apply-progress admits this). Pilot required before relying on it.
W3 WARNING: resolve_app_path only runs in the publish preflight, which runs AFTER the install action, and never on the validate path. install/action.yml interpolates app_path/use_filter directly into run: (pre-existing). Callers are trusted, so severity is low, but the traversal guard does not protect the first steps. Fix: validate app_path early in both jobs.
W4 WARNING: design-listed typecheck_command/test_command/build_command inputs absent; packages lacking a `typecheck` script fail the job. Document or add.
S1 SUGGESTION: README should note fork-PR callers cannot grant the required permissions.
S2 SUGGESTION: publish job builds/tests twice implicitly (validate on PR, publish on push); acceptable, but pack --dry-run is skipped on the publish path.
S3 SUGGESTION: size:exception label for PR 3 (~460 lines > 400) as noted in apply-progress.

## Key Learnings
1. semantic-release pushes the git tag before running publishCmd, so idempotent publish scripts cannot rescue a failed publish via a job re-run.
2. GITHUB_OUTPUT is inherited by child processes of a step, so a script run under semantic-release exec can write step outputs directly.
3. Static workflow_call permissions force PR-only callers to grant every permission the publish path needs.
