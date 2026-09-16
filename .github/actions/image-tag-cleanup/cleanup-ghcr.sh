#!/usr/bin/env bash
set -euo pipefail

# Deletes ephemeral package versions (see select-deletions.sh) from GHCR.
# A GHCR "version" is one image manifest and can carry several tags at
# once, so an entry is only a deletion candidate when EVERY tag on that
# version matches the ephemeral prefix — a version co-tagged with a stable
# release is always protected, same guarantee as Docker Hub's per-tag check.

GHCR_IMAGE_NAME="${1:?ghcr_image_name required, e.g. ghcr.io/sisques-labs/beacon-api}"
EPHEMERAL_PREFIX="${2:?ephemeral tag prefix required}"
RETENTION_DAYS="${3:?retention_days required}"
KEEP_MIN="${4:?keep_min required}"
DRY_RUN="${5:-true}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GITHUB_TOKEN="${GITHUB_TOKEN:?}"

WITHOUT_HOST="${GHCR_IMAGE_NAME#ghcr.io/}"
ORG="${WITHOUT_HOST%%/*}"
PACKAGE="${WITHOUT_HOST#*/}"
ENCODED_PACKAGE=$(jq -rn --arg v "$PACKAGE" '$v|@uri')

CANDIDATES="[]"
PAGE=1
while :; do
  RESP=$(curl -sf \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORG}/packages/container/${ENCODED_PACKAGE}/versions?per_page=100&page=${PAGE}")
  COUNT=$(echo "$RESP" | jq 'length')
  [ "$COUNT" = "0" ] && break
  PAGE_ENTRIES=$(echo "$RESP" | jq -c '[.[] | {id: (.id|tostring), tags: (.metadata.container.tags // []), updated_at: .created_at}]')
  CANDIDATES=$(jq -c -n --argjson a "$CANDIDATES" --argjson b "$PAGE_ENTRIES" '$a + $b')
  [ "$COUNT" -lt 100 ] && break
  PAGE=$((PAGE + 1))
done

TO_DELETE=$(echo "$CANDIDATES" | bash "${SCRIPT_DIR}/select-deletions.sh" "$EPHEMERAL_PREFIX" "$RETENTION_DAYS" "$KEEP_MIN")
TOTAL_COUNT=$(echo "$CANDIDATES" | jq 'length')
DELETE_COUNT=$(echo "$TO_DELETE" | jq 'length')

echo "GHCR (${GHCR_IMAGE_NAME}): ${DELETE_COUNT} version(s) selected for deletion out of ${TOTAL_COUNT} total versions scanned."

echo "$TO_DELETE" | jq -r '.[]' | while read -r VERSION_ID; do
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would delete package version ${VERSION_ID}"
  else
    echo "Deleting package version ${VERSION_ID}"
    curl -sf -X DELETE \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/orgs/${ORG}/packages/container/${ENCODED_PACKAGE}/versions/${VERSION_ID}" \
      || echo "::warning::Failed to delete package version ${VERSION_ID}"
  fi
done
