#!/usr/bin/env node
// Zero-dependency validator for GranaPaCa onboarding YAML profiles.
// Parses YAML files in profiles/, validates every field against profiles/schema.json,
// enforces globally unique IDs, and rejects judgmental vocabulary.

import { readdirSync, readFileSync } from "node:fs";
import { basename, extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROFILES_DIR = dirname(fileURLToPath(import.meta.url));
const SCHEMA_PATH = join(PROFILES_DIR, "schema.json");

// Normalized (lowercase, accent-free) judgmental words forbidden in profile text.
const FORBIDDEN_TERMS = [
  "superfluo",
  "superflua",
  "superfluos",
  "superfluas",
  "desnecessario",
  "desnecessaria",
  "desnecessarios",
  "desnecessarias",
  "desperdicio",
  "futil",
  "futeis",
  "luxo",
  "besteira",
  "inutil",
];

function stripDiacritics(text) {
  return text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

function stripInlineComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (ch === '"' && !inSingle && line[i - 1] !== "\\") {
      inDouble = !inDouble;
    } else if (ch === "#" && !inSingle && !inDouble && (i === 0 || /\s/.test(line[i - 1]))) {
      return line.slice(0, i);
    }
  }
  return line;
}

function parseScalar(raw, lineNo, filePath) {
  const trimmed = raw.trim();
  if (trimmed === "") return "";
  if (trimmed.startsWith('"')) {
    if (!trimmed.endsWith('"') || trimmed.length < 2) {
      throw new Error(`${filePath}:${lineNo}: unterminated double-quoted string`);
    }
    return JSON.parse(trimmed);
  }
  if (trimmed.startsWith("'")) {
    if (!trimmed.endsWith("'") || trimmed.length < 2) {
      throw new Error(`${filePath}:${lineNo}: unterminated single-quoted string`);
    }
    return trimmed.slice(1, -1).replace(/''/g, "'");
  }
  if (trimmed.startsWith("[")) {
    return parseFlowSequence(trimmed, lineNo, filePath);
  }
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (trimmed === "null" || trimmed === "~") return null;
  return trimmed;
}

function parseFlowSequence(raw, lineNo, filePath) {
  if (!raw.endsWith("]")) {
    throw new Error(`${filePath}:${lineNo}: unterminated flow sequence`);
  }
  const inner = raw.slice(1, -1).trim();
  if (inner === "") return [];

  const items = [];
  let current = "";
  let inSingle = false;
  let inDouble = false;

  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (ch === "'" && !inDouble) {
      inSingle = !inSingle;
      current += ch;
    } else if (ch === '"' && !inSingle && inner[i - 1] !== "\\") {
      inDouble = !inDouble;
      current += ch;
    } else if (ch === "," && !inSingle && !inDouble) {
      items.push(parseScalar(current, lineNo, filePath));
      current = "";
    } else {
      current += ch;
    }
  }
  if (inSingle || inDouble) {
    throw new Error(`${filePath}:${lineNo}: unterminated quote inside flow sequence`);
  }
  items.push(parseScalar(current, lineNo, filePath));
  return items;
}

function splitKeyValue(content, lineNo, filePath) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '"' && !inSingle && content[i - 1] !== "\\") inDouble = !inDouble;
    else if (ch === ":" && !inSingle && !inDouble) {
      const next = content[i + 1];
      if (next === undefined || next === " ") {
        const key = content.slice(0, i).trim();
        const rest = content.slice(i + 1).trim();
        if (!key) {
          throw new Error(`${filePath}:${lineNo}: empty mapping key`);
        }
        return [key, rest];
      }
    }
  }
  throw new Error(`${filePath}:${lineNo}: expected 'key: value' mapping entry`);
}

function parseYaml(source, filePath) {
  const rawLines = source.replace(/\r\n/g, "\n").split("\n");
  const lines = [];

  for (let i = 0; i < rawLines.length; i++) {
    const lineNo = i + 1;
    const raw = rawLines[i];
    if (/^\t/.test(raw)) {
      throw new Error(`${filePath}:${lineNo}: tab indentation is not allowed in YAML`);
    }
    const withoutComment = stripInlineComment(raw);
    if (withoutComment.trim() === "") continue;
    const indent = withoutComment.length - withoutComment.trimStart().length;
    lines.push({ indent, text: withoutComment.trim(), lineNo });
  }

  if (lines.length === 0) {
    throw new Error(`${filePath}: empty YAML document`);
  }

  let index = 0;

  function parseBlock(minIndent) {
    const current = lines[index];
    if (!current || current.indent < minIndent) {
      return null;
    }
    if (current.text === "-" || current.text.startsWith("- ")) {
      return parseSequence(current.indent);
    }
    return parseMapping(current.indent);
  }

  function parseSequence(seqIndent) {
    const list = [];
    while (index < lines.length) {
      const line = lines[index];
      if (line.indent < seqIndent) break;
      if (line.indent > seqIndent) {
        throw new Error(`${filePath}:${line.lineNo}: unexpected indentation in sequence`);
      }
      if (!(line.text === "-" || line.text.startsWith("- "))) break;

      const afterDash = line.text === "-" ? "" : line.text.slice(2).trim();
      index++;

      if (afterDash === "") {
        const next = lines[index];
        if (!next || next.indent <= seqIndent) {
          list.push(null);
        } else {
          list.push(parseBlock(next.indent));
        }
        continue;
      }

      // Check whether the inline content starts an object item ("- key: value").
      const looksLikeMapping = /^[A-Za-z0-9_-]+:(?:\s|$)/.test(afterDash);
      if (looksLikeMapping) {
        const item = {};
        const [key, rest] = splitKeyValue(afterDash, line.lineNo, filePath);
        if (rest === "") {
          const next = lines[index];
          item[key] = next && next.indent > seqIndent + 2 ? parseBlock(next.indent) : null;
        } else {
          item[key] = parseScalar(rest, line.lineNo, filePath);
        }

        const itemIndent = seqIndent + 2;
        while (index < lines.length && lines[index].indent >= itemIndent) {
          if (lines[index].indent > itemIndent) {
            throw new Error(`${filePath}:${lines[index].lineNo}: unexpected indentation inside sequence item`);
          }
          const sub = lines[index];
          const [subKey, subRest] = splitKeyValue(sub.text, sub.lineNo, filePath);
          if (Object.hasOwn(item, subKey)) {
            throw new Error(`${filePath}:${sub.lineNo}: duplicate key '${subKey}'`);
          }
          index++;
          if (subRest === "") {
            const next = lines[index];
            item[subKey] = next && next.indent > itemIndent ? parseBlock(next.indent) : null;
          } else {
            item[subKey] = parseScalar(subRest, sub.lineNo, filePath);
          }
        }
        list.push(item);
      } else {
        list.push(parseScalar(afterDash, line.lineNo, filePath));
      }
    }
    return list;
  }

  function parseMapping(mapIndent) {
    const obj = {};
    while (index < lines.length) {
      const line = lines[index];
      if (line.indent < mapIndent) break;
      if (line.indent > mapIndent) {
        throw new Error(`${filePath}:${line.lineNo}: unexpected indentation in mapping`);
      }
      if (line.text === "-" || line.text.startsWith("- ")) break;

      const [key, rest] = splitKeyValue(line.text, line.lineNo, filePath);
      if (Object.hasOwn(obj, key)) {
        throw new Error(`${filePath}:${line.lineNo}: duplicate key '${key}'`);
      }
      index++;

      if (rest === "") {
        const next = lines[index];
        obj[key] = next && next.indent > mapIndent ? parseBlock(next.indent) : null;
      } else {
        obj[key] = parseScalar(rest, line.lineNo, filePath);
      }
    }
    return obj;
  }

  const result = parseBlock(0);
  if (index !== lines.length) {
    const leftover = lines[index];
    throw new Error(`${filePath}:${leftover.lineNo}: trailing unparsed content`);
  }
  return result;
}

function validateAgainstSchema(value, schema, path, errors) {
  if (schema.type === "object") {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      errors.push(`${path}: expected object`);
      return;
    }

    const keys = Object.keys(value);

    if (typeof schema.minProperties === "number" && keys.length < schema.minProperties) {
      errors.push(`${path}: must have at least ${schema.minProperties} property`);
    }

    if (Array.isArray(schema.required)) {
      for (const req of schema.required) {
        if (!Object.hasOwn(value, req) || value[req] === null || value[req] === undefined) {
          errors.push(`${path}: missing required property '${req}'`);
        }
      }
    }

    if (schema.additionalProperties === false && schema.properties) {
      for (const key of keys) {
        if (!Object.hasOwn(schema.properties, key)) {
          errors.push(`${path}: unknown property '${key}'`);
        }
      }
    }

    if (Array.isArray(schema.anyOf)) {
      const anyMatched = schema.anyOf.some((branch) => {
        const branchErrors = [];
        validateAgainstSchema(value, { type: "object", ...branch }, path, branchErrors);
        return branchErrors.length === 0;
      });
      if (!anyMatched) {
        errors.push(`${path}: must satisfy at least one schema branch (categories and/or keywords)`);
      }
    }

    if (schema.properties) {
      for (const [key, propSchema] of Object.entries(schema.properties)) {
        if (Object.hasOwn(value, key) && value[key] !== undefined) {
          validateAgainstSchema(value[key], propSchema, `${path}.${key}`, errors);
        }
      }
    }
    return;
  }

  if (schema.type === "array") {
    if (!Array.isArray(value)) {
      errors.push(`${path}: expected array`);
      return;
    }
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      errors.push(`${path}: must have at least ${schema.minItems} item(s)`);
    }
    if (schema.uniqueItems) {
      const seen = new Set();
      for (const item of value) {
        const key = typeof item === "string" ? item.toLowerCase() : JSON.stringify(item);
        if (seen.has(key)) {
          errors.push(`${path}: duplicate item '${item}'`);
        }
        seen.add(key);
      }
    }
    if (schema.items) {
      value.forEach((item, idx) => {
        validateAgainstSchema(item, schema.items, `${path}[${idx}]`, errors);
      });
    }
    return;
  }

  if (schema.type === "string") {
    if (typeof value !== "string") {
      errors.push(`${path}: expected string`);
      return;
    }
    if (typeof schema.minLength === "number" && value.length < schema.minLength) {
      errors.push(`${path}: length ${value.length} is shorter than minimum ${schema.minLength}`);
    }
    if (typeof schema.maxLength === "number" && value.length > schema.maxLength) {
      errors.push(`${path}: length ${value.length} exceeds maximum ${schema.maxLength}`);
    }
    if (schema.pattern) {
      const re = new RegExp(schema.pattern);
      if (!re.test(value)) {
        errors.push(`${path}: value '${value}' does not match pattern ${schema.pattern}`);
      }
    }
    if (Array.isArray(schema.enum) && !schema.enum.includes(value)) {
      errors.push(`${path}: invalid value '${value}' (allowed: ${schema.enum.join(", ")})`);
    }
  }
}

function checkJudgmentalText(text, path, errors) {
  if (typeof text !== "string") return;
  const normalized = stripDiacritics(text);
  for (const term of FORBIDDEN_TERMS) {
    const re = new RegExp(`\\b${term}\\b`, "i");
    if (re.test(normalized)) {
      errors.push(`${path}: contains forbidden judgmental term '${term}'`);
    }
  }
}

function main() {
  let schema;
  try {
    schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
  } catch (err) {
    console.error(`Failed to read ${SCHEMA_PATH}: ${err.message}`);
    process.exit(1);
  }

  if (schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
    console.error("schema.json must declare JSON Schema Draft 2020-12.");
    process.exit(1);
  }

  const entries = readdirSync(PROFILES_DIR).sort();
  const yamlFiles = entries.filter((name) => {
    const ext = extname(name).toLowerCase();
    return ext === ".yaml" || ext === ".yml";
  });

  if (yamlFiles.length === 0) {
    console.error("No profile YAML files found in profiles/.");
    process.exit(1);
  }

  const errors = [];
  const seenProfileIds = new Map();
  const seenRuleIds = new Map();
  const groupsPresent = new Set();
  let totalRules = 0;

  for (const file of yamlFiles) {
    const fullPath = join(PROFILES_DIR, file);
    if (extname(file) !== ".yaml") {
      errors.push(`${file}: use the '.yaml' extension instead of '${extname(file)}'`);
    }

    let doc;
    try {
      doc = parseYaml(readFileSync(fullPath, "utf8"), file);
    } catch (err) {
      errors.push(err.message);
      continue;
    }

    validateAgainstSchema(doc, schema, file, errors);

    if (doc && typeof doc === "object") {
      const expectedId = basename(file, extname(file));
      if (typeof doc.id === "string") {
        if (doc.id !== expectedId) {
          errors.push(`${file}: profile id '${doc.id}' must match filename '${expectedId}'`);
        }
        if (seenProfileIds.has(doc.id)) {
          errors.push(`${file}: duplicate profile id '${doc.id}' (already defined in ${seenProfileIds.get(doc.id)})`);
        } else {
          seenProfileIds.set(doc.id, file);
        }
      }

      if (typeof doc.group === "string") {
        groupsPresent.add(doc.group);
      }

      checkJudgmentalText(doc.label, `${file}.label`, errors);
      checkJudgmentalText(doc.description, `${file}.description`, errors);

      if (Array.isArray(doc.rules)) {
        totalRules += doc.rules.length;
        doc.rules.forEach((rule, idx) => {
          if (!rule || typeof rule !== "object") return;
          if (typeof rule.id === "string") {
            if (seenRuleIds.has(rule.id)) {
              errors.push(
                `${file}.rules[${idx}]: duplicate rule id '${rule.id}' (already defined in ${seenRuleIds.get(rule.id)})`
              );
            } else {
              seenRuleIds.set(rule.id, file);
            }
          }
          checkJudgmentalText(rule.name, `${file}.rules[${idx}].name`, errors);
          checkJudgmentalText(rule.explanation, `${file}.rules[${idx}].explanation`, errors);
          checkJudgmentalText(rule.brand, `${file}.rules[${idx}].brand`, errors);
        });
      }
    }
  }

  for (const requiredGroup of schema.properties.group.enum) {
    if (!groupsPresent.has(requiredGroup)) {
      errors.push(`profiles/: missing at least one profile for group '${requiredGroup}'`);
    }
  }

  if (errors.length > 0) {
    console.error(`Profile validation failed with ${errors.length} error(s):`);
    for (const msg of errors) {
      console.error(`  - ${msg}`);
    }
    process.exit(1);
  }

  console.log(
    `OK: ${yamlFiles.length} profiles (${totalRules} rules) validated against profiles/schema.json.`
  );
}

main();
