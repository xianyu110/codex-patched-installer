import fs from "node:fs";

const [bundledPath, officialPath, outPath, reportPath] = process.argv.slice(2);
if (!bundledPath || !officialPath || !outPath || !reportPath) {
  throw new Error("expected bundled catalog, official catalog, output catalog, and report paths");
}

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
const bundled = readJson(bundledPath);
const official = readJson(officialPath);
if (!Array.isArray(bundled.models) || !Array.isArray(official.models)) {
  throw new Error("model catalogs must contain a models array");
}

const expected = {
  "gpt-5.6-sol": ["low", "medium", "high", "xhigh", "max", "ultra"],
  "gpt-5.6-terra": ["low", "medium", "high", "xhigh", "max", "ultra"],
  "gpt-5.6-luna": ["low", "medium", "high", "xhigh", "max"],
};
const wanted = new Set(Object.keys(expected));
const officialBySlug = new Map(official.models.map((model) => [model.slug, model]));
for (const slug of wanted) {
  if (!officialBySlug.has(slug)) throw new Error(`official catalog is missing ${slug}`);
}
if (officialBySlug.has("gpt-5.6-pro")) {
  throw new Error("official catalog unexpectedly contains gpt-5.6-pro; refusing to invent or merge it");
}

const merged = bundled.models.map((model) => wanted.has(model.slug) ? officialBySlug.get(model.slug) : model);
const seen = new Set(merged.map((model) => model.slug));
for (const slug of wanted) {
  if (!seen.has(slug)) merged.unshift(officialBySlug.get(slug));
}

const report = { totalModels: merged.length, gpt56: {} };
for (const [slug, efforts] of Object.entries(expected)) {
  const model = merged.find((item) => item.slug === slug);
  const actual = (model?.supported_reasoning_levels ?? []).map((item) => item.effort);
  if (JSON.stringify(actual) !== JSON.stringify(efforts)) {
    throw new Error(`${slug} efforts mismatch: ${actual.join(",")}`);
  }
  if (model.context_window !== 372000 || model.max_context_window !== 372000) {
    throw new Error(`${slug} context window mismatch`);
  }
  const serviceTiers = (model.service_tiers ?? []).map((tier) => tier.id);
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
