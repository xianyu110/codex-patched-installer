#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB_DIR="$SCRIPT_DIR/lib"
SOURCE_APP=""
INSTALL_APP="$HOME/Applications/Codex Patched.app"
CODEX_CLI=""

usage() {
  cat <<'EOF'
Usage: ./Patch-CodexApp-macos.sh [options]

Options:
  --source-app PATH   Official Codex/ChatGPT .app bundle to copy.
  --install-app PATH  Destination for the patched .app bundle.
  --codex-cli PATH    Override the bundled codex executable used to read models.
  -h, --help          Show this help.
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

is_canonical_app() {
  [[ -d "$1" && -f "$1/Contents/Resources/app.asar" && -d "$1/Contents/MacOS" ]]
}

canonical_directory() {
  (cd "$1" && pwd -P)
}

resolve_source_app() {
  local candidate
  if [[ -n "$SOURCE_APP" ]]; then
    [[ -d "$SOURCE_APP" ]] || die "Source app does not exist: $SOURCE_APP"
    candidate="$(canonical_directory "$SOURCE_APP")"
    is_canonical_app "$candidate" || die "Source app is not a supported Codex/ChatGPT app bundle: $candidate"
    printf '%s\n' "$candidate"
    return
  fi

  for candidate in "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app" "/Applications/Codex.app" "/Applications/ChatGPT.app"; do
    if is_canonical_app "$candidate"; then
      canonical_directory "$candidate"
      return
    fi
  done

  while IFS= read -r candidate; do
    if is_canonical_app "$candidate"; then
      canonical_directory "$candidate"
      return
    fi
  done < <(mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'" 2>/dev/null || true)

  die "Could not locate Codex.app or ChatGPT.app. Re-run with --source-app /path/to/Codex.app."
}

assert_safe_destination() {
  case "$INSTALL_APP" in
    "$HOME/Applications/"*.app) ;;
    *) die "For safety, --install-app must be an .app bundle below $HOME/Applications." ;;
  esac
}

safe_remove_work_dir() {
  local target="$1"
  case "$target" in
    "$ROOT/work/"*) ;;
    *) die "Refusing to remove a path outside this installer's work directory: $target" ;;
  esac
  if [[ -e "$target" ]]; then
    rm -rf "$target"
  fi
}

is_valid_model_catalog() {
  local catalog="$1"
  [[ -f "$catalog" ]] || return 1
  node -e 'try { const c = require(process.argv[1]); const expected = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]; if (!Array.isArray(c.models) || !expected.every((slug) => c.models.some((model) => model.slug === slug))) process.exit(1); } catch { process.exit(1); }' "$catalog"
}

while (($#)); do
  case "$1" in
    --source-app) SOURCE_APP="${2:-}"; shift 2 ;;
    --install-app) INSTALL_APP="${2:-}"; shift 2 ;;
    --codex-cli) CODEX_CLI="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_command node "Install Node.js LTS, then run the installer again."
require_command npx "Install Node.js LTS with npm/npx, then run the installer again."
require_command curl "This installer downloads the official model catalog."
require_command ditto "This installer requires the standard macOS ditto utility."
require_command shasum "This installer requires the standard macOS shasum utility."
require_command codesign "This installer must ad-hoc sign the modified app bundle."
require_command /usr/libexec/PlistBuddy "This installer must update Electron's app.asar integrity hash."

[[ -f "$LIB_DIR/patch-webview.mjs" && -f "$LIB_DIR/merge-model-catalog.mjs" && -f "$LIB_DIR/update-config.mjs" ]] || die "The macOS installer package is incomplete."
assert_safe_destination

SOURCE_APP="$(resolve_source_app)"
INSTALL_PARENT="$(dirname "$INSTALL_APP")"
WORK_ROOT="$ROOT/work"
UNPACK_DIR="$WORK_ROOT/app-unpacked"
PACKED_ASAR="$WORK_ROOT/app.asar"
OFFICIAL_MODELS="$WORK_ROOT/official-models.json"
BUNDLED_MODELS="$WORK_ROOT/bundled-models.json"
BACKUPS="$ROOT/backups"
MODEL_CATALOG="$ROOT/model-catalog.json"
MODEL_REPORT="$ROOT/model-catalog-report.json"
SUMMARY="$ROOT/patch-summary.json"
CONFIG_PATH="$HOME/.codex/config.toml"

mkdir -p "$INSTALL_PARENT" "$WORK_ROOT" "$BACKUPS"
if [[ -e "$INSTALL_APP" ]]; then
  step "Removing previous patched app: $INSTALL_APP"
  rm -rf "$INSTALL_APP"
fi

step "Official app source: $SOURCE_APP"
step "Patched app destination: $INSTALL_APP"
step "Copying the app bundle..."
ditto "$SOURCE_APP" "$INSTALL_APP"

ASAR="$INSTALL_APP/Contents/Resources/app.asar"
INFO_PLIST="$INSTALL_APP/Contents/Info.plist"
[[ -f "$ASAR" && -f "$INFO_PLIST" ]] || die "The copied app is missing app.asar or Info.plist."

ORIGINAL_HASH="$(shasum -a 256 "$ASAR" | awk '{print $1}')"
if [[ ! -f "$BACKUPS/app.asar.$ORIGINAL_HASH.bak" ]]; then
  cp "$ASAR" "$BACKUPS/app.asar.$ORIGINAL_HASH.bak"
fi
step "Backed up app.asar (SHA-256 $ORIGINAL_HASH)."

safe_remove_work_dir "$UNPACK_DIR"
mkdir -p "$UNPACK_DIR"
step "Unpacking app.asar..."
npx --yes @electron/asar extract "$ASAR" "$UNPACK_DIR"

step "Patching WebView JavaScript assets..."
node "$LIB_DIR/patch-webview.mjs" "$UNPACK_DIR"
CHANGED_JSON="$UNPACK_DIR/patched-js-files.json"
[[ -f "$CHANGED_JSON" ]] || die "The patcher did not produce a changed-file report."
while IFS= read -r changed_file; do
  step "Checking JavaScript syntax: $(basename "$changed_file")"
  node --check "$changed_file"
done < <(node -e 'const fs = require("fs"); for (const file of JSON.parse(fs.readFileSync(process.argv[1], "utf8")).changedFiles) console.log(file);' "$CHANGED_JSON")

if [[ -z "$CODEX_CLI" ]]; then
  CODEX_CLI="$INSTALL_APP/Contents/Resources/codex"
fi
[[ -x "$CODEX_CLI" ]] || die "Could not locate executable codex CLI. Pass --codex-cli /path/to/codex."
step "Reading the bundled model catalog..."
"$CODEX_CLI" debug models --bundled > "$BUNDLED_MODELS"

step "Downloading the official Codex model catalog..."
DOWNLOADED_MODELS="$WORK_ROOT/official-models.download.json"
rm -f "$DOWNLOADED_MODELS"
if [[ "${CODEX_PATCHED_OFFLINE:-0}" == "1" ]] && is_valid_model_catalog "$MODEL_CATALOG"; then
  cp "$MODEL_CATALOG" "$OFFICIAL_MODELS"
  step "Using the previously validated local model catalog (offline mode)."
elif curl --fail --location --retry 3 --connect-timeout 10 --max-time 60 --silent --show-error --output "$DOWNLOADED_MODELS" "https://raw.githubusercontent.com/openai/codex/main/codex-rs/models-manager/models.json" && is_valid_model_catalog "$DOWNLOADED_MODELS"; then
  mv "$DOWNLOADED_MODELS" "$OFFICIAL_MODELS"
elif is_valid_model_catalog "$MODEL_CATALOG"; then
  cp "$MODEL_CATALOG" "$OFFICIAL_MODELS"
  step "Official catalog download was unavailable; using the previously validated local catalog."
else
  die "Could not download a valid official model catalog and no valid local catalog is available."
fi
node "$LIB_DIR/merge-model-catalog.mjs" "$BUNDLED_MODELS" "$OFFICIAL_MODELS" "$MODEL_CATALOG" "$MODEL_REPORT"

step "Updating ~/.codex/config.toml..."
node "$LIB_DIR/update-config.mjs" "$CONFIG_PATH" "$MODEL_CATALOG"

rm -f "$PACKED_ASAR"
step "Repacking app.asar..."
npx --yes @electron/asar pack "$UNPACK_DIR" "$PACKED_ASAR"
PACKED_HASH="$(shasum -a 256 "$PACKED_ASAR" | awk '{print $1}')"
cp "$PACKED_ASAR" "$ASAR"
RUNTIME_HASH="$(shasum -a 256 "$ASAR" | awk '{print $1}')"
[[ "$PACKED_HASH" == "$RUNTIME_HASH" ]] || die "Repacked app.asar differs from the runtime app.asar."

step "Updating Electron app.asar integrity..."
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $RUNTIME_HASH" "$INFO_PLIST"
DECLARED_HASH="$(/usr/libexec/PlistBuddy -c 'Print :ElectronAsarIntegrity:Resources/app.asar:hash' "$INFO_PLIST")"
[[ "$DECLARED_HASH" == "$RUNTIME_HASH" ]] || die "Info.plist app.asar integrity hash verification failed."

step "Removing quarantine metadata and ad-hoc signing the patched app..."
xattr -dr com.apple.quarantine "$INSTALL_APP" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

node - "$SUMMARY" "$ROOT" "$SOURCE_APP" "$INSTALL_APP" "$ORIGINAL_HASH" "$RUNTIME_HASH" "$CHANGED_JSON" "$MODEL_CATALOG" "$MODEL_REPORT" "$CONFIG_PATH" <<'NODE'
const fs = require("fs");
const [summaryPath, root, sourceApp, app, originalAppAsarSha256, patchedAppAsarSha256, changedPath, modelCatalog, modelReport, configToml] = process.argv.slice(2);
const changedJsFiles = JSON.parse(fs.readFileSync(changedPath, "utf8")).changedFiles;
fs.writeFileSync(summaryPath, JSON.stringify({
  root,
  sourceApp,
  app,
  originalAppAsarSha256,
  patchedAppAsarSha256,
  changedJsFiles,
  modelCatalog,
  modelReport,
  configToml,
}, null, 2) + "\n");
NODE

step "Patch complete. Summary: $SUMMARY"
step "Launch with $SCRIPT_DIR/Open-CodexPatched.command to use isolated user data."
