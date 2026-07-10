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
    throw "缺少必需命令 '$Name'。$Help"
  }
}

$PackageRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

Write-Step "安装包目录：$PackageRoot"
Write-Step "安装目录：$InstallDir"

Require-Command "node" "请先安装 Node.js LTS，然后重新运行安装器。"
Require-Command "npx" "请先安装包含 npm/npx 的 Node.js LTS，然后重新运行安装器。"

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
    throw "安装包缺少文件：$file"
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $file) -Force
}

if (-not $NoRunPatch) {
  $patchScript = Join-Path $InstallDir "Patch-CodexApp.ps1"
  Write-Step "正在运行补丁脚本..."
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
  Write-Step "已创建桌面快捷方式。"
}

Write-Step "完成。请从 $InstallDir 打开 'Codex Patched.lnk'。"
