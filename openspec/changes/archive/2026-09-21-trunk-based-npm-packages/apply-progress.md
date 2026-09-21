# Apply progress

PR 1 complete: tasks 1.1, 1.2 done (setup action inputs package_json_file, fetch_depth).

PR 2 complete: tasks 2.1, 2.2 done. Created `.github/workflows/trunk-npm-publish.yml` with the full
inputs/secrets/permissions/concurrency skeleton and the `validate` job (pull_request path).

Deviation: the `outputs:` block (published, version, edge_version) is deferred to task 3.9, because a
workflow_call output must reference an existing job and the publish job is out of this slice.

Verification: `actionlint .github/workflows/trunk-npm-publish.yml` -> exit 0, no findings.

PR 3 complete: tasks 3.1-3.11 done. RED tests (tests/npm-dual-publish.test.sh, 35 assertions) written first and
confirmed failing (lib.sh missing), then lib.sh, publish.sh, action.yml, `publish` job + `outputs:` block (deviation
from PR 2 resolved), and the test.yml job. Pins verified via `npm view`: npm@11.6.2, semantic-release@25.0.2,
@semantic-release/exec@7.1.0 all exist, defaults unchanged.
Verification: bash tests/npm-dual-publish.test.sh -> 35 passed, 0 failed; shellcheck on .github/actions/**/*.sh and
tests/*.sh -> clean; actionlint on trunk-npm-publish.yml and test.yml -> exit 0.
Size: ~460 authored lines (over 400 budget); size:exception recommended, cohesive unit (tests+action+job).
Unverified: real semantic-release run (CLI unknown-option pass-through of --publish-cmd, --no-success-comment); needs pilot.

Phase 4 pending.

## W3 fix
Inline "Validate app_path" step (env-passed, same rule as resolve_app_path) added as the first step of both `validate` and `publish` in trunk-npm-publish.yml; tests assert placement, env usage, identical guards and parity with lib.sh. Tests 48/48, shellcheck and actionlint clean.

## W4 fix
Added `typecheck_command`/`test_command`/`build_command` workflow_call inputs (pnpm script names, defaults typecheck/test/build, empty skips via step `if:`). Steps in both jobs pass the value via `env: SCRIPT` and run `pnpm run "$SCRIPT"`; no inline interpolation. Header comment and README inputs/requirements updated. Tests 63/63 (RED 14 failing first), shellcheck and actionlint clean.
