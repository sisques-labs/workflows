#!/usr/bin/env bash
set -euo pipefail

STRATEGY="${1:?bump strategy required}"
VERSION_BUMP="${2:-minor}"

case "$STRATEGY" in
  open-cycle)
    NEW_VERSION=$(npm version "pre${VERSION_BUMP}" --preid=alpha --no-git-tag-version)
    ;;
  prerelease-alpha)
    NEW_VERSION=$(npm version prerelease --preid=alpha --no-git-tag-version)
    ;;
  promote-beta | prerelease-beta)
    NEW_VERSION=$(npm version prerelease --preid=beta --no-git-tag-version)
    ;;
  graduate)
    NEW_VERSION=$(npm version patch --no-git-tag-version)
    ;;
  *)
    echo "::error::Unknown bump strategy: ${STRATEGY}"
    exit 1
    ;;
esac

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=${NEW_VERSION#v}" >> "$GITHUB_OUTPUT"
  echo "tag=${NEW_VERSION}" >> "$GITHUB_OUTPUT"
else
  echo "version=${NEW_VERSION#v}"
  echo "tag=${NEW_VERSION}"
fi
