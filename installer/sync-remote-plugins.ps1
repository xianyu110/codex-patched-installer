[CmdletBinding()]
param(
  [string]$CodexCli
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$Script = Join-Path $Root "sync-remote-plugins.mjs"
$MarketplaceRoot = Join-Path $Root "plugin-marketplace"

if (-not (Test-Path -LiteralPath $Script)) {
  throw "Missing sync script: $Script"
}

Write-Host "[CodexPatched] Syncing local remote-plugin marketplace..."
node $Script
if ($LASTEXITCODE -ne 0) {
  throw "sync-remote-plugins.mjs failed"
}

if (-not $CodexCli) {
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { $CodexCli = $cmd.Source }
}
if (-not $CodexCli) {
  $bundled = Join-Path $Root "app\resources\codex.exe"
  if (Test-Path -LiteralPath $bundled) { $CodexCli = $bundled }
}
if (-not $CodexCli) {
  $localBins = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin") -Filter "codex.exe" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($localBins) { $CodexCli = $localBins.FullName }
}
if (-not $CodexCli) {
  throw "Could not locate codex.exe for marketplace registration. Pass -CodexCli <path>."
}

Write-Host "[CodexPatched] Registering marketplace: $MarketplaceRoot"
& $CodexCli plugin marketplace add $MarketplaceRoot
if ($LASTEXITCODE -ne 0) {
  $listJson = & $CodexCli plugin marketplace list --json
  if ($LASTEXITCODE -ne 0 -or $listJson -notmatch "openai-curated-remote-local") {
    throw "codex plugin marketplace add failed"
  }
}

$SummaryPath = Join-Path $Root "plugin-sync-summary.json"
if (Test-Path -LiteralPath $SummaryPath) {
  $summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json
  Write-Host "[CodexPatched] Available local remote plugins: $($summary.availableBundleCount)"
  Write-Host "[CodexPatched] Missing bundles: $($summary.missingBundleCount)"
}
