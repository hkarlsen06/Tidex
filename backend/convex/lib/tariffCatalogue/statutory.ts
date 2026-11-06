import {
  allDays,
  calendars,
  datedPercent,
  holidayDates,
  minimumSource,
  scopeEn,
  scopeNb,
  standardOvertime,
  tariff,
  type CategoryInput,
  type CatalogueEntry,
} from "./model";

const statutoryNoteEn = `${scopeEn} Weekly overtime threshold only. Daily limits and agreed averaging require your work schedule.`;
const statutoryNoteNb = `${scopeNb} Overtid beregnes bare etter uketerskelen. Daglige grenser og gjennomsnittsberegning krever arbeidsplanen din.`;
function minimum(
  id: string,
  en: string,
  nb: string,
  categories: CategoryInput[],
  legalDate = "2025-06-15",
  extraEn = "",
  extraNb = "",
): CatalogueEntry {
  return tariff({
    id,
    en,
    nb,
    categories,
    legalDate,
    source: minimumSource,
    noteEn: `${statutoryNoteEn} ${extraEn}`.trim(),
    noteNb: `${statutoryNoteNb} ${extraNb}`.trim(),
  });
}
export const statutoryTariffs: CatalogueEntry[] = [
  minimum(
    "hospitality_allmenngjort",
    "Hospitality, statutory minimum",
    "Hotell og servering, allmenngjort",
    [
      [-3, "Under 17", "Under 17 år", 142.58],
      [-1, "17 years", "17 år", 152.08],
      [-2, "18 years", "18 år", 166.34],
      [
        1,
        "Over 20, or 4 months of practice after 18",
        "Over 20 år, eller 4 måneders praksis etter 18 år",
        204.79,
      ],
    ],
    "2025-06-15",
    "No automatic evening, night or weekend premiums.",
    "Ingen automatiske kvelds-, natt- eller helgetillegg.",
  ),
  minimum(
    "automotive_allmenngjort",
    "Automotive, statutory minimum",
    "Bilbransjen, allmenngjort",
    [
      [1, "Adult assistant", "Hjelpearbeider over 18 år", 208],
      [
        2,
        "Assistant, at least 1 year",
        "Hjelpearbeider, minst 1 års praksis",
        212,
      ],
      [3, "Newly qualified worker", "Nyutlært fagarbeider", 223.5],
      [
        4,
        "Qualified worker, at least 1 year",
        "Fagarbeider, minst 1 års praksis",
        237,
      ],
    ],
    "2026-06-15",
    "Excludes vehicle sales, glass replacement and petrol stations unless the regulation specifically applies.",
    "Gjelder ikke bilsalg, ruteskift eller bensinstasjoner med mindre forskriften særskilt omfatter virksomheten.",
  ),
  minimum(
    "freight_allmenngjort",
    "Road freight, statutory minimum",
    "Godstransport, allmenngjort",
    [
      [
        1,
        "Freight vehicle over 2.5 tonnes",
        "Godstransport med kjøretøy over 2,5 tonn",
        229,
      ],
    ],
    "2025-06-15",
    "Own-account transport excluded. Multi-day minimum paid hours and travel allowances must be entered separately.",
    "Egentransport er unntatt. Minstebetaling på flerdagsturer og diett må legges inn separat.",
  ),
  minimum(
    "coach_allmenngjort",
    "Tour coaches, statutory minimum",
    "Turbuss, allmenngjort",
    [[1, "Tour coach driver", "Turbussjåfør", 218.62]],
    "2025-06-15",
    "Tendered public transport is excluded. Subsistence is separate.",
    "Rutetransport med konkurranseutsatt løyve er unntatt. Kost og losji kommer i tillegg.",
  ),
  minimum(
    "agriculture_seasonal_allmenngjort",
    "Agriculture, seasonal statutory minimum",
    "Jordbruk, sesonghjelp allmenngjort",
    [
      [-1, "Under 18", "Under 18 år", 142.9],
      [1, "Up to 12 weeks", "Til og med 12 ukers ansiennitet", 162.9],
      [
        2,
        "Over 12 weeks, up to 6 months",
        "Over 12 uker, til og med 6 måneder",
        168.4,
      ],
      [3, "Over 6 months", "Over 6 måneders ansiennitet", 182.8],
    ],
    "2025-06-15",
    "Rates do not apply below 16 or above 70.",
    "Satsene gjelder ikke under 16 eller over 70 år.",
  ),
  minimum(
    "agriculture_permanent_allmenngjort",
    "Agriculture, permanent statutory minimum",
    "Jordbruk, fast ansatt allmenngjort",
    [
      [-1, "Under 18", "Under 18 år", 152.4],
      [1, "Unskilled adult", "Ufaglært voksen", 182.8],
      [2, "Qualified adult", "Fagarbeider voksen", 197.3],
    ],
  ),
];
const relief = minimum(
  "agriculture_relief_allmenngjort",
  "Agriculture, regular animal-care rota",
  "Jordbruk, røkter og avløser i fast turnus",
  [
    [1, "Unskilled adult", "Ufaglært voksen", 182.8],
    [2, "Qualified adult", "Fagarbeider voksen", 197.3],
  ],
);
relief.version.supplements.rules = [
  { days: [6, 7], from: "00:00", to: "24:00", percent: 25 },
  datedPercent(
    [
      ...holidayDates,
      ...calendars.flatMap((c) => [c.christmasEve, c.newYearEve]),
    ],
    "00:00",
    "24:00",
    25,
  ),
];
statutoryTariffs.push(relief);
for (const [hours, shiftPercent] of [
  [37.5, 0],
  [36.5, 17],
  [35.5, 27.3],
  [33.6, 27.3],
]) {
  const adjustment =
    hours === 37.5
      ? 1
      : hours === 36.5
        ? 1.0274
        : hours === 35.5
          ? 1.0563
          : 1.1161;
  const entry = minimum(
    `electrical_allmenngjort_${String(hours).replace(".", "")}`,
    `Electrical work, ${hours} h statutory minimum`,
    `Elektro, ${String(hours).replace(".", ",")} t allmenngjort`,
    [
      [1, "Other worker", "Øvrig arbeidstaker", 241.77 * adjustment],
      [
        2,
        "Qualified electrical worker",
        "Faglært som utfører fagarbeid",
        270.45 * adjustment,
      ],
    ],
    "2025-06-15",
    "Excludes offshore petroleum. Select only the agreed shift arrangement.",
    "Petroleumsvirksomhet til havs er unntatt. Velg bare avtalt skiftordning.",
  );
  entry.version.overtime = standardOvertime(hours, "06:00", "24:00", true);
  if (shiftPercent)
    entry.version.supplements.rules = [
      {
        days: allDays,
        from: "00:00",
        to: "24:00",
        percent: shiftPercent / adjustment,
      },
    ];
  statutoryTariffs.push(entry);
}
for (const shifts of [1, 2, 3]) {
  const entry = tariff({
    id: `fish_processing_allmenngjort_${shifts}`,
    en: `Fish processing, ${shifts === 1 ? "day work" : `${shifts} shifts`}`,
    nb: `Fiskeindustri, ${shifts === 1 ? "dagarbeid" : `${shifts}-skift`}`,
    legalDate: "2026-11-06",
    source:
      "https://nnn.no/wp-content/uploads/2026/11/Allmenngjoring-Fiskeindustribedrifter.pdf",
    categories: [
      [1, "Production worker", "Produksjonsarbeider", 236.09],
      [2, "Qualified worker", "Fagarbeider", 252.09],
      [-1, "Under 18, production", "Under 18 år, produksjon", 236.09 * 0.8],
      [-2, "Under 18, qualified", "Under 18 år, fagarbeider", 252.09 * 0.8],
    ],
    rules:
      shifts === 1
        ? []
        : [
            {
              days: allDays,
              from: "00:00",
              to: "24:00",
              percent: shifts === 2 ? 20 : 25,
            },
          ],
    noteEn: `${statutoryNoteEn} Workers over 17 with 12 weeks in the business use adult rates. The prior regulation was repealed in August. This version starts on 6 November and includes Longyearbyen and Ny-Ålesund.`,
    noteNb: `${statutoryNoteNb} Ansatte over 17 år med 12 uker i bedriften bruker voksensats. Tidligere forskrift ble opphevet i august. Denne versjonen gjelder fra 6. november, også i Longyearbyen og Ny-Ålesund.`,
  });
  statutoryTariffs.push(entry);
}
statutoryTariffs.push(
  minimum(
    "shipyard_allmenngjort",
    "Shipyards, ordinary day work minimum",
    "Skips- og verftsindustri, dagarbeid allmenngjort",
    [
      [1, "Assistant", "Hjelpearbeider", 197.61],
      [2, "Specialised worker", "Spesialarbeider", 207.14],
      [3, "Qualified worker", "Fagarbeider", 216.79],
    ],
    "2025-06-15",
    "Day work only. Shift and overnight-assignment allowances require the agreed arrangement.",
    "Bare dagarbeid. Skifttillegg og overnattingstillegg krever avtalt ordning.",
  ),
);
statutoryTariffs[statutoryTariffs.length - 1].version.overtime =
  standardOvertime(37.5, "06:00", "24:00", true);
