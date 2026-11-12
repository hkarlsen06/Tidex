import { afterAll, afterEach, beforeAll, beforeEach, expect, spyOn, test } from "bun:test";
import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  main, collectTranslationWork, formatMatches, normalizeTranslationsPayload, sendToClaude,
  xcstringsStringify, TARGET_LANGUAGES,
} from "./translate-xcstrings.mjs";

const originalPath = process.env.PATH;
let stubDirectory;
let server;
let respond;
let directory;
let log;
let errorLog;

// The translator calls Claude through the ant CLI. Here `ant` is a stand-in that posts the request
// body to this file's server and prints the reply the way ant does, so each test answers in-process.
beforeAll(async () => {
  server = Bun.serve({
    port: 0,
    fetch: async (request) => {
      const body = await request.json();
      const payload = JSON.parse(body.messages[0].content.at(-1).text);
      return respond({ body, items: payload.strings, locale: payload.targetLanguage?.code });
    },
  });
  stubDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "tidex-ant-stub-"));
  await fs.writeFile(path.join(stubDirectory, "ant"), `#!${process.execPath}
    const response = await fetch(process.env.TIDEX_TEST_ANT_URL, { method: "POST", body: await Bun.stdin.text() });
    process.stdout.write(await response.text());
    if (!response.ok) {
      console.error(\`POST "https://api.anthropic.com/v1/messages?beta=true": \${response.status} \${response.statusText}\`);
      process.exit(1);
    }
  `, { mode: 0o755 });
  process.env.PATH = `${stubDirectory}:${originalPath}`;
  process.env.TIDEX_TEST_ANT_URL = server.url.href;
});

afterAll(async () => {
  process.env.PATH = originalPath;
  delete process.env.TIDEX_TEST_ANT_URL;
  await server.stop(true);
  await fs.rm(stubDirectory, { recursive: true, force: true });
});

beforeEach(async () => {
  directory = await fs.mkdtemp(path.join(os.tmpdir(), "tidex-translator-test-"));
  respond = (job) => completed(job.items);
  log = spyOn(console, "log").mockImplementation(() => {});
  errorLog = spyOn(console, "error").mockImplementation(() => {});
});

afterEach(async () => {
  log.mockRestore();
  errorLog.mockRestore();
  await fs.rm(directory, { recursive: true, force: true });
});

function unit(value, state = "translated") {
  return { stringUnit: { state, value } };
}

function plural(forms) {
  return { variations: { plural: Object.fromEntries(
    Object.entries(forms).map(([category, value]) => [category, unit(value)])
  ) } };
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

// Every language holds the same plural forms, as the catalog does after English-only translation.
function pluralCatalog(forms) {
  const data = catalog();
  const localizations = data.strings["z.pay"].localizations;
  for (const locale of Object.keys(localizations)) localizations[locale] = plural(forms);
  return data;
}

async function writeCatalog(data) {
  const file = path.join(directory, "Localizable.xcstrings");
  await fs.writeFile(file, xcstringsStringify(data));
  return file;
}

async function readCatalog(file) {
  return JSON.parse(await fs.readFile(file, "utf8"));
}

function setCatalogString(file, ...args) {
  execFileSync(path.resolve(import.meta.dir, "../../scripts/xcstrings-set"), [
    file, "z.pay", "--skip-xcstringstool-check", ...args,
  ], { encoding: "utf8" });
}

function reply(stopReason, translations = []) {
  return Response.json({
    type: "message",
    stop_reason: stopReason,
    content: [{ type: "text", text: JSON.stringify({ translations }) }],
    usage: { input_tokens: 1, output_tokens: 1 },
  });
}

function completed(items, value = (item) => item.english ?? item.norwegian) {
  return reply("end_turn", items.flatMap((item) =>
    item.translate.map((slot) => ({ id: slot.id, translation: value(item, slot) }))));
}

async function waitUntil(predicate) {
  const deadline = Date.now() + 10_000;
  while (!(await predicate())) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for test progress");
    await Bun.sleep(5);
  }
}

test("translates languages at the same time and preserves every existing entry in Xcode's order", async () => {
  const missing = ["de", "fr", "es", "it", "nl", "ca", "sv", "da"];
  const original = catalog(missing);
  const file = await writeCatalog(original);
  const gate = Promise.withResolvers();
  const started = [];
  respond = async (job) => {
    started.push(job.locale);
    await gate.promise;
    return completed(job.items, () => `Translated ${job.locale} %@`);
  };
  const run = main([file]);
  try {
    await waitUntil(() => started.length === missing.length);
  } finally {
    gate.resolve();
  }
  expect(await run).toBe(0);
  expect(started.sort()).toEqual(missing.sort());
  const saved = await readCatalog(file);
  // The fixture lists z.pay first. Saved catalogs use Xcode's key order.
  expect(Object.keys(saved.strings)).toEqual(["a.untouched", "z.pay"]);
  expect(saved.strings["a.untouched"]).toEqual(original.strings["a.untouched"]);
  for (const [locale, entry] of Object.entries(original.strings["z.pay"].localizations)) {
    expect(saved.strings["z.pay"].localizations[locale]).toEqual(entry);
  }
  expect(saved.strings["z.pay"].localizations.de).toEqual(unit("Translated de %@"));
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
  expect((await fs.readdir(directory)).filter((name) => name.endsWith(".tmp"))).toEqual([]);
});

test("failed batches report failure, keep successful work, and resume only missing translations", async () => {
  const file = await writeCatalog(catalog(["de", "fr"]));
  respond = (job) => job.locale === "de"
    ? Response.json({ type: "error", error: { type: "permission_error", message: "Test failure" } }, { status: 403 })
    : completed(job.items);
  expect(await main([file])).toBe(1);
  const partial = await readCatalog(file);
  expect(partial.strings["z.pay"].localizations.de).toBeUndefined();
  expect(partial.strings["z.pay"].localizations.fr.stringUnit.state).toBe("translated");
  expect(errorLog.mock.calls.flat().some((line) => line.includes("Test failure"))).toBe(true);
  const resumed = [];
  respond = (job) => {
    resumed.push(job.locale);
    return completed(job.items);
  };
  expect(await main([file])).toBe(0);
  expect(resumed).toEqual(["de"]);
});

test("invalid placeholders block success while valid results survive", async () => {
  const file = await writeCatalog(catalog(["de", "fr"]));
  respond = (job) => completed(job.items, () => job.locale === "de" ? "Missing placeholder" : "Valid %@");
  expect(await main([file])).toBe(1);
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de).toBeUndefined();
  expect(saved.strings["z.pay"].localizations.fr.stringUnit.value).toBe("Valid %@");
});

test("a translation may reorder numbered placeholders but never change what one reads", () => {
  expect(formatMatches("%@ worked %lld shifts", "%2$lld Schichten von %1$@")).toBe(true);
  expect(formatMatches("%1$@ to %2$@", "%2$@ から %1$@")).toBe(true);
  // Unnumbered placeholders read in order, so this would read a name as a number.
  expect(formatMatches("%@ worked %lld shifts", "%lld Schichten von %@")).toBe(false);
  expect(formatMatches("%lld shifts", "%d Schichten")).toBe(false);
  expect(formatMatches("%@ and %@", "%1$@ und %1$@")).toBe(false);
  expect(formatMatches("%1$@ to %2$@", "%1$@ bis %@")).toBe(false);
  expect(formatMatches("50%% of %@", "50% von %@")).toBe(false);
  // An extra specifier would read an argument the code never passes.
  expect(formatMatches("%@", "%@ %S")).toBe(false);
  expect(formatMatches("Half of %@", "50% - %@")).toBe(false);
});

test("valid empty translations are retained and never regenerate existing empty English", async () => {
  const original = catalog(["de"], "");
  const file = await writeCatalog(original);
  const locales = [];
  respond = (job) => {
    locales.push(job.locale);
    return completed(job.items, () => "");
  };
  expect(await main([file])).toBe(0);
  expect(locales).toEqual(["de"]);
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de.stringUnit.value).toBe("");
  expect(collectTranslationWork(saved).stringsNeedingEnglish).toHaveLength(0);
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
});

for (const sourceLocale of ["en", "nb"]) {
  test(`editing ${sourceLocale} through xcstrings-set queues other translations and preserves their text`, async () => {
    const original = catalog();
    const file = await writeCatalog(original);
    setCatalogString(file, `--${sourceLocale}`, "Updated pay %@", "--locale", "de=Updated German %@");
    const saved = await readCatalog(file);
    const localizations = saved.strings["z.pay"].localizations;
    // The fixture lists z.pay first. Saved catalogs use Xcode's key order.
    expect(Object.keys(saved.strings)).toEqual(["a.untouched", "z.pay"]);
    expect(saved.strings["a.untouched"]).toEqual(original.strings["a.untouched"]);
    expect(localizations[sourceLocale]).toEqual(unit("Updated pay %@"));
    const otherSource = sourceLocale === "en" ? "nb" : "en";
    expect(localizations[otherSource]).toEqual(original.strings["z.pay"].localizations[otherSource]);
    expect(localizations.de).toEqual(unit("Updated German %@"));
    const expectedLocales = TARGET_LANGUAGES.map(({ code }) => code)
      .filter((locale) => locale !== "nb" && locale !== "de");
    for (const locale of expectedLocales) {
      expect(localizations[locale]).toEqual(unit("Existing %@", "needs_review"));
    }
    const work = collectTranslationWork(saved).stringsToTranslate;
    expect(work.map(({ targetLang }) => targetLang.code)).toEqual(expectedLocales);
    expect(work.every((item) => item.english === localizations.en.stringUnit.value
      && item.norwegian === localizations.nb.stringUnit.value)).toBe(true);
  });
}

test("untranslatable and non-dot-notation keys are never queued", () => {
  const data = catalog(["de"]);
  const pay = data.strings["z.pay"];
  data.strings = {
    "z.flagged": { ...structuredClone(pay), shouldTranslate: false },
    "%@ / %@": { localizations: { en: unit("%1$@ / %2$@") } },
    "No messages": {},
  };
  expect(collectTranslationWork(data).stringsToTranslate).toHaveLength(0);
  expect(collectTranslationWork(data).stringsNeedingEnglish).toHaveLength(0);
});

test("unchanged source text, metadata and target-only edits do not queue other translations", async () => {
  const original = catalog();
  const file = await writeCatalog(original);
  setCatalogString(file, "--en", "Pay %@", "--nb", "Existing %@");
  expect(await readCatalog(file)).toEqual(original);
  setCatalogString(file, "--comment", "Updated context");
  setCatalogString(file, "--locale", "de=Updated German %@");
  const saved = await readCatalog(file);
  const expected = structuredClone(original);
  expected.strings["z.pay"].comment = "Updated context";
  expected.strings["z.pay"].localizations.de = unit("Updated German %@");
  expect(saved).toEqual(expected);
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
});

test("source edits mark nested translation units without replacing their structure", async () => {
  const original = catalog();
  original.strings["z.pay"].localizations.de = plural({ one: "One %@", other: "Many %@" });
  const file = await writeCatalog(original);
  expect(() => setCatalogString(file, "--en", "Updated pay %@")).toThrow();
  expect(await readCatalog(file)).toEqual(original);
  setCatalogString(file, "--en", "Updated pay %@", "--allow-complex");
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de).toEqual({ variations: { plural: {
    one: unit("One %@", "needs_review"), other: unit("Many %@", "needs_review"),
  } } });
});

test("needs_review entries are refreshed from their current text without retranslating other locales", async () => {
  const original = catalog();
  original.strings["z.pay"].localizations.de.stringUnit.state = "needs_review";
  const file = await writeCatalog(original);
  const jobs = [];
  respond = (job) => {
    jobs.push(job);
    return completed(job.items, () => "Updated %@");
  };
  expect(await main([file])).toBe(0);
  expect(jobs.map((job) => job.locale)).toEqual(["de"]);
  expect(jobs[0].items[0].current).toBe("Existing %@");
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de).toEqual(unit("Updated %@"));
  expect(saved.strings["z.pay"].localizations.nb).toEqual(original.strings["z.pay"].localizations.nb);
});

test("English generated from Norwegian becomes the source for the remaining languages", async () => {
  const file = await writeCatalog(catalog(["en", "de"]));
  const calls = [];
  respond = (job) => {
    calls.push(job);
    return completed(job.items, () => "New English %@");
  };
  expect(await main([file])).toBe(0);
  expect(calls.map((job) => job.locale)).toEqual(["en", "de"]);
  expect(calls[1].items[0].english).toBe("New English %@");
});

test("each string comes with the Swift code that shows it", async () => {
  const data = catalog(["de"]);
  data.strings["common.cancel"] = data.strings["z.pay"];
  delete data.strings["z.pay"];
  const file = await writeCatalog(data);
  const jobs = [];
  respond = (job) => {
    jobs.push(job);
    return completed(job.items);
  };
  expect(await main([file])).toBe(0);
  expect(jobs[0].items[0].code[0]).toContain(".commonCancel");
});

test("a request carries existing translations of related strings, not the whole catalog", async () => {
  const data = catalog(["de"]);
  // Complete in every language, so German is the only work.
  const string = (en, de) => ({ localizations: {
    ...structuredClone(data.strings["a.untouched"].localizations), en: unit(en), de: unit(de),
  } });
  data.strings["z.title"] = string("Overview", "Übersicht");
  data.strings["b.wage"] = string("Night pay", "Nachtzuschlag");
  for (let index = 0; index < 40; index++) {
    data.strings[`c.unrelated${index}`] = string(`Something else ${index}`, `Etwas anderes ${index}`);
  }
  const file = await writeCatalog(data);
  const bodies = [];
  respond = (job) => {
    bodies.push(JSON.stringify(job.body));
    return completed(job.items);
  };
  expect(await main([file])).toBe(0);
  expect(bodies).toHaveLength(1);
  // The same screen, and a shared word.
  expect(bodies[0]).toContain("Übersicht");
  expect(bodies[0]).toContain("Nachtzuschlag");
  expect(bodies[0]).not.toContain("unrelated");
});

test("a plural with a missing form is translated as a whole from its current forms", async () => {
  const original = pluralCatalog({ one: "%lld shift", other: "%lld shifts" });
  delete original.strings["z.pay"].localizations.de.variations.plural.other;
  const file = await writeCatalog(original);
  const jobs = [];
  respond = (job) => {
    jobs.push(job);
    return completed(job.items, (_item, slot) => `%lld ${slot.plural}`);
  };
  expect(await main([file])).toBe(0);
  expect(jobs.find((job) => job.locale === "de").items[0].current).toEqual({ one: "%lld shift" });
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de).toEqual(plural({ one: "%lld one", other: "%lld other" }));
  expect(saved.strings["z.pay"].localizations.fr).toEqual(original.strings["z.pay"].localizations.fr);
  expect(saved.strings["z.pay"].comment).toBe(original.strings["z.pay"].comment);
});

test("a language with more plural forms than English gets the forms it lacks", async () => {
  const file = await writeCatalog(pluralCatalog({ one: "%lld shift", other: "%lld shifts" }));
  const jobs = [];
  respond = (job) => {
    jobs.push(job);
    return completed(job.items, (_item, slot) => `%lld ${slot.plural}`);
  };
  expect(await main([file])).toBe(0);
  const russian = jobs.find((job) => job.locale === "ru").items[0];
  expect(russian.current).toEqual({ one: "%lld shift", other: "%lld shifts" });
  expect(russian.translate.map((slot) => `${slot.plural}: ${slot.numbers}`)).toEqual([
    "one: 1, 21, 31, 41, 51, 61, 71, 81, …",
    "few: 2, 3, 4, 22, 23, 24, 32, 33, …",
    "many: 0, 5, 6, 7, 8, 9, 10, 11, …",
    "other: fractions such as 1.5",
  ]);
  // German and Japanese have no form that English lacks.
  expect(jobs.some((job) => job.locale === "de" || job.locale === "ja")).toBe(false);
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.ru).toEqual(plural({
    one: "%lld one", few: "%lld few", many: "%lld many", other: "%lld other",
  }));
  expect(collectTranslationWork(saved).stringsToTranslate).toHaveLength(0);
});

test("a plural form keeps its number unless it covers a single number", async () => {
  const data = pluralCatalog({ one: "every week", other: "every %lld weeks" });
  delete data.strings["z.pay"].localizations.de;
  delete data.strings["z.pay"].localizations.fr;
  delete data.strings["z.pay"].localizations.ru;
  const file = await writeCatalog(data);
  // German "one" is only 1, and French "one" is 0 and 1, which "every week" in the source rules
  // out. Russian "one" is also 21 and 31, where "weekly" would be wrong.
  respond = (job) => completed(job.items, (_item, slot) => slot.plural === "one" ? "weekly" : "every %lld weeks");
  expect(await main([file])).toBe(1);
  const saved = await readCatalog(file);
  expect(saved.strings["z.pay"].localizations.de).toEqual(plural({ one: "weekly", other: "every %lld weeks" }));
  expect(saved.strings["z.pay"].localizations.fr).toEqual(plural({ one: "weekly", other: "every %lld weeks" }));
  expect(saved.strings["z.pay"].localizations.ru).toBeUndefined();
});

test("a plural form for 0 and 1 keeps its number when the source's form for 1 has it", async () => {
  const data = pluralCatalog({ one: "%lld shift", other: "%lld shifts" });
  delete data.strings["z.pay"].localizations.fr;
  const file = await writeCatalog(data);
  respond = (job) => completed(job.items, (_item, slot) => slot.plural === "one" ? "1 shift" : "%lld shifts");
  expect(await main([file])).toBe(1);
  expect((await readCatalog(file)).strings["z.pay"].localizations.fr).toBeUndefined();
});

test("a count in a plain string gets plural forms where the language inflects it", async () => {
  const file = await writeCatalog(catalog(["de", "ru", "pl"], "%lld selected"));
  respond = (job) => completed(job.items, (_item, slot) =>
    job.locale === "ru" ? `%lld ${slot.plural}` : "%lld same");
  expect(await main([file])).toBe(0);
  const { de, ru, pl } = (await readCatalog(file)).strings["z.pay"].localizations;
  expect(de).toEqual(unit("%lld same"));
  expect(ru).toEqual(plural({ one: "%lld one", few: "%lld few", many: "%lld many", other: "%lld other" }));
  // Polish was asked for every form and answered with one wording, so it stays a plain string.
  expect(pl).toEqual(unit("%lld same"));
});

test("a plain string's plural that lacks forms is queued until it has them all", () => {
  const data = catalog([], "%lld selected");
  data.strings["z.pay"].localizations.ru = plural({ one: "%lld one" });
  const work = collectTranslationWork(data).stringsToTranslate;
  expect(work.map((item) => item.targetLang.code)).toEqual(["ru"]);
  expect(work[0].slots.map((slot) => slot.category)).toEqual(["one", "few", "many", "other"]);
});

function twoStringsMissingGerman() {
  const data = catalog(["de"]);
  delete data.strings["a.untouched"].localizations.de;
  return data;
}

test("a response cut off at the output limit is retried in smaller batches", async () => {
  const file = await writeCatalog(twoStringsMissingGerman());
  const sizes = [];
  respond = (job) => {
    sizes.push(job.items.length);
    return job.items.length > 1 ? reply("max_tokens") : completed(job.items);
  };
  expect(await main([file])).toBe(0);
  expect(sizes).toEqual([2, 1, 1]);
  expect(collectTranslationWork(await readCatalog(file)).stringsToTranslate).toHaveLength(0);
});

test("a single string that cannot fit the output limit fails", async () => {
  const file = await writeCatalog(twoStringsMissingGerman());
  let calls = 0;
  respond = () => {
    calls++;
    return reply("max_tokens");
  };
  expect(await main([file])).toBe(1);
  expect(calls).toBe(3);
  expect((await readCatalog(file)).strings["z.pay"].localizations.de).toBeUndefined();
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
  const timeout = spyOn(AbortSignal, "timeout").mockImplementation(() => originalTimeout(200));
  respond = () => new Promise(() => {});
  try {
    await expect(sendToClaude({ messages: [{ role: "user", content: [{ type: "text", text: "{}" }] }] }))
      .rejects.toMatchObject({ name: "TimeoutError" });
  } finally {
    timeout.mockRestore();
  }
});

test("external edits during generation are preserved and reported as a failure", async () => {
  const original = catalog(["de"]);
  const file = await writeCatalog(original);
  const external = structuredClone(original);
  external.strings["z.pay"].comment = "Edited while translating";
  respond = async (job) => {
    await fs.writeFile(file, xcstringsStringify(external));
    return completed(job.items);
  };
  expect(await main([file])).toBe(1);
  expect(await readCatalog(file)).toEqual(external);
  expect(errorLog.mock.calls.flat().some((line) => line.includes("Catalog changed on disk"))).toBe(true);
});

test("SIGTERM saves completed work, aborts pending requests, and exits unsuccessfully", async () => {
  const file = await writeCatalog(catalog(["de", "fr", "es", "it", "nl", "ca", "sv"]));
  const secondFile = path.join(directory, "Second.xcstrings");
  const secondContent = xcstringsStringify(catalog(["de"]));
  await fs.writeFile(secondFile, secondContent);
  respond = (job) => job.locale === "de" ? completed(job.items, () => "Saved %@") : new Promise(() => {});
  const child = Bun.spawn([process.execPath, path.join(import.meta.dir, "translate-xcstrings.mjs"), file, secondFile], {
    stdout: "pipe", stderr: "pipe", env: process.env,
  });
  const output = new Response(child.stdout).text();
  const errors = new Response(child.stderr).text();
  try {
    await waitUntil(async () => (await readCatalog(file))
      .strings["z.pay"].localizations.de?.stringUnit.value === "Saved %@");
    child.kill("SIGTERM");
    expect(await child.exited).toBe(143);
    const saved = await readCatalog(file);
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
