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
 * Only currencies with 2 characters or less are included.
 * Krone appears first, followed by popular currencies, then others.
 */
export const CURRENCY_GROUPS: CurrencyGroup[] = [
  {
    label: "Krone",
    options: [{ value: "kr", label: "kr", display: "suffix" }],
  },
  {
    label: "Popular",
    options: [
      { value: "$", label: "Dollar ($)", display: "prefix" },
      { value: "€", label: "Euro (€)", display: "prefix" },
      { value: "£", label: "Pound (£)", display: "prefix" },
      { value: "¥", label: "Yen (¥)", display: "prefix" },
    ],
  },
  {
    label: "Other",
    options: [
      { value: "C$", label: "C$", display: "prefix" },
      { value: "A$", label: "A$", display: "prefix" },
      { value: "S$", label: "S$", display: "prefix" },
      { value: "R$", label: "R$", display: "prefix" },
      { value: "zł", label: "Zloty (zł)", display: "suffix" },
      { value: "Kč", label: "Koruna (Kč)", display: "suffix" },
      { value: "₹", label: "Rupee (₹)", display: "prefix" },
      { value: "₽", label: "Ruble (₽)", display: "suffix" },
      { value: "₩", label: "Won (₩)", display: "prefix" },
      { value: "R", label: "Rand (R)", display: "prefix" },
      { value: "฿", label: "Baht (฿)", display: "prefix" },
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
