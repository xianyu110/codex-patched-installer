import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const accountPath = path.join(root, "plugin-account.json");
const marketplaceRoot = path.join(root, "plugin-marketplace");
const marketplacePlugins = path.join(marketplaceRoot, "plugins");
const marketplaceJson = path.join(marketplaceRoot, ".agents", "plugins", "marketplace.json");
const summaryPath = path.join(root, "plugin-sync-summary.json");

const template = {
  authFile: "",
  accessToken: "",
  chatgptAccountId: "",
  baseUrl: "https://chatgpt.com/backend-api",
  include: [],
  downloadMissing: false,
  install: [],
};

function readJsonIfExists(file) {
  try {
    if (!fs.existsSync(file)) return null;
    return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    return { __error: String(error?.message ?? error), __path: file };
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function assertNoApiKeyToken(token, source) {
  if (typeof token === "string" && /^sk-[A-Za-z0-9_-]+/.test(token.trim())) {
    throw new Error(`${source} looks like an OpenAI API key. Use a ChatGPT/Codex OAuth access token or authFile instead.`);
  }
}

function findTokenDeep(value, depth = 0) {
  if (depth > 6 || value == null) return "";
  if (typeof value === "string") return "";
  if (Array.isArray(value)) {
    for (const item of value) {
      const token = findTokenDeep(item, depth + 1);
      if (token) return token;
    }
    return "";
  }
  if (typeof value === "object") {
    for (const key of ["accessToken", "access_token", "chatgpt_access_token", "id_token"]) {
      if (typeof value[key] === "string" && value[key].trim()) return value[key].trim();
    }
    for (const key of Object.keys(value)) {
      const token = findTokenDeep(value[key], depth + 1);
      if (token) return token;
    }
  }
  return "";
}

function resolveMaybeRelative(p) {
  if (!p) return "";
  return path.isAbsolute(p) ? p : path.resolve(root, p);
}

function localMarketplaceSources() {
  const home = os.homedir();
  const candidates = [
    path.join(home, ".codex", ".tmp", "plugins"),
    path.join(home, ".codex", "plugins", "cache", "remote_plugin_catalog"),
    path.join(home, ".codex", "plugins", "cache", "remote_plugin_catalog", "openai-curated-remote"),
  ];
  const roots = [];
  for (const candidate of candidates) {
    const json = path.join(candidate, ".agents", "plugins", "marketplace.json");
    const plugins = path.join(candidate, "plugins");
    if (fs.existsSync(json) && fs.existsSync(plugins)) {
      roots.push({ root: candidate, marketplace: json, plugins });
    }
  }
  return roots;
}

function readLocalBundles() {
  const byName = new Map();
  for (const source of localMarketplaceSources()) {
    const market = readJsonIfExists(source.marketplace);
    const entries = Array.isArray(market?.plugins) ? market.plugins : [];
    for (const entry of entries) {
      const name = entry?.name;
      if (!name) continue;
      const entryPath = entry?.source?.path ? path.resolve(source.root, entry.source.path) : path.join(source.plugins, name);
      const manifest = path.join(entryPath, ".codex-plugin", "plugin.json");
      if (!fs.existsSync(manifest)) continue;
      byName.set(name, {
        name,
        sourcePath: entryPath,
        category: entry.category || "Productivity",
        policy: entry.policy || { installation: "AVAILABLE", authentication: "ON_INSTALL" },
        localMarketplace: source.marketplace,
      });
    }
  }
  return byName;
}

function flattenPlugins(payload) {
  const out = [];
  const seen = new Set();
  function visit(value) {
    if (!value || typeof value !== "object") return;
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
      return;
    }
    const name = value.name || value.slug || value.id || value.plugin_name || value.pluginName;
    if (typeof name === "string" && name && (value.bundle_download_url || value.source || value.manifest || value.version || value.description || value.category)) {
      const key = `${name}:${value.bundle_download_url ?? ""}`;
      if (!seen.has(key)) {
        seen.add(key);
        out.push(value);
      }
    }
    for (const key of ["plugins", "items", "data", "results", "installed", "available"]) {
      if (value[key]) visit(value[key]);
    }
  }
  visit(payload);
  return out;
}

async function getRemotePlugins(account, token) {
  if (!token) return { plugins: [], errors: ["No OAuth token/authFile configured; using local bundle cache only."] };
  const baseUrl = (account.baseUrl || template.baseUrl).replace(/\/+$/, "");
  const endpoints = [
    "/ps/plugins/installed?includeDownloadUrls=true",
    "/ps/plugins/list?includeDownloadUrls=true",
    "/ps/plugins/suggested?includeDownloadUrls=true",
  ];
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  if (account.chatgptAccountId) headers["ChatGPT-Account-ID"] = account.chatgptAccountId;
  const plugins = [];
  const errors = [];
  for (const endpoint of endpoints) {
    try {
      const response = await fetch(baseUrl + endpoint, { headers });
      if (!response.ok) {
        errors.push(`${endpoint}: HTTP ${response.status}`);
        continue;
      }
      const json = await response.json();
      plugins.push(...flattenPlugins(json));
    } catch (error) {
      errors.push(`${endpoint}: ${String(error?.message ?? error)}`);
    }
  }
  const byName = new Map();
  for (const plugin of plugins) {
    const name = plugin.name || plugin.slug || plugin.id || plugin.plugin_name || plugin.pluginName;
    if (typeof name === "string" && name && !byName.has(name)) byName.set(name, plugin);
  }
  return { plugins: [...byName.values()], errors };
}

async function downloadBundle(name, url, dest, token, account) {
  const tmpDir = path.join(root, "work", "plugin-downloads");
  fs.mkdirSync(tmpDir, { recursive: true });
  const archive = path.join(tmpDir, `${name}.bundle`);
  const headers = { Accept: "application/octet-stream" };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (account.chatgptAccountId) headers["ChatGPT-Account-ID"] = account.chatgptAccountId;
  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(archive, buffer);
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  const tarCommand = process.platform === "win32" ? "tar.exe" : "tar";
  const result = spawnSync(tarCommand, ["-xf", archive, "-C", dest], { encoding: "utf8" });
  if (result.status !== 0) {
    fs.rmSync(dest, { recursive: true, force: true });
    throw new Error((result.stderr || result.stdout || "tar extraction failed").trim());
  }
  const nestedManifest = path.join(dest, ".codex-plugin", "plugin.json");
  if (!fs.existsSync(nestedManifest)) {
    const children = fs.readdirSync(dest, { withFileTypes: true }).filter((d) => d.isDirectory());
    if (children.length === 1) {
      const child = path.join(dest, children[0].name);
      if (fs.existsSync(path.join(child, ".codex-plugin", "plugin.json"))) {
        for (const item of fs.readdirSync(child)) fs.renameSync(path.join(child, item), path.join(dest, item));
        fs.rmSync(child, { recursive: true, force: true });
      }
    }
  }
  if (!fs.existsSync(path.join(dest, ".codex-plugin", "plugin.json"))) {
    throw new Error("downloaded bundle did not contain .codex-plugin/plugin.json");
  }
}

async function main() {
  if (!fs.existsSync(accountPath)) writeJson(accountPath, template);
  const account = { ...template, ...(readJsonIfExists(accountPath) || {}) };
  assertNoApiKeyToken(account.accessToken, "plugin-account.json accessToken");
  let token = account.accessToken?.trim() || "";
  if (account.authFile) {
    const authFile = resolveMaybeRelative(account.authFile);
    const auth = readJsonIfExists(authFile);
    if (auth?.__error) throw new Error(`Could not read authFile: ${auth.__error}`);
    token = findTokenDeep(auth) || token;
    assertNoApiKeyToken(token, "authFile token");
  }

  const localBundles = readLocalBundles();
  const remote = await getRemotePlugins(account, token);
  const remoteByName = new Map();
  for (const plugin of remote.plugins) {
    const name = plugin.name || plugin.slug || plugin.id || plugin.plugin_name || plugin.pluginName;
    if (typeof name === "string" && name) remoteByName.set(name, plugin);
  }

  const include = Array.isArray(account.include) ? account.include.filter(Boolean) : [];
  const includeSet = new Set(include);
  let names;
  if (remoteByName.size > 0) {
    names = [...remoteByName.keys()];
  } else {
    names = [...localBundles.keys()];
  }
  if (includeSet.size > 0) names = names.filter((name) => includeSet.has(name));
  names.sort((a, b) => a.localeCompare(b));

  fs.rmSync(marketplacePlugins, { recursive: true, force: true });
  fs.mkdirSync(marketplacePlugins, { recursive: true });

  const entries = [];
  const missingBundles = [];
  const downloaded = [];
  const copied = [];
  const downloadErrors = [];

  for (const name of names) {
    let bundle = localBundles.get(name);
    const remotePlugin = remoteByName.get(name);
    const dest = path.join(marketplacePlugins, name);
    if (!bundle && account.downloadMissing && remotePlugin?.bundle_download_url) {
      try {
        await downloadBundle(name, remotePlugin.bundle_download_url, dest, token, account);
        bundle = { name, sourcePath: dest, category: remotePlugin.category || "Productivity", policy: { installation: "AVAILABLE", authentication: "ON_INSTALL" } };
        downloaded.push(name);
      } catch (error) {
        downloadErrors.push({ name, reason: String(error?.message ?? error) });
      }
    }
    if (!bundle) {
      missingBundles.push(name);
      continue;
    }
    if (bundle.sourcePath !== dest) {
      fs.cpSync(bundle.sourcePath, dest, { recursive: true, force: true, dereference: true });
      copied.push(name);
    }
    entries.push({
      name,
      source: { source: "local", path: `./plugins/${name}` },
      policy: {
        installation: bundle.policy?.installation || "AVAILABLE",
        authentication: bundle.policy?.authentication || "ON_INSTALL",
      },
      category: bundle.category || remotePlugin?.category || "Productivity",
    });
  }

  const marketplace = {
    name: "openai-curated-remote-local",
    interface: { displayName: "OpenAI Curated Remote Local" },
    plugins: entries,
  };
  writeJson(marketplaceJson, marketplace);
  const summary = {
    marketplaceRoot,
    marketplaceJson,
    generatedAt: new Date().toISOString(),
    source: remoteByName.size > 0 ? "remote-account-plus-local-bundles" : "local-bundle-cache",
    remoteVisibleCount: remoteByName.size,
    availableBundleCount: entries.length,
    copiedCount: copied.length,
    downloadedCount: downloaded.length,
    missingBundleCount: missingBundles.length,
    missingBundles,
    downloadErrors,
    remoteErrors: remote.errors,
    requestedInstall: Array.isArray(account.install) ? account.install : [],
    samplePlugins: entries.slice(0, 25).map((x) => x.name),
    contains: {
      productDesign: entries.some((x) => x.name === "product-design"),
      github: entries.some((x) => x.name === "github"),
      figma: entries.some((x) => x.name === "figma"),
    },
  };
  writeJson(summaryPath, summary);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(String(error?.message ?? error));
  process.exit(1);
});
