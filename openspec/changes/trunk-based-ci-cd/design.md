## Context

See `proposal.md` for motivation. Today's model, implemented in `release-train.yml` + `.github/actions/release-train-detect/detect.sh`, treats git tags as the single source of truth for versioning and hardcodes a branch → channel mapping (`develop`→alpha, `staging`→beta, `main`→stable). `docker-release.yml` (called both by `release-train.yml` and by the manual `release.yml` in `legacy` mode) always rebuilds the image from source at release time — there is no existing mechanism to promote an already-built artifact.

No consuming repo has real deploy infrastructure yet, so this design defines the pipeline's shape and the exact point where real deploys will plug in, without implementing those deploys.

## Goals / Non-Goals

**Goals:**

- Decouple git branch topology (single `main`) from release/environment topology (`dev` → `pre` → `prod`).
- Guarantee "build once, promote the same artifact" for the path from `pre` to `prod`.
- Ship this as a purely additive change to `sisques-labs/workflows` so no existing consumer breaks or needs to act.
- Define where real deploy steps will plug in later, without requiring that infra to exist now.

**Non-Goals:**

- Implementing actual deployment logic to real dev/pre/prod infrastructure (no consuming repo has environments provisioned).
- Migrating any specific consuming repo — beacon-api will pilot this as a separate change in its own repository.
- Deprecating or modifying `release-train.yml` for repos that keep using it — that is a later, separate decision once the pilot is validated.
- Auditing which repos have consumers pinned to `:alpha`/`:beta` image tags — required before any given repo migrates, but tracked per-repo, not here.

## Decisions

### D1 — Two-phase versioning: continuous (unversioned) vs. release (versioned)

Every merge to `main` builds and publishes `image:sha-<shortsha>` (+ floating `image:edge`). No `npm version` bump, no git tag, no GitHub Release happens on merge. `package.json` is untouched until a release is explicitly cut.

**Alternatives considered:** computing a semver pre-release (`X.Y.Z-rc.N`) on every merge, mirroring today's alpha/beta channels — rejected because it produces version churn nobody consumes once there is only one branch, and it reintroduces the "which pre-release tag is actually deployed" ambiguity this change is meant to remove.

### D2 — `prod` releases promote an existing image by digest, never rebuild

`docker-release.yml` gains `bump_mode: promote`, which takes the digest of the already-built `sha-*` image (the one validated in `pre`) and runs `docker buildx imagetools create --tag <image>:X.Y.Z --tag <image>:latest <image>@sha256:<digest>`. The existing `legacy` and `release-train` modes (which build-then-push) are untouched — `promote` is a new branch in the existing mode dispatch, not a rewrite.

**Risk to validate during implementation:** `imagetools create` must correctly copy the full multi-arch manifest list (the repo builds `linux/amd64,linux/arm64`), not just a single-platform digest — confirm this before relying on it for a real release.

### D3 — Job graph: `build` → `deploy-dev` → `deploy-pre`, sequential

New reusable workflow `trunk-ci-cd.yml` (`workflow_call`), consumed via a repo's own `push: [main]` trigger:

```
build-and-publish (lint, test, build, push sha-*/edge tags)
        │
        ▼
   deploy-dev   (needs: build-and-publish; no gate)
        │
        ▼
   deploy-pre   (needs: deploy-dev; gate optional per consumer input)
```

`prod` is deliberately **not** a job in this workflow — it is only reachable via the manual `release.yml` dispatch (D2), which promotes the artifact that has already gone through `dev` and `pre`.

**Alternatives considered:** deploying `dev` and `pre` in parallel from `build` — rejected per the org's explicit decision to keep DEV as an early-feedback gate before promoting to the QA-facing `pre` environment.

### D4 — `deploy-dev`/`deploy-pre` ship as placeholders

Since no consuming repo has dev/pre/prod infrastructure yet, both jobs are defined with a placeholder step (log-only) in this iteration. The job graph, `needs:` ordering, and environment names are the real deliverable; wiring an actual deploy target is follow-up work once a repo provisions real infrastructure.

### D5 — Environments are configured per-repo, not in this shared repo

`dev`/`pre`/`prod` GitHub Environments (and any required-reviewer gates on them) are Settings-level config owned by each consuming repo. `sisques-labs/workflows` only defines the job names/order that reference environment names by convention.

### D6 — Rollout is additive and opt-in per repo

No file this change touches is edited in place for its existing behavior: `trunk-ci-cd.yml` is a new file nothing currently references, and `docker-release.yml`'s new `bump_mode: promote` branch is unreachable unless a caller explicitly passes it. A repo migrates by changing its *own* workflow files to reference the new pieces — `sisques-labs/workflows` never forces a migration.

### D7 — Changelog/release generation is reused, simplified

`docker-release.yml`'s existing git-cliff + GitHub Release steps apply unchanged when `release_type: stable`. Because there is only one channel once a repo migrates, the alpha/beta/rc tag-ignoring logic in the changelog range computation becomes dead code for that repo's future releases but is not removed here (other repos still exercise it via `legacy`/`release-train` modes).

## Risks / Trade-offs

- **[Risk] Multi-arch digest promotion is unproven** → Validate `imagetools create` against a real multi-platform image before beacon-api's pilot relies on it for an actual prod release.
- **[Risk] Downstream consumers pinned to `:alpha`/`:beta` tags** → Each repo must audit this before migrating; out of scope for this shared-workflow change.
- **[Trade-off] `deploy-dev`/`deploy-pre` are placeholders** → The pipeline shape ships now; real deploy logic is deferred until a repo has infrastructure to target.
- **[Trade-off] Org-wide standardization without a forced cutover** → Slower convergence (repos migrate on their own schedule) in exchange for zero blast radius on this change.

## Migration Plan

1. Merge this proposal/design into `sisques-labs/workflows` as documentation — no consumer is affected by merging it.
2. Implement `trunk-ci-cd.yml` and `docker-release.yml`'s `promote` mode per `tasks.md`.
3. Beacon-api pilots the migration in its own repository/change: drop `release-train.yml`, adopt `trunk-ci-cd.yml`, switch `release.yml` to `bump_mode: promote`.
4. Validate the pilot (including the multi-arch promotion risk in D2) before any other repo migrates.
5. Other repos opt in individually, on their own schedule.
6. Deprecating `release-train.yml` org-wide is a separate future decision, made only after enough repos have migrated.

## Open Questions

- Should `deploy-pre` carry a mandatory approval gate by default, or is that left to each repo's own GitHub Environment configuration?
- What is the audit process for repos with external consumers pinned to `:alpha`/`:beta` image tags before they migrate?
