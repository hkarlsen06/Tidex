#!/usr/bin/env bun

import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import { randomUUID } from "node:crypto";
import { config } from "dotenv";
import cliProgress from "cli-progress";
import pLimit from "p-limit";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load env properly with dotenv
config({ path: path.join(__dirname, "../../.env.local"), quiet: true });

const OPENAI_RESPONSES_API_URL = "https://api.openai.com/v1/responses";
const OPENAI_MODEL = process.env.OPENAI_MODEL?.trim() || "gpt-5.6-luna";
const OPENAI_REASONING_EFFORT = process.env.OPENAI_REASONING_EFFORT?.trim() || "high";
const REQUEST_TIMEOUT_MS = 120_000;
const MAX_OUTPUT_TOKENS = 16_384;
const BATCH_SIZE = 30;
const CONCURRENCY = 6;

const TARGET_LANGUAGES = [
  // Western Europe
  { code: "de", name: "German" },
  { code: "fr", name: "French" },
  { code: "es", name: "Spanish" },
  { code: "it", name: "Italian" },
  { code: "nl", name: "Dutch" },
  { code: "pt-BR", name: "Brazilian Portuguese" },
  { code: "ca", name: "Catalan" },

  // Nordic
  { code: "nb", name: "Norwegian Bokmål" },
  { code: "nn", name: "Norwegian Nynorsk" },
  { code: "sv", name: "Swedish" },
  { code: "da", name: "Danish" },
  { code: "fi", name: "Finnish" },
  { code: "is", name: "Icelandic" },

  // Baltic
  { code: "et", name: "Estonian" },
  { code: "lv", name: "Latvian" },
  { code: "lt", name: "Lithuanian" },

  // Central Europe
  { code: "hu", name: "Hungarian" },
  { code: "cs", name: "Czech" },
  { code: "sk", name: "Slovak" },
  { code: "sl", name: "Slovenian" },

  // Eastern Europe
  { code: "pl", name: "Polish" },
  { code: "ru", name: "Russian" },
  { code: "uk", name: "Ukrainian" },
  { code: "ro", name: "Romanian" },
  { code: "bg", name: "Bulgarian" },

  // Balkans
  { code: "hr", name: "Croatian" },
  { code: "sr", name: "Serbian" },
  { code: "el", name: "Greek" },
  { code: "tr", name: "Turkish" },

  // Middle East & RTL languages
  { code: "ar", name: "Arabic" },
  { code: "he", name: "Hebrew" },
  { code: "fa", name: "Persian" },
  { code: "ur", name: "Urdu" },

  // South Asia
  { code: "hi", name: "Hindi" },
  { code: "bn", name: "Bengali" },
  { code: "ta", name: "Tamil" },

  // East & Southeast Asia
  { code: "ja", name: "Japanese" },
  { code: "ko", name: "Korean" },
  { code: "zh-Hans", name: "Chinese Simplified" },
  { code: "zh-Hant", name: "Chinese Traditional" },
  { code: "th", name: "Thai" },
  { code: "vi", name: "Vietnamese" },
  { code: "id", name: "Indonesian" },
  { code: "fil", name: "Filipino" },

  // Africa
  { code: "sw", name: "Swahili" },
];

// Path to Xcode project file
const XCODE_PROJECT_PATH = path.join(
  __dirname,
  "../Tidex.xcodeproj/project.pbxproj"
);

// Path to TidexApp Resources lproj directory (for InfoPlist.strings)
const TIDEX_APP_PATH = path.join(__dirname, "../TidexApp/Resources");

// InfoPlist.strings keys that need translation (others like CFBundleName stay as "Tidex")
const INFO_PLIST_TRANSLATABLE_KEYS = [
  "NSCameraUsageDescription",
  "NSFaceIDUsageDescription",
  "NSPhotoLibraryAddUsageDescription",
  "NSCalendarsFullAccessUsageDescription",
];

// Stats for reporting
const stats = {
  translated: 0,
  skippedFormatMismatch: 0,
  skippedNoTranslation: 0,
  errors: [],
};

// Track current file state for graceful shutdown
let currentSave = null;
let currentMultibar = null;
let isShuttingDown = false;
const shutdownController = new AbortController();

// Graceful shutdown handler
async function saveAndExit(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  shutdownController.abort();

  // Stop progress bars first to clean up terminal
  if (currentMultibar) {
    currentMultibar.stop();
  }

  console.log("\n⚠ Interrupt received, saving progress...");

  try {
    await currentSave?.();
  } catch (error) {
    console.error(`✗ Failed to save: ${error.message}`);
    process.exit(1);
  }

  console.log(`\nProgress: ${stats.translated} strings translated before shutdown.`);
  console.log("Run the script again to continue from where you left off.\n");
  process.exit(signal === "SIGINT" ? 130 : 143);
}

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
  // Don't skip empty strings - if the key exists, it needs translation
  // (e.g., common.daySuffix is "" in English but "." in German)
  if (englishValue === undefined || englishValue === null) return true;

  // Skip internal identifiers (SCREAMING_SNAKE_CASE or camelCase.dotted.keys without spaces)
  if (/^[A-Z][A-Z0-9_]+$/.test(key) && key === englishValue) return true;

  return false;
}

// Retry with exponential backoff
async function withRetry(fn, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    shutdownController.signal.throwIfAborted();
    try {
      return await fn();
    } catch (error) {
      const isRetryable = error.status === 429 || error.status >= 500 ||
        error.name === "TimeoutError" || error instanceof TypeError;
      if (shutdownController.signal.aborted) throw error;
      if (!isRetryable || attempt === maxRetries - 1) {
        throw error;
      }
      const delay = Math.pow(2, attempt) * 1000 + Math.random() * 1000;
      reportProgress(`Retrying after ${error.message} in ${Math.round(delay / 1000)}s...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

function toErrorWithStatus(message, status) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function getOpenAIConfig() {
  const apiKey = process.env.OPENAI_API_KEY?.trim();

  if (!apiKey) {
    throw new Error(
      "OPENAI_API_KEY is not set in .env.local at the repository root. The localization translator now uses OpenAI Responses API."
    );
  }

  return {
    apiKey,
    model: OPENAI_MODEL,
  };
}

function buildTranslationSchema() {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      translations: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            id: { type: "string" },
            translation: { type: "string" },
          },
          required: ["id", "translation"],
        },
      },
    },
    required: ["translations"],
  };
}

function extractOpenAIText(responseJson) {
  if (typeof responseJson?.output_text === "string" && responseJson.output_text.trim()) {
    return responseJson.output_text.trim();
  }

  const output = Array.isArray(responseJson?.output) ? responseJson.output : [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];

    for (const block of content) {
      if (typeof block?.text === "string" && block.text.trim()) {
        return block.text.trim();
      }

      if (
        block?.text &&
        typeof block.text === "object" &&
        typeof block.text.value === "string" &&
        block.text.value.trim()
      ) {
        return block.text.value.trim();
      }
    }
  }

  throw new Error("OpenAI response did not include text output");
}

function extractOpenAIParsedPayload(responseJson) {
  if (
    responseJson?.output_parsed &&
    typeof responseJson.output_parsed === "object" &&
    !Array.isArray(responseJson.output_parsed)
  ) {
    return responseJson.output_parsed;
  }

  const output = Array.isArray(responseJson?.output) ? responseJson.output : [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];

    for (const block of content) {
      if (block?.parsed && typeof block.parsed === "object" && !Array.isArray(block.parsed)) {
        return block.parsed;
      }
    }
  }

  return null;
}

function normalizeTranslationsPayload(payload, expectedIds) {
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.translations)) {
    throw new Error("OpenAI translation payload did not match the expected schema");
  }

  const remaining = new Set(expectedIds);
  const translations = Object.create(null);
  for (const entry of payload.translations) {
    if (!entry || typeof entry.id !== "string" || typeof entry.translation !== "string" ||
        !remaining.delete(entry.id)) {
      throw new Error("Translation response contains an invalid, duplicate, or unexpected ID");
    }
    translations[entry.id] = entry.translation;
  }
  if (remaining.size > 0) {
    throw new Error(`Translation response is missing ${remaining.size} requested entries`);
  }
  return translations;
}

async function createStructuredOpenAIResponse({
  schemaName,
  instructions,
  prompt,
  maxOutputTokens,
  expectedIds,
  retryIncomplete = true,
}) {
  const { apiKey, model } = getOpenAIConfig();

  const response = await fetch(OPENAI_RESPONSES_API_URL, {
    method: "POST",
    signal: AbortSignal.any([
      shutdownController.signal,
      AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    ]),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      store: false,
      max_output_tokens: maxOutputTokens,
      reasoning: {
        effort: OPENAI_REASONING_EFFORT,
      },
      instructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: prompt,
            },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: schemaName,
          strict: true,
          schema: buildTranslationSchema(),
        },
      },
    }),
  });

  const responseJson = await response.json().catch((error) => {
    if (error instanceof SyntaxError) return null;
    throw error;
  });

  if (!response.ok) {
    const errorMessage =
      responseJson?.error?.message ||
      response.statusText ||
      "OpenAI Responses API request failed";
    throw toErrorWithStatus(
      `OpenAI Responses API request failed (${response.status}): ${errorMessage}`,
      response.status
    );
  }

  if (responseJson?.status === "incomplete") {
    const reason = responseJson.incomplete_details?.reason || "unknown reason";
    if (reason === "max_output_tokens" && retryIncomplete) {
      reportProgress(`${schemaName}: output limit reached; retrying with more room for reasoning and text.`);
      return createStructuredOpenAIResponse({
        schemaName, instructions, prompt, expectedIds,
        maxOutputTokens: maxOutputTokens * 2,
        retryIncomplete: false,
      });
    }
    throw new Error(`OpenAI response incomplete: ${reason}`);
  }
  if (responseJson?.status !== "completed") {
    throw new Error(`OpenAI response failed: ${responseJson?.error?.message || responseJson?.status || "invalid response"}`);
  }

  const parsedPayload = extractOpenAIParsedPayload(responseJson);
  if (parsedPayload) {
    return normalizeTranslationsPayload(parsedPayload, expectedIds);
  }

  const text = extractOpenAIText(responseJson);
  return normalizeTranslationsPayload(JSON.parse(text), expectedIds);
}

// Translate a batch using KEY-BASED mapping to avoid context collision
async function translateBatch(items, targetLang) {
  // Build context-aware prompt with keys and Norwegian reference
  const stringsToTranslate = items.map((item) => {
    const entry = { id: item.id, english: item.english };
    // Include Norwegian as reference when available (manually verified translations)
    if (item.norwegian !== undefined) {
      entry.norwegian = item.norwegian;
    }
    entry.context = item.key;
    if (item.comment) entry.comment = item.comment;
    return entry;
  });

  const hasNorwegianRefs = items.some((item) => item.norwegian !== undefined);

  const instructions = `You are a professional translator for Tidex, a work shift tracking app. Return only valid JSON that matches the provided schema.`;

  const prompt = `Translate the following strings from English to ${targetLang.name} for Tidex, a work shift tracking app.

CRITICAL RULES - FOLLOW EXACTLY:
1. PRESERVE ALL FORMAT SPECIFIERS EXACTLY AS THEY APPEAR:
   - %@ stays as %@
   - %lld stays as %lld (NOT %d)
   - %ld stays as %ld
   - %1$@ stays as %1$@
   - %d stays as %d
   - %.2f stays as %.2f
   - DO NOT change any format specifier types!
   - Format specifiers are placeholders for dynamic values passed by code - NEVER hardcode what they represent (e.g., if %@ represents a unit like "min" or "sec", keep it as %@ - do not replace it with the translated unit)
2. Keep translations concise (mobile UI has limited space)
3. Preserve leading/trailing whitespace exactly
4. The "context" field hints at usage - use it to disambiguate meanings
${hasNorwegianRefs ? `5. The "norwegian" field (when present) is a manually verified translation - use it to understand the intended meaning, especially for ambiguous or short strings` : ""}
6. Return exactly one translated entry for each input "id"

Strings to translate:
${JSON.stringify(stringsToTranslate, null, 2)}

Return one translation per input item.`;

  return withRetry(() =>
    createStructuredOpenAIResponse({
      schemaName: `translation_batch_${targetLang.code.replace(/[^a-z0-9_]/gi, "_")}`,
      instructions,
      prompt,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      expectedIds: items.map((item) => item.id),
    })
  );
}

// Translate a batch FROM Norwegian TO English
async function translateBatchToEnglish(items) {
  const stringsToTranslate = items.map((item) => ({
    id: item.id,
    norwegian: item.norwegian,
    context: item.key,
  }));

  const instructions = `You are a professional translator for Tidex, a work shift tracking app. Return only valid JSON that matches the provided schema.`;

  const prompt = `Translate the following strings from Norwegian (Bokmal) to English for Tidex, a work shift tracking app.

CRITICAL RULES - FOLLOW EXACTLY:
1. PRESERVE ALL FORMAT SPECIFIERS EXACTLY AS THEY APPEAR:
   - %@ stays as %@
   - %lld stays as %lld (NOT %d)
   - %ld stays as %ld
   - %1$@ stays as %1$@
   - %d stays as %d
   - %.2f stays as %.2f
   - DO NOT change any format specifier types!
   - Format specifiers are placeholders for dynamic values passed by code - NEVER hardcode what they represent
2. Keep translations concise (mobile UI has limited space)
3. Preserve leading/trailing whitespace exactly
4. The "context" field hints at usage - use it to disambiguate meanings
5. Return exactly one translated entry for each input "id"

Strings to translate:
${JSON.stringify(stringsToTranslate, null, 2)}

Return one translation per input item.`;

  return withRetry(() =>
    createStructuredOpenAIResponse({
      schemaName: "translation_batch_en",
      instructions,
      prompt,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      expectedIds: items.map((item) => item.id),
    })
  );
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

// Keep the catalog's existing order; sorting moves unrelated entries in diffs.
function xcstringsStringify(data) {
  const json = JSON.stringify(data, null, 2);
  return json.replace(/^(\s*"(?:[^"\\]|\\.)*"): /gm, "$1 : ") + "\n";
}

function reportProgress(message) {
  if (currentMultibar && process.stderr.isTTY) {
    currentMultibar.log(message + "\n");
  } else {
    console.error(message);
  }
}

// Concurrent requests must never write the catalog concurrently or overwrite edits.
function createCatalogSaver(filePath, data, originalContent) {
  let lastSavedContent = originalContent;
  const saveLimit = pLimit(1);
  return () => saveLimit(async () => {
    const content = xcstringsStringify(data);
    if (content === lastSavedContent) return;
    const assertUnchanged = async () => {
      if (await fs.readFile(filePath, "utf-8") !== lastSavedContent) {
        throw new Error(`Catalog changed on disk during translation: ${filePath}. Existing edits were preserved; rerun to resume.`);
      }
    };
    await assertUnchanged();
    const temporaryPath = `${filePath}.${randomUUID()}.tmp`;
    try {
      const { mode } = await fs.stat(filePath);
      await fs.writeFile(temporaryPath, content, { mode, flag: "wx" });
      await assertUnchanged();
      await fs.rename(temporaryPath, filePath);
      lastSavedContent = content;
    } finally {
      await fs.rm(temporaryPath, { force: true });
    }
  });
}

function needsTranslation(unit) {
  return unit?.value === undefined || unit.state === "needs_review" || unit.state === "new";
}

function collectTranslationWork(data) {
  // Collect ALL strings that need translation with unique IDs
  const stringsToTranslate = [];
  const stringsNeedingEnglish = []; // Strings with Norwegian but missing English
  let idCounter = 0;

  for (const [key, value] of Object.entries(data.strings)) {
    // Check for plural variations first (they take precedence)
    const enVariations = value.localizations?.en?.variations?.plural;
    const nbVariations = value.localizations?.nb?.variations?.plural;
    const hasPluralVariations = enVariations && Object.keys(enVariations).length > 0;
    const hasNbPluralVariations = nbVariations && Object.keys(nbVariations).length > 0;

    // Check for simple stringUnit
    const enStringUnit = value.localizations?.en?.stringUnit;
    const nbStringUnit = value.localizations?.nb?.stringUnit;

    // In xcstrings, the key itself is the English value when no explicit en localization exists
    // BUT only use key fallback if there are no plural variations (those need special handling)
    const norwegianValue = nbStringUnit?.value;
    const englishValue = enStringUnit?.value ?? (hasPluralVariations || hasNbPluralVariations || norwegianValue !== undefined ? null : key);

    // Check if English is missing but Norwegian exists (for simple strings)
    if (enStringUnit?.value === undefined && norwegianValue !== undefined && !hasPluralVariations && !shouldSkipString(key, norwegianValue)) {
      stringsNeedingEnglish.push({
        id: `en${idCounter++}`,
        key,
        norwegian: norwegianValue,
        type: "simple",
      });
    }

    if (englishValue !== null) {
      for (const targetLang of TARGET_LANGUAGES) {
        const hasTranslation = !needsTranslation(value.localizations?.[targetLang.code]?.stringUnit);
        if (!hasTranslation && !shouldSkipString(key, englishValue)) {
          const item = {
            id: `s${idCounter++}`,
            key,
            comment: value.comment,
            english: englishValue,
            targetLang,
            type: "simple",
          };
          // Include Norwegian reference when available
          if (norwegianValue !== undefined) {
            item.norwegian = norwegianValue;
          }
          stringsToTranslate.push(item);
        }
      }
    }

    // Handle plural variations
    if (enVariations) {
      for (const [pluralForm, pluralData] of Object.entries(enVariations)) {
        const englishValue = pluralData.stringUnit?.value;
        if (!englishValue) continue;

        // Get Norwegian plural variation as reference
        const nbPluralValue =
          value.localizations?.nb?.variations?.plural?.[pluralForm]?.stringUnit?.value;

        for (const targetLang of TARGET_LANGUAGES) {
          const hasTranslation = !needsTranslation(
            value.localizations?.[targetLang.code]?.variations?.plural?.[pluralForm]?.stringUnit
          );
          if (!hasTranslation && !shouldSkipString(key, englishValue)) {
            const item = {
              id: `s${idCounter++}`,
              key,
              comment: value.comment,
              english: englishValue,
              targetLang,
              type: "plural",
              pluralForm,
            };
            if (nbPluralValue !== undefined) {
              item.norwegian = nbPluralValue;
            }
            stringsToTranslate.push(item);
          }
        }
      }
    }

    // Check for Norwegian plural variations missing English equivalents
    if (hasNbPluralVariations && !hasPluralVariations) {
      for (const [pluralForm, pluralData] of Object.entries(nbVariations)) {
        const nbPluralValue = pluralData.stringUnit?.value;
        if (!nbPluralValue || shouldSkipString(key, nbPluralValue)) continue;

        stringsNeedingEnglish.push({
          id: `en${idCounter++}`,
          key,
          norwegian: nbPluralValue,
          type: "plural",
          pluralForm,
        });
      }
    }
  }

  return { stringsToTranslate, stringsNeedingEnglish };
}

async function translateXcstrings(filePath) {
  console.log(`\nProcessing: ${filePath}`);
  const content = await fs.readFile(filePath, "utf-8");
  const data = JSON.parse(content);
  const save = createCatalogSaver(filePath, data, content);
  currentSave = save;
  let { stringsToTranslate, stringsNeedingEnglish } = collectTranslationWork(data);

  // First, translate Norwegian to English for strings missing English
  if (stringsNeedingEnglish.length > 0) {
    console.log(`Found ${stringsNeedingEnglish.length} strings needing English translation (from Norwegian)`);

    const batches = [];
    for (let i = 0; i < stringsNeedingEnglish.length; i += BATCH_SIZE) {
      batches.push(stringsNeedingEnglish.slice(i, i + BATCH_SIZE));
    }

    for (const batch of batches) {
      try {
        const translations = await translateBatchToEnglish(batch);

        if (isShuttingDown) return;
        for (const item of batch) {
          const translation = translations[item.id];
          if (typeof translation !== "string" || (translation === "" && item.norwegian !== "")) {
            stats.skippedNoTranslation++;
            continue;
          }

          // Validate format specifiers
          if (!validateFormatSpecifiers(item.norwegian, translation)) {
            console.log(`  ⚠ Format mismatch for "${item.key}": nb="${item.norwegian}" -> en="${translation}"`);
            stats.skippedFormatMismatch++;
            continue;
          }

          // Apply English translation
          if (item.type === "simple") {
            deepSet(
              data.strings[item.key],
              ["localizations", "en", "stringUnit"],
              { state: "translated", value: translation }
            );
          } else if (item.type === "plural") {
            deepSet(
              data.strings[item.key],
              ["localizations", "en", "variations", "plural", item.pluralForm, "stringUnit"],
              { state: "translated", value: translation }
            );
          }

          stats.translated++;
        }
      } catch (error) {
        console.error(`  ✗ Error translating to English: ${error.message}`);
        stats.errors.push(`Norwegian->English: ${error.message}`);
      }
    }

    // Save progress after English translations
    await save();
    ({ stringsToTranslate } = collectTranslationWork(data));
  }

  console.log(`Found ${stringsToTranslate.length} strings needing translation to other languages`);

  if (stringsToTranslate.length === 0 && stringsNeedingEnglish.length === 0) {
    currentSave = null;
    console.log("Nothing to translate!");
    return;
  }

  if (stringsToTranslate.length === 0) {
    // Only had English translations to add, we're done
    currentSave = null;
    console.log(`\n✓ Completed: ${filePath}`);
    return;
  }

  // One queue across all languages keeps every request slot useful for small updates.
  const batches = TARGET_LANGUAGES.flatMap((targetLang) => {
    const items = stringsToTranslate.filter((item) => item.targetLang.code === targetLang.code);
    const batches = [];
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      batches.push({ targetLang, items: items.slice(i, i + BATCH_SIZE) });
    }
    return batches;
  });
  console.log(`${batches.length} batches, up to ${CONCURRENCY} concurrent requests across languages.`);
  const multibar = process.stderr.isTTY ? new cliProgress.MultiBar(
    {
      clearOnComplete: false,
      hideCursor: true,
      format: " {bar} | {value}/{total} processed | {status}",
    },
    cliProgress.Presets.shades_classic
  ) : null;
  currentMultibar = multibar;
  const overallBar = multibar?.create(stringsToTranslate.length, 0, { status: "starting..." });
  const limit = pLimit(CONCURRENCY);
  const formatWarnings = [];
  let completedStrings = 0;
  let translatedStrings = 0;
  let failedBatches = 0;
  let saveError = null;

  await Promise.all(batches.map(({ targetLang, items }, batchIndex) => limit(async () => {
    if (isShuttingDown || saveError) return;
    try {
      const translations = await translateBatch(items, targetLang);
      if (isShuttingDown || saveError) return;
      for (const item of items) {
        const translation = translations[item.id];
        if (typeof translation !== "string" || (translation === "" && item.english !== "")) {
          stats.skippedNoTranslation++;
          reportProgress(`${targetLang.code}: missing translation for ${item.key}`);
          continue;
        }
        if (!validateFormatSpecifiers(item.english, translation)) {
          const warning = `${targetLang.code}: format mismatch for ${item.key}`;
          formatWarnings.push(warning);
          reportProgress(warning);
          stats.skippedFormatMismatch++;
          continue;
        }
        const unitPath = item.type === "simple"
          ? ["localizations", targetLang.code, "stringUnit"]
          : ["localizations", targetLang.code, "variations", "plural", item.pluralForm, "stringUnit"];
        deepSet(data.strings[item.key], unitPath, { state: "translated", value: translation });
        translatedStrings++;
        stats.translated++;
      }
      try {
        await save();
      } catch (error) {
        saveError = error;
        throw error;
      }
      reportProgress(`${targetLang.name}: saved batch ${batchIndex + 1}/${batches.length}.`);
    } catch (error) {
      if (isShuttingDown) return;
      const message = `Batch ${batchIndex + 1} error for ${targetLang.name}: ${error.message}`;
      stats.errors.push(message);
      failedBatches++;
      reportProgress(message);
    } finally {
      completedStrings += items.length;
      overallBar?.update(completedStrings, {
        status: `${translatedStrings} translated, ${stats.skippedFormatMismatch + stats.skippedNoTranslation} skipped, ${failedBatches} failed batches`,
      });
    }
  })));
  multibar?.stop();
  currentMultibar = null;
  if (isShuttingDown) return;
  if (saveError) throw saveError;

  // Show format warnings if any
  if (formatWarnings.length > 0) {
    console.log(`\nFormat specifier mismatches (${formatWarnings.length}):`);
    formatWarnings.slice(0, 10).forEach((w) => console.log(`  - ${w}`));
    if (formatWarnings.length > 10) {
      console.log(`  ... and ${formatWarnings.length - 10} more`);
    }
  }

  // Clear tracking (file is fully saved)
  currentSave = null;
  currentMultibar = null;

  console.log(`\nSaved progress: ${filePath}`);
}

// Sync languages to Xcode project's knownRegions
async function syncXcodeProjectLanguages() {
  console.log("\nSyncing languages to Xcode project...");

  try {
    const content = await fs.readFile(XCODE_PROJECT_PATH, "utf-8");

    // Find the knownRegions section
    const knownRegionsRegex = /knownRegions\s*=\s*\(\s*([\s\S]*?)\s*\);/;
    const match = content.match(knownRegionsRegex);

    if (!match) {
      console.error("  ✗ Could not find knownRegions in project.pbxproj");
      return false;
    }

    // Parse existing regions
    const existingRegions = match[1]
      .split(",")
      .map((r) => r.trim().replace(/"/g, ""))
      .filter((r) => r.length > 0);

    // Build desired regions list: en + all target languages
    const desiredRegions = new Set(["en"]);
    for (const lang of TARGET_LANGUAGES) {
      desiredRegions.add(lang.code);
    }

    // Check what's missing
    const missingRegions = [...desiredRegions].filter(
      (r) => !existingRegions.includes(r)
    );

    if (missingRegions.length === 0) {
      console.log("  ✓ All languages already in Xcode project");
      return true;
    }

    console.log(`  Adding languages: ${missingRegions.join(", ")}`);

    // Build new knownRegions array
    // Format: codes with hyphens need quotes (e.g., "pt-BR"), others don't
    const formatRegion = (code) =>
      code.includes("-") ? `"${code}"` : code;

    const newRegions = [...desiredRegions].map(formatRegion);

    // Create new knownRegions block with proper indentation
    const newKnownRegions = `knownRegions = (\n\t\t\t\t${newRegions.join(",\n\t\t\t\t")},\n\t\t\t);`;

    // Replace in content
    const newContent = content.replace(knownRegionsRegex, newKnownRegions);

    await fs.writeFile(XCODE_PROJECT_PATH, newContent);
    console.log(`  ✓ Updated ${XCODE_PROJECT_PATH}`);
    return true;
  } catch (error) {
    console.error(`  ✗ Error updating Xcode project: ${error.message}`);
    stats.errors.push(`Xcode project sync: ${error.message}`);
    return false;
  }
}

// Parse InfoPlist.strings file format
function parseInfoPlistStrings(content) {
  const result = {};
  // Match "key" = "value"; patterns, handling escaped quotes
  const regex = /"([^"\\]*(?:\\.[^"\\]*)*)"\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*;/g;
  let match;
  while ((match = regex.exec(content)) !== null) {
    result[match[1]] = match[2];
  }
  return result;
}

// Generate InfoPlist.strings file content
function generateInfoPlistStrings(langName, strings) {
  const lines = [`/* ${langName} localization for Info.plist strings */`, ""];

  // Always include app name keys (not translated)
  lines.push("/* App display name */");
  lines.push('"CFBundleDisplayName" = "Tidex";');
  lines.push("");
  lines.push("/* App name */");
  lines.push('"CFBundleName" = "Tidex";');
  lines.push("");

  // Add translated keys
  for (const [key, value] of Object.entries(strings)) {
    const comment =
      key === "NSCameraUsageDescription"
        ? "/* Camera usage description */"
        : key === "NSFaceIDUsageDescription"
          ? "/* Face ID usage description */"
          : key === "NSPhotoLibraryAddUsageDescription"
            ? "/* Photo library save description */"
            : key === "NSCalendarsFullAccessUsageDescription"
              ? "/* Calendar access description */"
              : `/* ${key} */`;
    lines.push(comment);
    // Escape any quotes in the value
    const escapedValue = value.replace(/"/g, '\\"');
    lines.push(`"${key}" = "${escapedValue}";`);
    lines.push("");
  }

  return lines.join("\n");
}

// Translate InfoPlist.strings for all languages
async function translateInfoPlistStrings() {
  console.log("\nTranslating InfoPlist.strings...");

  try {
    // Read English source
    const enPath = path.join(TIDEX_APP_PATH, "en.lproj", "InfoPlist.strings");
    const enContent = await fs.readFile(enPath, "utf-8");
    const enStrings = parseInfoPlistStrings(enContent);

    // Get translatable strings
    const stringsToTranslate = {};
    for (const key of INFO_PLIST_TRANSLATABLE_KEYS) {
      if (enStrings[key]) {
        stringsToTranslate[key] = enStrings[key];
      }
    }

    if (Object.keys(stringsToTranslate).length === 0) {
      console.log("  No translatable strings found in InfoPlist.strings");
      return;
    }

    // Track what we create/update
    let created = 0;
    let skipped = 0;

    for (const targetLang of TARGET_LANGUAGES) {
      const lprojDir = path.join(TIDEX_APP_PATH, `${targetLang.code}.lproj`);
      const infoPlistPath = path.join(lprojDir, "InfoPlist.strings");

      // Check if file already exists with content
      let existingStrings = {};
      try {
        const existingContent = await fs.readFile(infoPlistPath, "utf-8");
        existingStrings = parseInfoPlistStrings(existingContent);
      } catch {
        // File doesn't exist, that's fine
      }

      // Check if all translatable keys already exist
      const missingKeys = INFO_PLIST_TRANSLATABLE_KEYS.filter(
        (key) => !existingStrings[key]
      );

      if (missingKeys.length === 0) {
        skipped++;
        continue;
      }

      console.log(`  Translating InfoPlist.strings for ${targetLang.name}...`);

      // Translate missing keys
      const items = missingKeys.map((key, idx) => ({
        id: `ip${idx}`,
        key,
        english: stringsToTranslate[key],
      }));

      try {
        const instructions =
          'You are a professional translator for Tidex, a work shift tracking app. Return only valid JSON that matches the provided schema.';

        const prompt = `Translate these iOS permission descriptions from English to ${targetLang.name} for Tidex, a work shift tracking app.

CRITICAL RULES:
1. Keep "Tidex" as-is (it's the app name)
2. Keep the tone friendly and clear
3. These appear in iOS permission dialogs, so be concise

Strings to translate:
${JSON.stringify(items, null, 2)}

Return one translation per input item.`;

        const translations = await withRetry(() =>
          createStructuredOpenAIResponse({
            schemaName: `infoplist_batch_${targetLang.code.replace(/[^a-z0-9_]/gi, "_")}`,
            instructions,
            prompt,
            maxOutputTokens: MAX_OUTPUT_TOKENS,
            expectedIds: items.map((item) => item.id),
          })
        );

        // Merge translations with existing
        const mergedStrings = { ...existingStrings };
        for (const item of items) {
          if (translations[item.id]) {
            mergedStrings[item.key] = translations[item.id];
          }
        }

        // Ensure lproj directory exists
        await fs.mkdir(lprojDir, { recursive: true });

        // Write InfoPlist.strings
        const content = generateInfoPlistStrings(targetLang.name, mergedStrings);
        await fs.writeFile(infoPlistPath, content);

        created++;
        stats.translated += missingKeys.length;
      } catch (error) {
        console.error(
          `    ✗ Error translating for ${targetLang.name}: ${error.message}`
        );
        stats.errors.push(`InfoPlist ${targetLang.name}: ${error.message}`);
      }

      // Brief delay between languages
      await new Promise((r) => setTimeout(r, 100));
    }

    console.log(
      `  ✓ InfoPlist.strings: ${created} created/updated, ${skipped} already complete`
    );
  } catch (error) {
    console.error(`  ✗ Error processing InfoPlist.strings: ${error.message}`);
    stats.errors.push(`InfoPlist.strings: ${error.message}`);
  }
}

async function main(args = process.argv.slice(2)) {
  Object.assign(stats, { translated: 0, skippedFormatMismatch: 0, skippedNoTranslation: 0, errors: [] });
  const defaultXcstringsFiles = [
    path.join(__dirname, "../Resources/Localization/App/Localizable.xcstrings"),
    path.join(__dirname, "../Resources/Localization/ShareExtension/Localizable.xcstrings"),
    path.join(__dirname, "../Resources/Localization/Watch/Localizable.xcstrings"),
    path.join(__dirname, "../Resources/Localization/Widget/Localizable.xcstrings"),
  ];
  const cliXcstringsFiles = args
    .filter((file) => file.endsWith(".xcstrings"))
    .map((file) => path.resolve(process.cwd(), file));
  const xcstringsFiles = cliXcstringsFiles.length > 0 ? cliXcstringsFiles : defaultXcstringsFiles;
  const isTargetedRun = cliXcstringsFiles.length > 0;

  console.log("XCStrings Translator v2");
  console.log("=======================");
  console.log(`Target languages: ${TARGET_LANGUAGES.map((l) => l.name).join(", ")}`);
  if (isTargetedRun) {
    console.log(`Target files: ${xcstringsFiles.join(", ")}`);
  }

  for (const file of xcstringsFiles) {
    if (isShuttingDown) break;
    try {
      await translateXcstrings(file);
    } catch (error) {
      console.error(`Error processing ${file}: ${error.message}`);
      stats.errors.push(`File error: ${error.message}`);
    }
  }

  if (isShuttingDown) return 1;

  if (!isTargetedRun) {
    // Translate InfoPlist.strings (permission descriptions)
    await translateInfoPlistStrings();

    // Sync languages to Xcode project (makes them selectable in iOS Settings)
    await syncXcodeProjectLanguages();
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
  if (stats.errors.length > 0 || stats.skippedFormatMismatch > 0 || stats.skippedNoTranslation > 0) {
    return 1;
  }

  console.log("\n✓ Done!");
  return 0;
}

export { main, translateXcstrings, collectTranslationWork, createCatalogSaver,
  createStructuredOpenAIResponse, normalizeTranslationsPayload, xcstringsStringify, TARGET_LANGUAGES };

if (import.meta.main) {
  process.on("SIGINT", () => { void saveAndExit("SIGINT"); });
  process.on("SIGTERM", () => { void saveAndExit("SIGTERM"); });
  process.exitCode = await main();
}
