[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\CodexPatched"),
  [switch]$NoRunPatch,
  [switch]$NoDesktopShortcut,
  [string]$SourceApp
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[CodexPatched Installer] $Message"
}

function Require-Command([string]$Name, [string]$Help) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '$Name'. $Help"
  }
}

$PackageRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

Write-Step "Package root: $PackageRoot"
Write-Step "Install directory: $InstallDir"

Require-Command "node" "Install Node.js LTS, then rerun this installer."
Require-Command "npx" "Install Node.js LTS with npm, then rerun this installer."

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$files = @(
  "Patch-CodexApp.ps1",
  "plugin-account.json",
  "sync-remote-plugins.mjs",
  "sync-remote-plugins.ps1",
  "README-remote-plugins.md"
)

foreach ($file in $files) {
  $src = Join-Path $PackageRoot $file
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Installer package is missing $file"
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $file) -Force
}

if (-not $NoRunPatch) {
  $patchScript = Join-Path $InstallDir "Patch-CodexApp.ps1"
  Write-Step "Running patch script..."
  if ($SourceApp) {
    & $patchScript -SourceApp $SourceApp
  } else {
    & $patchScript
  }
}

$shortcut = Join-Path $InstallDir "Codex Patched.lnk"
if (-not $NoDesktopShortcut -and (Test-Path -LiteralPath $shortcut)) {
  $desktop = [Environment]::GetFolderPath("DesktopDirectory")
  Copy-Item -LiteralPath $shortcut -Destination (Join-Path $desktop "Codex Patched.lnk") -Force
  Write-Step "Desktop shortcut created."
}

Write-Step "Done. Open 'Codex Patched.lnk' from $InstallDir."
