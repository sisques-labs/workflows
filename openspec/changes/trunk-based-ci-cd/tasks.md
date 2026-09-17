## 1. `trunk-ci-cd.yml` reusable workflow

- [x] 1.1 Add `.github/workflows/trunk-ci-cd.yml` (`workflow_call`) with a `build-and-publish` job: lint, test, build, push `image:sha-<shortsha>` + floating `image:edge` — no version bump, no git tag
- [x] 1.2 Add `deploy-dev` job (`needs: build-and-publish`) with a placeholder deploy step (no real target yet) — verify it runs unconditionally after a successful build
- [x] 1.3 Add `deploy-pre` job (`needs: deploy-dev`) with a placeholder deploy step — gating is configured via the `pre` GitHub Environment's required reviewers (D5), not a workflow input — verify it never runs before `deploy-dev` succeeds

## 2. `docker-release.yml` promote mode

- [x] 2.1 Add `bump_mode: promote` as a new accepted value alongside `legacy`/`release-train` — verify existing modes' code paths are untouched
- [x] 2.2 When `bump_mode: promote`, accept the source image digest as an input and skip the existing build steps entirely
- [x] 2.3 Implement the promotion step with `docker buildx imagetools create` retagging the digest to the computed release tag(s) + `:latest`
- [x] 2.4 Verify multi-arch manifest lists (`linux/amd64,linux/arm64`) survive the promotion intact, not just a single-platform digest — this is the flagged risk in `design.md` D2. **Confirmed live**: user ran the full release flow on beacon-api end-to-end successfully.
- [x] 2.5 Confirm changelog (git-cliff) and GitHub Release creation steps run unchanged for `promote` mode when `release_type: stable`. **Confirmed live** as part of the same beacon-api run.

## 3. Documentation

- [x] 3.1 Document the new `trunk-ci-cd.yml` inputs/outputs and the `promote` bump mode in this repo's README, alongside the existing `release-train.yml`/`docker-release.yml` docs
- [x] 3.2 Note in the README that `trunk-ci-cd.yml` is opt-in per repo and does not affect existing `release-train.yml` consumers

## 4. Verification

- [x] 4.1 Dry-run `trunk-ci-cd.yml` against a disposable test repo/branch to confirm the `build-and-publish` → `deploy-dev` → `deploy-pre` ordering holds. **Confirmed** — beacon-api PR #23 ran successfully end-to-end.
- [x] 4.2 Dry-run `docker-release.yml` with `bump_mode: promote` against a real multi-arch image and confirm the promoted tag pulls correctly on both architectures. **Confirmed** — full release flow validated live on beacon-api.
- [x] 4.3 Confirm no existing repo's `release-train.yml`-based pipeline changed behavior after this PR merges — `release-train-detect.test.sh` still 36/36 after every change to `docker-release.yml`; `release-train.yml` itself untouched

## 5. `promote` mode zero-input fix (D8)

- [x] 5.1 Separate `bump_mode: promote`'s version step from `legacy`'s — `promote` no longer runs the manual `npm version ${{ inputs.version }}` path
- [x] 5.2 Compute the version bump for `promote` automatically from conventional commits since the latest stable tag (mirrors `release-train-detect`'s `main`-channel logic)
- [x] 5.3 Make `source_digest` optional for `promote`: auto-resolve the current `:edge` tag's digest via `docker buildx imagetools inspect` when not passed explicitly
- [x] 5.4 Dry-run a real `promote` release with zero inputs and confirm the resolved version + digest are correct. **Confirmed** as part of the same beacon-api validation.

## 6. Ephemeral tag retention (D9)

- [x] 6.1 Add `.github/actions/image-tag-cleanup/select-deletions.sh` — pure, offline decision logic (which tags/versions are safe to delete) with no registry calls
- [x] 6.2 Add `tests/image-tag-cleanup-select.test.sh` covering: empty input, a non-ephemeral tag is never selected, a mixed-tag entry is never selected, an untagged entry is never selected, `keep_min` is respected regardless of age, entries beyond `keep_min` are selected once older than `retention_days`, a custom `ephemeral_tag_prefix` only matches its own tags, GHCR-shaped (numeric id) input works the same way — 9/9 passing
- [x] 6.3 Add `cleanup-dockerhub.sh` (lists tags via the Docker Hub API, deletes selected ones) and `cleanup-ghcr.sh` (lists package versions via the GitHub API, deletes selected ones) — both delegate the decision to 6.1, never decide themselves
- [x] 6.4 Add composite action `.github/actions/image-tag-cleanup/action.yml` wrapping both registry scripts behind a `registry: dockerhub | ghcr` input
- [x] 6.5 Add reusable workflow `.github/workflows/image-cleanup.yml` (`workflow_call`, no `on:` trigger of its own — the consumer owns the schedule) calling the composite action once per enabled registry
- [x] 6.6 Add `image-tag-cleanup-select` job to this repo's own `test.yml` and confirm `shellcheck`/`actionlint` are clean on every new file
- [x] 6.7 Document `image-cleanup.yml` usage, the never-touches-official-tags guarantee, and the `DOCKERHUB_TOKEN` Read/Write/Delete scope requirement in the README
- [ ] 6.8 Wire `image-cleanup.yml` into beacon-api (the pilot repo) with a real `on: schedule` trigger, run once with `dry_run: true`, confirm the logged output looks correct before trusting it unattended

## 7. Continuous-build vulnerability scanning (D10, regression fix)

- [x] 7.1 Add `scan_image` input to `trunk-ci-cd.yml` (default `false`, matching `docker-release.yml`'s own convention)
- [x] 7.2 Add the Trivy scan step scanning the just-pushed `:sha-<shortsha>` tag by registry reference (no separate local build needed, unlike `docker-release.yml`'s PR/legacy-mode scan)
- [x] 7.3 Add `security-events: write` to `trunk-ci-cd.yml`'s top-level permissions (same unconditional-declaration trap as D8/beacon-api's `release.yml`)
- [x] 7.4 Update README's `trunk-ci-cd.yml` usage example with `scan_image: true` and the matching permissions blocks
- [ ] 7.5 Confirm live: enable `scan_image: true` on a real repo's `trunk-ci-cd.yml` consumer and verify the SARIF report lands in Security > Code scanning
