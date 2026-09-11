import { afterEach, beforeEach, expect, spyOn, test } from "bun:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  main, collectTranslationWork, createStructuredOpenAIResponse,
  normalizeTranslationsPayload, xcstringsStringify, TARGET_LANGUAGES,
} from "./translate-xcstrings.mjs";

const originalFetch = globalThis.fetch;
const originalKey = process.env.OPENAI_API_KEY;
let directory;
let log;
let errorLog;

beforeEach(async () => {
  directory = await fs.mkdtemp(path.join(os.tmpdir(), "tidex-translator-test-"));
  process.env.OPENAI_API_KEY = "test-key";
  log = spyOn(console, "log").mockImplementation(() => {});
  errorLog = spyOn(console, "error").mockImplementation(() => {});
});

afterEach(async () => {
  globalThis.fetch = originalFetch;
  if (originalKey === undefined) delete process.env.OPENAI_API_KEY;
  else process.env.OPENAI_API_KEY = originalKey;
  log.mockRestore();
  errorLog.mockRestore();
  await fs.rm(directory, { recursive: true, force: true });
});

function unit(value, state = "translated") {
  return { stringUnit: { state, value } };
}

function catalog(missing = [], source = "Pay %@") {
  const localizations = Object.fromEntries(
    ["en", ...TARGET_LANGUAGES.map(({ code }) => code)].map((locale) =>
      [locale, unit(locale === "en" ? source : "Existing %@")])
  );
  const untouched = structuredClone(localizations);
  for (const locale of missing) delete localizations[locale];
  return {
    sourceLanguage: "en",
    strings: {
      "z.pay": { comment: "Pay label", extractionState: "manual", localizations },
      "a.untouched": { comment: "Preserve me", localizations: untouched },
    },
    version: "1.0",
  };
}

async function writeCatalog(data) {
  const file = path.join(directory, "Localizable.xcstrings");
  await fs.writeFile(file, xcstringsStringify(data));
  return file;
}

function request(init) {
  const body = JSON.parse(init.body);
  const prompt = body.input[0].content[0].text;
  const items = JSON.parse(prompt.split("Strings to translate:\n")[1].split("\n\nReturn")[0]);
  return { body, items, locale: body.text.format.name.replace("translation_batch_", "") };
}

function completed(items, value = (item) => item.english ?? item.norwegian) {
  return Response.json({
    status: "completed",
    output: [{ type: "message", content: [{
      type: "output_text",
      text: JSON.stringify({ translations: items.map((item) => ({
        id: item.id, translation: value(item),
      })) }),
    }] }],
  });
}

async function waitUntil(predicate) {
  const deadline = Date.now() + 2_000;
  while (!(await predicate())) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for test progress");
    await Bun.sleep(5);
  }
}

test("uses six slots across languages and preserves every existing entry and its order", async () => {
  const missing = ["de", "fr", "es", "it", "nl", "ca", "sv", "da"];
  const original = catalog(missing);
  const file = await writeCatalog(original);
  const gate = Promise.withResolvers();
  const started = [];
  let active = 0;
  let maximum = 0;
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    started.push(job.locale);
    maximum = Math.max(maximum, ++active);
    await gate.promise;
    await Bun.sleep(2);
    active--;
    return completed(job.items, () => `Translated ${job.locale} %@`);
  };
  const run = main([file]);
  try {
    await waitUntil(() => started.length === 6);
    expect(new Set(started).size).toBe(6);
  } finally {
    gate.resolve();
    await run;
  }
  expect(await run).toBe(0);
  expect(maximum).toBe(6);
  expect(started.sort()).toEqual(missing.sort());
  const saved = JSON.parse(await fs.readFile(file, "utf8"));
  expect(Object.keys(saved.strings)).toEqual(Object.keys(original.strings));
  expect(saved.strings["a.untouched"]).toEqual(original.strings["a.untouched"]);
  for (const [locale, entry] of Object.entries(original.strings["z.pay"].localizations)) {
    expect(saved.strings["z.pay"].localizations[locale]).toEqual(entry);
  }
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
  expect((await fs.readdir(directory)).filter((name) => name.endsWith(".tmp"))).toEqual([]);
});

test("failed batches report failure, keep successful work, and resume only missing translations", async () => {
  const file = await writeCatalog(catalog(["de", "fr"]));
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    return job.locale === "de"
      ? Response.json({ error: { message: "Test failure" } }, { status: 403 })
      : completed(job.items);
  };
  expect(await main([file])).toBe(1);
  const partial = JSON.parse(await fs.readFile(file, "utf8"));
  expect(partial.strings["z.pay"].localizations.de).toBeUndefined();
  expect(partial.strings["z.pay"].localizations.fr.stringUnit.state).toBe("translated");
  expect(errorLog.mock.calls.flat().some((line) => line.includes("Test failure"))).toBe(true);
  const resumed = [];
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    resumed.push(job.locale);
    return completed(job.items);
  };
  expect(await main([file])).toBe(0);
  expect(resumed).toEqual(["de"]);
});

test("invalid placeholders block success while valid results survive", async () => {
  const file = await writeCatalog(catalog(["de", "fr"]));
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    return completed(job.items, () => job.locale === "de" ? "Missing placeholder" : "Valid %@");
  };
  expect(await main([file])).toBe(1);
  const saved = JSON.parse(await fs.readFile(file, "utf8"));
  expect(saved.strings["z.pay"].localizations.de).toBeUndefined();
  expect(saved.strings["z.pay"].localizations.fr.stringUnit.value).toBe("Valid %@");
});

test("valid empty translations are retained and never regenerate existing empty English", async () => {
  const original = catalog(["de"], "");
  const file = await writeCatalog(original);
  const locales = [];
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    locales.push(job.locale);
    return completed(job.items, () => "");
  };
  expect(await main([file])).toBe(0);
  expect(locales).toEqual(["de"]);
  const saved = JSON.parse(await fs.readFile(file, "utf8"));
  expect(saved.strings["z.pay"].localizations.de.stringUnit.value).toBe("");
  expect(collectTranslationWork(saved).stringsNeedingEnglish).toHaveLength(0);
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
});

test("needs_review entries are refreshed without retranslating other locales", async () => {
  const original = catalog();
  original.strings["z.pay"].localizations.de.stringUnit.state = "needs_review";
  const file = await writeCatalog(original);
  const locales = [];
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    locales.push(job.locale);
    return completed(job.items, () => "Updated %@");
  };
  expect(await main([file])).toBe(0);
  expect(locales).toEqual(["de"]);
  const saved = JSON.parse(await fs.readFile(file, "utf8"));
  expect(saved.strings["z.pay"].localizations.de).toEqual(unit("Updated %@"));
  expect(saved.strings["z.pay"].localizations.nb).toEqual(original.strings["z.pay"].localizations.nb);
});

test("English generated from Norwegian becomes the source for the remaining languages", async () => {
  const file = await writeCatalog(catalog(["en", "de"]));
  const calls = [];
  globalThis.fetch = async (_url, init) => {
    const job = request(init);
    calls.push(job);
    return completed(job.items, () => "New English %@");
  };
  expect(await main([file])).toBe(0);
  expect(calls.map((job) => job.locale)).toEqual(["en", "de"]);
  expect(calls[1].items[0].english).toBe("New English %@");
});

test("plural translation preserves existing sibling forms and metadata", async () => {
  const original = catalog();
  const localizations = original.strings["z.pay"].localizations;
  for (const locale of Object.keys(localizations)) {
    localizations[locale] = { variations: { plural: {
      one: unit("%lld shift"), other: unit("%lld shifts"),
    } } };
  }
  delete localizations.de.variations.plural.other;
  const file = await writeCatalog(original);
  globalThis.fetch = async (_url, init) => completed(request(init).items, () => "%lld Schichten");
  expect(await main([file])).toBe(0);
  const saved = JSON.parse(await fs.readFile(file, "utf8"));
  expect(saved.strings["z.pay"].localizations.de.variations.plural).toEqual({
    one: unit("%lld shift"), other: unit("%lld Schichten"),
  });
  expect(saved.strings["z.pay"].comment).toBe(original.strings["z.pay"].comment);
});

const responseOptions = {
  schemaName: "test", instructions: "test", prompt: "test",
  expectedIds: ["s0"], maxOutputTokens: 16_384,
};

test("truncated responses are retried once with more output space before parsing", async () => {
  const limits = [];
  globalThis.fetch = async (_url, init) => {
    limits.push(JSON.parse(init.body).max_output_tokens);
    return limits.length === 1
      ? Response.json({ status: "incomplete", incomplete_details: { reason: "max_output_tokens" }, output_text: "{broken" })
      : completed([{ id: "s0", english: "Complete" }]);
  };
  expect(await createStructuredOpenAIResponse(responseOptions)).toEqual({ s0: "Complete" });
  expect(limits).toEqual([16_384, 32_768]);
});

test("repeated truncation fails after the bounded retry", async () => {
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ status: "incomplete", incomplete_details: { reason: "max_output_tokens" } });
  };
  await expect(createStructuredOpenAIResponse(responseOptions)).rejects.toThrow("incomplete: max_output_tokens");
  expect(calls).toBe(2);
});

test("missing, duplicate, unexpected and malformed translation IDs are rejected", () => {
  for (const translations of [
    [], [{ id: "other", translation: "x" }],
    [{ id: "s0", translation: "x" }, { id: "s0", translation: "y" }],
    [{ id: "s0", translation: 7 }],
  ]) {
    expect(() => normalizeTranslationsPayload({ translations }, ["s0"])).toThrow();
  }
});

test("a hanging request is aborted at its deadline", async () => {
  const originalTimeout = AbortSignal.timeout.bind(AbortSignal);
  const timeout = spyOn(AbortSignal, "timeout").mockImplementation((milliseconds) => {
    expect(milliseconds).toBe(120_000);
    return originalTimeout(5);
  });
  globalThis.fetch = async (_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener("abort", () => reject(init.signal.reason), { once: true });
  });
  try {
    await expect(createStructuredOpenAIResponse(responseOptions)).rejects.toMatchObject({ name: "TimeoutError" });
  } finally {
    timeout.mockRestore();
  }
});

test("external edits during generation are preserved and reported as a failure", async () => {
  const original = catalog(["de"]);
  const file = await writeCatalog(original);
  const external = structuredClone(original);
  external.strings["z.pay"].comment = "Edited while translating";
  globalThis.fetch = async (_url, init) => {
    await fs.writeFile(file, xcstringsStringify(external));
    return completed(request(init).items);
  };
  expect(await main([file])).toBe(1);
  expect(JSON.parse(await fs.readFile(file, "utf8"))).toEqual(external);
  expect(errorLog.mock.calls.flat().some((line) => line.includes("Catalog changed on disk"))).toBe(true);
});

test("SIGTERM saves completed work, aborts pending requests, and exits unsuccessfully", async () => {
  const file = await writeCatalog(catalog(["de", "fr", "es", "it", "nl", "ca", "sv"]));
  const secondFile = path.join(directory, "Second.xcstrings");
  const secondContent = xcstringsStringify(catalog(["de"]));
  await fs.writeFile(secondFile, secondContent);
  const preload = path.join(directory, "mock-network.mjs");
  await fs.writeFile(preload, `
    globalThis.fetch = async (_url, init) => {
      const body = JSON.parse(init.body);
      if (body.text.format.name !== "translation_batch_de") {
        return new Promise((_resolve, reject) => {
          init.signal.addEventListener("abort", () => reject(init.signal.reason), { once: true });
        });
      }
      const items = JSON.parse(body.input[0].content[0].text.split("Strings to translate:\\n")[1].split("\\n\\nReturn")[0]);
      return Response.json({ status: "completed", output_text: JSON.stringify({
        translations: items.map((item) => ({ id: item.id, translation: "Saved %@" }))
      }) });
    };
  `);
  const child = Bun.spawn([process.execPath, "--preload", preload,
    path.join(import.meta.dir, "translate-xcstrings.mjs"), file, secondFile], {
    stdout: "pipe", stderr: "pipe", env: { ...process.env, OPENAI_API_KEY: "test-key" },
  });
  const output = new Response(child.stdout).text();
  const errors = new Response(child.stderr).text();
  try {
    await waitUntil(async () => JSON.parse(await fs.readFile(file, "utf8"))
      .strings["z.pay"].localizations.de?.stringUnit.value === "Saved %@");
    child.kill("SIGTERM");
    expect(await child.exited).toBe(143);
    const saved = JSON.parse(await fs.readFile(file, "utf8"));
    expect(saved.strings["z.pay"].localizations.de.stringUnit.value).toBe("Saved %@");
    expect(saved.strings["z.pay"].localizations.fr).toBeUndefined();
    expect(await fs.readFile(secondFile, "utf8")).toBe(secondContent);
    expect(await output).not.toContain(`Processing: ${secondFile}`);
    expect((await fs.readdir(directory)).filter((name) => name.endsWith(".tmp"))).toEqual([]);
  } finally {
    child.kill();
    await child.exited;
    await Promise.all([output, errors]);
  }
});
