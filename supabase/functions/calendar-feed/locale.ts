import type { CalendarFeedLocale } from "./types.ts";

const SHIFT_LABELS: Record<CalendarFeedLocale, string> = {
  ar: "وردية",
  bg: "Смяна",
  bn: "শিফট",
  ca: "Torn",
  cs: "Směna",
  da: "Vagt",
  de: "Schicht",
  el: "Βάρδια",
  en: "Shift",
  es: "Turno",
  et: "Vahetus",
  fa: "شیفت",
  fi: "Vuoro",
  fil: "Shift",
  fr: "Service",
  he: "משמרת",
  hi: "शिफ्ट",
  hr: "Smjena",
  hu: "Műszak",
  id: "Shift",
  is: "Vakt",
  it: "Turno",
  ja: "シフト",
  ko: "근무",
  lt: "Pamaina",
  lv: "Maiņa",
  nb: "Vakt",
  nl: "Dienst",
  nn: "Vakt",
  pl: "Zmiana",
  pt: "Turno",
  "pt-br": "Turno",
  ro: "Tură",
  ru: "Смена",
  sk: "Zmena",
  sl: "Izmena",
  sr: "Smena",
  sv: "Pass",
  sw: "Zamu",
  ta: "ஷிப்ட்",
  th: "กะทำงาน",
  tr: "Vardiya",
  uk: "Зміна",
  ur: "شفٹ",
  vi: "Ca làm",
  zh: "班次",
  "zh-hans": "班次",
  "zh-hant": "班次",
};

const SUPPORTED_LOCALES = new Set(Object.keys(SHIFT_LABELS));

export function normalizeCalendarFeedLocale(
  locale: string | null | undefined,
): CalendarFeedLocale {
  const normalized = (locale ?? "").trim().toLowerCase().replaceAll("_", "-");
  if (!normalized) return "en";

  let language: string;
  if (normalized.startsWith("pt-br")) {
    language = "pt-br";
  } else if (normalized.startsWith("zh-hans")) {
    language = "zh-hans";
  } else if (normalized.startsWith("zh-hant")) {
    language = "zh-hant";
  } else {
    const baseLanguage = normalized.split("-")[0] ?? "en";
    language = baseLanguage === "no" ? "nb" : baseLanguage;
  }

  return SUPPORTED_LOCALES.has(language)
    ? language as CalendarFeedLocale
    : "en";
}

export function calendarShiftLabel(locale: string | null | undefined): string {
  return SHIFT_LABELS[normalizeCalendarFeedLocale(locale)];
}
