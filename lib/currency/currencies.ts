/**
 * Currency Configuration
 *
 * Defines all supported currencies for the currency selector.
 * The `value` field is stored directly in the database and displayed as-is.
 * The `display` field determines prefix/suffix positioning.
 */

export type CurrencyDisplay = "prefix" | "suffix";

export type CurrencyOption = {
  /** The symbol/text stored in DB and displayed (e.g., "$", "€", "kr", "NOK") */
  value: string;
  /** Label shown in the dropdown selector */
  label: string;
  /** Whether symbol appears before or after the amount */
  display: CurrencyDisplay;
};

export type CurrencyGroup = {
  /** Group label shown in dropdown */
  label: string;
  /** Currency options in this group */
  options: CurrencyOption[];
};

/**
 * Grouped currency options for the selector dropdown.
 * Norwegian Krone options appear first, followed by popular currencies, then others.
 */
export const CURRENCY_GROUPS: CurrencyGroup[] = [
  {
    label: "Norwegian Krone",
    options: [
      { value: "kr", label: "kr", display: "suffix" },
      { value: "NOK", label: "NOK", display: "suffix" },
    ],
  },
  {
    label: "Popular",
    options: [
      { value: "$", label: "US Dollar ($)", display: "prefix" },
      { value: "€", label: "Euro (€)", display: "prefix" },
      { value: "£", label: "British Pound (£)", display: "prefix" },
      { value: "SEK", label: "Swedish Krona (SEK)", display: "suffix" },
      { value: "DKK", label: "Danish Krone (DKK)", display: "suffix" },
    ],
  },
  {
    label: "Other",
    options: [
      { value: "CHF", label: "Swiss Franc (CHF)", display: "prefix" },
      { value: "¥", label: "Japanese Yen (¥)", display: "prefix" },
      { value: "C$", label: "Canadian Dollar (C$)", display: "prefix" },
      { value: "A$", label: "Australian Dollar (A$)", display: "prefix" },
      { value: "zł", label: "Polish Zloty (zł)", display: "suffix" },
      { value: "Kč", label: "Czech Koruna (Kč)", display: "suffix" },
      { value: "₹", label: "Indian Rupee (₹)", display: "prefix" },
      { value: "R$", label: "Brazilian Real (R$)", display: "prefix" },
      { value: "₽", label: "Russian Ruble (₽)", display: "suffix" },
      { value: "₩", label: "South Korean Won (₩)", display: "prefix" },
      { value: "CN¥", label: "Chinese Yuan (CN¥)", display: "prefix" },
      { value: "MX$", label: "Mexican Peso (MX$)", display: "prefix" },
      { value: "S$", label: "Singapore Dollar (S$)", display: "prefix" },
      { value: "HK$", label: "Hong Kong Dollar (HK$)", display: "prefix" },
      { value: "NZ$", label: "New Zealand Dollar (NZ$)", display: "prefix" },
      { value: "R", label: "South African Rand (R)", display: "prefix" },
      { value: "฿", label: "Thai Baht (฿)", display: "prefix" },
      { value: "ISK", label: "Icelandic Króna (ISK)", display: "suffix" },
    ],
  },
];

/**
 * Flat list of all currency options for lookup purposes
 */
export const ALL_CURRENCIES: CurrencyOption[] = CURRENCY_GROUPS.flatMap(
  (group) => group.options
);

/**
 * Default currency configuration
 */
export const DEFAULT_CURRENCY: CurrencyOption = {
  value: "kr",
  label: "kr",
  display: "suffix",
};

/**
 * Get currency configuration by its stored value (symbol).
 * Returns default currency if not found.
 */
export function getCurrencyConfig(currencyValue: string): CurrencyOption {
  const found = ALL_CURRENCIES.find((c) => c.value === currencyValue);
  return found ?? DEFAULT_CURRENCY;
}
