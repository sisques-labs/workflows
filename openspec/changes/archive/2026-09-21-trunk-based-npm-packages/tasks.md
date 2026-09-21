# Tasks: Trunk-based npm packages (issue #84)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~480 total (50 / 130 / 240 / 60) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 → PR 4 |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | setup inputs | PR 1 (base main) | `actionlint .github/actions/setup/action.yml` | Existing caller run unchanged | Revert `setup/action.yml` |
| 2 | PR path | PR 2 (base PR 1 branch) | `actionlint .github/workflows/trunk-npm-publish.yml` | Pilot repo PR run | Revert workflow file |
| 3 | Publish path, action, tests | PR 3 (base PR 2 branch) | `bash tests/npm-dual-publish.test.sh` | Pilot push to main (manual) | Revert action dir, test, job, publish job |
| 4 | README | PR 4 (base PR 3 branch) | N/A (docs) | N/A (docs only) | Revert README |

## Phase 1: Setup inputs (PR 1)

- [x] 1.1 `.github/actions/setup/action.yml`: add `package_json_file` (default `""`), forward to pnpm/action-setup.
- [x] 1.2 Same file: add `fetch_depth` (default `"1"`), forward to checkout.

## Phase 2: PR path (PR 2)

- [x] 2.1 Create `.github/workflows/trunk-npm-publish.yml`: `workflow_call` inputs per design, optional `NPM_TOKEN`, static permissions, concurrency without `cancel-in-progress`, outputs.
- [x] 2.2 Add `validate` job (`pull_request`): setup, install, typecheck, test, build, `pnpm pack --dry-run`, all with `working-directory: app_path`.

## Phase 3: Publish path (PR 3)

Threat-matrix RED tests first (unchanged from design):

- [x] 3.1 RED in `tests/npm-dual-publish.test.sh`: `resolve_app_path` rejects `/etc`, `../x`, `packages/../..`; accepts `.`, `packages/lib`.
- [x] 3.2 RED: guard asserts plugin list has no `@semantic-release/git` and `publish.sh` has no commit invocation.
- [x] 3.3 RED: guard asserts no `git push origin <branch>` form and `--branches main` present.
- [x] 3.4 RED: assert `successComment`/`failComment` are false; `classify_publish_failure` handles a version string with shell metacharacters.
- [x] 3.5 RED: `validate_scope` (own, foreign, unscoped), `next_edge_version`, `classify_publish_failure` (`EPUBLISHCONFLICT`).
- [x] 3.6 Create `.github/actions/npm-dual-publish/lib.sh` with the four pure functions.
- [x] 3.7 Create `.github/actions/npm-dual-publish/publish.sh`: order stable npmjs, stable GHP, edge npmjs, edge GHP; bash-array args, no `eval`; `$RUNNER_TEMP/.npmrc`; provenance on npmjs only.
- [x] 3.8 Create `.github/actions/npm-dual-publish/action.yml` composite wrapper.
- [x] 3.9 Extend `trunk-npm-publish.yml`: `publish` job (push to main), `fetch_depth: "0"`, preflight (scope, token, `npm_version`), semantic-release CLI with exec + github plugins, outputs.
- [x] 3.10 Pin defaults: `npm_version` `11.6.2`, `semantic_release_version` `25.0.2`, `semantic_release_exec_version` `7.1.0`; confirm each with `npm view <pkg>@<v> version` before commit.
- [x] 3.11 `.github/workflows/test.yml`: add job running `bash tests/npm-dual-publish.test.sh`.

## Phase 4: Documentation (PR 4)

- [x] 4.1 `README.md`: workflow section, file-tree entry, consumer example (PR and push callers, permissions, `NPM_TOKEN`).

## Non-blocking open items

- Edge as real prerelease versus dist-tag alias (D3): ship the prerelease per spec; revisit as a spec revision after the pilot.
- Pin bump ownership: manual until a consumer requests automation.

## Key Learnings

1. Slice 1 must merge first because the publish job depends on the setup action's `fetch_depth` input.
2. Threat-matrix RED tests live in one test file so slice 3 stays the only PR needing test wiring.
3. Version pins in tasks are provisional and must be verified against the registry before commit.
