## 1. `trunk-ci-cd.yml` reusable workflow

- [x] 1.1 Add `.github/workflows/trunk-ci-cd.yml` (`workflow_call`) with a `build-and-publish` job: lint, test, build, push `image:sha-<shortsha>` + floating `image:edge` — no version bump, no git tag
- [x] 1.2 Add `deploy-dev` job (`needs: build-and-publish`) with a placeholder deploy step (no real target yet) — verify it runs unconditionally after a successful build
- [x] 1.3 Add `deploy-pre` job (`needs: deploy-dev`) with a placeholder deploy step — gating is configured via the `pre` GitHub Environment's required reviewers (D5), not a workflow input — verify it never runs before `deploy-dev` succeeds

## 2. `docker-release.yml` promote mode

- [x] 2.1 Add `bump_mode: promote` as a new accepted value alongside `legacy`/`release-train` — verify existing modes' code paths are untouched
- [x] 2.2 When `bump_mode: promote`, accept the source image digest as an input and skip the existing build steps entirely
- [x] 2.3 Implement the promotion step with `docker buildx imagetools create` retagging the digest to the computed release tag(s) + `:latest`
- [ ] 2.4 Verify multi-arch manifest lists (`linux/amd64,linux/arm64`) survive the promotion intact, not just a single-platform digest — this is the flagged risk in `design.md` D2. **Not yet run** — needs a real dry-run (see 4.2).
- [ ] 2.5 Confirm changelog (git-cliff) and GitHub Release creation steps run unchanged for `promote` mode when `release_type: stable`. Statically verified (no `bump_mode` condition gates those steps) but **not yet run live** — needs a real dry-run.

## 3. Documentation

- [x] 3.1 Document the new `trunk-ci-cd.yml` inputs/outputs and the `promote` bump mode in this repo's README, alongside the existing `release-train.yml`/`docker-release.yml` docs
- [x] 3.2 Note in the README that `trunk-ci-cd.yml` is opt-in per repo and does not affect existing `release-train.yml` consumers

## 4. Verification

- [ ] 4.1 Dry-run `trunk-ci-cd.yml` against a disposable test repo/branch to confirm the `build-and-publish` → `deploy-dev` → `deploy-pre` ordering holds
- [ ] 4.2 Dry-run `docker-release.yml` with `bump_mode: promote` against a real multi-arch image and confirm the promoted tag pulls correctly on both architectures
- [ ] 4.3 Confirm no existing repo's `release-train.yml`-based pipeline changed behavior after this PR merges
