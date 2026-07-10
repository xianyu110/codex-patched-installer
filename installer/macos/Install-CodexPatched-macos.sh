#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALLER_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SUPPORT_DIR="$HOME/Library/Application Support/CodexPatched"
INSTALL_APP="$HOME/Applications/Codex Patched.app"
SOURCE_APP=""
RUN_PATCH=1
CREATE_DESKTOP_LAUNCHER=1

usage() {
  cat <<'EOF'
Usage: ./Install-CodexPatched-macos.sh [options]

Options:
  --source-app PATH          Official Codex/ChatGPT .app bundle to copy.
  --install-app PATH         Destination for the patched .app bundle.
  --no-run-patch             Install maintenance scripts without patching now.
  --no-desktop-launcher      Do not create the Desktop launcher.
  -h, --help                 Show this help.
EOF
}

step() {
  printf '[CodexPatched macOS] %s\n' "$*"
}

die() {
  printf '[CodexPatched macOS] Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command '$1'. $2"
}

while (($#)); do
  case "$1" in
    --source-app) SOURCE_APP="${2:-}"; shift 2 ;;
    --install-app) INSTALL_APP="${2:-}"; shift 2 ;;
    --no-run-patch) RUN_PATCH=0; shift ;;
    --no-desktop-launcher) CREATE_DESKTOP_LAUNCHER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_command node "Install Node.js LTS, then run this installer again."
require_command npx "Install Node.js LTS with npm/npx, then run this installer again."
require_command ditto "This installer requires the standard macOS ditto utility."

if [[ ! -f "$INSTALLER_DIR/plugin-account.json" || ! -f "$INSTALLER_DIR/sync-remote-plugins.mjs" ]]; then
  die "The installer package is missing its shared plugin files."
fi

step "Support directory: $SUPPORT_DIR"
step "Patched app destination: $INSTALL_APP"
mkdir -p "$SUPPORT_DIR"
rm -rf "$SUPPORT_DIR/macos"
ditto "$SCRIPT_DIR" "$SUPPORT_DIR/macos"

for file in plugin-account.json sync-remote-plugins.mjs README-remote-plugins.md; do
  ditto "$INSTALLER_DIR/$file" "$SUPPORT_DIR/$file"
done

chmod +x "$SUPPORT_DIR/macos"/*.sh "$SUPPORT_DIR/macos"/*.command

if ((RUN_PATCH)); then
  patch_args=(--install-app "$INSTALL_APP")
  if [[ -n "$SOURCE_APP" ]]; then
    patch_args+=(--source-app "$SOURCE_APP")
  fi
  step "Running patch script..."
  "$SUPPORT_DIR/macos/Patch-CodexApp-macos.sh" "${patch_args[@]}"
fi

if ((CREATE_DESKTOP_LAUNCHER)); then
  desktop_launcher="$HOME/Desktop/Open Codex Patched.command"
  if [[ -e "$desktop_launcher" || -L "$desktop_launcher" ]]; then
    if [[ -L "$desktop_launcher" ]] && [[ "$(readlink "$desktop_launcher")" == "$SUPPORT_DIR/macos/Open-CodexPatched.command" ]]; then
      rm -f "$desktop_launcher"
    else
      step "Desktop launcher already exists, leaving it unchanged: $desktop_launcher"
      step "Use this launcher instead: $SUPPORT_DIR/macos/Open-CodexPatched.command"
      step "Done."
      exit 0
    fi
  fi
  ln -s "$SUPPORT_DIR/macos/Open-CodexPatched.command" "$desktop_launcher"
  step "Created Desktop launcher: $desktop_launcher"
fi

step "Done. Launch the app with $SUPPORT_DIR/macos/Open-CodexPatched.command."
