#!/usr/bin/env bash
set -euo pipefail

# Tests for .github/actions/npm-dual-publish (lib.sh + static guards over
# publish.sh and action.yml). Threat-matrix cases from
# openspec/changes/trunk-based-npm-packages/design.md map to the test cases
# below. Run locally or in CI:
#   bash tests/npm-dual-publish.test.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_DIR="${REPO_ROOT}/.github/actions/npm-dual-publish"
LIB="${ACTION_DIR}/lib.sh"
PUBLISH="${ACTION_DIR}/publish.sh"
PREPARE="${ACTION_DIR}/prepare.sh"
ACTION="${ACTION_DIR}/action.yml"

# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
CURRENT_TEST=""

assert_eq() { # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [${CURRENT_TEST}] $1: expected '$2', got '$3'"
  fi
}

assert_ok() { # $1 = description, rest = command expected to succeed
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [${CURRENT_TEST}] ${desc}: expected success"; fi
}

assert_fails() { # $1 = description, rest = command expected to fail
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then FAIL=$((FAIL + 1)); echo "FAIL [${CURRENT_TEST}] ${desc}: expected failure"; else PASS=$((PASS + 1)); fi
}

# Static guard: pattern must (not) appear in a file.
assert_contains() { # $1 = description, $2 = file, $3 = fixed string
  if grep -qF -- "$3" "$2"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [${CURRENT_TEST}] $1: '$3' not found in $(basename "$2")"; fi
}
assert_absent() { # $1 = description, $2 = file, $3 = extended regex
  if grep -qE -- "$3" "$2"; then FAIL=$((FAIL + 1)); echo "FAIL [${CURRENT_TEST}] $1: '$3' found in $(basename "$2")"; else PASS=$((PASS + 1)); fi
}

test_case() { CURRENT_TEST="$1"; echo "--- $1"; }

# --- Threat matrix: git repository selection -------------------------------
test_case "resolve_app_path rejects absolute and traversal paths"
assert_fails "absolute /etc" resolve_app_path "/etc"
assert_fails "parent ../x" resolve_app_path "../x"
assert_fails "embedded packages/../.." resolve_app_path "packages/../.."
assert_fails "empty path" resolve_app_path ""

test_case "resolve_app_path accepts repo-relative paths"
assert_eq "dot" "." "$(resolve_app_path ".")"
assert_eq "packages/lib" "packages/lib" "$(resolve_app_path "packages/lib")"
assert_eq "dotted name is not traversal" "packages/a..b" "$(resolve_app_path "packages/a..b")"

# --- W3: app_path guard runs before setup/install --------------------------
WORKFLOW="${REPO_ROOT}/.github/workflows/trunk-npm-publish.yml"
# Prints the run script of the Nth "Validate app_path" step (1 = validate job).
guard_script() {
  awk -v n="$1" '/- name: Validate app_path/ {c++} c==n && /run: \|/ {f=1; next}
    f && /^$/ {exit} f {sub(/^          /, ""); print}' "$WORKFLOW"
}

test_case "app_path guard is the first step of validate and publish"
for job in validate publish; do
  first_step="$(awk -v j="  ${job}:" '$0==j {i=1} i && /^      - name:/ {print; exit}' "$WORKFLOW")"
  assert_eq "${job}: first step" "      - name: Validate app_path" "$first_step"
done
assert_eq "guard step count" "2" "$(grep -Ec '^      - name: Validate app_path' "$WORKFLOW")"
assert_eq "both guards identical" "$(guard_script 1)" "$(guard_script 2)"
assert_absent "app_path never inlined in a run: script" "$WORKFLOW" 'run:.*\$\{\{ *inputs\.app_path'
assert_eq "guard reads APP_PATH from env" "2" "$(grep -Ec '^          APP_PATH: \$\{\{ inputs\.app_path \}\}$' "$WORKFLOW")"

test_case "command inputs are env-passed script names, skippable when empty"
for k in typecheck test build; do
  assert_contains "${k}_command declared" "$WORKFLOW" "      ${k}_command:"
  assert_eq "${k}_command default" "1" "$(awk -v k="      ${k}_command:" '$0==k {i=1} i && /default:/ {print (index($0, "\"" "'${k}'" "\"")>0); exit}' "$WORKFLOW")"
  assert_eq "${k}: skip-when-empty in both jobs" "2" "$(grep -Ec "^        if: \\$\\{\\{ inputs\\.${k}_command != '' \\}\\}$" "$WORKFLOW")"
  assert_eq "${k}: env-passed in both jobs" "2" "$(grep -Ec "^          SCRIPT: \\$\\{\\{ inputs\\.${k}_command \\}\\}$" "$WORKFLOW")"
done
# shellcheck disable=SC2016 # literal $SCRIPT is the pattern, not an expansion
assert_eq "pnpm run quoted in 6 steps" "6" "$(grep -Ec '^        run: pnpm run "\$SCRIPT"$' "$WORKFLOW")"
assert_absent "no hardcoded pnpm typecheck/test/build" "$WORKFLOW" 'run: pnpm (typecheck|test|build)$'
assert_absent "commands never inlined in run:" "$WORKFLOW" 'run:.*\$\{\{ *inputs\.(typecheck|test|build)_command'

test_case "app_path guard rejects the same paths as resolve_app_path"
GUARD="$(guard_script 1)"
for p in "" "/etc" "../x" "packages/../.." "." "packages/lib" "packages/a..b"; do
  guard_rc=0
  APP_PATH="$p" bash -c "$GUARD" >/dev/null 2>&1 || guard_rc=$?
  lib_rc=0
  resolve_app_path "$p" >/dev/null 2>&1 || lib_rc=$?
  assert_eq "guard parity for '${p}'" "$lib_rc" "$guard_rc"
done

# --- Threat matrix: commit state -------------------------------------------
test_case "no commit-back to main unless commit_release_files"
# The git plugin may only be added inside the commit_release_files branch.
assert_eq "git plugin listed once (opt-in branch only)" "1" "$(grep -Ec '^          plugins\+=\(.*@semantic-release/git( |\))' "$ACTION")"
assert_contains "default list has no git plugin" "$ACTION" '          plugins+=(@semantic-release/exec @semantic-release/github)'
assert_absent "plugins never listed inline on the CLI" "$ACTION" '^ *--plugins .*@semantic-release/'
assert_absent "no git commit in publish.sh" "$PUBLISH" 'git[[:space:]]+(commit|add)'
assert_absent "no git commit in prepare.sh" "$PREPARE" 'git[[:space:]]+(commit|add|push)'
assert_absent "no git commit in action.yml" "$ACTION" 'git[[:space:]]+(commit|add)'
assert_contains "commit-back is opt-in, default false" "$ACTION" '    default: "false"'
assert_contains "commit message skips CI" "$ACTION" '[skip ci]'
assert_absent "assets never set (would leak to GitHub plugin)" "$ACTION" '^ *--assets'

test_case "commit-back plugin order: changelog, exec (prepare), git, github"
assert_contains "order" "$ACTION" 'plugins+=(@semantic-release/changelog @semantic-release/exec @semantic-release/git @semantic-release/github)'

test_case "release_token only feeds semantic-release, never GitHub Packages"
# shellcheck disable=SC2016 # literal ${{ }} expression is the pattern
assert_contains "GHP token stays github_token" "$ACTION" 'GHP_TOKEN: ${{ inputs.github_token }}'
assert_contains "publish.sh reads GHP_TOKEN" "$PUBLISH" 'GHP_TOKEN'

test_case "require_root_app_path_for_commit"
assert_ok "commit off, subdir" require_root_app_path_for_commit "packages/lib" "false"
assert_ok "commit on, root" require_root_app_path_for_commit "." "true"
assert_fails "commit on, subdir" require_root_app_path_for_commit "packages/lib" "true"

test_case "bump_manifest_version preserves formatting"
TMP_DIR="$(mktemp -d)"
printf '{\n  "name": "@x/y",\n  "version": "0.0.0",\n  "files": ["dist"],\n  "engines": {\n    "version": "1"\n  }\n}\n' >"${TMP_DIR}/a.json"
bump_manifest_version "${TMP_DIR}/a.json" "1.2.3"
assert_eq "2-space: top-level version only" '{
  "name": "@x/y",
  "version": "1.2.3",
  "files": ["dist"],
  "engines": {
    "version": "1"
  }
}' "$(cat "${TMP_DIR}/a.json")"
printf '{\n\t"version": "0.0.0",\n\t"dependencies": {\n\t\t"version": "9"\n\t}\n}\n' >"${TMP_DIR}/b.json"
bump_manifest_version "${TMP_DIR}/b.json" "0.4.0"
assert_eq "tab-indented, nested version untouched" "0.4.0/9" "$(jq -r '.version + "/" + .dependencies.version' "${TMP_DIR}/b.json")"
assert_contains "tab indent kept" "${TMP_DIR}/b.json" $'\t"version": "0.4.0"'
printf '{"name":"x","version":"0.0.0"}' >"${TMP_DIR}/c.json"
bump_manifest_version "${TMP_DIR}/c.json" "2.0.0"
assert_eq "compact JSON falls back to jq" "2.0.0" "$(jq -r .version "${TMP_DIR}/c.json")"
printf '{\n  "version": "1.0.0", "x": 1\n}\n' >"${TMP_DIR}/d.json"
bump_manifest_version "${TMP_DIR}/d.json" "1.0.1"
assert_eq "suffix after version kept" "1.0.1/1" "$(jq -r '.version + "/" + (.x|tostring)' "${TMP_DIR}/d.json")"
assert_fails "prerelease rejected" bump_manifest_version "${TMP_DIR}/a.json" "1.0.0-edge.1"
# shellcheck disable=SC2016 # literal metacharacters are the point
assert_fails "metachar version rejected" bump_manifest_version "${TMP_DIR}/a.json" '1.0.0"$(touch /tmp/x)'
assert_fails "missing file" bump_manifest_version "${TMP_DIR}/nope.json" "1.0.0"
assert_eq "no tmp left behind" "" "$(fd -H 'tmp$' "$TMP_DIR" 2>/dev/null || true)"
rm -rf "$TMP_DIR"

# --- Threat matrix: push state ---------------------------------------------
test_case "tag push only, branch pinned to main"
assert_absent "no git push origin <branch>" "$PUBLISH" 'git[[:space:]]+push'
assert_absent "no git push origin <branch> in action" "$ACTION" 'git[[:space:]]+push'
assert_contains "branches pinned" "$ACTION" '--branches main'

# --- Threat matrix: PR commands --------------------------------------------
test_case "comments disabled and no eval"
assert_contains "successComment disabled" "$ACTION" '--no-success-comment'
assert_contains "failComment disabled" "$ACTION" '--no-fail-comment'
assert_absent "no eval in publish.sh" "$PUBLISH" '(^|[^a-zA-Z_])eval[[:space:]]'
assert_absent "no eval in action.yml" "$ACTION" '(^|[^a-zA-Z_])eval[[:space:]]'

test_case "classify_publish_failure survives shell metacharacters"
touch "${TMPDIR:-/tmp}/npm-dual-publish-pwned-marker.$$" && rm -f "${TMPDIR:-/tmp}/npm-dual-publish-pwned-marker.$$"
# shellcheck disable=SC2016 # literal metacharacters are the point
NASTY='1.0.0$(touch /tmp/npm-dual-publish-pwned); `id` ; rm -rf / EPUBLISHCONFLICT'
assert_eq "metachar conflict" "conflict" "$(classify_publish_failure "$NASTY")"
# shellcheck disable=SC2016
assert_eq "metachar non-conflict" "failure" "$(classify_publish_failure '$(touch /tmp/npm-dual-publish-pwned); `id`')"
assert_fails "command substitution never executed" test -e /tmp/npm-dual-publish-pwned

# --- Pure functions --------------------------------------------------------
test_case "validate_scope"
assert_ok "own scope" validate_scope "@sisques-labs/pkg" "sisques-labs"
assert_ok "own scope, case-insensitive" validate_scope "@Sisques-Labs/pkg" "sisques-labs"
assert_fails "foreign scope" validate_scope "@other/pkg" "sisques-labs"
assert_fails "unscoped" validate_scope "pkg" "sisques-labs"
assert_fails "empty name" validate_scope "" "sisques-labs"

test_case "next_edge_version is next patch plus edge.<run>"
assert_eq "1.2.0" "1.2.1-edge.42" "$(next_edge_version "1.2.0" 42)"
assert_eq "0.0.9" "0.0.10-edge.1" "$(next_edge_version "0.0.9" 1)"
assert_eq "1.0.0" "1.0.1-edge.7" "$(next_edge_version "1.0.0" 7)"
assert_fails "prerelease input rejected" next_edge_version "1.2.0-beta.1" 3
assert_fails "garbage rejected" next_edge_version "nope" 3
assert_fails "non-numeric run rejected" next_edge_version "1.2.0" "x"

test_case "classify_publish_failure"
assert_eq "EPUBLISHCONFLICT" "conflict" "$(classify_publish_failure "npm error code EPUBLISHCONFLICT")"
assert_eq "cannot publish over" "conflict" "$(classify_publish_failure "You cannot publish over the previously published versions: 1.0.0.")"
assert_eq "auth failure" "failure" "$(classify_publish_failure "npm error code E401")"
assert_eq "empty output" "failure" "$(classify_publish_failure "")"

echo
echo "Passed: ${PASS}  Failed: ${FAIL}"
[ "$FAIL" -eq 0 ]
