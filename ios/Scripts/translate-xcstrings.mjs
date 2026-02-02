#!/usr/bin/env node

import Anthropic from "@anthropic-ai/sdk";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import { config } from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load env properly with dotenv
config({ path: path.join(__dirname, "../../next/.env.local") });

const client = new Anthropic({ apiKey: process.env.CLAUDE_API_KEY });

const TARGET_LANGUAGES = [
  { code: "de", name: "German" },
  { code: "nb", name: "Norwegian Bokmål" },
  { code: "es", name: "Spanish" },
  { code: "fr", name: "French" },
  { code: "ja", name: "Japanese" },
  { code: "ko", name: "Korean" },
  { code: "pt-BR", name: "Brazilian Portuguese" },
  { code: "ru", name: "Russian" },
  { code: "nl", name: "Dutch" },
  { code: "sv", name: "Swedish" },
  { code: "da", name: "Danish" },
];

// Stats for reporting
const stats = {
  translated: 0,
  skippedFormatMismatch: 0,
  skippedNoTranslation: 0,
  errors: [],
};

// Extract all format specifiers from a string
function extractFormatSpecifiers(str) {
  // Match all iOS/Mac format specifiers including %@, %d, %lld, %ld, %zd, %tu, %1$@, %.2f, etc.
  const regex = /%(\d+\$)?[-+0 #]*(\d+|\*)?(\.\d+|\.\*)?([hlLzjt]{0,2})?[@diouxXeEfFgGaAcspn%]/g;
  return (str.match(regex) || []).sort();
}

// Verify format specifiers match between original and translation
function validateFormatSpecifiers(original, translation) {
  const originalSpecs = extractFormatSpecifiers(original);
  const translationSpecs = extractFormatSpecifiers(translation);

  if (originalSpecs.length !== translationSpecs.length) return false;

  for (let i = 0; i < originalSpecs.length; i++) {
    if (originalSpecs[i] !== translationSpecs[i]) return false;
  }
  return true;
}

// Strings that shouldn't be translated
function shouldSkipString(key, englishValue) {
  if (!englishValue) return true;
  if (englishValue.trim() === "") return true;

  // Skip internal identifiers (SCREAMING_SNAKE_CASE or camelCase.dotted.keys without spaces)
  if (/^[A-Z][A-Z0-9_]+$/.test(key) && key === englishValue) return true;

  // Skip if it's ONLY symbols, numbers, or format specifiers (no letters at all)
  const stripped = englishValue
    .replace(/%(\d+\$)?[-+0 #]*(\d+|\*)?(\.\d+|\.\*)?([hlLzjt]{0,2})?[@diouxXeEfFgGaAcspn%]/g, "")
    .replace(/[^a-zA-Z]/g, "");

  if (stripped.length === 0) return true;

  return false;
}

// Retry with exponential backoff
async function withRetry(fn, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      const isRetryable = error.status === 429 || error.status >= 500;
      if (!isRetryable || attempt === maxRetries - 1) {
        throw error;
      }
      const delay = Math.pow(2, attempt) * 1000 + Math.random() * 1000;
      console.log(`    Rate limited, retrying in ${Math.round(delay / 1000)}s...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

// Extract JSON from potentially messy response
function extractJson(text) {
  // Try to find JSON object boundaries
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");

  if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
    throw new Error("No valid JSON object found in response");
  }

  let jsonText = text.slice(firstBrace, lastBrace + 1);

  // Fix common issues
  jsonText = jsonText
    .replace(/,(\s*[}\]])/g, "$1") // Remove trailing commas
    .replace(/[\u201C\u201D]/g, '"') // Replace smart quotes
    .replace(/[\u2018\u2019]/g, "'"); // Replace smart single quotes

  return JSON.parse(jsonText);
}

// Translate a batch using KEY-BASED mapping to avoid context collision
async function translateBatch(items, targetLang) {
  // Build context-aware prompt with keys
  const stringsToTranslate = items.map((item) => ({
    id: item.id,
    english: item.english,
    context: item.key, // Include key as context hint
  }));

  const prompt = `You are a professional translator for a work shift tracking app called "Tidex".
Translate the following strings from English to ${targetLang.name}.

CRITICAL RULES - FOLLOW EXACTLY:
1. PRESERVE ALL FORMAT SPECIFIERS EXACTLY AS THEY APPEAR:
   - %@ stays as %@
   - %lld stays as %lld (NOT %d)
   - %ld stays as %ld
   - %1$@ stays as %1$@
   - %d stays as %d
   - %.2f stays as %.2f
   - DO NOT change any format specifier types!
2. Keep translations concise (mobile UI has limited space)
3. Preserve leading/trailing whitespace exactly
4. The "context" field hints at usage - use it to disambiguate meanings
5. Return a JSON object mapping each "id" to its translation

Strings to translate:
${JSON.stringify(stringsToTranslate, null, 2)}

Return format (JSON only, no markdown, no explanation):
{"id1": "translation1", "id2": "translation2", ...}`;

  const response = await withRetry(() =>
    client.messages.create({
      model: "claude-haiku-4-5",
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }],
    })
  );

  const text = response.content[0].text.trim();
  return extractJson(text);
}

// Deep-set a value at a path without overwriting siblings
function deepSet(obj, path, value) {
  let current = obj;
  for (let i = 0; i < path.length - 1; i++) {
    const key = path[i];
    if (!current[key] || typeof current[key] !== "object") {
      current[key] = {};
    }
    current = current[key];
  }
  current[path[path.length - 1]] = value;
}

async function translateXcstrings(filePath) {
  console.log(`\nProcessing: ${filePath}`);

  const content = await fs.readFile(filePath, "utf-8");
  const data = JSON.parse(content);

  // Collect ALL strings that need translation with unique IDs
  const stringsToTranslate = [];
  let idCounter = 0;

  for (const [key, value] of Object.entries(data.strings)) {
    // Check for simple stringUnit
    const enStringUnit = value.localizations?.en?.stringUnit;
    if (enStringUnit?.value) {
      const englishValue = enStringUnit.value;

      for (const targetLang of TARGET_LANGUAGES) {
        const hasTranslation =
          value.localizations?.[targetLang.code]?.stringUnit?.value;
        if (!hasTranslation && !shouldSkipString(key, englishValue)) {
          stringsToTranslate.push({
            id: `s${idCounter++}`,
            key,
            english: englishValue,
            targetLang,
            type: "simple",
          });
        }
      }
    }

    // Check for plural variations
    const enVariations = value.localizations?.en?.variations?.plural;
    if (enVariations) {
      for (const [pluralForm, pluralData] of Object.entries(enVariations)) {
        const englishValue = pluralData.stringUnit?.value;
        if (!englishValue) continue;

        for (const targetLang of TARGET_LANGUAGES) {
          const hasTranslation =
            value.localizations?.[targetLang.code]?.variations?.plural?.[
              pluralForm
            ]?.stringUnit?.value;
          if (!hasTranslation && !shouldSkipString(key, englishValue)) {
            stringsToTranslate.push({
              id: `s${idCounter++}`,
              key,
              english: englishValue,
              targetLang,
              type: "plural",
              pluralForm,
            });
          }
        }
      }
    }
  }

  console.log(`Found ${stringsToTranslate.length} strings needing translation`);

  if (stringsToTranslate.length === 0) {
    console.log("Nothing to translate!");
    return;
  }

  // Process by language for clearer progress
  const BATCH_SIZE = 75;

  for (const targetLang of TARGET_LANGUAGES) {
    const stringsForLang = stringsToTranslate.filter(
      (s) => s.targetLang.code === targetLang.code
    );

    if (stringsForLang.length === 0) {
      continue;
    }

    console.log(
      `\nTranslating ${stringsForLang.length} strings to ${targetLang.name}...`
    );

    let translatedThisLang = 0;
    let skippedThisLang = 0;

    for (let i = 0; i < stringsForLang.length; i += BATCH_SIZE) {
      const batch = stringsForLang.slice(i, i + BATCH_SIZE);

      try {
        const translations = await translateBatch(batch, targetLang);

        // Apply translations using ID mapping
        for (const item of batch) {
          const translation = translations[item.id];

          if (!translation) {
            stats.skippedNoTranslation++;
            continue;
          }

          // Validate format specifiers
          if (!validateFormatSpecifiers(item.english, translation)) {
            console.warn(
              `    ⚠ Format mismatch: "${item.english}" → "${translation}"`
            );
            stats.skippedFormatMismatch++;
            skippedThisLang++;
            continue;
          }

          // Apply translation using deep-set to preserve existing metadata
          if (item.type === "simple") {
            deepSet(
              data.strings[item.key],
              ["localizations", targetLang.code, "stringUnit"],
              { state: "translated", value: translation }
            );
          } else if (item.type === "plural") {
            deepSet(
              data.strings[item.key],
              [
                "localizations",
                targetLang.code,
                "variations",
                "plural",
                item.pluralForm,
                "stringUnit",
              ],
              { state: "translated", value: translation }
            );
          }

          translatedThisLang++;
          stats.translated++;
        }

        const batchNum = Math.floor(i / BATCH_SIZE) + 1;
        const totalBatches = Math.ceil(stringsForLang.length / BATCH_SIZE);
        console.log(
          `  Batch ${batchNum}/${totalBatches}: +${translatedThisLang} translated`
        );

        // Small delay between batches
        await new Promise((r) => setTimeout(r, 300));
      } catch (error) {
        const errorMsg = `Batch error for ${targetLang.name}: ${error.message}`;
        console.error(`  ✗ ${errorMsg}`);
        stats.errors.push(errorMsg);
      }
    }

    console.log(
      `  ✓ ${targetLang.name}: ${translatedThisLang} translated${skippedThisLang ? `, ${skippedThisLang} skipped` : ""}`
    );
  }

  // Write back
  await fs.writeFile(filePath, JSON.stringify(data, null, 2) + "\n");
  console.log(`\nSaved: ${filePath}`);
}

// Main
const xcstringsFiles = [
  path.join(__dirname, "../Resources/Localization/App/Localizable.xcstrings"),
  path.join(__dirname, "../Resources/Localization/Watch/Localizable.xcstrings"),
  path.join(__dirname, "../Resources/Localization/Widget/Localizable.xcstrings"),
];

console.log("XCStrings Translator v2");
console.log("=======================");
console.log(`Target languages: ${TARGET_LANGUAGES.map((l) => l.name).join(", ")}`);

for (const file of xcstringsFiles) {
  try {
    await translateXcstrings(file);
  } catch (error) {
    console.error(`Error processing ${file}: ${error.message}`);
    stats.errors.push(`File error: ${error.message}`);
  }
}

// Print summary
console.log("\n" + "=".repeat(40));
console.log("SUMMARY");
console.log("=".repeat(40));
console.log(`✓ Translated: ${stats.translated}`);
if (stats.skippedFormatMismatch > 0) {
  console.log(`⚠ Skipped (format mismatch): ${stats.skippedFormatMismatch}`);
}
if (stats.skippedNoTranslation > 0) {
  console.log(`⚠ Skipped (no translation): ${stats.skippedNoTranslation}`);
}
if (stats.errors.length > 0) {
  console.log(`✗ Errors: ${stats.errors.length}`);
  stats.errors.forEach((e) => console.log(`  - ${e}`));
}

// Exit with error code if any failures
if (stats.errors.length > 0) {
  process.exit(1);
}

console.log("\n✓ Done!");
