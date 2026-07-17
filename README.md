# Reusable GitHub Workflows

This repository contains reusable GitHub Actions workflows and composite actions that can be used across multiple projects to centralize CI/CD logic.

## Structure

```
.github/
├── workflows/                  # Reusable workflows
│   ├── web-build.yml           # Web application build workflow
│   ├── api-build.yml           # API build workflow
│   ├── node-release.yml        # Node.js release workflow with semantic-release
│   ├── release-train.yml       # Automatic alpha/beta/stable release train
│   ├── docker-release.yml      # Version bump + Docker build & publish
│   ├── codeql.yml              # CodeQL security analysis (init + analyze)
│   ├── pr-labeler.yml          # Auto-label PRs by changed files
│   └── test.yml                # CI for this repository (detect tests + shellcheck)
├── actions/                    # Composite actions
│   ├── setup/                  # Common setup (Node.js, pnpm, checkout)
│   ├── install/                # Install dependencies with pnpm
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

**Example: Using the Web Build workflow**

Create `.github/workflows/ci.yml` in your project:

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  build-web:
    uses: sisques-labs/workflows/.github/workflows/web-build.yml@main
    with:
      app_path: "apps/web"
      app_name: "My Web App"
      node_version: "24"
      run_lint: true
      run_test: true
      build_command: "build"
    secrets: inherit # Required if the workflow needs secrets
```

**Key Points:**

- Use `uses: sisques-labs/workflows/.github/workflows/web-build.yml@main` to reference the workflow
- Replace `@main` with the branch/tag you want to use (e.g., `@v1.0.0` for versioned releases)
- All inputs are passed via the `with:` section
- Use `secrets: inherit` to pass secrets from your repository to the reusable workflow

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
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-web:
    uses: sisques-labs/workflows/.github/workflows/web-build.yml@main
    with:
      app_path: "apps/web"
      app_name: "Web App"

  build-admin:
    uses: sisques-labs/workflows/.github/workflows/web-build.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"

  build-api:
    uses: sisques-labs/workflows/.github/workflows/api-build.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
```

## Reusable Workflows

### Web Build

Builds a Next.js or web application with optional linting and testing.

**Usage:**

```yaml
name: Web Build

on:
  pull_request:
    paths:
      - "apps/web/**"
    branches: [main, dev]

jobs:
  build:
    uses: sisques-labs/workflows/.github/workflows/web-build.yml@main
    with:
      app_path: "apps/web"
      app_name: "Web App"
      node_version: "24"
      run_lint: true
      run_test: true
      build_command: "build"
```

**Inputs:**

- `app_path` (required): Path to the web app (e.g., `apps/web`)
- `app_name` (optional, default: `"Web App"`): Name of the app for display
- `node_version` (optional, default: `"24"`): Node.js version to use
- `run_lint` (optional, default: `true`): Whether to run lint
- `run_test` (optional, default: `true`): Whether to run tests
- `build_command` (optional, default: `"build"`): Build command to run (e.g., `build`, `build:prod`)
- `use_filter` (optional, default: `false`): Whether to use filter for installation

### API Build

Builds a NestJS or API application with optional linting and testing.

**Usage:**

```yaml
name: API Build

on:
  pull_request:
    paths:
      - "apps/api/**"
    branches: [main, dev]

jobs:
  build:
    uses: sisques-labs/workflows/.github/workflows/api-build.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
      node_version: "24"
      run_lint: true
      run_test: true
      build_command: "build"
```

**Inputs:**

- `app_path` (required): Path to the API app (e.g., `apps/api`)
- `app_name` (optional, default: `"API"`): Name of the app for display
- `node_version` (optional, default: `"24"`): Node.js version to use
- `run_lint` (optional, default: `true`): Whether to run lint
- `run_test` (optional, default: `true`): Whether to run tests
- `build_command` (optional, default: `"build"`): Build command to run (e.g., `build`, `build:prod`)
- `use_filter` (optional, default: `false`): Whether to use filter for installation

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
  build-web:
    uses: sisques-labs/workflows/.github/workflows/web-build.yml@main
    with:
      app_path: "apps/web"
      app_name: "Web App"
      node_version: "24"
      run_lint: true
      run_test: true
      build_command: "build"

  build-api:
    uses: sisques-labs/workflows/.github/workflows/api-build.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
      node_version: "24"
      run_lint: true
      run_test: true
      build_command: "build"

  release:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: [build-web, build-api]
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
