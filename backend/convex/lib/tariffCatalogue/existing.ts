import type { SupplementRule } from "../shared/payroll/types";
import {
  allDays,
  calendars,
  CHECKED_ON,
  dateOffset,
  datedPercent,
  holidayDates,
  holidayRules,
  minimumSource,
  scopeEn,
  scopeNb,
  standardOvertime,
  tariff,
  weekdays,
  type CategoryInput,
  type CatalogueEntry,
} from "./model";

const hkSource =
  "https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/";
export const hkRules: SupplementRule[] = [
  { days: weekdays, from: "18:00", to: "21:00", rate: 22 },
  { days: weekdays, from: "21:00", to: "24:00", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "24:00", rate: 110 },
  { days: [7], from: "00:00", to: "24:00", rate: 115 },
];
export const existingTariffs: CatalogueEntry[] = [
  tariff({
    id: "hk_retail",
    en: "Retail, HK–Virke",
    nb: "Butikk, HK–Virke",
    legalDate: "2026-04-01",
    source: hkSource,
    categories: [
      [-1, "Under 16", "Under 16 år", 136.41],
      [-2, "16–17 years", "16–17 år", 139.4],
      ...[195.04, 195.88, 197.96, 203.55, 221.31, 271.64].map(
        (rate, i): CategoryInput => [
          i + 1,
          `Level ${i + 1}`,
          `Trinn ${i + 1}`,
          rate,
        ],
      ),
    ],
    rules: hkRules,
    overtime: standardOvertime(37.5, "08:00"),
    noteEn:
      "Standard retail table. Earlier 2026 increases were handled separately as backpay. Local pay, apprentices and holiday-eve arrangements require your contract. Weekly overtime threshold only.",
    noteNb:
      "Vanlig butikktabell. Tidligere tillegg i 2026 ble håndtert som etterbetaling. Lokal lønn, lærlinger og helligdagsaftener krever arbeidsavtalen din. Overtid beregnes bare etter uketerskelen.",
  }),
  tariff({
    id: "bygg_allmenngjort",
    en: "Construction, statutory minimum",
    nb: "Bygg, allmenngjort",
    legalDate: "2025-06-15",
    source: minimumSource,
    categories: [
      [-1, "Under 18", "Under 18 år", 162.44],
      [1, "Unskilled, no experience", "Ufaglært uten bransjeerfaring", 239.61],
      [2, "Unskilled, at least 1 year", "Ufaglært, minst 1 års erfaring", 249],
      [3, "Qualified worker", "Fagarbeider", 264.32],
    ],
    noteEn: `${scopeEn} Weekly overtime threshold only.`,
    noteNb: `${scopeNb} Overtid beregnes bare etter uketerskelen.`,
  }),
  tariff({
    id: "renhold_allmenngjort",
    en: "Cleaning, statutory minimum",
    nb: "Renhold, allmenngjort",
    legalDate: "2025-06-15",
    source: minimumSource,
    categories: [
      [-1, "Under 18", "Under 18 år", 185.55],
      [1, "Adult", "Voksen", 236.54],
    ],
    rules: [{ days: allDays, from: "21:00", to: "06:00", rate: 29 }],
    noteEn: `${scopeEn} Not the collective agreement. Weekly overtime threshold only.`,
    noteNb: `${scopeNb} Ikke full tariffavtale. Overtid beregnes bare etter uketerskelen.`,
  }),
];

const riksRatesSource =
  "https://www.fellesforbundet.no/globalassets/lonn-og-tariffsaker/tariffavtaler/overenskomster-20262028/satser-landsoverenskomst-fra-1.-juni-2026.pdf";
const riksRulesSource =
  "https://www.nhoreiseliv.no/contentassets/3b3a903b8ed84576a60df30606b3fe5b/riksavtalen-2024---2026.pdf";
const seniorities = [0, 2, 4, 6, 8, 10];
const riksBands = [
  {
    en: "Other staff, no certificate",
    nb: "Øvrige, uten fagbrev",
    levels: [1, 7, 2, 8, 9, 3],
    normal: [215.29, 218.9, 232.51, 236.59, 239.21, 241.61],
    reduced: [227.17, 230.98, 245.34, 249.65, 252.41, 254.95],
  },
  {
    en: "Other staff, qualified",
    nb: "Øvrige, med fagbrev",
    levels: [4, 10, 5, 11, 12, 6],
    normal: [230.29, 233.9, 247.51, 251.59, 254.21, 256.61],
    reduced: [243, 246.81, 261.17, 265.48, 268.24, 270.77],
  },
  {
    en: "Cook, no certificate",
    nb: "Kokk, uten fagbrev",
    levels: [101, 102, 103, 104, 105, 106],
    normal: [220.21, 221.83, 235.44, 236.59, 239.21, 241.61],
    reduced: [232.36, 234.07, 248.44, 249.65, 252.41, 254.95],
  },
  {
    en: "Cook, qualified",
    nb: "Kokk, med fagbrev",
    levels: [111, 112, 113, 114, 115, 116],
    normal: [235.21, 236.83, 250.44, 251.59, 254.21, 256.61],
    reduced: [248.19, 249.9, 264.26, 265.48, 268.24, 270.77],
  },
];
const riksCategories = (reduced: boolean): CategoryInput[] => [
  [-3, "Under 17", "Under 17 år", reduced ? 161.53 : 153.08],
  [-1, "17 years", "17 år", reduced ? 171.55 : 162.58],
  [-2, "18 years", "18 år", reduced ? 186.6 : 176.84],
  ...riksBands.flatMap((band) =>
    seniorities.map(
      (years, i): CategoryInput => [
        band.levels[i],
        `${band.en}, ${years === 0 ? (band.en.includes("no certificate") ? "20+, or 4 months of practice after 18" : "entry") : `${years} years`}`,
        `${band.nb}, ${years === 0 ? (band.nb.includes("uten fagbrev") ? "over 20 år eller 4 måneders praksis etter 18 år" : "begynner") : `${years} år`}`,
        (reduced ? band.reduced : band.normal)[i],
      ],
    ),
  ),
];
for (const week of [37.5, 35.5])
  for (const role of ["other", "guard", "manual"]) {
    const reduced = week === 35.5;
    const roleEn =
      role === "other"
        ? "ordinary night work"
        : role === "guard"
          ? "night guard"
          : "night guard with agreed manual work";
    const roleNb =
      role === "other"
        ? "ordinært nattarbeid"
        : role === "guard"
          ? "nattevakt"
          : "nattevakt med avtalt manuelt arbeid";
    const excluded = calendars.flatMap((c) => [
      ...c.holidays,
      c.easterEve,
      c.whitEve,
      c.christmasEve,
      c.newYearEve,
    ]);
    const rules: SupplementRule[] = [
      {
        days: weekdays,
        from: "21:00",
        to: "24:00",
        rate: 16.59,
        excludedShiftStartDates: excluded,
      },
      {
        days: [6],
        from: "14:00",
        to: "24:00",
        rate: 31.52,
        excludedShiftStartDates: excluded,
      },
      {
        days: [7],
        from: "06:00",
        to: "24:00",
        rate: 31.52,
        excludedShiftStartDates: excluded,
      },
      {
        days: allDays,
        from: "00:00",
        to: "06:00",
        rate: role === "other" ? 58.04 : 43.94,
        excludedShiftStartDates: excluded,
      },
    ];
    if (role === "manual")
      rules.push({
        days: allDays,
        from: "00:00",
        to: "06:00",
        rate: 24.87,
        stackingGroup: "manual",
      });
    for (const rule of rules)
      if (rule.stackingGroup !== "manual")
        rule.excludedShiftStartDates = excluded;
    rules.push({
      days: allDays,
      from: "00:00",
      to: "24:00",
      percent: 100,
      shiftStartDates: holidayDates,
    });
    const eves = calendars.flatMap((c) => [
      c.easterEve,
      c.whitEve,
      c.christmasEve,
      c.newYearEve,
    ]);
    rules.push({
      days: allDays,
      from: "15:00",
      to: "24:00",
      percent: 100,
      dates: eves,
      shiftStartDates: eves,
    });
    rules.push({
      days: allDays,
      from: "00:00",
      to: "24:00",
      percent: 100,
      dates: eves.map((d) => dateOffset(d, 1)),
      shiftStartDates: eves,
    });
    if (role !== "other") {
      const followingNights = [
        ...new Set(
          [...holidayDates, ...eves].map((date) => dateOffset(date, 1)),
        ),
      ];
      rules.push({
        days: allDays,
        from: "00:00",
        to: "24:00",
        percent: 100,
        shiftStartDates: followingNights,
        shiftStartBefore: "06:00",
      });
    }
    existingTariffs.push(
      tariff({
        id:
          role === "other" && !reduced
            ? "riksavtalen_hotel"
            : `riksavtalen_${role}_${reduced ? 355 : 375}`,
        en: `Hotel and restaurant, ${week} h, ${roleEn}`,
        nb: `Hotell og restaurant, ${String(week).replace(".", ",")} t, ${roleNb}`,
        legalDate: "2026-06-01",
        source: riksRatesSource,
        sources: [riksRulesSource],
        categories: riksCategories(reduced),
        rules,
        overtime: standardOvertime(week, "06:00", "24:00", true),
        noteEn:
          "Fixed hourly pay and ordinary UB. Holiday pay follows the shift's start day. Work-plan overtime, percentage-paid servers and local allowances are not included. Weekly overtime threshold only.",
        noteNb:
          "Fast timelønn og ordinære tillegg. Helligdagsbetaling følger vaktens startdag. Overtid etter arbeidsplan, prosentlønnede servitører og lokale tillegg er ikke inkludert. Overtid beregnes bare etter uketerskelen.",
      }),
    );
  }

const securitySource =
  "https://www.nhosh.no/contentassets/385855c87911442eaf6c8fccaf866049/tariffbrev-2026-vekter.pdf";
const securityText =
  "https://www.virke.no/globalassets/uploaded-files/finn-tariffavtale/vekteroverenskomsten-2024-2026-nho-service-og-handel-naf.pdf";
const securityBands = [
  "0–12 months",
  "1–3 years",
  "3–5 years",
  "5–7 years",
  "7–9 years",
  "9+ years",
];
const securityBandsNb = [
  "0–12 måneder",
  "1–3 år",
  "3–5 år",
  "5–7 år",
  "7–9 år",
  "Minst 9 år",
];
for (const [week, rates] of [
  [37.5, [246.22, 248.72, 250.92, 251.92, 253.72, 255.72]],
  [35.5, [260.08, 262.72, 265.05, 266.1, 268, 270.12]],
  [33.6, [274.81, 277.6, 280.05, 281.17, 283.18, 285.41]],
] satisfies [number, number[]][]) {
  const holidayPremiums: SupplementRule[] = [];
  for (const c of calendars) {
    for (const [start, end, from] of [
      [dateOffset(c.easter, -4), dateOffset(c.easter, 2), "18:00"],
      [`${c.year}-04-30`, `${c.year}-05-02`, "21:00"],
      [`${c.year}-05-16`, `${c.year}-05-18`, "21:00"],
      [dateOffset(c.easter, 38), dateOffset(c.easter, 40), "18:00"],
      [c.whitEve, dateOffset(c.easter, 51), "15:00"],
      [c.christmasEve, `${c.year}-12-27`, "15:00"],
      [c.newYearEve, `${c.year + 1}-01-02`, "15:00"],
    ] satisfies [string, string, `${number}:${number}`][]) {
      holidayPremiums.push(
        datedPercent([start], from, "24:00", 100, {
          percentageBaseRate: 40008.29 / 162.5,
        }),
      );
      for (let d = dateOffset(start, 1); d < end; d = dateOffset(d, 1))
        holidayPremiums.push(
          datedPercent([d], "00:00", "24:00", 100, {
            percentageBaseRate: 40008.29 / 162.5,
          }),
        );
      holidayPremiums.push(
        datedPercent([end], "00:00", "06:00", 100, {
          percentageBaseRate: 40008.29 / 162.5,
        }),
      );
    }
  }
  const categories: CategoryInput[] = rates.map((rate, i) => [
    i + 1,
    securityBands[i],
    securityBandsNb[i],
    rate,
  ]);
  categories.push(
    ...rates.map(
      (rate, i): CategoryInput => [
        i + 11,
        `${securityBands[i]}, qualified`,
        `${securityBandsNb[i]}, med fagbrev`,
        Number((rate + 14.5).toFixed(2)),
      ],
    ),
  );
  const overtime = standardOvertime(week, "06:00", "12:00", true);
  // Security's ordinary night overtime is 50%, unlike hospitality.
  overtime.rules = overtime.rules.filter(
    (r) => !(r.days.length === 6 && r.percent === 100),
  );
  overtime.rules.push(
    {
      days: [1, 2, 3, 4, 5, 6],
      from: "00:00",
      to: "24:00",
      percent: 50,
      appliesOnHolidays: false,
    },
    {
      days: [1],
      from: "00:00",
      to: "06:00",
      percent: 100,
      appliesOnHolidays: false,
    },
  );
  for (const rule of holidayPremiums)
    overtime.rules.push({
      days: allDays,
      from: rule.from,
      to: rule.to,
      percent: 100,
      appliesOnHolidays: true,
      dates: rule.dates,
    });
  const adult = tariff({
    id:
      week === 37.5
        ? "vekteroverenskomst"
        : `vekter_${String(week).replace(".", "")}`,
    en: `Security, ${week} h`,
    nb: `Vekter, ${String(week).replace(".", ",")} t`,
    legalDate: "2026-04-01",
    source: securitySource,
    sources: [securityText],
    categories,
    rules: [
      {
        days: allDays,
        from: "21:00",
        to: "06:00",
        rate: 28,
        stackingGroup: "night",
      },
      {
        days: [6],
        from: "18:00",
        to: "24:00",
        rate: 48,
        stackingGroup: "weekend",
      },
      {
        days: [7],
        from: "00:00",
        to: "24:00",
        rate: 48,
        stackingGroup: "weekend",
      },
      {
        days: [1],
        from: "00:00",
        to: "06:00",
        rate: 48,
        stackingGroup: "weekend",
      },
      ...holidayPremiums.map((r) => ({ ...r, stackingGroup: "holiday" })),
    ],
    overtime,
    noteEn:
      "Choose the schedule in your contract. Qualified categories include 14.50 fagbrev pay. Apprentices use the published 37.5-hour amounts. Work-plan overtime, same-shift call-outs, service allowances and continuous shift arrangements require manual adjustment.",
    noteNb:
      "Velg arbeidstidsordningen i avtalen din. Fagbrev er inkludert med 14,50 i fagarbeidersatsene. Lærlinger bruker publiserte satser for 37,5 timer. Overtid etter arbeidsplan, tilkalling samme vakt, tjenestetillegg og kontinuerlig skift må tilpasses manuelt.",
  });
  existingTariffs.push(adult);
  if (week === 37.5) {
    const apprenticeRules = adult.version.supplements.rules.map((rule) => ({
      ...rule,
      ...(rule.rate === undefined ? {} : { rate: rule.rate / 2 }),
      ...(rule.percent === undefined ? {} : { percent: rule.percent / 2 }),
    }));
    existingTariffs.push(
      tariff({
        id: "vekter_apprentice_375",
        en: "Security, apprentices, 37.5 h",
        nb: "Vekter, lærlinger, 37,5 t",
        legalDate: adult.version.legal_effective_date,
        source: securitySource,
        sources: [securityText],
        categories: [
          [21, "Apprentice, first year", "Lærling, første år", 104.29],
          [22, "Apprentice, second year", "Lærling, andre år", 156.43],
        ],
        rules: apprenticeRules,
        overtime: {
          ...overtime,
          baseRate: rates[0],
          retainedSupplements: adult.version.supplements.rules,
        },
        noteEn:
          "Apprentice work within the training plan, with half supplement rates. Work outside that plan uses the adult entry table. Weekly overtime uses the adult entry wage and full supplements; other work-plan changes require manual adjustment.",
        noteNb:
          "Lærlingearbeid innenfor opplæringsplanen, med halve tilleggssatser. Arbeid utenfor planen bruker begynnerlønn for voksne. Ukentlig overtid bruker voksen begynnerlønn og fulle tillegg. Andre arbeidsplanendringer må tilpasses manuelt.",
      }),
    );
  }
}
