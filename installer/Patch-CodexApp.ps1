[CmdletBinding()]
param(
  [string]$SourceApp,
  [string]$CodexCli
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[CodexPatched] $Message"
}

function Assert-UnderRoot([string]$Path, [string]$Root) {
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝在目标目录之外操作：$resolvedPath"
  }
}

function Remove-TreeSafe([string]$Path, [string]$Root) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  Assert-UnderRoot $Path $Root
  $full = [System.IO.Path]::GetFullPath($Path)
  try {
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
  } catch {
    $long = if ($full.StartsWith("\\?\")) { $full } else { "\\?\$full" }
    Remove-Item -LiteralPath $long -Recurse -Force -ErrorAction Stop
  }
}

function Resolve-SourceApp {
  param([string]$Requested)
  if ($Requested) {
    $candidate = [System.IO.Path]::GetFullPath($Requested)
    if (-not (Test-Path -LiteralPath (Join-Path $candidate "resources\app.asar"))) {
      throw "SourceApp 看起来不是 Codex App 目录：$candidate"
    }
    return $candidate
  }

  $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    ($_.ProcessName -eq "ChatGPT" -or $_.ProcessName -eq "Codex" -or $_.ProcessName -eq "codex") -and
    $_.Path -like "*\WindowsApps\OpenAI.Codex_*"
  } | Sort-Object StartTime -Descending

  foreach ($proc in $processes) {
    $dir = Split-Path -Parent $proc.Path
    if ((Split-Path -Leaf $dir) -eq "resources") {
      $dir = Split-Path -Parent $dir
    }
    if ((Split-Path -Leaf $dir) -ne "app") {
      continue
    }
    if (Test-Path -LiteralPath (Join-Path $dir "resources\app.asar")) {
      return [System.IO.Path]::GetFullPath($dir)
    }
  }

  $pkg = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
  if ($pkg -and $pkg.InstallLocation) {
    $candidate = Join-Path $pkg.InstallLocation "app"
    if (Test-Path -LiteralPath (Join-Path $candidate "resources\app.asar")) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  throw "无法定位已安装的 Codex App。请传入 -SourceApp <官方安装目录下的 app 路径>。"
}

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [int[]]$AllowedExitCodes = @(0)
  )
  & $FilePath @Arguments
  $code = $LASTEXITCODE
  if ($AllowedExitCodes -notcontains $code) {
    throw "命令失败，退出码 ${code}: $FilePath $($Arguments -join ' ')"
  }
}

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$AppDest = Join-Path $Root "app"
$WorkRoot = Join-Path $Root "work"
$Backups = Join-Path $Root "backups"
$UnpackDir = Join-Path $WorkRoot "app-unpacked"
$PackedAsar = Join-Path $WorkRoot "app.asar"
$OfficialModels = Join-Path $WorkRoot "official-models.json"
$BundledModels = Join-Path $WorkRoot "bundled-models.json"
$ModelCatalog = Join-Path $Root "model-catalog.json"
$ModelReport = Join-Path $Root "model-catalog-report.json"

Assert-UnderRoot $AppDest $Root
Assert-UnderRoot $WorkRoot $Root
New-Item -ItemType Directory -Force -Path $Root, $Backups, $WorkRoot | Out-Null

$Source = Resolve-SourceApp -Requested $SourceApp
Write-Step "官方 App 来源：$Source"
Write-Step "补丁副本目标：$AppDest"

if (Test-Path -LiteralPath $AppDest) {
  Remove-TreeSafe $AppDest $Root
}
New-Item -ItemType Directory -Force -Path $AppDest | Out-Null
Write-Step "正在复制完整 App 目录..."
& robocopy $Source $AppDest /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
$rc = $LASTEXITCODE
if ($rc -gt 7) {
  throw "robocopy 失败，退出码 $rc"
}

$Asar = Join-Path $AppDest "resources\app.asar"
if (-not (Test-Path -LiteralPath $Asar)) {
  throw "复制后的 app.asar 未找到：$Asar"
}
$TopCodexExe = Join-Path $AppDest "Codex.exe"
$TopChatGptExe = Join-Path $AppDest "ChatGPT.exe"
if ((Test-Path -LiteralPath $TopCodexExe) -and (Test-Path -LiteralPath $TopChatGptExe)) {
  $codexShimBackup = Join-Path $AppDest "Codex.exe.original.bak"
  Copy-Item -LiteralPath $TopCodexExe -Destination $codexShimBackup -Force
  Copy-Item -LiteralPath $TopChatGptExe -Destination $TopCodexExe -Force
  Write-Step "已替换副本中的 Codex.exe 启动 shim，原 shim 已备份在 app 目录。"
}
$originalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Asar).Hash
$localBackup = Join-Path (Split-Path -Parent $Asar) "app.asar.original.bak"
Copy-Item -LiteralPath $Asar -Destination $localBackup -Force
$hashBackup = Join-Path $Backups "app.asar.$originalHash.bak"
if (-not (Test-Path -LiteralPath $hashBackup)) {
  Copy-Item -LiteralPath $Asar -Destination $hashBackup -Force
}
Write-Step "已备份 app.asar，SHA256 $originalHash"

if (Test-Path -LiteralPath $UnpackDir) {
  Remove-TreeSafe $UnpackDir $Root
}
New-Item -ItemType Directory -Force -Path $UnpackDir | Out-Null
Write-Step "正在解包 app.asar..."
Invoke-Checked -FilePath "npx.cmd" -Arguments @("--yes", "@electron/asar", "extract", $Asar, $UnpackDir)

$patcher = Join-Path $WorkRoot "patch-webview.mjs"
@'
import fs from "node:fs";
import path from "node:path";

const unpackDir = process.argv[2];
if (!unpackDir) throw new Error("missing unpack dir");
const assetsDir = path.join(unpackDir, "webview", "assets");
const changed = [];
const notes = [];

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function write(file, text) {
  fs.writeFileSync(file, text, "utf8");
}

function filesMatching(glob) {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  const re = new RegExp(`^${escaped}$`);
  return fs.readdirSync(assetsDir)
    .filter((name) => re.test(name))
    .map((name) => path.join(assetsDir, name));
}

function patchOne(glob, mutator) {
  const files = filesMatching(glob);
  if (files.length === 0) throw new Error(`no asset matched ${glob}`);
  for (const file of files) {
    const before = read(file);
    const after = mutator(before, path.basename(file));
    if (after !== before) {
      write(file, after);
      changed.push(file);
    }
  }
}

function ensure(condition, message) {
  if (!condition) throw new Error(message);
}

function literalReplace(text, from, to, label) {
  if (text.includes(to)) return text;
  ensure(text.includes(from), `could not find ${label}`);
  return text.replace(from, to);
}

const fullEffortsArray = "[`low`,`medium`,`high`,`xhigh`,`max`,`ultra`]";

patchOne("use-service-tier-settings-*.js", (text) => {
  if (!text.includes("fast_mode")) return text;
  const before = text;
  text = text.replace(/([A-Za-z_$][\w$]*)\?\.authMethod===`chatgpt`(?!\|\|)/, (_m, v) => `${v}?.authMethod===\`chatgpt\`||${v}?.authMethod===\`apikey\``);
  text = text.replace(/([A-Za-z_$][\w$]*)\.authMethod===`chatgpt`(?!\|\|)/, (_m, v) => `${v}.authMethod===\`chatgpt\`||${v}.authMethod===\`apikey\``);
  ensure(text !== before || text.includes("authMethod===`chatgpt`||") || text.includes("authMethod===`apikey`"), "service tier authMethod patch did not apply");
  return text;
});

patchOne("read-service-tier-for-request-*.js", (text) => {
  text = literalReplace(
    text,
    "if(n!==`chatgpt`)return!1;",
    "if(n!==`chatgpt`&&n!==`apikey`)return!1;",
    "read-service-tier chatgpt-only guard"
  );
  ensure(text.includes("case`apiKey`:return`apikey`"), "apiKey to apikey mapping is missing");
  return text;
});

patchOne("models-and-reasoning-efforts-*.js", (text) => {
  text = text.replace(/i=\[`minimal`,`low`,`medium`,`high`,`xhigh`,`max`\]/g, `i=${fullEffortsArray}`);
  text = text.replace(/i=\[`low`,`medium`,`high`,`xhigh`,`max`\]/g, `i=${fullEffortsArray}`);
  ensure(text.includes(`i=${fullEffortsArray}`), "default enabled reasoning efforts were not patched");
  return text;
});

patchOne("model-queries-*.js", (text) => {
  text = text.replace(/R=\[`low`,`medium`,`high`,`xhigh`\]/g, `R=${fullEffortsArray}`);
  text = text.replace(/([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)&&s\([A-Za-z_$][\w$]*,`1186680773`\)/g, "$1=$2");
  ensure(text.includes(`R=${fullEffortsArray}`), "model query enabled reasoning efforts were not patched");
  ensure(!text.includes("1186680773`"), "Ultra Statsig gate was not removed");
  return text;
});

patchOne("model-and-reasoning-dropdown-*.js", (text) => {
  const nativeFirstK = "function K(e){let t=oe(e).filter(e=>/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e.model));if(t.length>=4)return t.map((e,t)=>({...e,powerSettingIndex:t}));let n=q(ce,e);if(n.length>=4)return n;let r=q(le,e);return r.length>=4?r:ce.map((e,t)=>({...e,powerSettingIndex:t}))}";
  text = literalReplace(
    text,
    "function K(e){let t=q(ce,e);if(t.length>=4)return t;let n=q(le,e);return n.length>=4?n:[]}",
    nativeFirstK,
    "native-first GPT-5.6 power selection"
  );

  const combos = [
    ["gpt-5.6-sol", "5.6 Sol", ["low", "medium", "high", "xhigh", "max", "ultra"]],
    ["gpt-5.6-terra", "5.6 Terra", ["low", "medium", "high", "xhigh", "max", "ultra"]],
    ["gpt-5.6-luna", "5.6 Luna", ["low", "medium", "high", "xhigh", "max"]],
  ];
  const fallback = "[" + combos.flatMap(([model, label, efforts]) =>
    efforts.map((effort) => `{id:\`${model}:${effort}\`,model:\`${model}\`,modelLabel:\`${label}\`,reasoningEffort:\`${effort}\`}`)
  ).join(",") + "]";
  text = text.replace(/ce=\[.*?\],le=\[.*?\]\}\)\);function de/s, `ce=${fallback},le=[]}));function de`);
  text = literalReplace(
    text,
    "l(u,f.find(e=>{let{reasoningEffort:t}=e;return t===a})?.reasoningEffort??p)",
    "l(u,p)",
    "model switch default reasoning effort"
  );
  ensure(text.includes("oe(e).filter(e=>/^gpt-5\\.6-"), "native-first GPT-5.6 dropdown patch missing");
  ensure(text.includes("gpt-5.6-luna:max"), "fallback Luna max entry missing");
  ensure(text.includes("l(u,p)"), "model switch default effort patch missing");
  return text;
});

patchOne("use-model-settings-*.js", (text) => {
  const original = "let c=await T(`set-default-model-config-for-host`,{hostId:o,model:e,reasoningEffort:t,profile:g.profile});if(await T(`clear-prewarmed-threads-for-host`,{hostId:o}),c?.status===`okOverridden`)";
  const patched = "let c;if(/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e)){await T(`batch-write-config-value`,{hostId:o,edits:[{keyPath:g.profile==null?`model`:`profiles.${g.profile}.model`,value:e,mergeStrategy:`upsert`},{keyPath:g.profile==null?`model_reasoning_effort`:`profiles.${g.profile}.model_reasoning_effort`,value:t,mergeStrategy:`upsert`}],filePath:null,expectedVersion:null,reloadUserConfig:!0});await T(`clear-prewarmed-threads-for-host`,{hostId:o}),n.set(M,s,null),await R(),await n.query.fetch(H,{hostId:o,cwd:h});return}c=await T(`set-default-model-config-for-host`,{hostId:o,model:e,reasoningEffort:t,profile:g.profile});if(await T(`clear-prewarmed-threads-for-host`,{hostId:o}),c?.status===`okOverridden`)";
  text = literalReplace(text, original, patched, "GPT-5.6 batch config write branch");
  ensure(text.includes("batch-write-config-value"), "batch-write-config-value patch missing");
  ensure(text.includes("profiles.${g.profile}.model_reasoning_effort"), "profile-aware reasoning effort key missing");
  return text;
});

const changedUnique = [...new Set(changed)].sort();
fs.writeFileSync(path.join(path.dirname(assetsDir), "..", "patched-js-files.json"), JSON.stringify({
  changedFiles: changedUnique,
  notes,
}, null, 2));
console.log(JSON.stringify({ changedFiles: changedUnique.map((f) => path.relative(unpackDir, f)) }, null, 2));
'@ | Set-Content -LiteralPath $patcher -Encoding UTF8

Write-Step "正在补丁 WebView JavaScript 资源..."
Invoke-Checked -FilePath "node.exe" -Arguments @($patcher, $UnpackDir)
$changedFileJson = Join-Path $UnpackDir "patched-js-files.json"
$changedFiles = (Get-Content -Raw -LiteralPath $changedFileJson | ConvertFrom-Json).changedFiles
foreach ($file in $changedFiles) {
  Write-Step "node --check $([System.IO.Path]::GetFileName($file))"
  Invoke-Checked -FilePath "node.exe" -Arguments @("--check", $file)
}

$CodexExe = Join-Path $AppDest "resources\codex.exe"
if (-not (Test-Path -LiteralPath $CodexExe)) {
  if ($CodexCli) {
    $CodexExe = $CodexCli
  } else {
    throw "无法找到副本中的 resources\codex.exe"
  }
}

Write-Step "正在从副本 codex.exe 读取内置模型目录..."
& $CodexExe debug models --bundled | Set-Content -LiteralPath $BundledModels -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "codex debug models --bundled 执行失败"
}

Write-Step "正在从 OpenAI 官方 Codex main 分支读取最新模型目录..."
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/openai/codex/main/codex-rs/models-manager/models.json" -OutFile $OfficialModels -UseBasicParsing

$mergeModels = Join-Path $WorkRoot "merge-model-catalog.mjs"
@'
import fs from "node:fs";
const [bundledPath, officialPath, outPath, reportPath] = process.argv.slice(2);
const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8").replace(/^\uFEFF/, ""));
const bundled = readJson(bundledPath);
const official = readJson(officialPath);
if (!Array.isArray(bundled.models) || !Array.isArray(official.models)) {
  throw new Error("model catalogs must contain a models array");
}
const wanted = new Set(["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]);
const officialBySlug = new Map(official.models.map((m) => [m.slug, m]));
for (const slug of wanted) {
  if (!officialBySlug.has(slug)) throw new Error(`official catalog is missing ${slug}`);
}
if (officialBySlug.has("gpt-5.6-pro")) {
  throw new Error("official catalog unexpectedly contains gpt-5.6-pro; refusing to invent or merge it");
}
const merged = bundled.models.map((m) => wanted.has(m.slug) ? officialBySlug.get(m.slug) : m);
const seen = new Set(merged.map((m) => m.slug));
for (const slug of wanted) {
  if (!seen.has(slug)) merged.unshift(officialBySlug.get(slug));
}
const expected = {
  "gpt-5.6-sol": ["low", "medium", "high", "xhigh", "max", "ultra"],
  "gpt-5.6-terra": ["low", "medium", "high", "xhigh", "max", "ultra"],
  "gpt-5.6-luna": ["low", "medium", "high", "xhigh", "max"],
};
const report = { totalModels: merged.length, gpt56: {} };
for (const [slug, efforts] of Object.entries(expected)) {
  const model = merged.find((m) => m.slug === slug);
  const actual = (model?.supported_reasoning_levels ?? []).map((x) => x.effort);
  if (JSON.stringify(actual) !== JSON.stringify(efforts)) {
    throw new Error(`${slug} efforts mismatch: ${actual.join(",")}`);
  }
  if (model.context_window !== 372000 || model.max_context_window !== 372000) {
    throw new Error(`${slug} context window mismatch`);
  }
  const serviceTiers = (model.service_tiers ?? []).map((x) => x.id);
  if (!serviceTiers.includes("priority")) {
    throw new Error(`${slug} is missing priority service tier`);
  }
  report.gpt56[slug] = {
    default_reasoning_level: model.default_reasoning_level,
    supported_reasoning_levels: actual,
    context_window: model.context_window,
    max_context_window: model.max_context_window,
    service_tiers: serviceTiers,
    additional_speed_tiers: model.additional_speed_tiers ?? [],
    multi_agent_version: model.multi_agent_version ?? null,
    use_responses_lite: model.use_responses_lite ?? null,
    tool_mode: model.tool_mode ?? null,
  };
}
fs.writeFileSync(outPath, JSON.stringify({ models: merged }, null, 2) + "\n", "utf8");
fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n", "utf8");
console.log(JSON.stringify(report, null, 2));
'@ | Set-Content -LiteralPath $mergeModels -Encoding UTF8
Invoke-Checked -FilePath "node.exe" -Arguments @($mergeModels, $BundledModels, $OfficialModels, $ModelCatalog, $ModelReport)

Write-Step "正在更新用户 config.toml：model_catalog_json、xhigh effort、priority service tier..."
$ConfigPath = Join-Path $env:USERPROFILE ".codex\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
$updateConfig = Join-Path $WorkRoot "update-config.mjs"
@'
import fs from "node:fs";
const [configPath, catalogPath] = process.argv.slice(2);
let text = fs.existsSync(configPath) ? fs.readFileSync(configPath, "utf8") : "";
const nl = text.includes("\r\n") ? "\r\n" : "\n";
function tomlString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}
function setTopLevel(key, value) {
  const sectionIndex = text.search(/^\s*\[[^\]]+\]\s*$/m);
  let head = sectionIndex >= 0 ? text.slice(0, sectionIndex) : text;
  const tail = sectionIndex >= 0 ? text.slice(sectionIndex) : "";
  const re = new RegExp(`^\\s*${key}\\s*=.*$`, "m");
  const line = `${key} = ${value}`;
  if (re.test(head)) {
    head = head.replace(re, line);
  } else {
    if (head.length && !head.endsWith("\n") && !head.endsWith("\r\n")) head += nl;
    head += line + nl;
  }
  text = head + tail;
}
setTopLevel("model_catalog_json", tomlString(catalogPath));
setTopLevel("model_reasoning_effort", tomlString("xhigh"));
setTopLevel("service_tier", tomlString("priority"));
fs.writeFileSync(configPath, text, "utf8");
'@ | Set-Content -LiteralPath $updateConfig -Encoding UTF8
Invoke-Checked -FilePath "node.exe" -Arguments @($updateConfig, $ConfigPath, $ModelCatalog)

Write-Step "正在重新打包 app.asar..."
if (Test-Path -LiteralPath $PackedAsar) {
  Remove-Item -LiteralPath $PackedAsar -Force
}
Invoke-Checked -FilePath "npx.cmd" -Arguments @("--yes", "@electron/asar", "pack", $UnpackDir, $PackedAsar)
Copy-Item -LiteralPath $PackedAsar -Destination $Asar -Force
$packedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackedAsar).Hash
$runtimeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Asar).Hash
if ($packedHash -ne $runtimeHash) {
  throw "打包后的 app.asar 与运行时 app.asar SHA256 不一致"
}
Write-Step "已打包 app.asar，SHA256 $runtimeHash"

$shortcutPath = Join-Path $Root "Codex Patched.lnk"
$targetExe = Join-Path $AppDest "Codex.exe"
if (-not (Test-Path -LiteralPath $targetExe)) {
  throw "快捷方式目标不存在：$targetExe"
}
$userDataDir = Join-Path $Root "user-data"
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetExe
$shortcut.Arguments = "--user-data-dir=`"$userDataDir`""
$shortcut.WorkingDirectory = $AppDest
$shortcut.IconLocation = "$targetExe,0"
$shortcut.Description = "Codex Patched"
$shortcut.Save()
Write-Step "已创建快捷方式：$shortcutPath"

$summary = [ordered]@{
  root = $Root
  sourceApp = $Source
  app = $AppDest
  shortcut = $shortcutPath
  shortcutArguments = "--user-data-dir=`"$userDataDir`""
  originalAppAsarSha256 = $originalHash
  patchedAppAsarSha256 = $runtimeHash
  changedJsFiles = @($changedFiles | ForEach-Object { $_.Replace($UnpackDir + [System.IO.Path]::DirectorySeparatorChar, "") })
  modelCatalog = $ModelCatalog
  modelReport = $ModelReport
  configToml = $ConfigPath
}
$summaryPath = Join-Path $Root "patch-summary.json"
($summary | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Step "已写入摘要：$summaryPath"
