# Reusable GitHub Workflows

This repository contains reusable GitHub Actions workflows and composite actions that can be used across multiple projects to centralize CI/CD logic.

## Structure

```
.github/
├── workflows/          # Reusable workflows
│   └── web-build.yml   # Web application build workflow
└── actions/            # Composite actions
    ├── setup/          # Common setup (Node.js, pnpm, checkout)
    └── install/        # Install dependencies with pnpm
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

## Contributing

This is a centralized repository for reusable workflows. When adding new workflows or actions:

1. Follow the existing structure and naming conventions
2. Use the composite actions (`setup` and `install`) when possible
3. Document all inputs and their defaults
4. Update this README with usage examples
