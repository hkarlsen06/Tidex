const DEFAULT_NUMBER_LOCALE = "nb-NO";
const DEFAULT_CURRENCY_SYMBOL = "kr";

type FormatterOptions = Intl.NumberFormatOptions & { locale?: string };

type FormatterCacheKey = string;

const formatterCache = new Map<FormatterCacheKey, Intl.NumberFormat>();

function getCacheKey(locale: string, options: Intl.NumberFormatOptions): FormatterCacheKey {
  return `${locale}:${JSON.stringify(options)}`;
}

function createFormatter(locale: string, options: Intl.NumberFormatOptions) {
  const key = getCacheKey(locale, options);
  const cached = formatterCache.get(key);
  if (cached) {
    return cached;
  }

  const formatter = new Intl.NumberFormat(locale, options);
  formatterCache.set(key, formatter);
  return formatter;
}

function withDefaultDigits(options?: FormatterOptions): { locale: string; options: Intl.NumberFormatOptions } {
  const { locale = DEFAULT_NUMBER_LOCALE, ...intlOptions } = options ?? {};

  return {
    locale,
    options: {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
      ...intlOptions,
    },
  };
}

export function formatNumber(value: number, options?: FormatterOptions): string {
  const { locale, options: intlOptions } = withDefaultDigits(options);
  return createFormatter(locale, intlOptions).format(value);
}

export type FormatCurrencyOptions = FormatterOptions & {
  currencySymbol?: string;
  display?: "suffix" | "prefix" | "none";
  separator?: string;
};

export function formatCurrency(value: number, options?: FormatCurrencyOptions): string {
  const {
    currencySymbol = DEFAULT_CURRENCY_SYMBOL,
    display = "suffix",
    separator,
    ...formatterOptions
  } = options ?? {};

  const formatted = formatNumber(value, formatterOptions);

  if (!currencySymbol || display === "none") {
    return formatted;
  }

  // Default separator: space for suffix currencies (e.g., "100 kr"), no space for prefix (e.g., "$100")
  const defaultSeparator = display === "prefix" ? "" : " ";
  const joiner = separator ?? defaultSeparator;

  if (display === "prefix") {
    return joiner ? `${currencySymbol}${joiner}${formatted}` : `${currencySymbol}${formatted}`;
  }

  return joiner ? `${formatted}${joiner}${currencySymbol}` : `${formatted}${currencySymbol}`;
}

export function formatPlainAmount(value: number, options?: FormatterOptions): string {
  return formatNumber(value, options);
}

export type FormatHoursOptions = FormatterOptions & {
  suffix?: string;
};

export function formatHours(value: number, options?: FormatHoursOptions): string {
  const { suffix = "t", ...formatterOptions } = options ?? {};
  const formatted = formatNumber(value, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    ...formatterOptions,
  });

  return suffix ? `${formatted}${suffix}` : formatted;
}

export function formatCompactAmount(value: number, options?: FormatterOptions): string {
  return formatNumber(value, {
    notation: "compact",
    ...options,
  });
}

export function formatInteger(value: number, options?: FormatterOptions): string {
  return formatNumber(value, {
    minimumIntegerDigits: 2,
    ...options,
  });
}

export function clearNumberFormatterCache() {
  formatterCache.clear();
}
