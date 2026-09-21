#!/usr/bin/env bash
set -euo pipefail

# Runs at semantic-release's prepare step (exec prepareCmd), only when
# commit_release_files is true. Writes the stable version into package.json so
# the release commit includes it. Order matters: @semantic-release/changelog
# runs before this step and @semantic-release/git after it (plugin order in
# action.yml). publish.sh still rewrites the version per publish in the runner.
#
# Env: APP_PATH.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

VERSION="${1:?version required}"
APP_PATH="$(resolve_app_path "${APP_PATH:-.}")"
bump_manifest_version "${APP_PATH}/package.json" "$VERSION"
