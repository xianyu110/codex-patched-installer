#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
APP_PATH="${CODEX_PATCHED_APP:-$HOME/Applications/Codex Patched.app}"
USER_DATA_DIR="${CODEX_PATCHED_USER_DATA:-$SCRIPT_DIR/../user-data}"

if [[ ! -d "$APP_PATH" ]]; then
  printf 'Codex Patched app was not found at: %s\n' "$APP_PATH" >&2
  printf 'Run Install-CodexPatched-macos.sh first, or set CODEX_PATCHED_APP.\n' >&2
  exit 1
fi

mkdir -p "$USER_DATA_DIR"
open -n "$APP_PATH" --args "--user-data-dir=$USER_DATA_DIR"
