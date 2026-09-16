#!/usr/bin/env bash
set -euo pipefail

# Deletes ephemeral tags (see select-deletions.sh) from a Docker Hub
# repository. Fetches the real tag list, delegates the decision of what's
# safe to delete to select-deletions.sh, then deletes only those.

IMAGE_NAME="${1:?image_name required, e.g. sisqueslabs/beacon-api}"
EPHEMERAL_PREFIX="${2:?ephemeral tag prefix required}"
RETENTION_DAYS="${3:?retention_days required}"
KEEP_MIN="${4:?keep_min required}"
DRY_RUN="${5:-true}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:?}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:?}"

TOKEN=$(curl -sf -X POST "https://hub.docker.com/v2/users/login/" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${DOCKERHUB_USERNAME}\", \"password\": \"${DOCKERHUB_TOKEN}\"}" \
  | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "::error::Failed to authenticate with Docker Hub." >&2
  exit 1
fi

CANDIDATES="[]"
URL="https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags?page_size=100&ordering=last_updated"
while [ -n "$URL" ] && [ "$URL" != "null" ]; do
  PAGE=$(curl -sf -H "Authorization: JWT ${TOKEN}" "$URL")
  PAGE_ENTRIES=$(echo "$PAGE" | jq -c '[.results[] | {id: .name, tags: [.name], updated_at: .last_updated}]')
  CANDIDATES=$(jq -c -n --argjson a "$CANDIDATES" --argjson b "$PAGE_ENTRIES" '$a + $b')
  URL=$(echo "$PAGE" | jq -r '.next')
done

TO_DELETE=$(echo "$CANDIDATES" | bash "${SCRIPT_DIR}/select-deletions.sh" "$EPHEMERAL_PREFIX" "$RETENTION_DAYS" "$KEEP_MIN")
TOTAL_COUNT=$(echo "$CANDIDATES" | jq 'length')
DELETE_COUNT=$(echo "$TO_DELETE" | jq 'length')

echo "Docker Hub (${IMAGE_NAME}): ${DELETE_COUNT} tag(s) selected for deletion out of ${TOTAL_COUNT} total tags scanned."

echo "$TO_DELETE" | jq -r '.[]' | while read -r TAG; do
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would delete ${IMAGE_NAME}:${TAG}"
  else
    echo "Deleting ${IMAGE_NAME}:${TAG}"
    curl -sf -X DELETE -H "Authorization: JWT ${TOKEN}" \
      "https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags/${TAG}/" \
      || echo "::warning::Failed to delete ${IMAGE_NAME}:${TAG}"
  fi
done
