#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/package-dev-app.sh" >/dev/null
open "$ROOT_DIR/build/Observer.app"
