# Reusable GitHub Workflows

This repository contains reusable GitHub Actions workflows and composite actions that can be used across multiple projects to centralize CI/CD logic.

## Structure

```
.github/
├── workflows/                  # Reusable workflows
│   ├── node-ci.yml              # Lint, test, and build a Node.js app as parallel jobs
│   ├── node-release.yml        # Node.js release workflow with semantic-release
│   ├── release-train.yml       # Automatic alpha/beta/stable release train
│   ├── docker-release.yml      # Version bump + Docker build & publish
│   ├── docker-smoke-build.yml  # PR-time Dockerfile build + blocking vuln scan
│   ├── codeql.yml              # CodeQL security analysis (init + analyze)
│   ├── pr-labeler.yml          # Auto-label PRs by changed files
│   ├── coolify-deploy.yml      # Trigger a Coolify deploy via its API
│   └── test.yml                # CI for this repository (detect tests + shellcheck)
├── actions/                    # Composite actions
│   ├── setup/                  # Common setup (Node.js, pnpm, checkout)
│   ├── install/                # Install dependencies with pnpm
│   ├── trivy-scan/             # Scan a local image, report always, block optionally
│   └── release-train-detect/   # Compute the exact next version from git tags
└── tests/                      # Test suites for the scripts in this repo
```

## How to Use in Other Projects

### Prerequisites

1. **Repository Access**: The target project must have access to the `sisques-labs/workflows` repository. If it's a private repository, ensure proper permissions are configured.

2. **Project Structure**: Your project should use:
   - `pnpm` as package manager
   - A monorepo structure (optional, but recommended for `app_path` usage)

### Using Reusable Workflows

To use a reusable workflow in another project, create a workflow file in your project's `.github/workflows/` directory and reference the workflow using the `uses` keyword.

**Example: Using the Node CI workflow**

Create `.github/workflows/ci.yml` in your project:

```yaml
name: CI

on:
  pull_request:

jobs:
  ci:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      node_version: "24"
```

**Key Points:**

- Use `uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main` to reference the workflow
- Replace `@main` with the branch/tag you want to use (e.g., `@v1.0.0` for versioned releases)
- All inputs are passed via the `with:` section
- Use `secrets: inherit` only if the workflow you're calling actually needs secrets (`node-ci.yml` doesn't)

### Using Composite Actions

You can also use the composite actions directly in your own workflows:

**Example: Using Setup and Install actions**

```yaml
name: Custom Workflow

on:
  push:
    branches: [main]

jobs:
  custom-job:
    runs-on: ubuntu-latest
    steps:
      - name: Setup
        uses: sisques-labs/workflows/.github/actions/setup@main
        with:
          node_version: "24"
          # pnpm_version is optional - will auto-detect from package.json if not specified

      - name: Install dependencies
        uses: sisques-labs/workflows/.github/actions/install@main
        with:
          app_path: "apps/web"
          use_filter: "true"
          frozen_lockfile: "true"

      - name: Your custom step
        run: echo "Do something custom here"
```

### Using the Shared Renovate Config

This repository also hosts a shared [Renovate](https://docs.renovatebot.com/) preset (`default.json`) so dependency-update policy (schedule, grouping, commit style) is centralized instead of duplicated per project.

**Prerequisites**:
- The [Mend Renovate GitHub App](https://github.com/apps/renovate) must be installed on the target repository (or the whole org).
- The preset targets update PRs at a `dependabot/updates` branch (`baseBranches`) instead of the default branch, so that branch must already exist in the target repository before Renovate runs. Promote it to your default branch on whatever cadence you want.

Add a `renovate.json` at the root of your project:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>sisques-labs/workflows"]
}
```

Project-specific overrides (e.g. a different schedule or extra `packageRules`) can be added alongside the `extends` array in that same file — they take precedence over the shared preset.

**Note**: if the project previously used Dependabot version updates (`.github/dependabot.yml`), remove that file when adopting this preset to avoid duplicate PRs for the same dependencies.

**Automerge**: minor, patch, pin, digest, and lockfile-maintenance PRs are automerged once all GitHub Actions checks on the PR pass (`automergeType: "pr"`, `platformAutomerge: false`). Major updates are never automerged and always wait for manual review.

`platformAutomerge` is deliberately `false`: it makes Renovate merge the PR itself via the API as soon as it sees all checks green, instead of relying on GitHub's native auto-merge queue. That avoids a hard prerequisite — GitHub's native auto-merge only works when **Settings → General → Allow auto-merge** is enabled on the target repository, and this has been inconsistent across our repos in practice (some had it off, silently leaving green Renovate PRs unmerged). If you'd rather use the native queue for its better branch-protection integration, enable that setting on the repo and flip `platformAutomerge` back to `true`.

### Versioning Strategy

- **`@main`**: Use for latest/development version (may have breaking changes)
- **`@v1.0.0`**: Use for stable, versioned releases (recommended for production)
- **`@feature-branch`**: Use for testing new features before merging

**Recommendation**: Pin to a specific version tag for production projects to ensure stability.

### Multiple Apps in Monorepo

If you have multiple apps in a monorepo, you can create separate jobs for each:

```yaml
name: CI

on:
  pull_request:

jobs:
  ci-web:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      app_path: "apps/web"
      node_version: "24"

  ci-api:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      app_path: "apps/api"
      node_version: "24"
```

## Reusable Workflows

### Node CI

Lints, unit-tests, and builds a Node.js app. Unlike a single sequential job,
`lint`, `test`, `build`, and the optional `extra_check` run as **four
independent jobs with no `needs:` between them** — they only need `install`,
so they all start at once instead of queuing behind each other.

**Usage:**

```yaml
name: CI

on:
  pull_request:

jobs:
  ci:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      node_version: "22"
      test_command: "test:coverage" # only if it differs from the default "test"
      extra_check_command: "gen:topics:check" # optional, runs as its own parallel job
```

**Inputs:**

- `app_path` (optional, default: `"."`): Path to the app/package (e.g., `apps/web`)
- `node_version` (required): Node.js version to use
- `use_filter` (optional, default: `false`): Whether to use filter for installation
- `run_lint` / `lint_command` (optional, default: `true` / `"lint"`)
- `run_test` / `test_command` (optional, default: `true` / `"test"`)
- `run_build` / `build_command` (optional, default: `true` / `"build"`)
- `extra_check_command` (optional, default: `""`): an extra `pnpm <command>` that runs as its own parallel job when non-empty — e.g. a codegen-sync check, a `tsc --noEmit` type check, or a service-less test suite (`test:e2e` for an app with no DB dependency). Free-form, so it's whatever the consumer repo needs; there's exactly one slot, not a list.
- `env_vars` (optional, default: `""`): extra environment variables applied to every job, as newline-separated `KEY=VALUE` pairs — for non-secret values a test suite needs (e.g. a mocked login). Use repository/environment secrets instead for anything sensitive.

**What this deliberately does NOT cover:** DB-backed `e2e`/`integration` jobs
(Postgres services, migrations, seed data). Those differ too much between
consumers (DB engine/version, env var names, extra setup steps) to fit a
generic reusable workflow without turning it into a pile of pass-through
inputs. Define those as ordinary jobs alongside the `ci:` job in the
consumer's own `ci.yml` — with **no `needs: ci`** unless they genuinely
consume `node-ci.yml`'s build output (most e2e/integration suites run
straight from source and only need `install`, so gating them behind lint/
test/build just adds wall-clock time for no reason).

### Node Release

Automatically releases a Node.js package using semantic-release. Updates the version in `package.json`, creates Git tags, generates GitHub releases, and creates changelogs automatically based on conventional commits.

**Usage:**

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/node-release.yml@main
    secrets: inherit
    with:
      app_path: "packages/sdk"
      build_command: "build"
      use_filter: true
```

**Inputs:**

- `app_path` (optional, default: `"."`): Path to the app/package (e.g., `packages/sdk`, `apps/api`). Use `"."` for root
- `working_directory` (optional): Working directory for semantic-release (defaults to `app_path`)
- `node_version` (optional, default: `"24"`): Node.js version to use
- `pnpm_version` (optional, default: `""`): pnpm version to use. If empty, will auto-detect from `package.json`
- `use_filter` (optional, default: `false`): Whether to use filter for installation
- `build_command` (optional): Build command to run before release (e.g., `build`, `build:prod`)
- `release_command` (optional): Custom release command. Defaults to `pnpm release` if found in package.json, otherwise uses `npx semantic-release`

**Requirements:**

- Your project must have `semantic-release` configured. You can either:
  - Add a `release` script to your `package.json`: `"release": "semantic-release"`
  - Or install `semantic-release` as a dependency (the workflow will use `npx semantic-release`)
- The workflow requires `GITHUB_TOKEN` (automatically provided) and optionally `NPM_TOKEN` if publishing to npm
- Ensure your commits follow [Conventional Commits](https://www.conventionalcommits.org/) format for automatic versioning

**Example with monorepo:**

```yaml
name: Release SDK

on:
  push:
    paths:
      - "packages/sdk/**"
    branches:
      - main

jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/node-release.yml@main
    secrets: inherit
    with:
      app_path: "packages/sdk"
      working_directory: "packages/sdk"
      build_command: "build"
      use_filter: true
```

### Release Train

Fully automatic semver pipeline driven by branch merges. Every push to a train
branch publishes a Docker image, a git tag, and a GitHub Release for the
corresponding channel:

| Branch    | Channel | Version produced                  | Docker tags                          |
| --------- | ------- | ---------------------------------- | ------------------------------------- |
| `develop` | alpha   | `X.Y.Z-alpha.N`                   | `:X.Y.Z-alpha.N`, `:alpha`           |
| `staging` | beta    | `X.Y.Z-beta.N`                    | `:X.Y.Z-beta.N`, `:beta`             |
| `main`    | stable  | `X.Y.Z`                           | `:X.Y.Z`, `:latest`                  |

**How versions are computed**

Git tags are the single source of truth — `package.json` is overwritten with
the computed version at release time and is never read to derive one. The
`release-train-detect` action computes the exact next version in one place:

- `develop` continues the open alpha cycle (`0.16.0-alpha.3` → `0.16.0-alpha.4`)
  or opens a new one from the latest stable when the previous cycle graduated.
  The bump for a new cycle follows conventional commits: `feat:` → minor,
  breaking change (`!` or `BREAKING CHANGE:`) → major, anything else → patch.
- `staging` promotes the newest alpha cycle to `beta.0`, or iterates the
  current beta cycle when a fix is merged into staging directly.
- `main` graduates the leading beta cycle to stable, or cuts a patch release
  for hotfixes merged straight to main.

A computed version is **always strictly greater than the latest stable
release**: a stale pre-release cycle whose base already shipped (e.g.
`0.15.1-beta.N` after `v0.15.1` went stable) is abandoned, never continued.
Duplicate tags are rejected before anything is published.

**Publish ordering (atomic releases)**

1. Lint, test, and **build** the Docker image without pushing.
2. Tag the release commit and push. Only `main` also commits the version bump
   + `CHANGELOG.md` before tagging — `develop` and `staging` tag the existing
   commit as-is, so pre-release channels never push a bot commit back to the
   branch. If this fails, nothing has been published anywhere.
3. Push the image (instant — reuses the buildx cache) and create the GitHub
   Release.

This guarantees a git tag can never lag behind a published image, which is
what previously allowed version reuse.

**Outputs:** `should_release` (`"true"`/`"false"`), `release_type`
(`alpha`/`beta`/`stable`, empty when nothing released), `next_tag` (empty when
nothing released). A push with no integrated changes since the last tag still
completes the `uses:` call successfully — the internal `release` job is
skipped, not failed — so a caller chaining a job after this one (e.g. a
Coolify deploy) must check `should_release` explicitly rather than relying on
`needs.<job>.result`:

```yaml
jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
    # ...

  deploy:
    needs: release
    if: needs.release.outputs.should_release == 'true'
    uses: sisques-labs/workflows/.github/workflows/coolify-deploy.yml@main
    # ...
```

**Release notes:** only `main` generates `CHANGELOG.md`/release notes with
git-cliff, accumulating everything shipped since the previous stable release
into one flat section (the work that flowed through alpha/beta), so the notes
describe what actually lands in production. `develop` and `staging` releases
use GitHub's auto-generated notes instead.

**Usage (consumer repository):**

```yaml
name: Release Train

on:
  push:
    branches: [develop, staging, main]

permissions:
  contents: write
  packages: write

# One group for the whole repo: develop/staging/main releases are serialized
# so two channels never read/write tags concurrently.
concurrency:
  group: release-train
  cancel-in-progress: false

jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
    with:
      image_name: sisqueslabs/my-app
      ghcr_image_name: ghcr.io/sisques-labs/my-app
      push_ghcr: true
      node_version: "22"
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
    permissions:
      contents: write
      packages: write
```

**Testing:** the version-computation logic is covered by
`tests/release-train-detect.test.sh`, which runs on every PR to this
repository (including a regression test for the stale-beta bug).

### Branch sync after a stable release

After a stable release (a push to `main` that graduates a release), both
`release-train.yml` and `docker-release.yml` (`bump_mode: release-train`)
can merge the new tag back into other long-lived branches so they don't
drift behind `main`. Two independent inputs control this, both default
`true` on `release-train.yml`:

- `sync_develop_after_stable`: merges the new tag into `develop`.
- `sync_dependabot_updates_after_stable`: merges the new tag into
  `dependabot/updates` — the Renovate base branch from the shared preset
  above. Renovate PRs accumulate there until someone promotes the branch
  into `main` by hand, so keeping it merged up to date with every stable
  release avoids that promotion turning into a painful catch-up merge.

Both syncs:

- Only run on `main` (the stable channel) — regardless of the input value,
  `release-train.yml` gates the call with `github.ref_name == 'main'`, so a
  `develop`/`staging` push never touches either branch.
- Skip silently (exit 0) if the target branch doesn't exist in the
  repository yet.
- Fail the job on a merge conflict rather than resolving it silently. By
  that point the release itself (git tag, Docker image, GitHub Release) has
  already published successfully, so a failure here just means the branch
  needs a manual conflict resolution and re-sync — nothing that already
  shipped is affected.

```yaml
uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
with:
  image_name: sisqueslabs/my-app
  sync_develop_after_stable: true # default
  sync_dependabot_updates_after_stable: true # default
```

### Docker Hub description sync

Both `docker-release.yml` and `release-train.yml` accept an optional
`dockerhub_readme_path` input (default: `docker/README.md`). It points to a
README file in the consumer's checkout — a Docker Hub-specific one, separate
from the repo's own development `README.md` — that is pushed as the
repository description on Docker Hub via
[`peter-evans/dockerhub-description`](https://github.com/peter-evans/dockerhub-description).

Consumers don't need to pass anything to opt in: just add a
`docker/README.md` file to the repo. Nothing else changes for repos that
don't have that file yet.

```yaml
uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
with:
  image_name: sisqueslabs/my-app
  # dockerhub_readme_path: docker/README.md is the default — override only
  # if your Docker Hub README lives somewhere else, or pass "" to disable.
secrets:
  DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
  DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
```

**Behavior:**

- **100% backwards compatible.** Consumers without a `docker/README.md` (or
  whatever custom path they set) see no change — the sync step is skipped.
  Passing `dockerhub_readme_path: ""` explicitly disables it.
- **Skips without failing the job** if the input is empty, or if the file
  doesn't exist in the checkout at that path. Not every consumer has this
  file yet, so a missing file is not an error.
- **Only runs on the stable channel** — `release_type == 'stable'`. In
  `docker-release.yml` this is the `release_type` input directly (legacy
  manual releases default to `stable`). `release-train.yml` doesn't
  re-derive this: it just forwards `dockerhub_readme_path` to
  `docker-release.yml`, which already receives the channel computed by
  `release-train-detect` (`develop` → alpha, `staging` → beta, `main` →
  stable) as its own `release_type` input. Alpha/beta/rc releases and
  every push to `develop`/`staging` never touch the Docker Hub description.
- **Only runs after a real publish.** `image_name` is a required input and
  the Docker Hub login step is unconditional, so by the time this step is
  reached the image has already been pushed — there's no separate
  "did we actually publish" flag to check.
- **Best-effort — never blocks the release.** The sync step runs with
  `continue-on-error: true`. If it fails (e.g. `DOCKERHUB_TOKEN` lacking the
  required scope, or a transient Docker Hub API error), the job logs an
  `::warning::` and carries on — the image was already published and the
  git tag/GitHub Release already created by this point, so a broken
  description sync must not fail an otherwise-successful release. Check the
  job summary/logs for the warning if the description isn't updating.

**⚠️ Token permissions:** `peter-evans/dockerhub-description` calls the
Docker Hub API to update the repository description, which requires a
password or Personal Access Token with **`Read, Write, Delete`** scope.
This is a **broader scope than what `docker login`/image push needs**
(typically `Read & Write`). The sync step reuses the existing
`DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets — if your `DOCKERHUB_TOKEN`
was created with only `Read & Write` scope, the sync step will fail with
`401`/`403` even though image pushes keep working fine. Before enabling
`dockerhub_readme_path`, regenerate/upgrade that token in Docker Hub
(Account Settings → Security → Access Tokens) to `Read, Write, Delete`.
If the repository belongs to a Docker Hub organization, the account also
needs `Admin` permissions on that repository.

### Coolify Deploy

Triggers a deploy on a [Coolify](https://coolify.io) instance by calling its
deploy API for a specific resource. This is a thin, single-purpose workflow —
it doesn't know about release channels, branches, or environments; the caller
decides when to run it and which resource UUID to target.

**Usage (consumer repository):** chain it after a release job, gated on that
job actually having published something (see `should_release` under
[Release Train](#release-train) above). Each environment (dev/staging/prod)
maps to a different Coolify resource UUID, selected by the branch that
triggered the release:

```yaml
name: Release Train

on:
  push:
    branches: [develop, staging, main]

permissions:
  contents: write
  packages: write
  security-events: write

concurrency:
  group: release-train
  cancel-in-progress: false

jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
    with:
      image_name: sisqueslabs/my-app
      # ...
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
    permissions:
      contents: write
      packages: write
      security-events: write

  deploy:
    name: Deploy to Coolify
    needs: release
    if: needs.release.outputs.should_release == 'true'
    uses: sisques-labs/workflows/.github/workflows/coolify-deploy.yml@main
    secrets:
      COOLIFY_BASE_URL: ${{ secrets.COOLIFY_BASE_URL }}
      COOLIFY_TOKEN: ${{ secrets.COOLIFY_TOKEN }}
      COOLIFY_UUID: >-
        ${{
          github.ref_name == 'main' && secrets.COOLIFY_UUID_PROD ||
          github.ref_name == 'staging' && secrets.COOLIFY_UUID_STAGING ||
          secrets.COOLIFY_UUID_DEV
        }}
```

**Inputs:**

- `force` (optional, default: `false`): forces Coolify to redeploy even if it
  thinks nothing changed (the API's `force` param) — useful for a manual
  `workflow_dispatch` retry, not normally needed for a release-triggered
  deploy since a new image tag is itself a change.

**Secrets (all required):**

- `COOLIFY_BASE_URL`: base URL of the Coolify instance (e.g.
  `https://coolify.example.com`).
- `COOLIFY_TOKEN`: a Coolify API token with permission to deploy the target
  resource. Generate it in Coolify under your team/account's API tokens.
- `COOLIFY_UUID`: UUID of the Coolify resource (application) to deploy. Found
  on the resource's page in Coolify, or in its own webhook/API settings.

**Naming convention for consumer repo secrets:** one `COOLIFY_TOKEN` and one
`COOLIFY_BASE_URL` per repo, plus one UUID secret per environment —
`COOLIFY_UUID_DEV`, `COOLIFY_UUID_STAGING`, `COOLIFY_UUID_PROD` — selected at
call time by `github.ref_name` as shown above. Treat the UUID as a secret
even though it isn't a credential by itself: combined with the base URL and
token it identifies exactly which resource in your infrastructure gets
redeployed.

**How it works:** a single `GET {COOLIFY_BASE_URL}/api/v1/deploy` request
with `uuid` and `force` as query params and `Authorization: Bearer
{COOLIFY_TOKEN}`. The job fails if Coolify returns a non-2xx status. This is
Coolify's documented deploy-by-API mechanism — verify the exact path against
your Coolify version's API docs before relying on this in production, since
self-hosted instances can lag behind the latest API.

**Environments you haven't set up yet are a silent no-op, not a failure.**
`required: true` on a `workflow_call` secret only means the caller's
`secrets:` block must reference the key — it does **not** mean the resolved
value is non-empty. In the branch-based UUID selector shown above, a branch
whose UUID secret was never created (e.g. you only have prod today, so
`COOLIFY_UUID_STAGING`/`COOLIFY_UUID_DEV` don't exist) resolves to an empty
string, not an error. This workflow checks for that: if
`COOLIFY_BASE_URL`/`COOLIFY_TOKEN`/`COOLIFY_UUID` is empty, it logs a
`::notice::` and exits `0` instead of calling Coolify with a blank UUID (which
would otherwise fail the job with a confusing 404/422 on every push to that
branch). This means the `deploy` job pattern above is safe to add for all
three environments up front, even if only prod's secrets exist right now —
`develop`/`staging` pushes just show a green, skipped-looking run until you
add their UUID secrets later.

### Docker image vulnerability scanning

Vulnerability scanning is split across **two** reusable workflows, on
purpose, so that blocking happens where it's actually useful and never
surprises an already-merged release:

| Workflow | When | Blocks on CRITICAL (fixable)? |
| --- | --- | --- |
| `docker-smoke-build.yml` | On the PR, before merge | **Yes** |
| `docker-release.yml` / `release-train.yml` | On publish, after merge | No — report only |

Both scan with [Trivy](https://github.com/aquasecurity/trivy) via the shared
`trivy-scan` composite action (below); they only differ in whether the
action's `block_on_critical` is set.

**Why split it this way:** blocking at publish time means a CVE that gets
published *after* a PR already merged cleanly can fail a release train run
for code nobody touched — "we already merged to `develop`, why did the
release just fail?" Blocking at PR time instead gives the same protection
(a known-vulnerable image never reaches `main`) without that surprise: once
merged, later scans are purely informational (SARIF still uploads to
Security → Code scanning either way, so nothing is silently missed).

**Docker Smoke Build (the blocking one):**

```yaml
name: Docker Build

on:
  pull_request:

permissions:
  contents: read
  security-events: write # required for the SARIF upload

jobs:
  docker:
    uses: sisques-labs/workflows/.github/workflows/docker-smoke-build.yml@main
    with:
      image_name: my-app
      platforms: linux/amd64,linux/arm64
      scan_image: true
```

**Inputs:**

- `image_name` (required): local tag used for the smoke build/scan — never pushed anywhere.
- `dockerfile` (optional, default: `"Dockerfile"`)
- `context` (optional, default: `"."`)
- `platforms` (optional, default: `"linux/amd64,linux/arm64"`): comma-separated platforms the smoke build validates. Each platform builds **natively** on its own runner (`ubuntu-latest` for `linux/amd64`, `ubuntu-24.04-arm` for `linux/arm64`) via a matrix — no QEMU emulation. `linux/arm64` requires GitHub-hosted arm64 runners to be available to the calling repo (public repos, or Team/Enterprise on private repos); if unavailable, pass `platforms: linux/amd64` only.
- `scan_image` (optional, default: `false`): scan with Trivy and **fail the check** on a CRITICAL vulnerability with a known fix. Runs once, on the `linux/amd64` leg.

**Docker Release / Release Train (report-only):**

```yaml
uses: sisques-labs/workflows/.github/workflows/release-train.yml@main
with:
  image_name: sisqueslabs/my-app
  scan_image: true
permissions:
  contents: write
  packages: write
  security-events: write # required for the SARIF upload
```

**Build strategy:**

- `docker-smoke-build.yml` builds each requested platform **natively**, one
  per matrix leg (`ubuntu-latest` for `linux/amd64`, `ubuntu-24.04-arm` for
  `linux/arm64`) — no QEMU. The `linux/amd64` leg is also the only one that
  can `docker load` a single-arch image locally, so `scan_image` reuses that
  same build/load as its scan target instead of a separate scan-only build.
- `docker-release.yml`/`release-train.yml` still build one true multi-arch
  manifest with `push: false` first (needed to publish a single manifest
  list across platforms), which can't be `docker load`ed. When `scan_image`
  is enabled there, a second `linux/amd64`-only image is built with
  `load: true` purely to scan locally — it reuses the same buildx cache as
  the real build, so the extra build is cheap, but that workflow's real
  multi-arch build still goes through QEMU for the `linux/arm64` leg.

**Scan behavior (both workflows):**

- A full-severity SARIF report is always generated and uploaded to the
  consumer repo's Security → Code scanning tab, regardless of whether
  anything CRITICAL was found — this step never fails the job.
- `docker-smoke-build.yml` then also fails the check if it finds a
  **CRITICAL** vulnerability that **has a known fix** (`ignore-unfixed:
  true`). A CRITICAL with no upstream fix available is reported in the
  SARIF but does not block — otherwise a single unfixable CVE in a base
  image would block every future PR with no way out short of a
  `.trivyignore` entry. `docker-release.yml`/`release-train.yml` never run
  this blocking step at all.
- The release-side scan runs on **every** channel (alpha/beta/stable via
  `release-train.yml`, or any manual run via `docker-release.yml`
  directly) — an alpha/beta image still reaches real users testing it, so
  it isn't scoped to stable-only like the branch syncs above.
- Scanning happens **before** the version bump, git tag, and any registry
  push — so even though it never blocks, a fresh SARIF is always available
  for the exact image about to publish.

**Requirements:**

- The calling job must grant `security-events: write` explicitly (same
  rule as CodeQL below) — `secrets: inherit` alone does not cover this.
- Off by default (`scan_image: false`) on both workflows, so enabling it is
  an explicit, per-repo opt-in rather than something that can suddenly fail
  an existing pipeline on CVEs nobody has triaged yet.

### CodeQL

Runs GitHub's CodeQL static analysis (`init` + `analyze`) and uploads results
to the consumer repo's Security → Code scanning tab. Triggers, branches, and
schedule are owned by the caller workflow — this reusable workflow only runs
the scan itself.

**Usage (consumer repository):**

```yaml
name: CodeQL

on:
  push:
    branches: [develop, staging, main]
  pull_request:
    branches: [develop, staging, main]
  schedule:
    - cron: "0 6 * * 1" # weekly, Monday 06:00 UTC

jobs:
  analyze:
    uses: sisques-labs/workflows/.github/workflows/codeql.yml@main
    permissions:
      actions: read
      contents: read
      security-events: write
```

**Inputs:**

- `language` (optional, default: `"javascript-typescript"`): CodeQL language identifier. A JS/TS project needs no build step — CodeQL extracts directly from source.
- `queries` (optional, default: `"security-extended"`): Query suite to run (`default`, `security-extended`, or `security-and-quality`)

**Requirements:**

- The calling job must grant `security-events: write` (to upload SARIF), `actions: read`, and `contents: read` — CodeQL code scanning does not work with a token from `secrets: inherit` alone, permissions must be set explicitly on the job.
- Public repositories get code scanning for free; private repositories need GitHub Advanced Security enabled on the repo/org.

### PR Labeler

Labels pull requests automatically based on which files changed, using
[`actions/labeler`](https://github.com/actions/labeler). The consumer repo
owns the path → label mapping (`.github/labeler.yml`); this reusable workflow
just runs the labeler and makes sure the labels it references exist first
(created with a fixed name/color/description on first use, so nothing has to
be set up by hand in the repo's Settings → Labels).

**Usage (consumer repository):**

```yaml
name: PR Labeler

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  label:
    uses: sisques-labs/workflows/.github/workflows/pr-labeler.yml@main
```

Add `.github/labeler.yml` to the consumer repo, e.g.:

```yaml
documentation:
  - changed-files:
      - any-glob-to-any-file:
          - "**/*.md"
          - "docs/**"

tests:
  - changed-files:
      - any-glob-to-any-file:
          - "**/*.spec.ts"
          - "**/*.e2e-spec.ts"

ci:
  - changed-files:
      - any-glob-to-any-file:
          - ".github/workflows/**"
          - ".github/actions/**"

dependencies:
  - changed-files:
      - any-glob-to-any-file:
          - "package.json"
          - "pnpm-lock.yaml"

docker:
  - changed-files:
      - any-glob-to-any-file:
          - "Dockerfile"
          - "docker/**"

config:
  - changed-files:
      - any-glob-to-any-file:
          - "*.config.*"
          - "tsconfig*.json"
```

**Inputs:**

- `configuration-path` (optional, default: `".github/labeler.yml"`): path to the labeler config in the consumer repo's checkout.
- `sync-labels` (optional, default: `true`): remove a label from the PR once it no longer touches matching files, so labels always reflect the current diff.

**Requirements:**

- The calling job needs no explicit `permissions:` block — `pull-requests: write` and `contents: read` are already granted inside the reusable workflow's own job.
- The label set (`documentation`, `tests`, `ci`, `dependencies`, `docker`, `config`) is fixed by this workflow, not configurable per consumer — it exists to keep names/colors consistent across repos. A consumer's `labeler.yml` can only choose which of these labels apply to which paths, not invent new label names.

## Composite Actions

### Setup

Common setup action for repository checkout, Node.js, and pnpm installation.
Caches the pnpm store (keyed on the lockfile) via `actions/setup-node`'s
built-in `cache: pnpm` support, so repeat runs reuse packages already in the
store instead of re-downloading the whole dependency tree every time. This
requires pnpm to be installed *before* Node.js — the composite action's step
order does this internally, no action needed by callers.

**Usage:**

```yaml
# Auto-detect pnpm version from package.json (recommended)
- name: Setup
  uses: sisques-labs/workflows/.github/actions/setup@main
  with:
    node_version: "24"

# Or specify pnpm version explicitly
- name: Setup
  uses: sisques-labs/workflows/.github/actions/setup@main
  with:
    node_version: "24"
    pnpm_version: "9.0.0"
```

**Inputs:**

- `node_version` (optional, default: `"24"`): Node.js version to use
- `pnpm_version` (optional, default: `""`): pnpm version to use. If empty, will auto-detect from `package.json` `packageManager` field

### Install

Install dependencies using pnpm with optional filter and frozen lockfile handling.

**Usage:**

```yaml
- name: Install dependencies
  uses: sisques-labs/workflows/.github/actions/install@main
  with:
    app_path: "apps/web"
    use_filter: "true"
    frozen_lockfile: "true"
```

**Inputs:**

- `app_path` (optional, default: `"."`): Path to the app/package (e.g., `apps/web`). Use `"."` for root
- `use_filter` (optional, default: `"false"`): Whether to use filter for installation
- `frozen_lockfile` (optional, default: `"true"`): Whether to use --frozen-lockfile (automatically skipped for dependabot)

### Trivy Scan

Scans an already-built, local Docker image with Trivy: always uploads a
full-severity SARIF report to Security → Code scanning, and optionally fails
the step on a CRITICAL vulnerability that has a known fix. Shared by
`docker-smoke-build.yml` (`block_on_critical: "true"`) and
`docker-release.yml`/`release-train.yml` (`block_on_critical: "false"`) so
the scan logic lives in exactly one place — see
["Docker image vulnerability scanning"](#docker-image-vulnerability-scanning)
above for why the two callers block differently.

**Usage:**

```yaml
- name: Scan image for vulnerabilities
  uses: sisques-labs/workflows/.github/actions/trivy-scan@main
  with:
    image_ref: my-app:scan
    block_on_critical: "true"
```

**Inputs:**

- `image_ref` (required): local, already-built image ref to scan (e.g. `my-app:scan`)
- `block_on_critical` (optional, default: `"false"`): fail the step if a CRITICAL vulnerability with a known fix is found

**Requirements:** the calling job needs `security-events: write` for the SARIF upload.

## Best Practices

1. **Always use `secrets: inherit`** when calling workflows that require secrets
2. **Use consistent Node.js versions** across your project (default is `24`)
3. **Use install_filter** when you only need dependencies for a specific app/package
4. **Combine workflows** in your project's workflow files for complete CI/CD pipelines

## Example: Complete CI Pipeline

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci-web:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      app_path: "apps/web"
      node_version: "24"

  ci-api:
    uses: sisques-labs/workflows/.github/workflows/node-ci.yml@main
    with:
      app_path: "apps/api"
      node_version: "24"

  release:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: [ci-web, ci-api]
    uses: sisques-labs/workflows/.github/workflows/node-release.yml@main
    secrets: inherit
    with:
      app_path: "."
      build_command: "build"
```

## Contributing

This is a centralized repository for reusable workflows. When adding new workflows or actions:

1. Follow the existing structure and naming conventions
2. Use the composite actions (`setup` and `install`) when possible
3. Document all inputs and their defaults
4. Update this README with usage examples
