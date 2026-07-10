import fs from "node:fs";
import path from "node:path";

const [configPath, catalogPath] = process.argv.slice(2);
if (!configPath || !catalogPath) throw new Error("expected config and catalog paths");

let text = fs.existsSync(configPath) ? fs.readFileSync(configPath, "utf8") : "";
const newline = text.includes("\r\n") ? "\r\n" : "\n";

function tomlString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}

function setTopLevel(key, value) {
  const sectionIndex = text.search(/^\s*\[[^\]]+\]\s*$/m);
  let head = sectionIndex >= 0 ? text.slice(0, sectionIndex) : text;
  const tail = sectionIndex >= 0 ? text.slice(sectionIndex) : "";
  const line = `${key} = ${value}`;
  const expression = new RegExp(`^\\s*${key}\\s*=.*$`, "m");
  if (expression.test(head)) {
    head = head.replace(expression, line);
  } else {
    if (head.length && !head.endsWith("\n") && !head.endsWith("\r\n")) head += newline;
    head += line + newline;
  }
  text = head + tail;
}

setTopLevel("model_catalog_json", tomlString(catalogPath));
setTopLevel("model_reasoning_effort", tomlString("xhigh"));
setTopLevel("service_tier", tomlString("priority"));
fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, text, "utf8");
