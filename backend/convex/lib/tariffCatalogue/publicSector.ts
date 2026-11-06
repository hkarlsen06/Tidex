import type { SupplementRule } from "../shared/payroll/types";
import {
  allDays,
  calendars,
  holidayDates,
  holidayRules,
  standardOvertime,
  tariff,
  type CategoryInput,
  type CatalogueEntry,
} from "./model";

const ksSource =
  "https://www.ks.no/globalassets/fagomrader/lonn-og-tariff/tariff-2024/hovedtariffavtalen-2026-2028---interaktiv-til-nettsiden.pdf";
const ksSupplementSource =
  "https://www.ks.no/fagomrader/lonn-og-tariff/hovedtariffavtalen/endringer-i-tilleggene-i-hta-kapittel-1--5-fra-forste-oktober/";
const ksBands = [
  {
    en: "No formal qualification required",
    nb: "Uten særskilt utdanningskrav",
    annual: [418600, 421600, 429700, 476000, 515800],
  },
  {
    en: "Qualified worker",
    nb: "Fagarbeider",
    annual: [475300, 479500, 490900, 534700, 551100],
  },
  {
    en: "Certificate + 1 year vocational college",
    nb: "Fagbrev og 1-årig fagskole",
    annual: [497300, 501500, 512900, 554700, 572500],
  },
  {
    en: "Certificate + 2 years vocational college",
    nb: "Fagbrev og 2-årig fagskole",
    annual: [517300, 521500, 532900, 574700, 592500],
  },
  {
    en: "3-year university degree, non-teaching",
    nb: "3-årig høyere utdanning, ikke undervisning",
    annual: [545400, 558400, 568600, 620800, 639900],
  },
  {
    en: "4-year university degree, non-teaching",
    nb: "4-årig høyere utdanning, ikke undervisning",
    annual: [586400, 601800, 622000, 647900, 673200],
  },
  {
    en: "5-year university degree, non-teaching",
    nb: "5-årig høyere utdanning, ikke undervisning",
    annual: [624700, 638900, 652300, 686000, 735300],
  },
  {
    en: "Master's degree, non-teaching",
    nb: "Mastergrad, ikke undervisning",
    annual: [655800, 676700, 687500, 723100, 797500],
  },
];
export const publicSectorTariffs: CatalogueEntry[] = [];
for (const [hours, rota] of [
  [37.5, false],
  [35.5, true],
  [33.6, true],
] satisfies [number, boolean][]) {
  const divisor = 52 * hours;
  const categories: CategoryInput[] = ksBands.flatMap((band, group) =>
    band.annual.map(
      (annual, i): CategoryInput => [
        group * 10 + i + 1,
        `${band.en}, ${[0, 6, 8, 10, 16][i]} years`,
        `${band.nb}, ${[0, 6, 8, 10, 16][i]} år`,
        annual / divisor,
      ],
    ),
  );
  const rules: SupplementRule[] = [
    {
      days: [6, 7],
      from: "00:00",
      to: "24:00",
      percent: 23,
      minimumRate: 73,
      stackingGroup: "weekend",
    },
    ...holidayRules(400 / 3, "12:00", true).map((r) => ({
      ...r,
      stackingGroup: "holiday",
    })),
  ];
  rules.push(
    ...((rota
      ? [
          {
            days: allDays,
            from: "17:00",
            to: "21:00",
            percent: 20,
            minimumRate: 60,
            stackingGroup: "evening",
          },
          {
            days: allDays,
            from: "21:00",
            to: "06:00",
            percent: 25,
            minimumRate: 70,
            stackingGroup: "evening",
          },
        ]
      : [
          {
            days: allDays,
            from: "17:00",
            to: "06:00",
            percent: 20,
            minimumRate: 56,
            stackingGroup: "evening",
          },
        ]) satisfies SupplementRule[]),
  );
  const overtime = standardOvertime(hours, "06:00", "00:00");
  overtime.premiumBaseMultiplier = divisor / 1850;
  for (const rule of overtime.rules)
    if (rule.appliesOnHolidays) rule.percent = 400 / 3;
  for (const rule of holidayRules(400 / 3, "12:00", true))
    overtime.rules.push({
      days: allDays,
      from: rule.from,
      to: rule.to,
      percent: 400 / 3,
      appliesOnHolidays: true,
      dates: rule.dates,
    });
  if (rota) overtime.enabled = false;
  publicSectorTariffs.push(
    tariff({
      id: `ks_ch4_${String(hours).replace(".", "")}`,
      en: `Municipal KS, chapter 4, ${hours} h`,
      nb: `Kommune KS, kapittel 4, ${String(hours).replace(".", ",")} t`,
      legalDate: "2026-10-01",
      source: ksSource,
      sources: [ksSupplementSource],
      categories,
      rules,
      overtime,
      noteEn: `Minimum annual salaries divided by ${divisor} hours. Ordinary supplements use October 2026 rates. Excludes Oslo, teaching, leaders and local agreements. ${rota ? "Rota overtime and night-shift extension after 06:00 require your work plan and must be entered manually." : "Weekly overtime only. Daily scheduled overtime and night-shift extension after 06:00 require manual adjustment."}`,
      noteNb: `Minste årslønn delt på ${divisor} timer. Ordinære tillegg bruker satsene fra oktober 2026. Gjelder ikke Oslo, undervisning, ledere eller lokale avtaler. ${rota ? "Turnusovertid og nattillegg etter 06:00 krever arbeidsplanen din og må legges inn manuelt." : "Bare ukentlig overtid. Daglig overtid etter arbeidsplan og nattillegg etter 06:00 må tilpasses manuelt."}`,
    }),
  );
}
const pblSource =
  "https://pbl.no/tariff-og-loenn/hovedavtale-og-hovedtariffavtale-2024-2026";
const pblBands = [
  {
    en: "Assistant",
    nb: "Assistent",
    annual: [420500, 427800, 440900, 483000, 519300],
  },
  {
    en: "Qualified child-care worker",
    nb: "Barne- og ungdomsarbeider",
    annual: [478400, 489000, 501600, 543700, 559900],
  },
  {
    en: "Preschool teacher, no management responsibility",
    nb: "Barnehagelærer uten lederansvar",
    annual: [558400, 562800, 577400, 634600, 651800],
  },
  {
    en: "Pedagogical leader",
    nb: "Pedagogisk leder",
    annual: [593400, 597800, 612400, 670100, 687300],
  },
  {
    en: "Special education teacher",
    nb: "Spesialpedagog",
    annual: [594200, 602600, 613300, 671300, 689700],
  },
];
for (const rota of [false, true]) {
  const categories: CategoryInput[] = pblBands.flatMap((band, group) =>
    band.annual.map(
      (annual, i): CategoryInput => [
        group * 10 + i + 1,
        `${band.en}, ${[0, 4, 8, 10, 16][i]} years`,
        `${band.nb}, ${[0, 4, 8, 10, 16][i]} år`,
        annual / 1950,
      ],
    ),
  );
  const rules: SupplementRule[] = [
    {
      days: [6, 7],
      from: "00:00",
      to: "24:00",
      percent: 22,
      minimumRate: 70,
      stackingGroup: "calendar",
    },
    ...holidayRules(400 / 3, "12:00", true).map((r) => ({
      ...r,
      stackingGroup: "calendar",
    })),
  ];
  rules.push(
    ...((rota
      ? [
          {
            days: allDays,
            from: "17:00",
            to: "21:00",
            rate: 56,
            stackingGroup: "evening",
          },
          {
            days: allDays,
            from: "21:00",
            to: "06:00",
            percent: 25,
            minimumRate: 70,
            stackingGroup: "evening",
          },
        ]
      : [
          {
            days: allDays,
            from: "17:00",
            to: "06:00",
            rate: 32,
            stackingGroup: "evening",
          },
        ]) satisfies SupplementRule[]),
  );
  const overtime = standardOvertime(37.5, "06:00", "00:00");
  overtime.premiumBaseMultiplier = 1950 / 1850;
  for (const rule of overtime.rules)
    if (rule.appliesOnHolidays) rule.percent = 400 / 3;
  for (const rule of holidayRules(400 / 3, "12:00", true))
    overtime.rules.push({
      days: allDays,
      from: rule.from,
      to: rule.to,
      percent: 400 / 3,
      appliesOnHolidays: true,
      dates: rule.dates,
    });
  publicSectorTariffs.push(
    tariff({
      id: `pbl_${rota ? "rota" : "day"}`,
      en: `Private preschool PBL, ${rota ? "rota" : "day work"}`,
      nb: `Privat barnehage PBL, ${rota ? "turnus" : "dagarbeid"}`,
      legalDate: "2026-05-01",
      source: pblSource,
      categories,
      rules,
      overtime,
      noteEn:
        "Hourly equivalents of annual minima, annual salary / 1950. Overtime premium uses annual salary / 1850. Weekly overtime only. Daily work-plan triggers, call-out minimums, managers, youth, apprentices and additional-education supplements require manual settings.",
      noteNb:
        "Årslønn omregnet til timelønn, årslønn / 1950. Overtidstillegg bruker årslønn / 1850. Bare ukentlig overtid. Daglig arbeidsplan, minstebetaling ved tilkalling, styrere, ungdom, lærlinger og videreutdanning krever manuelle innstillinger.",
    }),
  );
}
