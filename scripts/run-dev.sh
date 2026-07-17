#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/stable-signing-config.sh"

"$ROOT_DIR/scripts/package-dev-app.sh" >/dev/null
open "$OBSERVER_INSTALL_PATH"
