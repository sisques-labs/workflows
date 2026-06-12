#!/usr/bin/env bash
set -euo pipefail

# Tests for .github/actions/release-train-detect/detect.sh
#
# Each scenario builds a throwaway git repository with a tag layout and
# asserts the computed next version. Run locally or in CI:
#   bash tests/release-train-detect.test.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${REPO_ROOT}/.github/actions/release-train-detect/detect.sh"

PASS=0
FAIL=0
CURRENT_TEST=""
WORKDIR=""

cleanup() {
  if [ -n "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi
}
trap cleanup EXIT

new_repo() {
  cleanup
  WORKDIR=$(mktemp -d)
  cd "$WORKDIR"
  git init -q -b main
  git config user.email "test@test"
  git config user.name "test"
  git config commit.gpgsign false
  git config tag.gpgsign false
  git config gpg.format openpgp
  commit "chore: initial commit"
}

commit() {
  echo "$RANDOM" >> file.txt
  git add file.txt
  git commit -qm "$1"
}

tag() { git tag "$1"; }

run_detect() { # $1 = branch
  OUTPUT_FILE=$(mktemp)
  DETECT_EXIT=0
  GITHUB_OUTPUT="$OUTPUT_FILE" bash "$DETECT" "$1" >/dev/null 2>&1 || DETECT_EXIT=$?
}

out() { grep "^$1=" "$OUTPUT_FILE" | head -1 | cut -d= -f2- || true; }

assert_eq() { # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [${CURRENT_TEST}] $1: expected '$2', got '$3'"
  fi
}

test_case() { CURRENT_TEST="$1"; echo "--- $1"; }

# ---------------------------------------------------------------------------
test_case "first ever release on develop opens 0.1.0-alpha.0"
new_repo
commit "feat: first feature"
run_detect develop
assert_eq "should_release" "true" "$(out should_release)"
assert_eq "strategy" "open-cycle" "$(out bump_strategy)"
assert_eq "next_version" "0.1.0-alpha.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "develop continues an open alpha cycle"
new_repo
tag "v0.15.1"
commit "feat: start cycle"
tag "v0.15.2-alpha.0"
commit "fix: more work"
run_detect develop
assert_eq "strategy" "prerelease-alpha" "$(out bump_strategy)"
assert_eq "next_version" "0.15.2-alpha.1" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "REGRESSION: staging abandons stale beta of an already-stable base and promotes the live alpha cycle"
# Exact production state that broke: v0.15.1 shipped stable on main while
# staging kept iterating v0.15.1-beta.N and develop was on v0.15.2-alpha.N.
new_repo
tag "v0.15.0-alpha.9"
tag "v0.15.1-beta.3"
tag "v0.15.1"
commit "feat: alpha cycle work"
tag "v0.15.2-alpha.3"
commit "Merge develop into staging"
run_detect staging
assert_eq "should_release" "true" "$(out should_release)"
assert_eq "strategy" "promote-beta" "$(out bump_strategy)"
assert_eq "next_version" "0.15.2-beta.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "staging iterates the current beta cycle when it still leads"
new_repo
tag "v0.15.1"
tag "v0.16.0-alpha.2"
commit "fix: promoted work"
tag "v0.16.0-beta.0"
commit "fix: staging hotfix"
run_detect staging
assert_eq "strategy" "prerelease-beta" "$(out bump_strategy)"
assert_eq "next_version" "0.16.0-beta.1" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "staging promotes a newer alpha cycle over an older live beta"
new_repo
tag "v0.15.1"
tag "v0.16.0-beta.1"
commit "feat: new cycle"
tag "v0.17.0-alpha.4"
commit "Merge develop into staging"
run_detect staging
assert_eq "strategy" "promote-beta" "$(out bump_strategy)"
assert_eq "next_version" "0.17.0-beta.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "staging hotfix with nothing ahead of stable opens a fresh beta cycle"
new_repo
tag "v0.15.1"
tag "v0.15.1-beta.3"
commit "fix: urgent staging hotfix"
run_detect staging
assert_eq "strategy" "open-cycle-beta" "$(out bump_strategy)"
assert_eq "next_version" "0.15.2-beta.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "main graduates the leading beta cycle"
new_repo
tag "v0.15.1"
commit "feat: cycle work"
tag "v0.16.0-beta.2"
commit "Merge staging into main"
run_detect main
assert_eq "strategy" "graduate" "$(out bump_strategy)"
assert_eq "next_version" "0.16.0" "$(out next_version)"
assert_eq "release_type" "stable" "$(out release_type)"

# ---------------------------------------------------------------------------
test_case "main never re-releases an already-graduated beta base"
new_repo
tag "v0.15.1-beta.3"
tag "v0.15.1"
commit "fix: hotfix straight to main"
run_detect main
assert_eq "strategy" "hotfix-stable" "$(out bump_strategy)"
assert_eq "next_version" "0.15.2" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "main graduates an alpha cycle when develop merged straight to main"
new_repo
tag "v0.15.1"
commit "feat: fast-tracked work"
tag "v0.16.0-alpha.1"
commit "Merge develop into main"
run_detect main
assert_eq "strategy" "graduate" "$(out bump_strategy)"
assert_eq "next_version" "0.16.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "develop opens a new cycle after its previous cycle graduated (feat -> minor)"
new_repo
tag "v0.15.2-alpha.3"
tag "v0.15.2"
commit "feat: new work after release"
run_detect develop
assert_eq "strategy" "open-cycle" "$(out bump_strategy)"
assert_eq "next_version" "0.16.0-alpha.0" "$(out next_version)"
assert_eq "version_bump" "minor" "$(out version_bump)"

# ---------------------------------------------------------------------------
test_case "develop opens a new cycle with fix-only commits (patch)"
new_repo
tag "v0.15.2-alpha.3"
tag "v0.15.2"
commit "fix: small fix after release"
run_detect develop
assert_eq "next_version" "0.15.3-alpha.0" "$(out next_version)"
assert_eq "version_bump" "patch" "$(out version_bump)"

# ---------------------------------------------------------------------------
test_case "develop opens a major cycle on breaking change"
new_repo
tag "v0.15.2"
commit "feat!: breaking api change"
run_detect develop
assert_eq "next_version" "1.0.0-alpha.0" "$(out next_version)"
assert_eq "version_bump" "major" "$(out version_bump)"

# ---------------------------------------------------------------------------
test_case "develop stays ahead of a beta cycle opened independently on staging"
new_repo
tag "v0.15.1"
tag "v0.15.2-beta.0"
commit "fix: develop work"
run_detect develop
assert_eq "strategy" "open-cycle" "$(out bump_strategy)"
assert_eq "next_version" "0.15.3-alpha.0" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "no release when HEAD is already tagged for the channel"
new_repo
commit "feat: work"
tag "v0.16.0-alpha.0"
run_detect develop
assert_eq "should_release" "false" "$(out should_release)"
assert_eq "strategy" "skip" "$(out bump_strategy)"

# ---------------------------------------------------------------------------
test_case "no release on staging when HEAD is already tagged beta"
new_repo
commit "feat: work"
tag "v0.16.0-beta.1"
run_detect staging
assert_eq "should_release" "false" "$(out should_release)"

# ---------------------------------------------------------------------------
test_case "first ever stable release on main without any pre-release"
new_repo
commit "fix: tiny project"
run_detect main
assert_eq "should_release" "true" "$(out should_release)"
assert_eq "next_version" "0.0.1" "$(out next_version)"

# ---------------------------------------------------------------------------
test_case "unsupported branch fails"
new_repo
commit "feat: work"
run_detect feature/foo
assert_eq "exit code" "1" "$DETECT_EXIT"

# ---------------------------------------------------------------------------
echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
