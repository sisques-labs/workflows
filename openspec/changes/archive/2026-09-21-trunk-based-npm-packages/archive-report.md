# Archive Report: trunk-based-npm-packages (issue #84)

## Change Archived

**Change**: trunk-based-npm-packages  
**Issue**: #84  
**Archive Location**: `openspec/changes/archive/2026-09-21-trunk-based-npm-packages/`  
**Archived Date**: 2026-09-21  
**Archive Status**: Complete with accepted risks

## Artifact Traceability (Hybrid Store)

This change was persisted across both Engram and OpenSpec. Observation IDs in Engram:
- **Proposal** (obs 836): `sdd/trunk-based-npm-packages/proposal` — full proposal with delivery strategy and slice breakdown
- **Spec** (obs 837 / file): `sdd/trunk-based-npm-packages/spec` — 9 requirements, 15 scenarios covering PR validation and trunk publish
- **Design** (obs 838): `sdd/trunk-based-npm-packages/design` — 9 design decisions (D1-D9) with threat matrix and slices
- **Tasks** (obs 839 / file): `sdd/trunk-based-npm-packages/tasks` — 16 implementation tasks across 4 stacked PRs
- **Apply Progress** (obs 840 / file): `sdd/trunk-based-npm-packages/apply-progress` — 7 stacked PRs delivered, W3/W4 fixes documented
- **Verify Report** (obs 852 / file): `sdd/trunk-based-npm-packages/verify-report` — re-verification after W3/W4 fixes, PASS WITH WARNINGS

## Specs Synced

| Domain | Action | Details |
|--------|--------|---------|
| trunk-npm-publish | Created | Full spec (9 requirements, 15 scenarios) promoted from `openspec/changes/trunk-based-npm-packages/specs/trunk-npm-publish/spec.md` to `openspec/specs/trunk-npm-publish/spec.md` |

**Spec Sync Method**: Mechanical copy (no model-based Read/Write); verified with `diff -q` post-copy.

## Archive Contents (Mechanical Verification)

- ✅ `proposal.md` — 8.2 KB
- ✅ `design.md` — 13.7 KB
- ✅ `tasks.md` — 4.1 KB (16/16 tasks complete)
- ✅ `apply-progress.md` — 2.1 KB
- ✅ `verify-report.md` — 14.1 KB
- ✅ `specs/trunk-npm-publish/spec.md` — 5.5 KB

**Verification**: `diff -r` against pre-move snapshot → empty diff (byte-identity confirmed)

## Task Completion Status

**Tasks Persisted**: 16/16 complete  
**Unchecked Tasks**: 0  
**Task Completion Gate**: PASSED

All implementation tasks marked with `[x]` in `tasks.md`. Verification confirms all slices delivered:
- Slice 1 (setup inputs): PR #85 (+13 lines) — COMPLETE
- Slice 2 (PR validation path): PR #86 (+133 lines) — COMPLETE
- Slice 3 (publish path, action, tests): PR #87 (+393), PR #88 (+64/-4 lines) — COMPLETE
- Slice 4 (README): PR #89 (+74 lines) — COMPLETE
- W3 fix (app_path guard): PR #91 (+54 lines) — COMPLETE
- W4 fix (command inputs): PR #92 (+63/-9 lines) — COMPLETE

## Final Verification Status

**Verdict**: PASS WITH WARNINGS (per re-verification after W3/W4 fixes)  
**CRITICAL Issues**: 0  
**Warnings**: 4 (W1, W2, W5, W7)  
**Suggestions**: 4 (S1, S2, S4, S5)

**Test Results** (latest):
- npm-dual-publish: 63 passed, 0 failed
- release-train-detect: 36 passed, 0 failed
- image-tag-cleanup-select: 9 passed, 0 failed
- shellcheck: clean (no findings)
- actionlint: 1 pre-existing SC2086 at node-release.yml:72 (unrelated)

**Protected Files** (verified byte-identical to main):
- node-release.yml ✅
- node-ci.yml ✅
- release-train.yml ✅
- openspec/changes/trunk-based-ci-cd/ ✅ (untouched)

## Accepted Risks (Explicitly Authorized 2026-09-21)

These risks were reviewed and accepted by the user before archiving. Future sessions should consult this list when considering follow-up work or spec revisions.

### W1: Semantic-Release Tag Before Publish
**Origin**: Design note D2, discovered in verification  
**Description**: `semantic-release` pushes the git tag to the repository BEFORE invoking the publish step (exec.publishCmd). If `publish.sh` fails partway through, a re-run finds the tag already in place, reports no new releasable commits, and never re-attempts `publish.sh`. The GitHub Release is also never created. This contradicts D2's claim that "Release only after all registries succeed."  
**Status**: Contradicts spec D2 on release ordering; partially satisfied scenarios only.  
**Resolution Path**: Pilot merge on sisques-labs/beacon-ts-sdk to confirm behavior and implement mitigation (e.g., detect "tag at HEAD without published version" and call publish.sh directly, or document manual tag deletion recovery).

### W2: CLI-Only Semantic-Release Flags Unverified
**Origin**: Design D2, never exercised in real run  
**Description**: The workflow passes `--publish-cmd`, `--no-success-comment`, `--no-fail-comment` as CLI flags to `semantic-release`. These flags rely on unknown-option pass-through to plugins. This has never been tested in a real semantic-release execution (no real or simulated run was performed; the design was validated by reading only).  
**Status**: Static code review only; runtime behavior unconfirmed.  
**Resolution Path**: Pilot merge will exercise these flags in real semantic-release context.

### W5: Explicit Empty String Input Override Unconfirmed
**Origin**: W4 fix (typecheck_command, test_command, build_command inputs)  
**Description**: The workflow uses `if: ${{ inputs.X_command != '' }}` to allow callers to skip steps by passing an empty string. GitHub's behavior when a caller explicitly passes `with: typecheck_command: ""` on a `workflow_call` input is unconfirmed—the platform may silently apply the declared default instead of an empty string. If this occurs, the documented opt-out would fail silently and still run `pnpm run typecheck`, causing failures for packages without that script.  
**Status**: Unverifiable locally; cannot be tested without a real merge and workflow call.  
**Resolution Path**: Pilot merge to sisques-labs/beacon-ts-sdk will test explicit empty-string passing. If confirmed broken, mitigation: use a sentinel value (e.g., `"none"`) or boolean `run_typecheck` / `run_test` / `run_build` inputs (same pattern as node-ci.yml).

### W7: First Real End-to-End Run Pending
**Origin**: Stack merge blocking  
**Description**: All 7 PRs are currently OPEN on the feature branches. The workflow and its referenced actions (`@main` for setup, npm-dual-publish) do not exist on the feature branches, so the workflow cannot execute before the stack merges and lands on `main`. The first truly end-to-end run (with real semantic-release and dual-registry publish) requires the full stack to merge in order.  
**Status**: Deferred until PR merge sequence completes.  
**Resolution Path**: Merge stack in order (#85 → #86 → #87 → #88 → #89 → #91 → #92), then trigger a test push on sisques-labs/beacon-ts-sdk or another pilot repo.

## Design Open Item: Edge Prerelease vs Dist-Tag Alias

**Status**: Shipped per spec (edge as real prerelease `x.y.z-edge.N`)  
**Alternative Considered**: Make `edge` a plain `npm dist-tag add` alias of the stable version (cheaper, less churn, no immutable version burn per chore)  
**Decision**: Spec requires real prerelease semantics; the alternative is filed as a future spec revision.  
**Follow-up**: Pilot run will gather data on edge prerelease adoption and churn to inform a future spec revision if desired.

## Source of Truth Updated

The following specs now define the new capability:
- `openspec/specs/trunk-npm-publish/spec.md` — canonical trunk-npm-publish workflow specification

New implementation:
- `.github/workflows/trunk-npm-publish.yml` — workflow_call workflow
- `.github/actions/npm-dual-publish/{action.yml, publish.sh, lib.sh}` — dual-registry publish action
- `tests/npm-dual-publish.test.sh` — RED tests + functional tests
- `.github/workflows/test.yml` (extended) — test job for npm-dual-publish
- `.github/actions/setup/action.yml` (extended) — added `package_json_file` and `fetch_depth` inputs
- `README.md` (extended) — workflow section and consumer example

Unmodified (verified byte-identical to main):
- `node-release.yml` ✅
- `node-ci.yml` ✅
- `release-train.yml` ✅
- `openspec/changes/trunk-based-ci-cd/` ✅

## SDD Cycle Complete

✅ **Proposal** — Issue #84 defined scope, slices, and delivery strategy  
✅ **Spec** — 9 requirements and 15 scenarios defined trunk-npm-publish behavior  
✅ **Design** — 9 decisions resolved (D1-D9); threat matrix and slice plan  
✅ **Tasks** — 16 tasks broken down across 4 stacked PRs  
✅ **Apply** — 7 PRs delivered with W3/W4 fixes; all tasks complete  
✅ **Verify** — Re-verification PASS WITH WARNINGS; no CRITICAL issues  
✅ **Archive** — Change archived to `openspec/changes/archive/2026-09-21-trunk-based-npm-packages/`; specs promoted to `openspec/specs/`  

The change is ready for pilot testing on sisques-labs/beacon-ts-sdk to confirm real-world behavior of W1, W2, W5, and W7.

## Key Learnings

1. semantic-release creates and pushes the git tag before the publish step (exec.publishCmd), making partial-failure recovery through job re-run impossible without additional logic.
2. Workflow_call empty-string input overrides cannot be confirmed locally without an actual merge and runtime execution.
3. A workflow using `if: inputs.X != ''` for optional step skipping is only reliable if GitHub honors an explicitly passed empty string over the declared default.
4. GitHub Packages lacks npm provenance support, so dual-registry publish must apply `--provenance` only to the npmjs step.
5. Stacked PR references must use `@main` for shared actions, making the workflow impossible to test before merge; pilot runs require the full stack merged.
