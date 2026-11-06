import type { SupplementRule } from "../shared/payroll/types";
import {
  allDays,
  calendars,
  datedPercent,
  dateOffset,
  holidayDates,
  holidayRules,
  scopeEn,
  scopeNb,
  standardOvertime,
  tariff,
  weekdays,
  type CategoryInput,
  type CatalogueEntry,
} from "./model";

const retailNoteEn = `${scopeEn} Weekly overtime only. Scheduled daily overtime and minimum call-out payments need manual adjustment.`;
const retailNoteNb = `${scopeNb} Bare ukentlig overtid. Overtid etter daglig arbeidsplan og minstebetaling ved tilkalling må tilpasses manuelt.`;
const handelRules: SupplementRule[] = [
  { days: weekdays, from: "18:00", to: "21:00", rate: 22 },
  { days: weekdays, from: "21:00", to: "24:00", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 55 },
  { days: [6], from: "15:00", to: "18:00", rate: 65 },
  { days: [6], from: "18:00", to: "24:00", rate: 120 },
  { days: [7], from: "00:00", to: "24:00", rate: 120 },
  datedPercent(
    calendars.flatMap((c) => [c.christmasEve, c.newYearEve, c.whitEve]),
    "13:15",
    "24:00",
    100,
  ),
  datedPercent(
    calendars.map((c) => c.easterEve),
    "00:00",
    "24:00",
    100,
  ),
];
export const retailTariffs: CatalogueEntry[] = [
  tariff({
    id: "handel_nho",
    en: "Retail, NHO Handelsoverenskomsten",
    nb: "Handel, NHO Handelsoverenskomsten",
    legalDate: "2026-04-01",
    source: "https://hk.no/shared-files/6846/",
    sources: [
      "https://www.nhosh.no/contentassets/abb252e3ee844c1b8d259089b5dcc038/tariffbrev-hok-2026.pdf",
    ],
    categories: [
      [-1, "16 or younger", "16 år eller yngre", 148.66],
      [-2, "17 years", "17 år", 151.66],
      ...[195.8, 196.6, 198.7, 203.3, 221.1, 276.29].map(
        (r, i): CategoryInput => [i + 1, `Level ${i + 1}`, `Trinn ${i + 1}`, r],
      ),
      [7, "Qualified, entry", "Fagbrev, begynner", 276.29],
      [
        8,
        "Qualified, year 2 / practice candidate",
        "Fagbrev, fra år 2 / praksiskandidat",
        288.79,
      ],
    ],
    rules: handelRules,
    overtime: {
      ...standardOvertime(37.5, "08:00", "13:00"),
      retainedSupplements: handelRules.filter(
        (rule) => rule.dates !== undefined,
      ),
    },
    noteEn: retailNoteEn,
    noteNb: retailNoteNb,
  }),
  tariff({
    id: "butikk_nho",
    en: "Retail, NHO Butikkoverenskomsten",
    nb: "Butikk, NHO Butikkoverenskomsten",
    legalDate: "2026-05-01",
    source:
      "https://www.nhosh.no/contentassets/6aa225fee04043d9b9a6bc9e0a1986a3/protokoll-butikkoverenskomsten-2026-07-09.pdf",
    sources: ["https://hk.no/shared-files/7703/"],
    categories: [
      [-1, "16 years", "16 år", 153.98],
      [-2, "17 years", "17 år", 157.74],
      ...[198.68, 201.39, 203.41, 209.28, 211.3, 221.6, 257.02].map(
        (r, i): CategoryInput => [
          i + 1,
          `${i} years of service`,
          `${i} års ansiennitet`,
          r,
        ],
      ),
      ...[198.68, 201.39, 203.41, 209.28, 211.3, 221.6, 257.02].map(
        (r, i): CategoryInput => [
          i + 11,
          `${i} years, relevant certificate`,
          `${i} år, relevant fagbrev`,
          Number((r + 11).toFixed(2)),
        ],
      ),
    ],
    rules: [
      { days: weekdays, from: "18:00", to: "21:00", rate: 21 },
      { days: weekdays, from: "21:00", to: "24:00", rate: 42 },
      { days: [6], from: "13:00", to: "16:00", rate: 42 },
      { days: [6], from: "16:00", to: "24:00", rate: 84 },
    ],
    overtime: standardOvertime(37.5, "08:00", "12:00"),
    noteEn: `${retailNoteEn} UB excludes holiday substitutes. The night-overtime start condition and scheduled time off must be checked against your contract.`,
    noteNb: `${retailNoteNb} Ferievikarer har ikke UB. Vilkåret om når nattovertid begynner og oppsatte fridager må kontrolleres mot avtalen din.`,
  }),
];
retailTariffs[0].version.overtime.rules.push({
  days: allDays,
  from: "13:00",
  to: "24:00",
  percent: 100,
  appliesOnHolidays: true,
  dates: holidayDates.map((date) => dateOffset(date, -1)),
});

for (const week of [37.5, 35.5]) {
  const ratio = 37.5 / week;
  const rates = [196.08, 199.07, 202.08, 205.07, 211.07, 256.58];
  const years = [0, 2, 3, 4, 5, 6];
  const entry = tariff({
    id: week === 37.5 ? "energy_hk_virke" : "energy_hk_virke_355",
    en: `Energy stations, HK–Virke, ${week} h`,
    nb: `Energistasjon, HK–Virke, ${String(week).replace(".", ",")} t`,
    legalDate: "2026-04-01",
    source:
      "https://www.virke.no/tariff-og-lonn/finn-tariffavtale/energistasjonsoverenskomsten-virkehk/",
    sources: [
      "https://www.virke.no/globalassets/6.tariff-og-lonn/protokoller-og-lonnssatser/bensinstasjonoversenskomsten-virkehk/energistasjonsoverkomsten-2024-2026-virke-hk2.pdf",
      "https://www.virke.no/globalassets/6.tariff-og-lonn/protokoller-og-lonnssatser/energistasjonsoverenskomsten-hk/protokoll-05.10.26---hovedoppgjoret-2026---energistasjonsoverenskomsten-virke-hk.pdf",
    ],
    categories: [
      [-1, "Under 18", "Under 18 år", 149.84 * ratio],
      ...rates.map(
        (r, i): CategoryInput => [
          i + 1,
          `${years[i]} years`,
          `${years[i]} års ansiennitet`,
          r * ratio,
        ],
      ),
      ...rates.map(
        (r, i): CategoryInput => [
          i + 11,
          `${years[i]} years, qualified`,
          `${years[i]} år, med fagbrev`,
          (r + 10) * ratio,
        ],
      ),
    ],
    rules: [
      { days: weekdays, from: "18:00", to: "21:00", rate: 12 },
      { days: weekdays, from: "21:00", to: "24:00", rate: 22 },
      { days: weekdays, from: "00:00", to: "06:00", rate: 32 },
      { days: [6], from: "18:00", to: "24:00", rate: 27.5 },
      { days: [7], from: "00:00", to: "06:00", rate: 38 },
      { days: [7], from: "06:00", to: "18:00", rate: 24.5 },
      { days: [7], from: "18:00", to: "24:00", rate: 27.5 },
      ...holidayRules(100, "15:00", false, "15:00"),
    ],
    overtime: {
      ...standardOvertime(week, "06:00", "24:00"),
      retainedSupplements: holidayRules(100, "15:00", false, "15:00"),
    },
    noteEn: retailNoteEn,
    noteNb: retailNoteNb,
  });
  retailTariffs.push(entry);
}
const grossistSource =
  "https://www.virke.no/tariff-og-lonn/finn-tariffavtale/grossistoverenskomsten-ff/";
for (const shifts of [1, 2, 3]) {
  const hours = shifts === 1 ? 37.5 : shifts === 2 ? 36.5 : 35.5;
  const ratio = 37.5 / hours;
  const overtime = standardOvertime(hours, "07:00", "14:00", shifts !== 1);
  if (shifts !== 1) overtime.enabled = false;
  retailTariffs.push(
    tariff({
      id: `grossist_virke_${shifts}`,
      en: `Warehouse, Virke, ${shifts === 1 ? "day work" : `${shifts} shifts`}`,
      nb: `Lager, Virke, ${shifts === 1 ? "dagarbeid" : `${shifts}-skift`}`,
      legalDate: "2026-04-01",
      source: grossistSource,
      sources: [
        "https://www.virke.no/globalassets/6.tariff-og-lonn/tariffavtaler/2020/grossistoverenskomsten-virke-fellesforbundet-2024-2026-korrig.-19.11.24.pdf",
      ],
      categories: [
        [-1, "16–17 years", "16–17 år", 196.5 * ratio],
        [-2, "17–18 years", "17–18 år", 224.58 * ratio],
        [1, "Adult warehouse worker", "Voksen lagerarbeider", 280.72 * ratio],
        [
          2,
          "Working foreman or mechanic",
          "Arbeidende formann eller mekaniker",
          284.08 * ratio,
        ],
      ],
      rules:
        shifts === 1
          ? [
              {
                days: [1, 2, 3, 4, 5, 6],
                from: "04:00",
                to: "06:00",
                percent: 100,
              },
              {
                days: [1, 2, 3, 4, 5, 6],
                from: "06:00",
                to: "07:00",
                percent: 60,
              },
              { days: [6], from: "07:00", to: "14:00", percent: 20 },
            ]
          : [
              {
                days: allDays,
                from: "00:00",
                to: "24:00",
                percent: shifts === 2 ? 20 : 30,
              },
            ],
      overtime,
      noteEn: `${retailNoteEn} ${shifts === 1 ? "Early work must be agreed locally." : "Shift overtime depends on the scheduled shift and is entered manually."} Company-specific BTA and the 150% combined shift/overtime cap require the local agreement.`,
      noteNb: `${retailNoteNb} ${shifts === 1 ? "Tidlig arbeid må være avtalt lokalt." : "Skiftovertid følger arbeidsplanen og legges inn manuelt."} Bedriftstilpasset arbeidstid og grensen på150% for samlet skift/overtid krever lokal avtale.`,
    }),
  );
}
