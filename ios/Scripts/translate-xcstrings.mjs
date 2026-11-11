#!/usr/bin/env bun

import fs from "fs/promises";
import { rmSync } from "fs";
import os from "os";
import path from "path";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";
import { randomUUID } from "node:crypto";
import cliProgress from "cli-progress";
import pLimit from "p-limit";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const MODEL = process.env.TIDEX_TRANSLATE_MODEL?.trim() || "claude-opus-5-5";
const EFFORT = process.env.TIDEX_TRANSLATE_EFFORT?.trim() || "high";
// With this beta, a request that a safety classifier declines reruns on the API's default fallback model.
const FALLBACK_BETA = "server-side-fallback-2026-07-01";
const REQUEST_TIMEOUT_MS = 300_000;
const MAX_TOKENS = 32_000;
const BATCH_SIZE = 30;
// One slot per language, so a commit with a few new strings finishes in one round of requests.
const CONCURRENCY = 48;

const ENGLISH = { code: "en", name: "English" };

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

const IOS_ROOT = path.join(__dirname, "..");
const GUIDE_PATH = path.join(__dirname, "translation-guide.md");
const DEFAULT_CATALOG = path.join(IOS_ROOT, "Resources/Localization/App/Localizable.xcstrings");
const XCODE_PROJECT_PATH = path.join(IOS_ROOT, "Tidex.xcodeproj/project.pbxproj");

// Path to TidexApp Resources lproj directory (for InfoPlist.strings)
const TIDEX_APP_PATH = path.join(IOS_ROOT, "TidexApp/Resources");

// InfoPlist.strings keys that need translation (others like CFBundleName stay as "Tidex")
const INFO_PLIST_TRANSLATABLE_KEYS = [
  "NSCameraUsageDescription",
  "NSFaceIDUsageDescription",
  "NSLocationWhenInUseUsageDescription",
  "NSPhotoLibraryAddUsageDescription",
  "NSCalendarsFullAccessUsageDescription",
];

function newStats() {
  return {
    translated: 0,
    skippedFormatMismatch: 0,
    skippedNoTranslation: 0,
    errors: [],
    requests: 0,
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
  };
}

const stats = newStats();

// Track current file state for graceful shutdown
let currentSave = null;
let currentMultibar = null;
let isShuttingDown = false;
const shutdownController = new AbortController();
const openRequestBodies = new Set();

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
  for (const bodyPath of openRequestBodies) rmSync(bodyPath, { force: true });

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

const FORMAT_SPECIFIER = /%(\d+\$)?([-+0 #]*(?:\d+|\*)?(?:\.\d+|\.\*)?[hlLzjt]{0,2}[@dDiuUoOxXeEfFgGaAcCsSpn%])/g;

// The argument each specifier reads, by position. Unnumbered specifiers read arguments in order.
// Returns null for a string iOS would format wrongly: numbered and unnumbered specifiers mixed.
function formatArguments(text) {
  const byPosition = new Map();
  // "%%" prints a percent sign. A "%" that starts no specifier is counted apart from it, so a
  // translation cannot add one that String(format:) would read as the start of a specifier.
  const strayPercents = text.replace(FORMAT_SPECIFIER, "").split("%").length - 1;
  let literalPercents = 0;
  let unnumbered = 0;
  let numbered = 0;
  for (const [, position, specifier] of text.matchAll(FORMAT_SPECIFIER)) {
    if (specifier === "%") {
      literalPercents++;
      continue;
    }
    if (position) numbered++;
    const index = position ? Number.parseInt(position, 10) : ++unnumbered;
    // ios:l10n:validate counts specifiers, so a translation uses each argument once.
    if (byPosition.has(index)) return null;
    byPosition.set(index, specifier);
  }
  return numbered > 0 && unnumbered > 0 ? null : { byPosition, percents: `${literalPercents}/${strayPercents}` };
}

// A translation may reorder arguments by numbering its specifiers, but each one must keep the
// type of the argument it reads, or the app shows the wrong value or crashes.
function formatMatches(source, translation, { mayOmitArguments = false } = {}) {
  const expected = formatArguments(source);
  const actual = formatArguments(translation);
  if (!expected || !actual) return false;
  for (const [position, specifier] of actual.byPosition) {
    if (expected.byPosition.get(position) !== specifier) return false;
  }
  return mayOmitArguments ||
    (actual.byPosition.size === expected.byPosition.size && actual.percents === expected.percents);
}

function hasOneCount(text) {
  const specifiers = [...text.matchAll(FORMAT_SPECIFIER)].filter(([, , specifier]) => specifier !== "%");
  return specifiers.length === 1 && /[dDiuU]$/.test(specifiers[0][2]);
}

const PLURAL_CATEGORY_ORDER = ["zero", "one", "two", "few", "many", "other"];
const pluralCategoriesByLanguage = new Map();

// The plural categories a language uses for whole numbers up to 200, with the numbers each one
// covers. Categories that only apply to larger numbers, such as French "many" for a million, are
// left to "other", which every language has.
function pluralCategories(code) {
  if (!pluralCategoriesByLanguage.has(code)) {
    const rules = new Intl.PluralRules(code);
    const numbers = { other: [] };
    for (let number = 0; number <= 200; number++) (numbers[rules.select(number)] ??= []).push(number);
    pluralCategoriesByLanguage.set(code, PLURAL_CATEGORY_ORDER
      .filter((category) => numbers[category])
      .map((category) => ({ category, numbers: numbers[category] })));
  }
  return pluralCategoriesByLanguage.get(code);
}

function numbersOf(code, category) {
  return pluralCategories(code).find((entry) => entry.category === category)?.numbers ?? [];
}

function describeNumbers(numbers) {
  if (numbers.length === 0) return "fractions such as 1.5";
  return numbers.slice(0, 8).join(", ") + (numbers.length > 8 ? ", …" : "");
}

// Retry with exponential backoff
async function withRetry(fn, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    shutdownController.signal.throwIfAborted();
    try {
      return await fn();
    } catch (error) {
      const isRetryable = error.retryable === true || error.name === "TimeoutError" ||
        [408, 409, 429].includes(error.status) || error.status >= 500;
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

const TRANSLATION_SCHEMA = {
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

function antError(stdout, stderr) {
  // ant prints the failed call as `POST "<url>": 429 Too Many Requests` and the API's error as JSON.
  const status = Number(stderr.match(/: (\d{3}) /)?.[1]) || undefined;
  let detail;
  try {
    detail = JSON.parse(stdout).error?.message;
  } catch {
    detail = undefined;
  }
  const hint = status === 401 ? " Run `ant auth login`." : "";
  const error = new Error(
    `Claude request failed${status ? ` (${status})` : ""}: ${detail || stderr.trim() || "ant printed nothing"}.${hint}`
  );
  error.status = status;
  error.retryable = status === undefined;
  return error;
}

// Sends one Messages API request through the ant CLI, which signs it with the `ant auth login`
// profile or ANTHROPIC_API_KEY. ant replaces any body string that starts with "@" by the contents
// of the file it names, so every text block in a request starts with fixed text.
async function sendToClaude(body) {
  const ant = Bun.which("ant", { PATH: process.env.PATH });
  if (!ant) {
    throw new Error("The ant CLI is not installed. Run `brew install anthropics/tap/ant`, then `ant auth login`.");
  }
  const signal = AbortSignal.any([
    shutdownController.signal,
    AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  ]);
  // ant reads the body from a file, not a pipe. When many large requests start together a piped
  // body arrives late, and ant then runs without it and fails with "Required flags not set".
  const bodyPath = path.join(os.tmpdir(), `tidex-translate-${randomUUID()}.json`);
  openRequestBodies.add(bodyPath);
  try {
    await fs.writeFile(bodyPath, JSON.stringify(body), { mode: 0o600 });
    const child = Bun.spawn(
      [ant, "beta:messages", "create", "--beta", FALLBACK_BETA, "--format", "json", "--format-error", "json"],
      { stdin: Bun.file(bodyPath), stdout: "pipe", stderr: "pipe", env: process.env, signal }
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    signal.throwIfAborted();
    if (exitCode !== 0) throw antError(stdout, stderr);
    return JSON.parse(stdout);
  } finally {
    await fs.rm(bodyPath, { force: true });
    openRequestBodies.delete(bodyPath);
  }
}

async function askClaude(system, content) {
  const message = await sendToClaude({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    fallbacks: "default",
    thinking: { type: "adaptive" },
    output_config: {
      effort: EFFORT,
      format: { type: "json_schema", schema: TRANSLATION_SCHEMA },
    },
    system,
    messages: [{ role: "user", content }],
  });
  const usage = message.usage ?? {};
  stats.requests++;
  stats.inputTokens += (usage.input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
  stats.cachedInputTokens += usage.cache_read_input_tokens ?? 0;
  stats.outputTokens += usage.output_tokens ?? 0;
  if (message.content?.some((block) => block.type === "fallback")) {
    reportProgress(`${MODEL} declined a request, so ${message.model} answered it.`);
  }
  return message;
}

function normalizeTranslationsPayload(payload, expectedIds) {
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.translations)) {
    throw new Error("Translation response did not match the expected schema");
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

async function requestTranslations(system, content, expectedIds) {
  return withRetry(async () => {
    const message = await askClaude(system, content);
    if (message.stop_reason === "max_tokens") {
      throw Object.assign(new Error("Claude ran out of output space"), { truncated: true });
    }
    if (message.stop_reason !== "end_turn") {
      throw new Error(`Claude stopped without translating (${message.stop_details?.category ?? message.stop_reason})`);
    }
    try {
      const text = message.content.findLast((block) => block.type === "text")?.text ?? "";
      return normalizeTranslationsPayload(JSON.parse(text), expectedIds);
    } catch (error) {
      error.retryable = true;
      throw error;
    }
  });
}

const DOT_NOTATION_KEY = /^[a-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/;

// Symbols, format-only compositions and English-only admin text are not translated.
// Only dot-notation keys are real strings; Xcode extracts the rest from literals.
function isTranslatable(key, entry) {
  return entry.shouldTranslate !== false && DOT_NOTATION_KEY.test(key);
}

// A localization's text: a string, or its plural forms by category.
function readText(localization) {
  const plural = Object.entries(localization?.variations?.plural ?? {});
  if (plural.length === 0) return localization?.stringUnit?.value;
  return Object.fromEntries(plural
    .filter(([, form]) => form.stringUnit?.value !== undefined)
    .map(([category, form]) => [category, form.stringUnit.value]));
}

function needsTranslation(unit) {
  return unit?.value === undefined || unit.state === "needs_review" || unit.state === "new";
}

// What one language still lacks for one string: [] when it is complete, [null] for a plain
// translation, or the plural categories to write.
function pendingCategories(source, targetLang, target) {
  const existingPlural = target?.variations?.plural ?? {};
  const hasPlural = Object.keys(existingPlural).length > 0;
  const sourceIsPlural = typeof source !== "string";
  const categories = pluralCategories(targetLang.code).map(({ category }) => category);
  // A plural is complete when it has every category the language needs and none awaits review.
  const units = sourceIsPlural || hasPlural
    ? [...categories.map((category) => existingPlural[category]), ...Object.values(existingPlural)]
      .map((form) => form?.stringUnit)
    : [target?.stringUnit];
  if (!units.some(needsTranslation)) return [];
  // The forms of one plural are written together, so they share one wording.
  if (sourceIsPlural) return categories;
  // English "%lld selected" works for every number. Russian, Polish, Arabic and others inflect the
  // words around the number, so they get plural forms even though the source has none.
  const inflects = hasOneCount(source) &&
    (hasPlural || categories.some((category) => category !== "one" && category !== "other"));
  return inflects ? categories : [null];
}

function collectTranslationWork(data) {
  const stringsToTranslate = [];
  const stringsNeedingEnglish = []; // Strings with Norwegian but missing English
  let idCounter = 0;
  const slots = (categories) => categories.map((category) => ({ id: `s${idCounter++}`, category }));

  for (const [key, entry] of Object.entries(data.strings)) {
    if (!isTranslatable(key, entry)) continue;
    const localizations = entry.localizations ?? {};
    const english = readText(localizations.en);
    const norwegian = readText(localizations.nb);

    if (english === undefined) {
      if (norwegian !== undefined) {
        stringsNeedingEnglish.push({
          key,
          comment: entry.comment,
          norwegian,
          targetLang: ENGLISH,
          slots: slots(pendingCategories(norwegian, ENGLISH, undefined)),
        });
      }
      continue;
    }

    for (const targetLang of TARGET_LANGUAGES) {
      const target = localizations[targetLang.code];
      const categories = pendingCategories(english, targetLang, target);
      if (categories.length === 0) continue;
      stringsToTranslate.push({
        key,
        comment: entry.comment,
        english,
        norwegian: targetLang.code === "nb" ? undefined : norwegian,
        current: readText(target),
        targetLang,
        slots: slots(categories),
      });
    }
  }

  return { stringsToTranslate, stringsNeedingEnglish };
}

// Writes an item's translations into its catalog entry. Returns "translated", or the reason the
// item was left as it was. An item is written whole, so a plural never ends up half updated.
function applyTranslations(entry, item, translations) {
  const source = item.english ?? item.norwegian;
  const reference = typeof source === "string" ? source : source.other ?? Object.values(source)[0] ?? "";
  const texts = item.slots.map((slot) => translations[slot.id]);
  if (texts.some((text) => typeof text !== "string" || (text === "" && reference !== ""))) {
    return "missing";
  }
  const formatsMatch = item.slots.every((slot, index) => formatMatches(reference, texts[index], {
    // "one" covers only 1 in English, so "every week" may drop the number. In Russian it also
    // covers 21 and 31, so the number has to stay.
    mayOmitArguments: slot.category !== null && numbersOf(item.targetLang.code, slot.category).length === 1,
  }));
  if (!formatsMatch) return "format";

  const localization = ((entry.localizations ??= {})[item.targetLang.code] ??= {});
  if (item.slots[0].category === null || (typeof source === "string" && new Set(texts).size === 1)) {
    localization.stringUnit = { state: "translated", value: texts[0] };
    if (localization.variations) delete localization.variations.plural;
    if (localization.variations && Object.keys(localization.variations).length === 0) {
      delete localization.variations;
    }
    return "translated";
  }
  // Xcode keeps the plural forms and drops a plain value next to them. The slots are every
  // category the language uses, so a leftover category from older data goes too.
  delete localization.stringUnit;
  (localization.variations ??= {}).plural = Object.fromEntries(item.slots.map((slot, index) =>
    [slot.category, { stringUnit: { state: "translated", value: texts[index] } }]));
  return "translated";
}

const SKIPPED_SOURCE_DIRECTORIES = /(^|\/)(DerivedData|build|\.build|Vendor|Scripts|TidexAppTests|TidexAppUITests)\//;
const CODE_CONTEXT_LINES = 6;
const CODE_EXCERPTS_PER_STRING = 3;

// Xcode generates `.settingsPayTitle` for the key `settings.pay.title`.
function symbolName(key) {
  return key.split(/[._]/).filter(Boolean)
    .map((part, index) => (index === 0 ? part : part[0].toUpperCase() + part.slice(1)))
    .join("");
}

// Finds where the app's Swift code uses each key and returns the surrounding lines, so the
// translator sees whether a string is a button, a title, a spoken label or a fragment.
async function findCodeUsage(keys) {
  const keyByName = new Map();
  for (const key of keys) keyByName.set(symbolName(key), key).set(key, key);
  const uses = new Map();
  const files = (await fs.readdir(IOS_ROOT, { recursive: true }))
    .filter((file) => file.endsWith(".swift") && !SKIPPED_SOURCE_DIRECTORIES.test(file))
    .sort();
  for (const file of files) {
    const lines = (await fs.readFile(path.join(IOS_ROOT, file), "utf8")).split("\n");
    lines.forEach((line, index) => {
      // `.symbol` as an implicit member, or the key as a string literal.
      for (const match of line.matchAll(/(?<![\w)\]])\.([a-z][A-Za-z0-9]*)\b|"([a-z][A-Za-z0-9_.]*)"/g)) {
        const key = keyByName.get(match[1] ?? match[2]);
        if (!key) continue;
        if (!uses.has(key)) uses.set(key, []);
        uses.get(key).push({ file, lines, index });
      }
    });
  }

  const excerpts = new Map();
  for (const [key, found] of uses) {
    // One excerpt per file first, so a string used on several screens shows several screens.
    const firstPerFile = found.filter((use, index) => found.findIndex((other) => other.file === use.file) === index);
    const chosen = [...firstPerFile, ...found.filter((use) => !firstPerFile.includes(use))]
      .slice(0, CODE_EXCERPTS_PER_STRING);
    const texts = chosen.map(({ file, lines, index }) => {
      const excerpt = lines.slice(Math.max(0, index - CODE_CONTEXT_LINES), index + CODE_CONTEXT_LINES + 1);
      const indent = Math.min(...excerpt.filter((line) => line.trim()).map((line) => line.search(/\S/)));
      return `// ${file}:${index + 1}\n${excerpt.map((line) => line.slice(indent)).join("\n")}`;
    });
    if (found.length > chosen.length) texts.push(`// and ${found.length - chosen.length} more uses`);
    excerpts.set(key, texts);
  }
  return excerpts;
}

// The guide and the whole catalog are identical in every request of a run, so the API caches them
// after the first request and the other languages read them at a fraction of the price.
async function buildSystemPrompt(data) {
  const lines = [];
  for (const [key, entry] of Object.entries(data.strings)) {
    if (!isTranslatable(key, entry)) continue;
    lines.push(JSON.stringify({
      key,
      comment: entry.comment,
      english: readText(entry.localizations?.en),
      norwegian: readText(entry.localizations?.nb),
    }));
  }
  return [
    { type: "text", text: await fs.readFile(GUIDE_PATH, "utf8") },
    {
      type: "text",
      text: `Every translatable string in Tidex, one JSON object per line.\n${lines.join("\n")}`,
      cache_control: { type: "ephemeral" },
    },
  ];
}

// The app's finished translations in one language, for consistent terms and form of address.
function languageReference(data, targetLang, pendingItems, sharedByBatches) {
  if (targetLang.code === ENGLISH.code) return [];
  const pendingKeys = new Set(pendingItems.map((item) => item.key));
  const lines = [];
  for (const [key, entry] of Object.entries(data.strings)) {
    if (!isTranslatable(key, entry) || pendingKeys.has(key)) continue;
    const translation = readText(entry.localizations?.[targetLang.code]);
    if (translation === undefined) continue;
    lines.push(JSON.stringify({ key, english: readText(entry.localizations?.en), translation }));
  }
  if (lines.length === 0) return [];
  const block = {
    type: "text",
    text: `Existing ${targetLang.name} translations in Tidex, one JSON object per line.\n${lines.join("\n")}`,
  };
  if (sharedByBatches) block.cache_control = { type: "ephemeral" };
  return [block];
}

async function warmPromptCache(system) {
  await withRetry(() => askClaude(system, [
    { type: "text", text: "Cache warm-up before the translation requests. Return an empty translations list." },
  ]));
}

// Translates one batch of items that share a target language. Returns translations by slot id.
async function translateBatch(items, { system, reference, codeUsage }) {
  const { targetLang } = items[0];
  const strings = items.map((item) => ({
    key: item.key,
    comment: item.comment,
    english: item.english,
    norwegian: item.norwegian,
    current: item.current,
    code: codeUsage.get(item.key),
    translate: item.slots.map(({ id, category }) => (category === null
      ? { id }
      : { id, plural: category, numbers: describeNumbers(numbersOf(targetLang.code, category)) })),
  }));
  const content = [
    ...reference,
    { type: "text", text: JSON.stringify({ targetLanguage: targetLang, strings }, null, 1) },
  ];
  try {
    return await requestTranslations(system, content, items.flatMap((item) => item.slots.map((slot) => slot.id)));
  } catch (error) {
    if (!error.truncated || items.length === 1) throw error;
    const middle = Math.ceil(items.length / 2);
    const halves = await Promise.all([items.slice(0, middle), items.slice(middle)]
      .map((half) => translateBatch(half, { system, reference, codeUsage })));
    return Object.assign(Object.create(null), ...halves);
  }
}

// Writes the catalog the way Xcode's String Catalog editor saves it, so a later
// save in Xcode changes nothing. Only CoreFoundation reproduces Xcode's key order,
// so scripts/xcstrings-set does the formatting.
const XCSTRINGS_SET = path.join(__dirname, "../../scripts/xcstrings-set");

function xcstringsStringify(data) {
  return execFileSync(XCSTRINGS_SET, ["--format-stdin"], {
    input: JSON.stringify(data),
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
  });
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
  let queuedSave = null;
  const saveLimit = pLimit(1);
  // Formatting the catalog takes about a second, so batches that finish together share one save.
  return () => queuedSave ??= saveLimit(async () => {
    queuedSave = null;
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

// Translates the items into their target languages and saves the catalog after every batch.
async function translateItems(data, items, save) {
  const system = await buildSystemPrompt(data);
  const codeUsage = await findCodeUsage(new Set(items.map((item) => item.key)));
  const batchesByLanguage = [];
  const references = new Map();
  for (const targetLang of [ENGLISH, ...TARGET_LANGUAGES]) {
    const ofLanguage = items.filter((item) => item.targetLang.code === targetLang.code);
    if (ofLanguage.length === 0) continue;
    references.set(targetLang.code, languageReference(data, targetLang, ofLanguage, ofLanguage.length > BATCH_SIZE));
    const batches = [];
    for (let i = 0; i < ofLanguage.length; i += BATCH_SIZE) {
      batches.push({ targetLang, items: ofLanguage.slice(i, i + BATCH_SIZE) });
    }
    batchesByLanguage.push(batches);
  }
  const batchCount = batchesByLanguage.flat().length;
  console.log(`${batchCount} batches, up to ${CONCURRENCY} concurrent requests across languages.`);
  // Requests sent together cannot read each other's cache entry, so one request writes it first.
  if (batchCount > 1) await warmPromptCache(system);

  const multibar = process.stderr.isTTY ? new cliProgress.MultiBar(
    {
      clearOnComplete: false,
      hideCursor: true,
      format: " {bar} | {value}/{total} processed | {status}",
    },
    cliProgress.Presets.shades_classic
  ) : null;
  currentMultibar = multibar;
  const overallBar = multibar?.create(items.length, 0, { status: "starting..." });
  const limit = pLimit(CONCURRENCY);
  const formatWarnings = [];
  let completedStrings = 0;
  let translatedStrings = 0;
  let failedBatches = 0;
  let startedBatches = 0;
  let saveError = null;

  // One queue across all languages keeps every request slot useful for small updates.
  const translate = ({ targetLang, items }) => limit(async () => {
    if (isShuttingDown || saveError) return;
    const batchNumber = ++startedBatches;
    try {
      const translations = await translateBatch(items, {
        system, codeUsage, reference: references.get(targetLang.code),
      });
      if (isShuttingDown || saveError) return;
      for (const item of items) {
        const outcome = applyTranslations(data.strings[item.key], item, translations);
        if (outcome === "missing") {
          stats.skippedNoTranslation++;
          reportProgress(`${targetLang.code}: missing translation for ${item.key}`);
        } else if (outcome === "format") {
          const warning = `${targetLang.code}: format mismatch for ${item.key}`;
          formatWarnings.push(warning);
          reportProgress(warning);
          stats.skippedFormatMismatch++;
        } else {
          translatedStrings++;
          stats.translated++;
        }
      }
      try {
        await save();
      } catch (error) {
        saveError = error;
        throw error;
      }
      reportProgress(`${targetLang.name}: saved batch ${batchNumber}/${batchCount}.`);
    } catch (error) {
      if (isShuttingDown) return;
      const message = `Batch ${batchNumber} error for ${targetLang.name}: ${error.message}`;
      stats.errors.push(message);
      failedBatches++;
      reportProgress(message);
    } finally {
      completedStrings += items.length;
      overallBar?.update(completedStrings, {
        status: `${translatedStrings} translated, ${stats.skippedFormatMismatch + stats.skippedNoTranslation} skipped, ${failedBatches} failed batches`,
      });
    }
  });
  // A language's first batch writes the cache entry for its existing translations, and its other
  // batches wait for that so they read it.
  await Promise.all(batchesByLanguage.map(async ([first, ...rest]) => {
    await translate(first);
    await Promise.all(rest.map(translate));
  }));
  multibar?.stop();
  currentMultibar = null;
  if (isShuttingDown) return;
  if (saveError) throw saveError;

  if (formatWarnings.length > 0) {
    console.log(`\nFormat specifier mismatches (${formatWarnings.length}):`);
    formatWarnings.slice(0, 10).forEach((w) => console.log(`  - ${w}`));
    if (formatWarnings.length > 10) {
      console.log(`  ... and ${formatWarnings.length - 10} more`);
    }
  }
}

async function translateXcstrings(filePath) {
  console.log(`\nProcessing: ${filePath}`);
  const content = await fs.readFile(filePath, "utf-8");
  const data = JSON.parse(content);
  const save = createCatalogSaver(filePath, data, content);
  currentSave = save;

  // English comes first, because it is the source for every other language.
  const { stringsNeedingEnglish } = collectTranslationWork(data);
  if (stringsNeedingEnglish.length > 0) {
    console.log(`Found ${stringsNeedingEnglish.length} strings needing English translation (from Norwegian)`);
    await translateItems(data, stringsNeedingEnglish, save);
    if (isShuttingDown) return;
  }

  const { stringsToTranslate } = collectTranslationWork(data);
  console.log(`Found ${stringsToTranslate.length} strings needing translation to other languages`);
  if (stringsToTranslate.length > 0) {
    await translateItems(data, stringsToTranslate, save);
    if (isShuttingDown) return;
  }

  // Clear tracking (file is fully saved)
  currentSave = null;
  const didWork = stringsNeedingEnglish.length + stringsToTranslate.length > 0;
  console.log(didWork ? `\nSaved progress: ${filePath}` : "Nothing to translate!");
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

const INFO_PLIST_COMMENTS = {
  NSCameraUsageDescription: "Camera usage description",
  NSFaceIDUsageDescription: "Face ID usage description",
  NSPhotoLibraryAddUsageDescription: "Photo library save description",
  NSCalendarsFullAccessUsageDescription: "Calendar access description",
};

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

  for (const [key, value] of Object.entries(strings)) {
    if (key === "CFBundleDisplayName" || key === "CFBundleName") continue;
    lines.push(`/* ${INFO_PLIST_COMMENTS[key] ?? key} */`);
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
    const enStrings = parseInfoPlistStrings(await fs.readFile(enPath, "utf-8"));
    const translatableKeys = INFO_PLIST_TRANSLATABLE_KEYS.filter((key) => enStrings[key]);

    const pending = [];
    for (const targetLang of TARGET_LANGUAGES) {
      const infoPlistPath = path.join(TIDEX_APP_PATH, `${targetLang.code}.lproj`, "InfoPlist.strings");
      let existingStrings = {};
      try {
        existingStrings = parseInfoPlistStrings(await fs.readFile(infoPlistPath, "utf-8"));
      } catch {
        // File doesn't exist, that's fine
      }
      const missingKeys = translatableKeys.filter((key) => !existingStrings[key]);
      if (missingKeys.length > 0) pending.push({ targetLang, infoPlistPath, existingStrings, missingKeys });
    }
    if (pending.length === 0) {
      console.log(`  ✓ InfoPlist.strings: ${TARGET_LANGUAGES.length} already complete`);
      return;
    }

    // The app catalog gives the permission texts the same vocabulary as the app.
    const data = JSON.parse(await fs.readFile(DEFAULT_CATALOG, "utf-8"));
    const system = await buildSystemPrompt(data);
    if (pending.length > 1) await warmPromptCache(system);
    const limit = pLimit(CONCURRENCY);
    let created = 0;

    await Promise.all(pending.map(({ targetLang, infoPlistPath, existingStrings, missingKeys }) => limit(async () => {
      console.log(`  Translating InfoPlist.strings for ${targetLang.name}...`);
      const items = missingKeys.map((key, index) => ({
        key,
        comment: "Shown by iOS in the system prompt that asks the user for this permission. It says why Tidex needs the access.",
        english: enStrings[key],
        targetLang,
        slots: [{ id: `ip${index}`, category: null }],
      }));

      try {
        const translations = await translateBatch(items, {
          system,
          reference: languageReference(data, targetLang, [], false),
          codeUsage: new Map(),
        });
        const mergedStrings = { ...existingStrings };
        for (const item of items) {
          const translation = translations[item.slots[0].id];
          if (translation) mergedStrings[item.key] = translation;
        }
        await fs.mkdir(path.dirname(infoPlistPath), { recursive: true });
        await fs.writeFile(infoPlistPath, generateInfoPlistStrings(targetLang.name, mergedStrings));
        created++;
        stats.translated += missingKeys.length;
      } catch (error) {
        console.error(`    ✗ Error translating for ${targetLang.name}: ${error.message}`);
        stats.errors.push(`InfoPlist ${targetLang.name}: ${error.message}`);
      }
    })));

    console.log(
      `  ✓ InfoPlist.strings: ${created} created/updated, ${TARGET_LANGUAGES.length - pending.length} already complete`
    );
  } catch (error) {
    console.error(`  ✗ Error processing InfoPlist.strings: ${error.message}`);
    stats.errors.push(`InfoPlist.strings: ${error.message}`);
  }
}

async function main(args = process.argv.slice(2)) {
  Object.assign(stats, newStats());
  const cliXcstringsFiles = args
    .filter((file) => file.endsWith(".xcstrings"))
    .map((file) => path.resolve(process.cwd(), file));
  const xcstringsFiles = cliXcstringsFiles.length > 0 ? cliXcstringsFiles : [DEFAULT_CATALOG];
  const isTargetedRun = cliXcstringsFiles.length > 0;

  console.log("XCStrings Translator v3");
  console.log("=======================");
  console.log(`Model: ${MODEL} (effort ${EFFORT}) through the ant CLI`);
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
  if (stats.requests > 0) {
    console.log(
      `Claude: ${stats.requests} requests, ${stats.inputTokens} input tokens, ` +
      `${stats.cachedInputTokens} read from cache, ${stats.outputTokens} output tokens`
    );
  }
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

export { main, translateXcstrings, collectTranslationWork, createCatalogSaver, sendToClaude,
  normalizeTranslationsPayload, formatMatches, xcstringsStringify, TARGET_LANGUAGES };

if (import.meta.main) {
  process.on("SIGINT", () => { void saveAndExit("SIGINT"); });
  process.on("SIGTERM", () => { void saveAndExit("SIGTERM"); });
  process.exitCode = await main();
}
