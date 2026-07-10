import fs from "node:fs";
import path from "node:path";

const unpackDir = process.argv[2];
if (!unpackDir) throw new Error("missing unpack dir");

const assetsDir = path.join(unpackDir, "webview", "assets");
if (!fs.existsSync(assetsDir)) throw new Error(`missing webview assets directory: ${assetsDir}`);

const changed = [];

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function write(file, text) {
  fs.writeFileSync(file, text, "utf8");
}

function filesMatching(glob, marker) {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  const re = new RegExp(`^${escaped}$`);
  const markers = marker ? (Array.isArray(marker) ? marker : [marker]) : [];
  const matchesMarkers = (file) => {
    const text = read(file);
    return markers.every((value) => text.includes(value));
  };
  const named = fs.readdirSync(assetsDir)
    .filter((name) => re.test(name))
    .map((name) => path.join(assetsDir, name));
  if (markers.length === 0) return named;
  const namedMatches = named.filter(matchesMarkers);
  if (namedMatches.length > 0) return namedMatches;
  return fs.readdirSync(assetsDir)
    .filter((name) => name.endsWith(".js"))
    .map((name) => path.join(assetsDir, name))
    .filter(matchesMarkers);
}

function patchOne({ glob, marker }, mutator) {
  const files = filesMatching(glob, marker);
  if (files.length === 0) throw new Error(`no asset matched ${glob} or marker ${marker}`);
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

patchOne({ glob: "use-service-tier-settings-*.js", marker: ["fast_mode", "isServiceTierAllowed", "authMethod===`chatgpt`"] }, (text) => {
  if (!text.includes("fast_mode")) return text;
  const before = text;
  text = text.replace(/([A-Za-z_$][\w$]*)\?\.authMethod===`chatgpt`(?!\|\|)/, (_m, value) => `${value}?.authMethod===\`chatgpt\`||${value}?.authMethod===\`apikey\``);
  text = text.replace(/([A-Za-z_$][\w$]*)\.authMethod===`chatgpt`(?!\|\|)/, (_m, value) => `${value}.authMethod===\`chatgpt\`||${value}.authMethod===\`apikey\``);
  ensure(text !== before || text.includes("authMethod===`chatgpt`||") || text.includes("authMethod===`apikey`"), "service tier authMethod patch did not apply");
  return text;
});

patchOne({ glob: "read-service-tier-for-request-*.js", marker: "case`apiKey`:return`apikey`" }, (text) => {
  text = literalReplace(
    text,
    "if(n!==`chatgpt`)return!1;",
    "if(n!==`chatgpt`&&n!==`apikey`)return!1;",
    "read-service-tier chatgpt-only guard"
  );
  ensure(text.includes("case`apiKey`:return`apikey`"), "apiKey to apikey mapping is missing");
  return text;
});

const effortArray = /([A-Za-z_$][\w$]*)=\[`(?:minimal`,)?`low`,`medium`,`high`,`xhigh`(?:,`max`)?\]/g;
const hasEffortArray = /([A-Za-z_$][\w$]*)=\[`(?:minimal`,)?`low`,`medium`,`high`,`xhigh`(?:,`max`)?\]/;
const effortFiles = fs.readdirSync(assetsDir)
  .filter((name) => name.endsWith(".js"))
  .map((name) => path.join(assetsDir, name))
  .filter((file) => hasEffortArray.test(read(file)));
if (effortFiles.length === 0) {
  const alreadyPatched = fs.readdirSync(assetsDir)
    .filter((name) => name.endsWith(".js"))
    .some((name) => read(path.join(assetsDir, name)).includes(fullEffortsArray));
  ensure(alreadyPatched, "could not locate the default enabled reasoning efforts array");
} else {
  for (const file of effortFiles) {
    const before = read(file);
    const after = before.replace(effortArray, (_match, value) => `${value}=${fullEffortsArray}`);
    if (after !== before) {
      write(file, after);
      changed.push(file);
    }
  }
}

patchOne({ glob: "model-queries-*.js", marker: "1186680773" }, (text) => {
  text = text.replace(/R=\[`low`,`medium`,`high`,`xhigh`\]/g, `R=${fullEffortsArray}`);
  text = text.replace(/([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)&&s\([A-Za-z_$][\w$]*,`1186680773`\)/g, "$1=$2");
  text = text.replace(/includeUltraReasoningEffort:([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*),`1186680773`\)/g, "includeUltraReasoningEffort:$2");
  ensure(!text.includes("1186680773`"), "Ultra Statsig gate was not removed");
  return text;
});

patchOne({ glob: "model-queries-*.js", marker: "function Jv({authMethod" }, (text) => {
  const virtualModels = "[{model:`gpt-5.6-sol`,displayName:`GPT-5.6 Sol`,defaultReasoningEffort:`low`,supportedReasoningEfforts:[`low`,`medium`,`high`,`xhigh`,`max`,`ultra`].map(reasoningEffort=>({reasoningEffort,description:``})),hidden:!1,isDefault:!1},{model:`gpt-5.6-terra`,displayName:`GPT-5.6 Terra`,defaultReasoningEffort:`medium`,supportedReasoningEfforts:[`low`,`medium`,`high`,`xhigh`,`max`,`ultra`].map(reasoningEffort=>({reasoningEffort,description:``})),hidden:!1,isDefault:!1},{model:`gpt-5.6-luna`,displayName:`GPT-5.6 Luna`,defaultReasoningEffort:`medium`,supportedReasoningEfforts:[`low`,`medium`,`high`,`xhigh`,`max`].map(reasoningEffort=>({reasoningEffort,description:``})),hidden:!1,isDefault:!1}]";
  const original = "}),c??=s.find(e=>e.model===n)??null,{models:s,defaultModel:c,hasModelSupportingMaxReasoningEffort:u,hasModelSupportingUltraReasoningEffort:d}}";
  const patched = `});for(let e of ${virtualModels})s.some(t=>t.model===e.model)||s.unshift(e);u||=s.some(e=>e.supportedReasoningEfforts.some(({reasoningEffort:e})=>e===\`max\`)),d||=i&&s.some(e=>e.supportedReasoningEfforts.some(({reasoningEffort:e})=>e===\`ultra\`)),c??=s.find(e=>e.model===n)??null,{models:s,defaultModel:c,hasModelSupportingMaxReasoningEffort:u,hasModelSupportingUltraReasoningEffort:d}}`;
  text = literalReplace(text, original, patched, "GPT-5.6 virtual model menu fallback");
  ensure(text.includes("model:`gpt-5.6-sol`"), "GPT-5.6 Sol fallback model missing");
  ensure(text.includes("model:`gpt-5.6-luna`"), "GPT-5.6 Luna fallback model missing");
  return text;
});

patchOne({ glob: "model-and-reasoning-dropdown-*.js", marker: ["powerSettingIndex", "gpt-5.6-sol"] }, (text) => {
  const nativeFirstK = "function K(e){let t=oe(e).filter(e=>/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e.model));if(t.length>=4)return t.map((e,t)=>({...e,powerSettingIndex:t}));let n=q(ce,e);if(n.length>=4)return n;let r=q(le,e);return r.length>=4?r:ce.map((e,t)=>({...e,powerSettingIndex:t}))}";
  const currentNativeFirst = "function ARe(e){let t=MRe(e).filter(e=>/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e.model));if(t.length>=4)return t.map((e,t)=>({...e,powerSettingIndex:t}));let n=PRe(FRe,e);if(n.length>=4)return n;let r=PRe(IRe,e);return r.length>=4?r:[]}";
  if (text.includes("function K(e){let t=q(ce,e);if(t.length>=4)return t;let n=q(le,e);return n.length>=4?n:[]}")) {
    text = literalReplace(text, "function K(e){let t=q(ce,e);if(t.length>=4)return t;let n=q(le,e);return n.length>=4?n:[]}", nativeFirstK, "native-first GPT-5.6 power selection");
    const combinations = [
      ["gpt-5.6-sol", "5.6 Sol", ["low", "medium", "high", "xhigh", "max", "ultra"]],
      ["gpt-5.6-terra", "5.6 Terra", ["low", "medium", "high", "xhigh", "max", "ultra"]],
      ["gpt-5.6-luna", "5.6 Luna", ["low", "medium", "high", "xhigh", "max"]],
    ];
    const fallback = "[" + combinations.flatMap(([model, label, efforts]) =>
      efforts.map((effort) => `{id:\`${model}:${effort}\`,model:\`${model}\`,modelLabel:\`${label}\`,reasoningEffort:\`${effort}\`}`)
    ).join(",") + "]";
    text = text.replace(/ce=\[.*?\],le=\[.*?\]\}\)\);function de/s, `ce=${fallback},le=[]}));function de`);
  } else {
    text = literalReplace(text, "function ARe(e){let t=PRe(FRe,e);if(t.length>=4)return t;let n=PRe(IRe,e);return n.length>=4?n:[]}", currentNativeFirst, "native-first GPT-5.6 power selection");
  }
  text = literalReplace(
    text,
    "l(u,f.find(e=>{let{reasoningEffort:t}=e;return t===a})?.reasoningEffort??p)",
    "l(u,p)",
    "model switch default reasoning effort"
  );
  ensure(text.includes("gpt-5\\.6-(?:sol|terra|luna)"), "native-first GPT-5.6 dropdown patch missing");
  ensure(text.includes("l(u,p)"), "model switch default effort patch missing");
  return text;
});

patchOne({ glob: "use-model-settings-*.js", marker: "let c=await Ch(`set-default-model-config-for-host`" }, (text) => {
  const original = "let c=await T(`set-default-model-config-for-host`,{hostId:o,model:e,reasoningEffort:t,profile:g.profile});if(await T(`clear-prewarmed-threads-for-host`,{hostId:o}),c?.status===`okOverridden`)";
  const patched = "let c;if(/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e)){await T(`batch-write-config-value`,{hostId:o,edits:[{keyPath:g.profile==null?`model`:`profiles.${g.profile}.model`,value:e,mergeStrategy:`upsert`},{keyPath:g.profile==null?`model_reasoning_effort`:`profiles.${g.profile}.model_reasoning_effort`,value:t,mergeStrategy:`upsert`}],filePath:null,expectedVersion:null,reloadUserConfig:!0});await T(`clear-prewarmed-threads-for-host`,{hostId:o}),n.set(M,s,null),await R(),await n.query.fetch(H,{hostId:o,cwd:h});return}c=await T(`set-default-model-config-for-host`,{hostId:o,model:e,reasoningEffort:t,profile:g.profile});if(await T(`clear-prewarmed-threads-for-host`,{hostId:o}),c?.status===`okOverridden`)";
  const currentOriginal = "let c=await Ch(`set-default-model-config-for-host`,{hostId:a,model:e,reasoningEffort:t,profile:p.profile});if(await Ch(`clear-prewarmed-threads-for-host`,{hostId:a}),c?.status===`okOverridden`)";
  const currentPatched = "let c;if(/^gpt-5\\.6-(?:sol|terra|luna)$/u.test(e)){await Ch(`batch-write-config-value`,{hostId:a,edits:[{keyPath:p.profile==null?`model`:`profiles.${p.profile}.model`,value:e,mergeStrategy:`upsert`},{keyPath:p.profile==null?`model_reasoning_effort`:`profiles.${p.profile}.model_reasoning_effort`,value:t,mergeStrategy:`upsert`}],filePath:null,expectedVersion:null,reloadUserConfig:!0});await Ch(`clear-prewarmed-threads-for-host`,{hostId:a}),n.set(Wa,s,null),await k(),await n.query.fetch(Dv,{hostId:a,cwd:f});return}c=await Ch(`set-default-model-config-for-host`,{hostId:a,model:e,reasoningEffort:t,profile:p.profile});if(await Ch(`clear-prewarmed-threads-for-host`,{hostId:a}),c?.status===`okOverridden`)";
  if (text.includes(currentOriginal)) {
    text = literalReplace(text, currentOriginal, currentPatched, "current GPT-5.6 batch config write branch");
  } else {
    text = literalReplace(text, original, patched, "GPT-5.6 batch config write branch");
  }
  ensure(text.includes("batch-write-config-value"), "batch-write-config-value patch missing");
  ensure(text.includes(".model_reasoning_effort"), "profile-aware reasoning effort key missing");
  return text;
});

const changedFiles = [...new Set(changed)].sort();
fs.writeFileSync(path.join(unpackDir, "patched-js-files.json"), JSON.stringify({
  changedFiles,
}, null, 2) + "\n");
console.log(JSON.stringify({ changedFiles: changedFiles.map((file) => path.relative(unpackDir, file)) }, null, 2));
