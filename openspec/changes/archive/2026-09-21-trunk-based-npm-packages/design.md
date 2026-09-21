## Context

See `proposal.md` and `specs/trunk-npm-publish/spec.md`. `trunk-ci-cd.yml` gives Docker consumers a trunk-based pipeline; npm/pnpm libraries have none. `node-release.yml` delegates semantic-release to the consumer and commits the bump back to `main`. This design keeps that file untouched and adds a self-contained reusable workflow where the **workflow owns the release config** and git tags are the only version source.

## Goals / Non-Goals

**Goals:** one `workflow_call` file covering PR validation and trunk publish; zero commits written back to `main`; provenance-signed npmjs publish mirrored to GitHub Packages; additive-only change to the shared `setup` action.

**Non-Goals:** touching `node-release.yml`/`node-ci.yml`/`release-train.yml` or `openspec/changes/trunk-based-ci-cd`; migrating any consumer; non-npm registries; deploys.

## Decisions

### D1 — One file, two jobs, dispatched on `github.event_name`

`validate` runs `if: github.event_name == 'pull_request'`; `publish` runs `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`. In a `workflow_call` workflow the `github` context belongs to the **caller's** event, so this dispatch is reliable without an extra input.

**Rejected:** two workflow files (doubles the README surface and the consumer's wiring); a `mode` input (the caller already encodes the mode in its own `on:` trigger, so an input can only disagree with it); a `trunk_branch` input (spec fixes the trunk at `main`; a consumer on another trunk name is out of scope).

### D2 — semantic-release computes, `exec` publishes, `github` records

Plugin list, supplied entirely on the CLI (CLI options outrank any consumer `.releaserc`, so a consumer config cannot inject `@semantic-release/npm` or `@semantic-release/git`):

```
--branches main --plugins @semantic-release/commit-analyzer,\
@semantic-release/release-notes-generator,@semantic-release/exec,@semantic-release/github
```

`exec.publishCmd` runs `npm-dual-publish`, so the GitHub Release is created only **after** every registry publish succeeds. `successComment`/`failComment` are disabled, which is what keeps `issues:`/`pull-requests:` out of the permission set.

**Version pinning:** `npx -y -p semantic-release@<exact> -p @semantic-release/exec@<exact>`. commit-analyzer, release-notes-generator and github ship as dependencies of `semantic-release`, so pinning the top package pins them transitively with no version skew. Exact pins only, no ranges, exposed as `semantic_release_version` / `semantic_release_exec_version` inputs.

### D3 — Edge is derived from the stable release, and is suppressed without one (open item a)

`edge_version = <next patch above the stable just released>-edge.<github.run_number>`, published with `npm publish --tag edge`. Deriving it from the released stable keeps `edge` strictly **above** `latest` (a `1.2.0-edge.N` alongside stable `1.2.0` would sort below it); `run_number` is monotonic per repo, so no registry read is needed to pick `N`.

**A merge with no releasable commits publishes nothing — no stable and no edge.** The job succeeds with `published=false`. An edge-only publish would have to invent a bump no commit justified, would burn an immutable npm version per chore merge, and would push `edge` ahead of a stable that never ships.

**Rejected:** making `edge` a dist-tag alias of the stable version (`npm dist-tag add`) — cheaper and version-churn-free, but the spec requires a real `x.y.z-edge.N` prerelease; recorded under Open Questions as a possible spec revision.

### D4 — Scope validation gates GitHub Packages, and is skippable (open item b)

GitHub Packages resolves an npm package to a repository through its scope, so `name` in `<app_path>/package.json` must be `@<repository_owner>/<pkg>` (compared lowercased). A preflight step on the publish path — before any registry call — fails fast naming the required scope when the name is unscoped or foreign-scoped. The same preflight asserts `NPM_TOKEN` is non-empty, so a missing token also fails before GitHub Packages is attempted.

The escape hatch is `publish_github_packages` (default `true`). Set to `false`, the scope check is skipped entirely and only npmjs is published — an explicit opt-out, never a silent skip.

### D5 — npm CLI is pinned, and provenance failure is fatal (open item c)

Provenance needs npm ≥ 9.5.0, and the bundled npm otherwise drifts silently with `node_version`. The publish path runs `npm install -g npm@${{ inputs.npm_version }}` (exact pin, no range, default a current npm 11.x patch fixed in `tasks.md`) and asserts `npm --version` matches before publishing. Build and install stay on pnpm; only the publish call uses the npm CLI, because `--provenance` is first-party there.

`--provenance` is applied to the **npmjs** step only — GitHub Packages does not support it. A provenance failure (private repo, missing `id-token: write`) fails the publish rather than downgrading to an unsigned one.

### D6 — Dual publish is ordered and idempotent

Publish order: stable→npmjs, stable→GitHub Packages, edge→npmjs, edge→GitHub Packages. Stable goes first so a failure never leaves `edge` ahead of a stable that does not exist. Each call classifies its own failure: `EPUBLISHCONFLICT` (or "cannot publish over the previously published versions") means *already there* → log and continue; anything else fails the job loudly. A re-run therefore republishes only the missing registry.

Per-registry mechanics: `package.json` is rewritten in the runner only (`version`, plus a `publishConfig.registry` override so a consumer's own `publishConfig` cannot redirect the GitHub Packages call); auth lives in `$RUNNER_TEMP/.npmrc` passed via `--userconfig`, never `~/.npmrc`; npmjs adds `--access public --provenance`.

### D7 — `setup` gains two additive inputs, landing first

`package_json_file` (default `""`) forwards to `pnpm/action-setup`, fixing pnpm auto-detect for a subdirectory package. `fetch_depth` (default `"1"`, matching `actions/checkout`'s own default) forwards to the checkout step; the publish job passes `"0"` so semantic-release sees the tag history. Both defaults reproduce today's behavior byte-for-byte for existing callers, which is why this lands as slice 1, before anything depends on it.

### D8 — Static permissions, optional secret, empty outputs on PR runs

```yaml
permissions:
  contents: write    # semantic-release tag + GitHub Release
  packages: write    # GitHub Packages publish
  id-token: write    # OIDC for --provenance
```

Declared unconditionally at the top level, following `trunk-ci-cd.yml`: GitHub validates a caller's granted permissions **statically** against this declaration, not against which job actually runs, so a PR-only caller must still grant all three. `NPM_TOKEN` is declared `required: false` so PR callers need not hold it, and D4's preflight enforces it on the publish path. Outputs `published` / `version` / `edge_version` come from the publish job; a PR call skips that job and yields empty strings.

`concurrency: group: trunk-npm-publish-${{ github.ref }}` with **no** `cancel-in-progress` — cancelling a run mid-publish is what produces a tag without a package.

### D9 — Non-trivial shell is extracted and unit-tested

Following `image-tag-cleanup`: `.github/actions/npm-dual-publish/` holds `action.yml`, `publish.sh` (I/O), and `lib.sh` (pure functions: `validate_scope`, `next_edge_version`, `classify_publish_failure`, `resolve_app_path`). `tests/npm-dual-publish.test.sh` runs them offline and gets its own job in `test.yml`; the existing shellcheck job globs the new scripts automatically. No `eval` of an interpolated command (the trap in `node-release.yml`'s release step) — arguments are built as a bash array.

## Data Flow

```
caller on: pull_request ──► validate  ─ setup(pnpm) ─ install ─ typecheck ─ test ─ build ─ pack --dry-run
caller on: push[main]  ──► publish   ─ setup(fetch_depth 0) ─ install ─ build
                                      └─ preflight: scope + NPM_TOKEN + npm pin
                                      └─ npx semantic-release
                                            commit-analyzer ─► version
                                            exec.publishCmd ─► npm-dual-publish
                                                  stable→npmjs(+provenance) ─► stable→GHP
                                                  edge→npmjs ─► edge→GHP
                                            github ─► tag notes + Release
                                      └─ outputs: published / version / edge_version
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `.github/actions/setup/action.yml` | Modify | Add `package_json_file`, `fetch_depth` (D7) |
| `.github/workflows/trunk-npm-publish.yml` | Create | Reusable workflow, both paths (D1) |
| `.github/actions/npm-dual-publish/action.yml` | Create | Composite wrapper for the publish script |
| `.github/actions/npm-dual-publish/publish.sh` | Create | Registry I/O, ordering, idempotency (D6) |
| `.github/actions/npm-dual-publish/lib.sh` | Create | Pure, testable helpers (D9) |
| `tests/npm-dual-publish.test.sh` | Create | Offline unit tests for `lib.sh` |
| `.github/workflows/test.yml` | Modify | New job running that test file |
| `README.md` | Modify | Workflow section, file-tree entry, consumer example |

## Interfaces / Contracts

| Input | Type | Default |
|---|---|---|
| `app_path` | string | `.` |
| `node_version` | string | `24` |
| `pnpm_version` | string | `""` (auto-detect) |
| `use_filter` | boolean | `false` |
| `typecheck_command` / `test_command` / `build_command` | string | `typecheck` / `test` / `build` (empty skips) |
| `publish_github_packages` | boolean | `true` |
| `npm_version` | string | exact npm 11.x pin |
| `semantic_release_version` / `semantic_release_exec_version` | string | exact pins |

Secrets: `NPM_TOKEN` (`required: false`, enforced on the publish path). Outputs: `published` (`true`/`false`), `version`, `edge_version`.

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit | `validate_scope`, `next_edge_version`, `classify_publish_failure`, `resolve_app_path` | `tests/npm-dual-publish.test.sh`, offline, no registry |
| Static | Shell quality; workflow/plugin-list assertions | shellcheck job; grep guards asserting no `@semantic-release/git`, no branch push, comments disabled |
| Integration | PR path, publish path, partial-failure re-run, `app_path` subdir | Pilot consumer repo after slice 3; re-run assertion is manual once |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A — the workflow never classifies files for execution; it runs fixed pnpm/npm commands | — | — |
| Git repository selection | Applicable — `app_path` selects the cwd for every install/check/pack/publish step | `resolve_app_path` rejects absolute paths and `..` traversal before use; all steps use `working-directory` | `resolve_app_path` rejects `/etc`, `../x`, `packages/../..`; accepts `.`, `packages/lib` |
| Commit state | Applicable — the release must leave the index untouched | No `git add`/`git commit`; `@semantic-release/git` absent from the CLI plugin list; `package.json` rewritten in the runner only | Guard test asserting the plugin list contains no `@semantic-release/git` and no commit invocation exists in `publish.sh` |
| Push state | Applicable — semantic-release pushes the release tag to `origin` | Tag push only, never a branch push; `--branches main` pinned on the CLI | Guard test asserting no `git push origin <branch>` form in the action and that `--branches main` is present |
| PR commands | Applicable — `@semantic-release/github` composes API calls; publish args are composed in bash | `successComment`/`failComment` disabled; npm args built as a quoted bash array, never `eval` | Config assertion that both comment options are false; `classify_publish_failure` exercised with a version string containing shell metacharacters |

## Migration / Rollout

Strictly additive — nothing references the new workflow until a consumer edits its own file. Chained PRs, each independently landable, slices 2–4 depending on 1:

| # | Slice | Est. lines | Boundary |
|---|---|---|---|
| 1 | `setup`: `package_json_file` + `fetch_depth` | ~50 | Existing callers byte-identical in behavior |
| 2 | `trunk-npm-publish.yml` PR path | ~130 | Workflow usable for validation only |
| 3 | Publish path + `npm-dual-publish` action, script, tests, `test.yml` job | ~240 | Publishing enabled end to end |
| 4 | README section, file-tree entry, consumer example | ~60 | Documentation complete |

**Rollback:** revert the PR or the chain; `node-release.yml` and `node-ci.yml` are untouched. A bad npm version cannot be unpublished after 72h — forward-fix with `npm dist-tag rm <pkg> edge`, `npm deprecate`, and a new patch. Delete a bad GitHub Packages version from the repo's Packages UI. Because semantic-release tags **before** it publishes (D2), a failed publish can leave a tag with no GitHub Release: delete the stray tag before re-running.

## Open Questions

- [ ] Should `edge` become a dist-tag alias of the stable version instead of a real `x.y.z-edge.N` prerelease (D3)? That removes the version churn the proposal flags as a risk, but requires revising the "Stable and edge dist-tags" requirement.
- [ ] Which exact `npm_version` and `semantic_release_version` pins ship (D5/D2), and who bumps them — resolved at implementation time in `tasks.md`.
