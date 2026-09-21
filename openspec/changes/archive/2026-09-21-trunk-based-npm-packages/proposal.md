# Proposal: Trunk-Based npm Package Publishing

## Why

Issue [#84](https://github.com/sisques-labs/workflows/issues/84). `trunk-ci-cd.yml` gives Docker consumers a trunk-based pipeline (build once on merge to `main`, promote later). npm/pnpm library consumers have no equivalent: `node-release.yml` assumes semantic-release is configured inside the consumer, commits the version bump back to `main` (fights branch protection), has no `id-token: write`/provenance, and carries `develop`/`staging` sync inputs that trunk-based repos do not have. There is no single reusable workflow that validates a package on PRs and publishes it from `main`.

Success: a consuming library repo adds one `workflow_call` reference, sets `NPM_TOKEN`, and gets PR validation plus versioned, provenance-signed publishes to npmjs and GitHub Packages on every merge, with zero commits written back to `main`.

## What Changes

### In Scope

- New reusable workflow `.github/workflows/trunk-npm-publish.yml` (`workflow_call`), one workflow handling both PR validation and `main` publish via `github.event_name`.
- PR path: install, typecheck, test, build, `pnpm pack --dry-run`.
- `main` path: semantic-release driven **by the workflow** (config supplied by the workflow, not the consumer), tags + GitHub Release only, no commit-back — `package.json` stays `0.0.0` in git.
- Every merge publishes the stable version plus an `edge` dist-tag prerelease.
- Dual publish: npmjs public (`NPM_TOKEN`, `--provenance` via `id-token: write`) and GitHub Packages (`GITHUB_TOKEN`, `packages: write`).
- `app_path` input for monorepo subdirectories; `.github/actions/setup` gains `package_json_file` (pnpm auto-detect in subdirs) and full-history checkout control (semantic-release needs tag history).
- Concurrency group per ref without `cancel-in-progress`; README section + file-tree entry.

### Out of Scope

- Changing or deprecating `node-release.yml`, `node-ci.yml`, `release-train.yml`, or `release-train-detect`.
- Anything under `openspec/changes/trunk-based-ci-cd`.
- Migrating any consuming repo (a follow-up per-repo change).
- Non-npm registries, private/scoped-paid npm plans, and `latest`-tag promotion of an existing version.
- Deploy/environment steps — this publishes packages, it does not deploy.

## Capabilities

### New Capabilities

- `trunk-npm-publish`: reusable workflow that validates an npm/pnpm package on pull requests and, on merge to `main`, computes a version from conventional commits and publishes it to npmjs and GitHub Packages without writing a version commit back to the trunk.

### Modified Capabilities

- None. `openspec/specs/` is empty; no existing capability's requirements change. The `setup` composite action gains additive inputs only.

## Approach

1. **Version source of truth = git tags.** semantic-release runs in the workflow with an inline config (`@semantic-release/commit-analyzer`, `release-notes-generator`, `github`), explicitly **without** `@semantic-release/git` and **without** `@semantic-release/npm`'s commit step. The version is written to `package.json` in the runner only, immediately before publish.
2. **Publish twice from the same built artifact.** Step one: npmjs with `--provenance` and `--access public`. Step two: GitHub Packages with a generated `.npmrc` pointing the scope at `npm.pkg.github.com` (no `--provenance`; GitHub Packages does not support it).
3. **Edge prerelease.** semantic-release `prerelease` branch config publishes `x.y.z-edge.N` under dist-tag `edge` alongside the stable release on each merge.
4. **Composite action fixes first.** `setup` is shared, so its new inputs land as an isolated, backward-compatible slice before the workflow depends on them.
5. **Bash stays out of it if possible.** If any non-trivial shell is added, it follows the repo convention: extracted script + `tests/*.test.sh` run by `test.yml` with shellcheck.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `.github/workflows/trunk-npm-publish.yml` | New | The reusable workflow (PR + publish paths) |
| `.github/actions/setup/action.yml` | Modified | Add `package_json_file`, full-history checkout control |
| `README.md` | Modified | New workflow section + file-tree entry |
| `tests/*.test.sh`, `.github/workflows/test.yml` | Modified (conditional) | Only if extracted bash is introduced |
| `.github/workflows/node-release.yml` | Untouched | Explicitly not extended |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `package.json` stays `0.0.0` in git; consumers reading it locally see a fake version | High (by design) | Document it in the README section; the published artifact always carries the real version |
| Partial dual publish (npmjs succeeds, GitHub Packages fails) leaves registries out of sync | Medium | Publish npmjs first, make each step idempotent (tolerate `EPUBLISHCONFLICT`), fail the job loudly; re-run republishes only the missing registry |
| GitHub Packages requires an org-scoped package name; an unscoped or foreign-scoped name fails | Medium | Validate the scope early and fail fast with a clear message; document the naming requirement |
| Shallow checkout hides tags, so semantic-release computes a wrong first version | Medium | Full-history fetch is part of the `setup` slice and verified before the publish slice lands |
| `edge` prerelease on every merge floods npm with immutable versions | Medium | Prereleases are cheap and unlisted under `edge`; `npm dist-tag rm` plus deprecate if it becomes noise |
| Provenance requires a public repo and a supported npm CLI | Low | Pin the npm CLI version in the workflow; provenance failure fails the publish rather than silently downgrading |

## Rollback Plan

The change is strictly additive; no consumer references the new workflow until it edits its own file.

1. Revert the PR (or the chain) — `node-release.yml` and `node-ci.yml` are untouched and keep working.
2. If a bad version reached npm: `npm dist-tag rm <pkg> edge` and `npm deprecate <pkg>@<version>`; npm versions cannot be unpublished after 72h, so the forward fix is a new patch.
3. If a bad version reached GitHub Packages: delete the package version from the repo's Packages UI.
4. Delete the stray git tag and GitHub Release if semantic-release created one for a failed publish.

## Review Workload Forecast

Delivery strategy: `auto-chain` (400-line budget).

```
Decision needed before apply: No
Chained PRs recommended: Yes
400-line budget risk: High
```

Estimated total: ~420 authored lines. Suggested stacked slices to `main`, each independently landable:

| # | Slice | Est. lines | Boundary |
|---|-------|-----------|----------|
| 1 | `setup` action: `package_json_file` + full-history checkout inputs (backward compatible) | ~50 | Existing callers keep current behavior |
| 2 | `trunk-npm-publish.yml` PR path: install, typecheck, test, build, `pack --dry-run` | ~130 | Workflow exists and is usable for validation only |
| 3 | `main` publish path: semantic-release, dual-registry publish, provenance, `edge` prerelease | ~180 | Publishing enabled end to end |
| 4 | README section, file-tree entry, consumer usage example | ~60 | Documentation complete |

Slices 2–4 depend on 1. If any bash is extracted, its `tests/*.test.sh` ships inside the same slice.

## Dependencies

- `NPM_TOKEN` (automation, scoped, publish rights) configured as a secret in each consuming repo.
- `id-token: write` and `packages: write` permissions granted by the calling workflow.
- Consuming repos must use conventional commits for version inference.

## Success Criteria

- [ ] A consuming repo publishes to npmjs and GitHub Packages via a single `workflow_call` reference plus `NPM_TOKEN`.
- [ ] No commit is written back to `main` by the release process; `package.json` in git remains `0.0.0`.
- [ ] Published npmjs versions show a verified provenance attestation.
- [ ] Every merge to `main` produces both a stable version and an `edge` dist-tag prerelease.
- [ ] PRs run install, typecheck, test, build, and `pnpm pack --dry-run`, including when `app_path` points at a subdirectory.
- [ ] `node-release.yml`, `node-ci.yml`, and `release-train.yml` are byte-identical after the change.
