#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CODEX_CLI=""

usage() {
  cat <<'EOF'
Usage: ./sync-remote-plugins-macos.sh [--codex-cli PATH]
EOF
}

step() {
  printf '[CodexPatched macOS] %s\n' "$*"
}

die() {
  printf '[CodexPatched macOS] Error: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --codex-cli) CODEX_CLI="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command -v node >/dev/null 2>&1 || die "Install Node.js LTS before syncing plugins."
[[ -f "$ROOT/sync-remote-plugins.mjs" ]] || die "Missing sync script: $ROOT/sync-remote-plugins.mjs"

step "Syncing the local remote-plugin marketplace..."
node "$ROOT/sync-remote-plugins.mjs"

if [[ -z "$CODEX_CLI" ]] && command -v codex >/dev/null 2>&1; then
  CODEX_CLI="$(command -v codex)"
fi
if [[ -z "$CODEX_CLI" && -x "$HOME/Applications/Codex Patched.app/Contents/Resources/codex" ]]; then
  CODEX_CLI="$HOME/Applications/Codex Patched.app/Contents/Resources/codex"
fi
if [[ -z "$CODEX_CLI" && -x "/Applications/ChatGPT.app/Contents/Resources/codex" ]]; then
  CODEX_CLI="/Applications/ChatGPT.app/Contents/Resources/codex"
fi
[[ -n "$CODEX_CLI" && -x "$CODEX_CLI" ]] || die "Could not locate codex. Re-run with --codex-cli /path/to/codex."

marketplace_root="$ROOT/plugin-marketplace"
step "Registering marketplace: $marketplace_root"
if ! "$CODEX_CLI" plugin marketplace add "$marketplace_root"; then
  if ! "$CODEX_CLI" plugin marketplace list --json | grep -q 'openai-curated-remote-local'; then
    die "codex plugin marketplace add failed."
  fi
fi

summary_path="$ROOT/plugin-sync-summary.json"
if [[ -f "$summary_path" ]]; then
  node -e 'const s = require(process.argv[1]); console.log(`[CodexPatched macOS] Available local remote plugins: ${s.availableBundleCount}`); console.log(`[CodexPatched macOS] Missing bundles: ${s.missingBundleCount}`);' "$summary_path"
fi
