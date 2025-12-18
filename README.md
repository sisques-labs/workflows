# Reusable GitHub Workflows

This repository contains reusable GitHub Actions workflows and composite actions that can be used across multiple projects to centralize CI/CD logic.

## Structure

```
.github/
├── workflows/          # Reusable workflows
└── actions/            # Composite actions
    ├── setup/          # Common setup (Node.js, pnpm, checkout)
    ├── install/        # Install dependencies with pnpm
    └── prisma-generate/ # Prisma client generation
```

## Reusable Workflows

### Build

Builds an application or package with optional linting, type checking, tests, and Prisma generation.

**Usage:**

```yaml
jobs:
  build:
    uses: sisques-labs/workflows/.github/workflows/build.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"
      run_lint: true
      run_test: false
      run_check_types: false
      run_prisma_generate: false
```

**Inputs:**

- `app_path` (required): Path to the app/package (e.g., `apps/admin`, `packages/sdk`)
- `app_name` (required): Name of the app/package for display
- `run_lint` (optional, default: `true`): Whether to run lint
- `run_test` (optional, default: `false`): Whether to run tests
- `run_check_types` (optional, default: `false`): Whether to run type checking
- `run_prisma_generate` (optional, default: `false`): Whether to run Prisma generate

### Code Quality

Runs linting, type checking, and optionally SonarCloud scan.

**Usage:**

```yaml
jobs:
  quality:
    uses: sisques-labs/workflows/.github/workflows/code-quality.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"
      node_version: "24"
      run_lint: true
      check_types: true
      run_sonarcloud: false
```

**Inputs:**

- `app_path` (required): Path to the app/package
- `app_name` (required): Name of the app/package for display
- `node_version` (optional, default: `"24"`): Node.js version to use
- `run_lint` (optional, default: `true`): Whether to run lint
- `check_types` (optional, default: `true`): Whether to run type checking
- `run_sonarcloud` (optional, default: `false`): Whether to run SonarCloud scan

**Note:** This workflow replaces the old `lint.yml` workflow and provides more flexibility.

### Test

Runs tests with optional coverage and Prisma generation.

**Usage:**

```yaml
jobs:
  test:
    uses: sisques-labs/workflows/.github/workflows/test.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
      node_version: "24"
      test_command: "test"
      coverage: true
      run_prisma_generate: true
```

**Inputs:**

- `app_path` (required): Path to the app/package
- `app_name` (required): Name of the app/package for display
- `node_version` (optional, default: `"24"`): Node.js version to use
- `test_command` (optional, default: `"test"`): Test command to run (e.g., `test`, `test:unit`, `test:e2e`)
- `coverage` (optional, default: `false`): Whether to collect test coverage
- `run_prisma_generate` (optional, default: `false`): Whether to run Prisma generate before tests

### Deploy

Deploys an application to a specified environment.

**Usage:**

```yaml
jobs:
  deploy:
    uses: sisques-labs/workflows/.github/workflows/deploy.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
      environment: "production"
      deploy_command: "deploy"
      node_version: "24"
      build_before_deploy: true
    secrets: inherit
```

**Inputs:**

- `app_path` (required): Path to the app (e.g., `apps/api`)
- `app_name` (required): Name of the app for display
- `environment` (required): Deployment environment (e.g., `staging`, `production`)
- `deploy_command` (optional, default: `"deploy"`): Deploy command to run
- `node_version` (optional, default: `"24"`): Node.js version to use
- `build_before_deploy` (optional, default: `true`): Whether to build before deploying

### Security Scan

Runs security scans using npm audit, Snyk, and Trivy.

**Usage:**

```yaml
jobs:
  security:
    uses: sisques-labs/workflows/.github/workflows/security-scan.yml@main
    with:
      app_path: "."
      node_version: "24"
    secrets: inherit
```

**Inputs:**

- `app_path` (optional, default: `"."`): Path to scan (default: entire repository)
- `node_version` (optional, default: `"24"`): Node.js version to use

**Required Secrets:**

- `SNYK_TOKEN`: Snyk API token

### Package Release

Releases a package using semantic-release.

**Usage:**

```yaml
jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/package-release.yml@main
    with:
      package_path: "packages/sdk"
      package_name: "SDK"
    secrets: inherit
```

**Inputs:**

- `package_path` (required): Path to the package (e.g., `packages/sdk`, `packages/shared`)
- `package_name` (required): Name of the package for display

**Required Permissions:**

- `contents: write`
- `issues: write`
- `pull-requests: write`

### App Release with Docker

Releases an application and builds/pushes a Docker image to GitHub Container Registry.

**Usage:**

```yaml
jobs:
  release:
    uses: sisques-labs/workflows/.github/workflows/app-release.yml@main
    with:
      app_path: "apps/api"
      app_name: "API"
      dockerfile_path: "."
    secrets: inherit
```

**Inputs:**

- `app_path` (required): Path to the app (e.g., `apps/api`)
- `app_name` (required): Name of the app for display
- `dockerfile_path` (optional, default: `"."`): Path to Dockerfile directory (default: root)

**Required Secrets:**

- `GHCR_TOKEN`: GitHub Container Registry token
- `GHCR_USERNAME`: GitHub Container Registry username

**Required Permissions:**

- `contents: write`
- `packages: write`
- `issues: write`
- `pull-requests: write`

### PR Preview

Deploys a preview environment for pull requests (Vercel, Netlify, or Cloudflare).

**Usage:**

```yaml
jobs:
  preview:
    uses: sisques-labs/workflows/.github/workflows/pr-preview.yml@main
    with:
      app_path: "apps/web"
      app_name: "Web App"
      node_version: "24"
      preview_platform: "vercel"
      build_command: "build"
    secrets: inherit
```

**Inputs:**

- `app_path` (required): Path to the app (e.g., `apps/web`)
- `app_name` (required): Name of the app for display
- `node_version` (optional, default: `"24"`): Node.js version to use
- `preview_platform` (optional, default: `"vercel"`): Preview platform (`vercel`, `netlify`, `cloudflare`)
- `build_command` (optional, default: `"build"`): Build command to run

**Required Secrets (Vercel):**

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

**Required Secrets (Netlify):**

- `NETLIFY_AUTH_TOKEN`
- `NETLIFY_SITE_ID`

### Web Build

Builds a Next.js or web application with optional linting and testing.

**Usage:**

```yaml
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

## Composite Actions

### Setup

Common setup action for repository checkout, Node.js, and pnpm installation.

**Usage:**

```yaml
- name: Setup
  uses: sisques-labs/workflows/.github/actions/setup@main
  with:
    node_version: "24"
    pnpm_version: "latest"
```

**Inputs:**

- `node_version` (optional, default: `"24"`): Node.js version to use
- `pnpm_version` (optional, default: `"latest"`): pnpm version to use

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
- `use_filter` (optional, default: `"false"`): Whether to use filter when installing (only install dependencies for app_path)
- `frozen_lockfile` (optional, default: `"true"`): Whether to use --frozen-lockfile (automatically skipped for dependabot)

### Prisma Generate

Generates Prisma master and tenant clients.

**Usage:**

```yaml
- name: Generate Prisma clients
  uses: sisques-labs/workflows/.github/actions/prisma-generate@main
  with:
    app_path: "apps/api"
```

**Inputs:**

- `app_path` (required): Path to the app/package (e.g., `apps/api`)

## Best Practices

1. **Always use `secrets: inherit`** when calling workflows that require secrets
2. **Use consistent Node.js versions** across your project (default is `24`)
3. **Enable cache** (`use_cache: "true"`) for faster builds in most cases
4. **Use install_filter** when you only need dependencies for a specific app/package
5. **Combine workflows** in your project's workflow files for complete CI/CD pipelines

## Example: Complete CI Pipeline

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality:
    uses: sisques-labs/workflows/.github/workflows/code-quality.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"

  test:
    uses: sisques-labs/workflows/.github/workflows/test.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"
      coverage: true

  build:
    needs: [quality, test]
    uses: sisques-labs/workflows/.github/workflows/build.yml@main
    with:
      app_path: "apps/admin"
      app_name: "Admin App"
      run_lint: false # Already run in quality job
      run_test: false # Already run in test job
```

## Migration from Old Workflows

If you were using `lint.yml`, it has been merged into `code-quality.yml`. Update your workflows:

**Before:**

```yaml
uses: sisques-labs/workflows/.github/workflows/lint.yml@main
```

**After:**

```yaml
uses: sisques-labs/workflows/.github/workflows/code-quality.yml@main
with:
  run_lint: true
  check_types: false
  run_sonarcloud: false
```
