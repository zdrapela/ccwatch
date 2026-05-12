#!/usr/bin/env bun
/**
 * Reads cli/src/types.ts and generates
 * bar/Sources/CCWatchBar/Models.swift
 *
 * Usage: bun scripts/generate-models.ts   (from repo root)
 */

import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";

const ROOT = dirname(new URL(import.meta.url).pathname);
const TYPES_PATH = join(ROOT, "../cli/src/types.ts");
const OUTPUT_PATH = join(
  ROOT,
  "../bar/Sources/CCWatchBar/Models.swift",
);

const src = readFileSync(TYPES_PATH, "utf-8");

// --- Extract SessionState union values ---
const stateMatch = src.match(
  /export\s+type\s+SessionState\s*=\s*([^;]+);/,
);
if (!stateMatch) {
  console.error("Could not find SessionState type in types.ts");
  process.exit(1);
}

const stateValues = [...stateMatch[1].matchAll(/"([^"]+)"/g)].map(
  (m) => m[1],
);

// --- Extract Provider union values ---
const providerMatch = src.match(
  /export\s+type\s+Provider\s*=\s*([^;]+);/,
);
const providerValues = providerMatch
  ? [...providerMatch[1].matchAll(/"([^"]+)"/g)].map((m) => m[1])
  : [];

// --- Extract Session interface fields ---
const sessionMatch = src.match(
  /export\s+interface\s+Session\s*\{([^}]+)\}/,
);
if (!sessionMatch) {
  console.error("Could not find Session interface in types.ts");
  process.exit(1);
}

interface Field {
  name: string;
  tsType: string;
  optional: boolean;
}

const fields: Field[] = [];
for (const line of sessionMatch[1].split("\n")) {
  const m = line.match(/^\s*(\w+)(\??)\s*:\s*(.+?)\s*;/);
  if (!m) continue;
  fields.push({ name: m[1], tsType: m[3], optional: m[2] === "?" });
}

// --- Helpers ---

// Fields that should map to Int instead of Double
const intFields = new Set(["pid"]);

function tsTypeToSwift(name: string, tsType: string, optional: boolean): string {
  let base: string;
  switch (tsType) {
    case "string":
      base = "String";
      break;
    case "number":
      base = intFields.has(name) ? "Int" : "Double";
      break;
    case "boolean":
      base = "Bool";
      break;
    case "SessionState":
      base = "SessionState";
      break;
    case "Provider":
      base = "Provider";
      break;
    default:
      console.error(`Unknown TypeScript type "${tsType}", defaulting to String`);
      base = "String";
  }
  return optional ? `${base}?` : base;
}

function toCamelCase(raw: string): string {
  // "waiting:permission" → "waitingPermission"
  return raw.replace(/[^a-zA-Z0-9]+(.)/g, (_, c) => c.toUpperCase());
}

// --- Generate Swift ---

const lines: string[] = [];

lines.push("// Generated from cli/src/types.ts — do not edit manually.");
lines.push("// Run: bun generate-models.ts");
lines.push("");
lines.push("import Foundation");
lines.push("");

// SessionState enum
lines.push("enum SessionState: String, Codable {");
for (const val of stateValues) {
  lines.push(`    case ${toCamelCase(val)} = "${val}"`);
}
lines.push("}");
lines.push("");

// Provider enum
if (providerValues.length > 0) {
  lines.push("enum Provider: String, Codable {");
  for (const val of providerValues) {
    lines.push(`    case ${toCamelCase(val)} = "${val}"`);
  }
  lines.push("}");
  lines.push("");
}

// Session struct
lines.push("struct Session: Codable, Identifiable {");
lines.push("    var id: String { sessionId }");
lines.push("");

for (const f of fields) {
  const swiftType = tsTypeToSwift(f.name, f.tsType, f.optional);
  const keyword = f.name === "sessionId" ? "let" : "var";
  lines.push(`    ${keyword} ${f.name}: ${swiftType}`);
}

lines.push("}");
lines.push("");

const output = lines.join("\n");
writeFileSync(OUTPUT_PATH, output);
console.log(`Generated ${OUTPUT_PATH}`);
