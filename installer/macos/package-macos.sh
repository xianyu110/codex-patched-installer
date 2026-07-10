#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
DIST_DIR="$ROOT/dist"
OUTPUT="$DIST_DIR/CodexPatched-macOS-Installer.zip"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/CodexPatched-macos.XXXXXX")"
PACKAGE_DIR="$STAGING_ROOT/CodexPatched-macOS-Installer"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

mkdir -p "$PACKAGE_DIR/installer" "$DIST_DIR"
ditto "$ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"
ditto "$ROOT/README.md" "$PACKAGE_DIR/README.md"
ditto "$ROOT/installer/macos" "$PACKAGE_DIR/installer/macos"
rm -f "$PACKAGE_DIR/installer/macos/package-macos.sh"
for file in plugin-account.json sync-remote-plugins.mjs README-remote-plugins.md; do
  ditto "$ROOT/installer/$file" "$PACKAGE_DIR/installer/$file"
done

rm -f "$OUTPUT" "$OUTPUT.sha256"
(
  cd "$STAGING_ROOT"
  /usr/bin/zip -q -r -X "$OUTPUT" "$(basename "$PACKAGE_DIR")" -x '*/.DS_Store' '*/._*'
)
shasum -a 256 "$OUTPUT" > "$OUTPUT.sha256"
printf 'Created %s\nCreated %s\n' "$OUTPUT" "$OUTPUT.sha256"
