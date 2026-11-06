import type {
  OvertimeConfig,
  OvertimeRule,
  SupplementRule,
} from "../shared/payroll/types";
import { getNorwegianHolidays } from "../shared/payroll/norwegianHolidays";
import { validatePresentations } from "./presentation";

export const CATALOGUE_REVISION = "2026-11";
export const CHECKED_ON = "2026-11-06";
export const VALID_THROUGH = "2028-12-31";
export const REVIEW_ON = "2026-12-01";
export const allDays = [1, 2, 3, 4, 5, 6, 7];
export const weekdays = [1, 2, 3, 4, 5];
export const minimumSource =
  "https://www.arbeidstilsynet.no/lonn-og-ansettelse/lonn/minstelonn/";
export type CategoryInput = readonly [
  level: number,
  en: string,
  nb: string,
  rate: number,
];
export type TariffCategory = {
  level: number;
  label_en: string;
  label_nb: string;
};
export type TariffPresentationOption = {
  dimension_id: string;
  label_en: string;
  label_nb: string;
  help_en?: string;
  help_nb?: string;
  value: string;
  value_en: string;
  value_nb: string;
};
export type TariffPresentation = {
  family_id: string;
  name_en: string;
  name_nb: string;
  kind: "agreement" | "statutory";
  search_terms: string[];
  category_group: string;
  options: TariffPresentationOption[];
};
export type CatalogueVersion = {
  id: string;
  tariff_type_id: string;
  effective_date: string;
  legal_effective_date: string;
  name: string;
  rates: Record<string, number>;
  categories: TariffCategory[];
  supplements: { rules: SupplementRule[] };
  overtime: OvertimeConfig;
  source_url: string;
  source_urls: string[];
  verified_on: string;
  review_on: string;
  valid_through: string;
  catalogue_revision: string;
  coverage_note: string;
  coverage_note_en: string;
  coverage_note_nb: string;
};
export type CatalogueEntry = {
  type: {
    id: string;
    display_name: string;
    display_name_en: string;
    display_name_nb: string;
    description: string;
    country: string;
    is_default: boolean;
    presentation?: TariffPresentation;
  };
  version: CatalogueVersion;
};
export function tariff(input: {
  id: string;
  en: string;
  nb: string;
  legalDate: string;
  categories: CategoryInput[];
  source: string;
  sources?: string[];
  rules?: SupplementRule[];
  overtime?: OvertimeConfig;
  noteEn: string;
  noteNb: string;
}): CatalogueEntry {
  return {
    type: {
      id: input.id,
      display_name: input.nb,
      display_name_en: input.en,
      display_name_nb: input.nb,
      description: input.noteNb,
      country: "NO",
      is_default: input.id === "hk_retail",
    },
    version: {
      id: `catalogue:${CATALOGUE_REVISION}:${input.id}`,
      tariff_type_id: input.id,
      effective_date: CHECKED_ON,
      legal_effective_date: input.legalDate,
      name: input.nb,
      categories: input.categories.map(([level, label_en, label_nb]) => ({
        level,
        label_en,
        label_nb,
      })),
      rates: Object.fromEntries(
        input.categories.map(([level, , , rate]) => [String(level), rate]),
      ),
      supplements: { rules: input.rules ?? [] },
      overtime: input.overtime ?? statutoryOvertime(),
      source_url: input.source,
      source_urls: [...new Set([input.source, ...(input.sources ?? [])])],
      verified_on: CHECKED_ON,
      review_on: REVIEW_ON,
      valid_through: VALID_THROUGH,
      catalogue_revision: CATALOGUE_REVISION,
      coverage_note: input.noteEn,
      coverage_note_en: input.noteEn,
      coverage_note_nb: input.noteNb,
    },
  };
}
export function statutoryOvertime(weekly = 40): OvertimeConfig {
  return {
    enabled: true,
    weeklyThresholdHours: weekly,
    retainSupplements: true,
    rules: [
      overtimeRule(allDays, "00:00", "24:00", 40),
      {
        ...overtimeRule(allDays, "00:00", "24:00", 40),
        appliesOnHolidays: true,
      },
    ],
  };
}
export function overtimeRule(
  days: number[],
  from: `${number}:${number}`,
  to: `${number}:${number}`,
  percent: number,
): OvertimeRule {
  return { days, from, to, percent, appliesOnHolidays: false };
}
export function standardOvertime(
  weekly = 37.5,
  morning: `${number}:${number}` = "06:00",
  saturday: `${number}:${number}` = "24:00",
  retain = false,
): OvertimeConfig {
  const rules = [
    overtimeRule([1, 2, 3, 4, 5, 6], "00:00", morning, 100),
    overtimeRule([1, 2, 3, 4, 5, 6], morning, "21:00", 50),
    overtimeRule([1, 2, 3, 4, 5, 6], "21:00", "24:00", 100),
    overtimeRule([7], "00:00", "24:00", 100),
    {
      ...overtimeRule(allDays, "00:00", "24:00", 100),
      appliesOnHolidays: true,
    },
  ];
  if (saturday !== "24:00")
    rules.push(overtimeRule([6], saturday, "24:00", 100));
  return {
    enabled: true,
    weeklyThresholdHours: weekly,
    retainSupplements: retain,
    rules: rules.filter((rule) => rule.from !== rule.to),
  };
}
export function dateOffset(date: string, days: number): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}
export const calendars = [2026, 2027, 2028].map((year) => {
  const holidays = getNorwegianHolidays(year).map((h) => h.date);
  const easter = getNorwegianHolidays(year).find(
    (h) => h.nameEN === "Easter Sunday",
  )?.date;
  if (!easter) throw new Error(`Missing Easter ${year}`);
  return {
    year,
    holidays,
    easter,
    easterEve: dateOffset(easter, -1),
    whitEve: dateOffset(easter, 48),
    maundyEve: dateOffset(easter, -4),
    christmasEve: `${year}-12-24`,
    newYearEve: `${year}-12-31`,
  };
});
export const holidayDates = calendars.flatMap((c) => c.holidays);
export function datedPercent(
  dates: string[],
  from: `${number}:${number}`,
  to: `${number}:${number}`,
  percent: number,
  options: Partial<SupplementRule> = {},
): SupplementRule {
  return { days: allDays, dates, from, to, percent, ...options };
}
export function holidayRules(
  percent: number,
  eveTime: `${number}:${number}`,
  includeMaundyEve = false,
  easterEveTime: `${number}:${number}` = "00:00",
): SupplementRule[] {
  return [
    datedPercent(holidayDates, "00:00", "24:00", percent),
    datedPercent(
      calendars.map((c) => c.easterEve),
      easterEveTime,
      "24:00",
      percent,
    ),
    datedPercent(
      calendars.flatMap((c) => [
        c.whitEve,
        c.christmasEve,
        c.newYearEve,
        ...(includeMaundyEve ? [c.maundyEve] : []),
      ]),
      eveTime,
      "24:00",
      percent,
    ),
  ];
}
export const scopeEn =
  "Hourly minimum and ordinary time supplements. Confirm your employment contract and work schedule. Local allowances, paid absence and expense reimbursements are not included.";
export const scopeNb =
  "Timesats og ordinære tillegg. Kontroller arbeidsavtalen og arbeidstidsordningen din. Lokale tillegg, betalt fravær og utgiftsrefusjon er ikke inkludert.";

function dateIsValid(value: string): boolean {
  return (
    /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString().slice(0, 10) === value
  );
}
function minutes(value: string): number {
  if (!/^\d{2}:\d{2}$/.test(value)) return NaN;
  const [hour, minute] = value.split(":").map(Number);
  return hour >= 0 &&
    hour <= 24 &&
    minute >= 0 &&
    minute < 60 &&
    (hour < 24 || minute === 0)
    ? hour * 60 + minute
    : NaN;
}
export function validateCatalogue(entries: CatalogueEntry[]): void {
  validatePresentations(entries);
  const ids = new Set<string>();
  for (const entry of entries) {
    const { type, version } = entry;
    if (
      ids.has(type.id) ||
      type.id !== version.tariff_type_id ||
      !/^[a-z][a-z0-9_]+$/.test(type.id)
    )
      throw new Error(`Duplicate or invalid tariff ${type.id}`);
    ids.add(type.id);
    for (const value of [
      version.effective_date,
      version.legal_effective_date,
      version.verified_on,
      version.review_on,
      version.valid_through,
    ])
      if (!dateIsValid(value))
        throw new Error(`Invalid tariff date ${type.id}`);
    if (
      version.legal_effective_date > version.effective_date ||
      version.review_on <= version.verified_on ||
      version.valid_through < version.effective_date
    )
      throw new Error(`Invalid date order ${type.id}`);
    if (
      !version.source_urls.length ||
      !version.source_urls.every((url) => new URL(url).protocol === "https:")
    )
      throw new Error(`Missing HTTPS source ${type.id}`);
    const levels = new Set<number>();
    for (const c of version.categories) {
      const rate = version.rates[String(c.level)];
      if (
        !Number.isSafeInteger(c.level) ||
        levels.has(c.level) ||
        !c.label_en ||
        !c.label_nb ||
        !Number.isFinite(rate) ||
        rate <= 0
      )
        throw new Error(`Invalid category ${type.id}:${c.level}`);
      levels.add(c.level);
    }
    if (levels.size !== Object.keys(version.rates).length || levels.size === 0)
      throw new Error(`Unlabelled rate ${type.id}`);
    if (
      version.overtime.baseRate !== undefined &&
      (!Number.isFinite(version.overtime.baseRate) ||
        version.overtime.baseRate <= 0)
    ) {
      throw new Error(`Invalid overtime base ${type.id}`);
    }
    for (const rule of [
      ...version.supplements.rules,
      ...version.overtime.rules,
      ...(version.overtime.retainedSupplements ?? []),
    ]) {
      const from = minutes(rule.from),
        to = minutes(rule.to);
      if (
        !Number.isFinite(from) ||
        !Number.isFinite(to) ||
        from === to ||
        rule.days.length === 0 ||
        rule.days.some((d) => !Number.isInteger(d) || d < 1 || d > 7)
      )
        throw new Error(`Invalid time rule ${type.id}`);
      if (
        !("appliesOnHolidays" in rule) &&
        rule.shiftStartBefore !== undefined &&
        (!Number.isFinite(minutes(rule.shiftStartBefore)) ||
          minutes(rule.shiftStartBefore) <= 0)
      ) {
        throw new Error(`Invalid shift start cutoff ${type.id}`);
      }
      if ("appliesOnHolidays" in rule && from > to)
        throw new Error(`Overnight overtime must be split ${type.id}`);
      if (
        !("appliesOnHolidays" in rule) &&
        (rule.rate === undefined) === (rule.percent === undefined)
      )
        throw new Error(
          `Supplement needs exactly one monetary basis ${type.id}`,
        );
      if (!("appliesOnHolidays" in rule)) {
        for (const value of [
          rule.rate,
          rule.minimumRate,
          rule.percentageBaseRate,
        ]) {
          if (value !== undefined && (!Number.isFinite(value) || value < 0))
            throw new Error(`Invalid supplement ${type.id}`);
        }
      }
      if ("appliesOnHolidays" in rule && rule.percent <= 0)
        throw new Error(`Invalid overtime percentage ${type.id}`);
      if (
        rule.percent !== undefined &&
        (!Number.isFinite(rule.percent) || rule.percent < 0)
      )
        throw new Error(`Invalid percentage ${type.id}`);
      if ("dates" in rule && rule.dates?.some((d) => !dateIsValid(d)))
        throw new Error(`Invalid rule date ${type.id}`);
      if (
        "excludedDates" in rule &&
        rule.excludedDates?.some((d) => !dateIsValid(d))
      )
        throw new Error(`Invalid rule exclusion ${type.id}`);
      if (
        !("appliesOnHolidays" in rule) &&
        [
          ...(rule.shiftStartDates ?? []),
          ...(rule.excludedShiftStartDates ?? []),
        ].some((d) => !dateIsValid(d))
      )
        throw new Error(`Invalid shift-start date ${type.id}`);
    }
    if (
      version.overtime.premiumBaseMultiplier !== undefined &&
      (!Number.isFinite(version.overtime.premiumBaseMultiplier) ||
        version.overtime.premiumBaseMultiplier <= 0)
    )
      throw new Error(`Invalid overtime basis ${type.id}`);
    if (
      !Number.isFinite(version.overtime.weeklyThresholdHours) ||
      version.overtime.weeklyThresholdHours <= 0
    )
      throw new Error(`Invalid overtime threshold ${type.id}`);
  }
  if (entries.filter((entry) => entry.type.is_default).length !== 1)
    throw new Error("Catalogue must have one default");
}
