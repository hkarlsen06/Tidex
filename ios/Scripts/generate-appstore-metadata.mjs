#!/usr/bin/env node

/**
 * App Store Metadata Generator
 *
 * Generates localized .txt files for Fastlane deliver from a structured JSON source.
 * Reads supported locales from the Xcode project file (knownRegions).
 * For source locales (en, nb), writes directly from the source JSON.
 * For other locales, translates in parallel using Claude API.
 *
 * Usage:
 *   node generate-appstore-metadata.mjs                  # Generate all metadata
 *   node generate-appstore-metadata.mjs --validate-only  # Only validate, don't write
 *   node generate-appstore-metadata.mjs --source-only    # Only write source locales
 *   node generate-appstore-metadata.mjs --force          # Re-translate even if files exist
 */

import Anthropic from "@anthropic-ai/sdk";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import { config } from "dotenv";
import cliProgress from "cli-progress";
import pLimit from "p-limit";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load env from next/.env.local
config({ path: path.join(__dirname, "../../next/.env.local") });

// Paths
const XCODE_PROJECT_PATH = path.join(__dirname, "../Tidex.xcodeproj/project.pbxproj");
const METADATA_SOURCE_PATH = path.join(__dirname, "appstore-metadata-source.json");
const METADATA_OUTPUT_PATH = path.join(__dirname, "../fastlane/metadata");

// Parse command line args
const args = process.argv.slice(2);
const validateOnly = args.includes("--validate-only");
const sourceOnly = args.includes("--source-only");
const forceRegenerate = args.includes("--force");

// Source locales (manually maintained, not translated)
const SOURCE_LOCALES = ["en", "nb"];
const PRIMARY_LOCALE = "en";

// App Store Connect folder name mapping
// Maps Xcode locale codes to Fastlane/ASC folder names
const ASC_FOLDER_MAP = {
  en: "en-US",
  "en-GB": "en-GB",
  nb: "no",
  nn: "no",
  de: "de-DE",
  fr: "fr-FR",
  es: "es-ES",
  "es-MX": "es-MX",
  it: "it",
  nl: "nl-NL",
  "pt-BR": "pt-BR",
  sv: "sv",
  da: "da",
  fi: "fi",
  pl: "pl",
  ru: "ru",
  uk: "uk",
  tr: "tr",
  el: "el",
  ro: "ro",
  ja: "ja",
  ko: "ko",
  "zh-Hans": "zh-Hans",
  "zh-Hant": "zh-Hant",
  th: "th",
  vi: "vi",
  ca: "ca",
  cs: "cs",
  hr: "hr",
  hu: "hu",
  id: "id",
  he: "he",
  hi: "hi",
  sk: "sk",
  ar: "ar-SA",
  Base: null, // Skip Base locale
  // No ASC equivalent: is, et, lv, lt, sl, bg, sr, fa, ur, bn, ta, fil, sw
};

// Fields that get translated — name is handled separately (see NAME_TAKEN_LOCALES)
// Stable fields are only translated once; --force does not re-translate them
const STABLE_FIELDS = ["subtitle", "promotional_text"];
const RELEASE_FIELDS = ["description", "keywords", "release_notes"];
const TRANSLATED_FIELDS = [...STABLE_FIELDS, ...RELEASE_FIELDS];

// Translated locales where "Tidex" is already claimed on the App Store.
// These get a translated name with a descriptive suffix; all others get "Tidex".
// (en-US and sv have "Tidex" taken; en-US is a source locale so only sv is listed here)
const NAME_TAKEN_LOCALES = new Set(["sv"]);

// Language names for translation prompts
const LANGUAGE_NAMES = {
  de: "German",
  fr: "French",
  es: "Spanish (Spain)",
  "es-MX": "Spanish (Mexico)",
  "en-GB": "British English",
  it: "Italian",
  nl: "Dutch",
  "pt-BR": "Brazilian Portuguese",
  nn: "Norwegian Nynorsk",
  sv: "Swedish",
  da: "Danish",
  fi: "Finnish",
  pl: "Polish",
  ru: "Russian",
  uk: "Ukrainian",
  tr: "Turkish",
  el: "Greek",
  ro: "Romanian",
  ja: "Japanese",
  ko: "Korean",
  "zh-Hans": "Simplified Chinese",
  "zh-Hant": "Traditional Chinese",
  th: "Thai",
  vi: "Vietnamese",
  ca: "Catalan",
  cs: "Czech",
  hr: "Croatian",
  hu: "Hungarian",
  id: "Indonesian",
  he: "Hebrew",
  hi: "Hindi",
  sk: "Slovak",
  ar: "Arabic",
};

// App Store metadata field constraints
const FIELD_LIMITS = {
  name: 30,
  subtitle: 30,
  promotional_text: 170,
  description: 4000,
  keywords: 100,
  release_notes: 4000,
};

const FIELDS = ["name", "subtitle", "promotional_text", "description", "keywords", "release_notes"];

// Concurrency settings
const CONCURRENCY = 10;

// Stats tracking
const stats = {
  translated: 0,
  skipped: 0,
  errors: [],
};

// Track state for graceful shutdown
let isShuttingDown = false;
let currentMultibar = null;

// Graceful shutdown handler
async function handleShutdown() {
  if (isShuttingDown) return;
  isShuttingDown = true;

  if (currentMultibar) {
    currentMultibar.stop();
  }

  console.log("\n\n⚠ Interrupt received. Partial progress has been saved.");
  console.log("Run the script again to continue.\n");
  process.exit(0);
}

process.on("SIGINT", handleShutdown);
process.on("SIGTERM", handleShutdown);

/**
 * Read supported locales from Xcode project's knownRegions
 */
async function readProjectLocales() {
  const content = await fs.readFile(XCODE_PROJECT_PATH, "utf-8");

  const match = content.match(/knownRegions\s*=\s*\(\s*([\s\S]*?)\s*\);/);
  if (!match) {
    throw new Error("Could not find knownRegions in project.pbxproj");
  }

  const regions = match[1]
    .split(",")
    .map((r) => r.trim().replace(/"/g, ""))
    .filter((r) => r.length > 0 && r !== "Base");

  return regions;
}

/**
 * Validate metadata field lengths
 */
function validateMetadata(metadata, locale, fields = FIELDS) {
  const errors = [];

  for (const field of fields) {
    const value = metadata[field];
    const limit = FIELD_LIMITS[field];

    if (!value && value !== "") {
      errors.push(`[${locale}] Missing required field: ${field}`);
      continue;
    }

    if (value.length > limit) {
      errors.push(
        `[${locale}] ${field} exceeds limit: ${value.length}/${limit} characters`
      );
    }
  }

  return errors;
}

/**
 * Read existing translated field values from disk for a locale
 */
async function readExistingFields(folderName, fields) {
  const localeDir = path.join(METADATA_OUTPUT_PATH, folderName);
  const existing = {};

  for (const field of fields) {
    try {
      const content = await fs.readFile(path.join(localeDir, `${field}.txt`), "utf-8");
      existing[field] = content.trim();
    } catch {
      // Field doesn't exist yet
    }
  }

  return existing;
}

/**
 * Write metadata files for a locale
 * Only writes fields present in the metadata object (skips missing keys)
 */
async function writeMetadataFiles(folderName, metadata) {
  const localeDir = path.join(METADATA_OUTPUT_PATH, folderName);

  await fs.mkdir(localeDir, { recursive: true });

  for (const field of FIELDS) {
    if (!(field in metadata)) continue;
    const filePath = path.join(localeDir, `${field}.txt`);
    const content = metadata[field] || "";
    await fs.writeFile(filePath, content + "\n", "utf-8");
  }
}

/**
 * Retry with exponential backoff
 */
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
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

/**
 * Extract JSON from potentially messy response
 */
function extractJson(text) {
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");

  if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
    throw new Error("No valid JSON object found in response");
  }

  let jsonText = text.slice(firstBrace, lastBrace + 1);

  try {
    return JSON.parse(jsonText);
  } catch {
    // Try fixing common issues
    jsonText = jsonText
      .replace(/[\u201C\u201D]/g, '"')
      .replace(/[\u2018\u2019]/g, "'")
      .replace(/,(\s*[}\]])/g, "$1");

    return JSON.parse(jsonText);
  }
}

/**
 * Translate metadata using Claude API
 */
async function translateMetadata(sourceMetadata, norwegianMetadata, targetLocale, languageName, client, fields = TRANSLATED_FIELDS) {
  // Build source/reference objects with only the requested fields
  const sourceFields = Object.fromEntries(fields.map((f) => [f, sourceMetadata[f]]));
  const referenceFields = Object.fromEntries(fields.map((f) => [f, norwegianMetadata[f]]));

  const limitRules = [];
  if (fields.includes("subtitle")) limitRules.push("subtitle (30)");
  if (fields.includes("promotional_text")) limitRules.push("promotional_text (170)");
  if (fields.includes("keywords")) limitRules.push("keywords (100)");
  const limitText = limitRules.length > 0 ? `\n4. Respect character limits: ${limitRules.join(", ")}` : "";

  const prompt = `You are a professional translator for a work shift tracking app called "Tidex".
Translate the following App Store metadata to ${languageName}.

CRITICAL RULES:
1. Maintain the same structure and formatting (bullet points, line breaks)
2. Keep keywords comma-separated WITHOUT spaces after commas
3. Make translations natural and idiomatic for ${languageName} speakers${limitText}

Source metadata (English):
${JSON.stringify(sourceFields, null, 2)}

Reference translation (Norwegian Bokmål) - use this to understand intended meaning:
${JSON.stringify(referenceFields, null, 2)}

Return ONLY a valid JSON object with these exact keys: ${fields.join(", ")}
No markdown, no explanation, just the JSON object.`;

  // Retry the full translate+parse cycle since JSON parse failures are non-deterministic
  const maxAttempts = 3;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await withRetry(() =>
      client.messages.create({
        model: "claude-sonnet-4-5",
        max_tokens: 2000,
        messages: [{ role: "user", content: prompt }],
      })
    );

    try {
      return extractJson(response.content[0].text.trim());
    } catch (parseError) {
      if (attempt === maxAttempts - 1) throw parseError;
    }
  }
}

/**
 * Validate character limits and throw error if exceeded
 */
function enforceCharacterLimits(metadata, locale) {
  const errors = [];

  if (metadata.subtitle && metadata.subtitle.length > FIELD_LIMITS.subtitle) {
    errors.push(`subtitle is ${metadata.subtitle.length}/${FIELD_LIMITS.subtitle} chars: "${metadata.subtitle}"`);
  }

  if (metadata.keywords && metadata.keywords.length > FIELD_LIMITS.keywords) {
    errors.push(`keywords is ${metadata.keywords.length}/${FIELD_LIMITS.keywords} chars`);
  }

  if (errors.length > 0) {
    throw new Error(`[${locale}] Character limits exceeded:\n  - ${errors.join("\n  - ")}`);
  }

  return metadata;
}

/**
 * Process a single locale translation
 */
async function processLocale(locale, folderName, sourceMetadata, norwegianMetadata, client) {
  if (isShuttingDown) return { status: "skipped", locale };

  const languageName = LANGUAGE_NAMES[locale];
  if (!languageName) {
    return { status: "error", locale, error: `Unknown language: ${locale}` };
  }

  const existingFields = await readExistingFields(folderName, TRANSLATED_FIELDS);
  const missingFields = TRANSLATED_FIELDS.filter((f) => !(f in existingFields));

  // Skip if all fields exist (unless --force)
  if (!forceRegenerate && missingFields.length === 0) {
    stats.skipped++;
    return { status: "exists", locale };
  }

  try {
    // Determine which fields need translation:
    // --force: re-translate release fields + any missing stable fields
    // normal:  only translate missing fields
    const fieldsToTranslate = forceRegenerate
      ? [...RELEASE_FIELDS, ...STABLE_FIELDS.filter((f) => !(f in existingFields))]
      : missingFields;

    let translated = {};
    if (fieldsToTranslate.length > 0) {
      translated = await translateMetadata(
        sourceMetadata,
        norwegianMetadata,
        locale,
        languageName,
        client,
        fieldsToTranslate
      );
    }

    // Merge: preserve existing fields, overlay new translations
    translated = { ...existingFields, ...translated };

    // Enforce character limits
    translated = enforceCharacterLimits(translated, locale);

    // Set app name — use "Tidex" unless it's taken on this locale's App Store
    if (NAME_TAKEN_LOCALES.has(locale)) {
      try {
        const existing = await fs.readFile(
          path.join(METADATA_OUTPUT_PATH, folderName, "name.txt"), "utf-8"
        );
        translated.name = existing.trim();
      } catch {
        const nameResult = await translateMetadata(
          sourceMetadata, norwegianMetadata, locale, languageName, client, ["name"]
        );
        translated.name = nameResult.name;
      }
    } else {
      translated.name = "Tidex";
    }

    // Validate (should pass now after enforcement)
    const errors = validateMetadata(translated, locale, TRANSLATED_FIELDS);
    if (errors.length > 0) {
      stats.errors.push(...errors.map((e) => `Warning: ${e}`));
    }

    await writeMetadataFiles(folderName, translated);
    stats.translated++;
    return { status: "success", locale };
  } catch (error) {
    stats.errors.push(`${locale}: ${error.message}`);
    return { status: "error", locale, error: error.message };
  }
}

async function main() {
  console.log("App Store Metadata Generator");
  console.log("============================\n");

  // Read project locales
  console.log("Reading locales from Xcode project...");
  const projectLocales = await readProjectLocales();
  console.log(`Found ${projectLocales.length} locales: ${projectLocales.join(", ")}\n`);

  // Load source metadata
  const sourceData = JSON.parse(await fs.readFile(METADATA_SOURCE_PATH, "utf-8"));
  const { metadata } = sourceData;

  // Validate source metadata
  console.log("Validating source metadata...");
  const allErrors = [];

  for (const locale of SOURCE_LOCALES) {
    if (metadata[locale]) {
      const errors = validateMetadata(metadata[locale], locale);
      allErrors.push(...errors);
    } else {
      allErrors.push(`Missing source metadata for locale: ${locale}`);
    }
  }

  if (allErrors.length > 0) {
    console.error("\n❌ Validation errors:");
    allErrors.forEach((e) => console.error(`  - ${e}`));
    process.exit(1);
  }

  console.log("✓ Source metadata validation passed\n");

  if (validateOnly) {
    console.log("Validation only mode - skipping file generation");
    return;
  }

  // Write source locale metadata
  console.log("Writing source locale metadata...");
  for (const locale of SOURCE_LOCALES) {
    const folderName = ASC_FOLDER_MAP[locale];
    if (folderName && metadata[locale]) {
      await writeMetadataFiles(folderName, metadata[locale]);
      console.log(`  ✓ ${folderName}`);
    }
  }

  if (sourceOnly) {
    console.log("\n✓ Source-only mode complete");
    return;
  }

  // Check for Claude API key
  const apiKey = process.env.CLAUDE_API_KEY;
  if (!apiKey) {
    console.log("\n⚠ CLAUDE_API_KEY not set - skipping translations");
    console.log("  Set CLAUDE_API_KEY in next/.env.local to enable translations");
    return;
  }

  // Initialize client
  const client = new Anthropic({ apiKey });

  // Collect ASC folders already written by source locales
  const sourceFolders = new Set(
    SOURCE_LOCALES.map((l) => ASC_FOLDER_MAP[l]).filter(Boolean)
  );

  // Filter locales that need translation
  const localesToTranslate = projectLocales.filter((locale) => {
    // Skip source locales
    if (SOURCE_LOCALES.includes(locale)) return false;
    // Skip locales without ASC mapping
    if (!ASC_FOLDER_MAP[locale]) return false;
    // Skip if folder name is null (e.g., Base)
    if (ASC_FOLDER_MAP[locale] === null) return false;
    // Skip if ASC folder is already covered by a source locale (e.g., nn → "no" already written by nb)
    if (sourceFolders.has(ASC_FOLDER_MAP[locale])) return false;
    return true;
  });

  if (localesToTranslate.length === 0) {
    console.log("\n✓ No additional locales to translate");
    return;
  }

  console.log(`\nTranslating to ${localesToTranslate.length} locales...`);

  // Create progress bar
  const multibar = (currentMultibar = new cliProgress.MultiBar(
    {
      clearOnComplete: false,
      hideCursor: true,
      format: " {bar} | {label} | {value}/{total} | {status}",
      barCompleteChar: "\u2588",
      barIncompleteChar: "\u2591",
    },
    cliProgress.Presets.shades_classic
  ));

  const progressBar = multibar.create(localesToTranslate.length, 0, {
    label: "Progress".padEnd(12),
    status: "starting...",
  });

  // Process in parallel with concurrency limit
  const limit = pLimit(CONCURRENCY);
  let completed = 0;

  const promises = localesToTranslate.map((locale) =>
    limit(async () => {
      if (isShuttingDown) return;

      const folderName = ASC_FOLDER_MAP[locale];
      const result = await processLocale(
        locale,
        folderName,
        metadata[PRIMARY_LOCALE],
        metadata.nb,
        client
      );

      completed++;
      const statusText =
        result.status === "success"
          ? `✓ ${locale}`
          : result.status === "exists"
            ? `⊘ ${locale} (exists)`
            : `✗ ${locale}`;

      progressBar.update(completed, {
        status: statusText,
      });

      return result;
    })
  );

  await Promise.all(promises);

  // Cleanup
  multibar.stop();
  currentMultibar = null;

  // Summary
  console.log("\n" + "=".repeat(40));
  console.log("SUMMARY");
  console.log("=".repeat(40));
  console.log(`✓ Translated: ${stats.translated}`);
  console.log(`⊘ Skipped (existing): ${stats.skipped}`);

  if (stats.errors.length > 0) {
    console.log(`\n⚠ Warnings/Errors (${stats.errors.length}):`);
    stats.errors.slice(0, 10).forEach((e) => console.log(`  - ${e}`));
    if (stats.errors.length > 10) {
      console.log(`  ... and ${stats.errors.length - 10} more`);
    }
  }

  console.log("\n✓ Done!");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
