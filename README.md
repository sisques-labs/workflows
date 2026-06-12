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
| --------- | ------- | --------------------------------- | ------------------------------------ |
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
2. Commit the version bump + changelog, tag the release commit, and push both
   atomically. If this fails, nothing has been published anywhere.
3. Push the image (instant — reuses the buildx cache) and create the GitHub
   Release.

This guarantees a git tag can never lag behind a published image, which is
what previously allowed version reuse.

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
