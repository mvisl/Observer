#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/create-private-github-brain-repo.sh <repo-name>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_NAME="$1"
BRANCH_NAME="observer-brain-export"

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is not installed." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This script must run inside the Observer git repository." >&2
  exit 1
fi

git branch -D "$BRANCH_NAME" >/dev/null 2>&1 || true
git subtree split --prefix=brain -b "$BRANCH_NAME" >/dev/null

gh repo create "$REPO_NAME" --private
REMOTE_URL="$(gh repo view "$REPO_NAME" --json sshUrl -q .sshUrl)"
git push "$REMOTE_URL" "$BRANCH_NAME:main"

echo "Private brain-only repo pushed: $REPO_NAME"
