#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:?branch required}"
CURRENT=$(node -p "require('./package.json').version")

case "$BRANCH" in
  develop) CHANNEL="alpha" ;;
  staging) CHANNEL="beta" ;;
  main) CHANNEL="stable" ;;
  *)
    echo "::error::Unsupported release-train branch: ${BRANCH}"
    exit 1
    ;;
esac

find_last_channel_tag() {
  local current="$1"
  local channel="$2"

  if [[ "$channel" == "alpha" && "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-alpha\. ]]; then
    git describe --tags --abbrev=0 --match "v${BASH_REMATCH[1]}-alpha.*" 2>/dev/null || true
  elif [[ "$channel" == "beta" && "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\. ]]; then
    git describe --tags --abbrev=0 --match "v${BASH_REMATCH[1]}-beta.*" 2>/dev/null || true
  elif [[ "$channel" == "beta" && "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-alpha\. ]]; then
    git describe --tags --abbrev=0 --match "v${BASH_REMATCH[1]}-alpha.*" 2>/dev/null || true
  elif [[ "$channel" == "stable" && "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\. ]]; then
    git describe --tags --abbrev=0 --match "v${BASH_REMATCH[1]}-beta.*" 2>/dev/null || true
  elif [[ ! "$current" =~ - ]]; then
    if git rev-parse -q --verify "refs/tags/v${current}" >/dev/null 2>&1; then
      echo "v${current}"
    else
      git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
    fi
  else
    git describe --tags --abbrev=0 2>/dev/null || true
  fi
}

find_last_stable_tag() {
  git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
}

resolve_version_bump() {
  local since_tag="$1"
  if [ -z "$since_tag" ]; then
    echo "minor"
    return
  fi

  if git log "${since_tag}..HEAD" --pretty=%s | grep -qiE '^feat(\(.+\))?!?:'; then
    echo "minor"
  else
    echo "patch"
  fi
}

resolve_bump_strategy() {
  case "$BRANCH" in
    develop)
      if [[ "$CURRENT" =~ -alpha\. ]]; then
        echo "prerelease-alpha"
      elif [[ ! "$CURRENT" =~ - ]]; then
        echo "open-cycle"
      else
        echo "::error::Unexpected version ${CURRENT} on develop (expected stable or alpha pre-release)" >&2
        exit 1
      fi
      ;;
    staging)
      if [[ "$CURRENT" =~ -alpha\. ]]; then
        echo "promote-beta"
      elif [[ "$CURRENT" =~ -beta\. ]]; then
        echo "prerelease-beta"
      else
        echo "::error::Unexpected version ${CURRENT} on staging (expected alpha or beta pre-release)" >&2
        exit 1
      fi
      ;;
    main)
      if [[ "$CURRENT" =~ -beta\. ]]; then
        echo "graduate"
      else
        echo "::error::Unexpected version ${CURRENT} on main (expected beta pre-release before stable)" >&2
        exit 1
      fi
      ;;
  esac
}

write_github_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  else
    echo "${key}=${value}"
  fi
}

LAST_TAG=$(find_last_channel_tag "$CURRENT" "$CHANNEL")

SHOULD_RELEASE=false
if [ -z "$LAST_TAG" ]; then
  SHOULD_RELEASE=true
elif [ "$(git rev-parse HEAD)" != "$(git rev-parse "$LAST_TAG")" ]; then
  COMMIT_COUNT=$(git rev-list "${LAST_TAG}..HEAD" --count)
  if [ "$COMMIT_COUNT" -gt 0 ]; then
    SHOULD_RELEASE=true
  fi
fi

if [ "$SHOULD_RELEASE" = "true" ]; then
  BUMP_STRATEGY=$(resolve_bump_strategy)
  write_github_output "should_release" "true"
  write_github_output "bump_strategy" "$BUMP_STRATEGY"

  case "$BRANCH" in
    develop) write_github_output "release_type" "alpha" ;;
    staging) write_github_output "release_type" "beta" ;;
    main) write_github_output "release_type" "stable" ;;
  esac

  if [ "$BUMP_STRATEGY" = "open-cycle" ]; then
    write_github_output "version_bump" "$(resolve_version_bump "$(find_last_stable_tag)")"
  else
    write_github_output "version_bump" "patch"
  fi

  echo "Release train: will release on ${BRANCH} (${BUMP_STRATEGY})"
else
  write_github_output "should_release" "false"
  write_github_output "bump_strategy" "skip"
  write_github_output "release_type" "none"
  write_github_output "version_bump" "patch"
  echo "Release train: no integrated changes since ${LAST_TAG:-<no prior tag>}, skipping release"
fi
