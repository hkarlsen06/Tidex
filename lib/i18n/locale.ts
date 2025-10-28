import { Locale, defaultLocale } from "@/lib/i18n/config";

type SupportedLocale = Locale | string;

const localeMap: Record<Locale, string> = {
  no: "nb-NO",
  en: "en-US",
  de: "de-DE",
};

function normalizeLocale(locale: SupportedLocale): Locale | undefined {
  if (typeof locale !== "string") {
    return locale;
  }

  if (localeMap[locale as Locale]) {
    return locale as Locale;
  }

  const normalized = locale.split("-")[0] as Locale;
  if (localeMap[normalized]) {
    return normalized;
  }

  return undefined;
}

export function getDateLocale(locale: SupportedLocale): string {
  const normalized = normalizeLocale(locale) ?? defaultLocale;
  return localeMap[normalized];
}

export function getDateFormatter(locale: SupportedLocale, options?: Intl.DateTimeFormatOptions) {
  return new Intl.DateTimeFormat(getDateLocale(locale), options);
}

export function formatDate(
  value: string | number | Date,
  locale: SupportedLocale,
  options?: Intl.DateTimeFormatOptions
): string {
  const date = value instanceof Date ? value : new Date(value);
  return getDateFormatter(locale, options).format(date);
}
