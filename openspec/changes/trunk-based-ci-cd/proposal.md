## Why

Every consuming repo releases through `release-train.yml`, which maps git branch to release channel (`develop` → alpha, `staging` → beta, `main` → stable) via `release-train-detect/detect.sh`. This couples the org's git topology to its release topology. Today no consuming repo has real environments provisioned, so `develop`/`staging` gate a version channel but not an actual deployment — the three-branch model carries the cost of environment branches (merge overhead, drift risk between branches) without their benefit.

Standardizing on a single long-lived `main` branch (trunk-based development) lets environment promotion be driven by the CI/CD pipeline instead of by branch merges: one artifact is built per merge to `main` and the *same* artifact is promoted through `dev` → `pre` → `prod`, rather than being rebuilt per branch. This removes an entire class of "works in staging, different bytes in prod" risk.

## What Changes

- Add a new reusable workflow `trunk-ci-cd.yml`: triggered by a consumer's `push: [main]`, it builds and publishes an immutable, commit-addressed image (`image:sha-<shortsha>` + floating `image:edge`) with no version bump, then runs `deploy-dev` followed by `deploy-pre` (`needs: deploy-dev`).
- Add a new `bump_mode: promote` to the existing `docker-release.yml` reusable workflow. When set, the release job skips the build step entirely and promotes an already-published image by digest (`docker buildx imagetools create`) to the release tag(s) instead of rebuilding from source — guaranteeing the exact bytes validated in `pre` are what ships to `prod`.
- Both changes are strictly additive: `release-train.yml`, `release-train-detect/detect.sh`, and the existing `legacy`/`release-train` bump modes in `docker-release.yml` are untouched. No consuming repo is affected until it edits its own workflow file to reference `trunk-ci-cd.yml` and pass `bump_mode: promote`.
- **Out of scope for this change**: implementing real deploy steps for `dev`/`pre`/`prod` (no consuming repo has provisioned environments yet — the jobs are defined as the pipeline's shape with a placeholder deploy step); migrating any specific repo (beacon-api will pilot this in its own repo as a follow-up change); deprecating `release-train.yml` for repos that don't migrate (a later decision, once the pilot is validated).

## Capabilities

### New Capabilities

- `trunk-based-ci-cd`: A continuous integration/delivery pipeline that builds an artifact once per merge to `main` and promotes that same artifact through `dev` → `pre` → `prod`, decoupling release/environment topology from git branch topology.

### Modified Capabilities

- `docker-release`: gains a `promote` bump mode that retags an existing image by digest instead of rebuilding, for use when cutting a `prod` release from an already-validated artifact.

## Impact

- **Code**: new file `.github/workflows/trunk-ci-cd.yml`; additive changes to `.github/workflows/docker-release.yml` (new `bump_mode` branch, no existing code path touched). No other file is modified.
- **Consumers**: zero impact on existing repos using `release-train.yml` — nothing here is wired into any consumer's workflow yet.
- **Environments**: `dev`/`pre`/`prod` GitHub Environments are configured per-repo (not part of this shared-workflows change) when a repo migrates and provisions real infrastructure.
- **Rollback**: revert this PR; nothing references the new workflow or bump mode until a consumer opts in.
