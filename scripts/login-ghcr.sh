#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GHCR_USERNAME:-}" ]]; then
  read -rp "GitHub username: " GHCR_USERNAME
fi

if [[ -z "${GHCR_TOKEN:-}" ]]; then
  read -rsp "GitHub Personal Access Token (with read:packages scope): " GHCR_TOKEN
  echo
fi

echo "Logging in to ghcr.io as ${GHCR_USERNAME}" >&2
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
