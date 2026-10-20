// deno-lint-ignore-file no-import-prefix
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeCalendarFeedLocale } from "./locale.ts";

Deno.test("normalizeCalendarFeedLocale matches supported shift notification locales", () => {
  assertEquals(normalizeCalendarFeedLocale("nb-NO"), "nb");
  assertEquals(normalizeCalendarFeedLocale("no_NO"), "nb");
  assertEquals(normalizeCalendarFeedLocale("nn-NO"), "nn");
  assertEquals(normalizeCalendarFeedLocale("pt-BR"), "pt-br");
  assertEquals(normalizeCalendarFeedLocale("zh-Hans-CN"), "zh-hans");
  assertEquals(normalizeCalendarFeedLocale("zh-Hant-TW"), "zh-hant");
  assertEquals(normalizeCalendarFeedLocale("fil-PH"), "fil");
  assertEquals(normalizeCalendarFeedLocale("unsupported"), "en");
});
