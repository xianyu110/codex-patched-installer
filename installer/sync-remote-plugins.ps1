[CmdletBinding()]
param(
  [string]$CodexCli
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$Script = Join-Path $Root "sync-remote-plugins.mjs"
$MarketplaceRoot = Join-Path $Root "plugin-marketplace"

if (-not (Test-Path -LiteralPath $Script)) {
  throw "缺少同步脚本：$Script"
}

Write-Host "[CodexPatched] 正在同步本地远程插件 marketplace..."
node $Script
if ($LASTEXITCODE -ne 0) {
  throw "sync-remote-plugins.mjs 执行失败"
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
  throw "无法定位用于注册 marketplace 的 codex.exe。请传入 -CodexCli <路径>。"
}

Write-Host "[CodexPatched] 正在注册 marketplace：$MarketplaceRoot"
& $CodexCli plugin marketplace add $MarketplaceRoot
if ($LASTEXITCODE -ne 0) {
  $listJson = & $CodexCli plugin marketplace list --json
  if ($LASTEXITCODE -ne 0 -or $listJson -notmatch "openai-curated-remote-local") {
    throw "codex plugin marketplace add 执行失败"
  }
}

$SummaryPath = Join-Path $Root "plugin-sync-summary.json"
if (Test-Path -LiteralPath $SummaryPath) {
  $summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json
  Write-Host "[CodexPatched] 可用本地远程插件数量：$($summary.availableBundleCount)"
  Write-Host "[CodexPatched] 缺失 bundle 数量：$($summary.missingBundleCount)"
}
