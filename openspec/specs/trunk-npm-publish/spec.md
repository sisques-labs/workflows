# trunk-npm-publish Specification

## Purpose

Reusable `workflow_call` workflow (`.github/workflows/trunk-npm-publish.yml`) that validates an npm/pnpm package on pull requests and publishes it from `main` to npmjs and GitHub Packages, without writing a version commit back to the trunk.

## Requirements

### Requirement: PR validation path

On `pull_request`, the workflow MUST run install, typecheck, test, build, and `pnpm pack --dry-run`, and MUST NOT publish or tag.

#### Scenario: PR runs validation only
- GIVEN a consumer calls the workflow from a pull request
- WHEN the run executes
- THEN install, typecheck, test, build, and `pnpm pack --dry-run` run in order
- AND no registry publish, git tag, or GitHub Release is created

#### Scenario: Failing step stops the run
- GIVEN the typecheck step fails
- WHEN the run continues
- THEN the job fails and later steps do not run

### Requirement: Trunk publish path

On `push` to `main`, the workflow MUST run semantic-release with a workflow-supplied config (commit-analyzer, release-notes-generator, github). Unless `commit_release_files` is `true`, it MUST NOT use `@semantic-release/git` or commit anything back. Version MUST come from git tags; unless `commit_release_files` is `true`, `package.json` MUST stay `0.0.0` in git and be rewritten only in the runner before publish.

#### Scenario: Releasable commit on main
- GIVEN a `feat:` commit merges to `main`
- WHEN the publish path runs
- THEN a tag and GitHub Release are created
- AND the runner's `package.json` carries the computed version at publish time

#### Scenario: No commit-back
- GIVEN any successful publish run with `commit_release_files` false (default)
- WHEN it completes
- THEN `main` has no new commit and git `package.json` still reads `0.0.0`

#### Scenario: No releasable commits
- GIVEN only `chore:` commits since the last tag
- WHEN the publish path runs
- THEN no version is published and the job succeeds with `published` = `false`

### Requirement: Optional release commit

When `commit_release_files` is `true` (default `false`), a stable release MUST also update `CHANGELOG.md` and the `package.json` version and commit both to `main` with `chore(release): <version> [skip ci]`, using a workflow-fixed plugin list (changelog, exec, git after commit-analyzer/notes; github last). The workflow MUST fail before publishing when `app_path` is not `.`. The optional `RELEASE_TOKEN` secret, when set, is used only for the semantic-release push and never for GitHub Packages.

#### Scenario: Release commit on main
- GIVEN `commit_release_files` is true and a `feat:` commit merges to `main`
- WHEN the publish path succeeds
- THEN `main` gains one `chore(release): X.Y.Z [skip ci]` commit with `CHANGELOG.md` and `package.json` at `X.Y.Z`
- AND the release commit does not trigger another publish run

#### Scenario: Subdirectory package rejected
- GIVEN `commit_release_files` is true and `app_path` is `packages/lib`
- WHEN the release step starts
- THEN the job fails before any registry publish

### Requirement: Stable and edge dist-tags

Every merge to `main` MUST produce a stable version and an `x.y.z-edge.N` prerelease published under the `edge` dist-tag.

#### Scenario: Both tags published
- GIVEN a releasable merge
- WHEN publishing completes
- THEN the stable version is on the default dist-tag and an edge prerelease is on `edge`

### Requirement: Dual registry publish

The workflow MUST publish to npmjs (public, `NPM_TOKEN`, `--provenance`) first, then to GitHub Packages (`GITHUB_TOKEN`, no provenance). Each step MUST tolerate an already-published version. The package scope MUST be validated before publishing.

#### Scenario: Both registries succeed
- GIVEN a scoped package matching the repository owner
- WHEN publishing runs
- THEN npmjs shows a verified provenance attestation and GitHub Packages holds the same version

#### Scenario: Partial failure re-run
- GIVEN npmjs succeeded and GitHub Packages failed
- WHEN the job is re-run
- THEN the npmjs conflict is tolerated and only GitHub Packages is published

#### Scenario: Invalid scope
- GIVEN an unscoped or foreign-scoped package name
- WHEN validation runs
- THEN the job fails before any publish with a message naming the required scope

### Requirement: app_path input

The workflow MUST accept `app_path` (default `.`), and every install, check, pack, and publish step MUST run in that directory.

#### Scenario: Subdirectory package
- GIVEN `app_path: packages/lib`
- WHEN the PR path runs
- THEN all steps execute against `packages/lib`

### Requirement: Setup action additive inputs

`.github/actions/setup` MUST gain `package_json_file` (pnpm version auto-detect from that file) and full-history checkout control. Defaults MUST preserve current behavior for existing callers.

#### Scenario: Subdirectory pnpm detection
- GIVEN `package_json_file: packages/lib/package.json` declares a `packageManager` version
- WHEN setup runs
- THEN that pnpm version is installed

#### Scenario: Full history for tags
- GIVEN the publish path requests full history
- WHEN checkout runs
- THEN all tags are available to semantic-release

#### Scenario: Existing callers unchanged
- GIVEN a caller passes neither new input
- WHEN setup runs
- THEN behavior matches the pre-change action

### Requirement: Concurrency

Runs MUST be grouped per ref and MUST NOT set `cancel-in-progress`.

#### Scenario: Two merges in sequence
- GIVEN two pushes to `main` in quick succession
- WHEN both run
- THEN the second waits and the first is not cancelled

### Requirement: Permissions and secrets

The workflow MUST require `contents: write`, `packages: write`, and `id-token: write` from the caller, and `NPM_TOKEN` as a secret. PR runs MUST NOT need `NPM_TOKEN`.

#### Scenario: Missing token on main
- GIVEN `NPM_TOKEN` is unset on a `main` run
- WHEN the npmjs publish step runs
- THEN the job fails with a clear error and GitHub Packages is not attempted

### Requirement: Outputs

The workflow MUST expose `published` (`true`/`false`), `version`, and `edge_version` outputs.

#### Scenario: Consumer reads outputs
- GIVEN a successful release
- WHEN a downstream job reads outputs
- THEN `published` is `true` and `version` equals the published stable version

## Key Learnings

1. Provenance applies only to the npmjs step because GitHub Packages does not support it.
2. The setup action must gain full-history and package_json_file inputs before the workflow can compute versions or detect pnpm in subdirectories.
3. Publishing npmjs first with idempotent conflict handling makes partial dual-registry failures recoverable by a simple re-run.
