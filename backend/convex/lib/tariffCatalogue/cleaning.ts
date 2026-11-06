import type { SupplementRule } from "../shared/payroll/types";
import {
  allDays,
  calendars,
  datedPercent,
  dateOffset,
  holidayDates,
  scopeEn,
  scopeNb,
  standardOvertime,
  tariff,
  type CategoryInput,
  type CatalogueEntry,
} from "./model";

export const cleaningTariffs: CatalogueEntry[] = [];
for (const employer of ["nho", "virke"])
  for (const hours of [37.5, 35.5, 33.6]) {
    const adjustment = hours === 37.5 ? 1 : hours === 35.5 ? 1.0563 : 1.1161;
    const bands = [247.29, 250.66, 257.39, 261.24];
    const labelsEn = ["0–2 years", "2–4 years", "4–10 years", "Over 10 years"];
    const labelsNb = ["0–2 år", "2–4 år", "4–10 år", "Over 10 år"];
    const categories: CategoryInput[] = [
      [-1, "Under 18", "Under 18 år", 196.05 * adjustment],
      ...bands.map(
        (r, i): CategoryInput => [
          i + 1,
          labelsEn[i],
          labelsNb[i],
          r * adjustment,
        ],
      ),
      ...bands.map(
        (r, i): CategoryInput => [
          i + 11,
          `${labelsEn[i]}, qualified`,
          `${labelsNb[i]}, med fagbrev`,
          (r + 15.5) * adjustment,
        ],
      ),
    ];
    const rules: SupplementRule[] = [
      {
        days: allDays,
        from: "21:00",
        to: "06:00",
        rate: 29,
        stackingGroup: "night",
      },
      {
        days: [6],
        from: "18:00",
        to: "24:00",
        percent: 50,
        excludedDates: holidayDates,
        stackingGroup: "calendar",
      },
      {
        days: [7],
        from: "00:00",
        to: "24:00",
        percent: 75,
        excludedDates: holidayDates,
        stackingGroup: "calendar",
      },
      datedPercent(holidayDates, "00:00", "24:00", 100, {
        stackingGroup: "calendar",
      }),
      datedPercent(
        calendars.flatMap((c) => [
          c.easterEve,
          c.whitEve,
          c.christmasEve,
          c.newYearEve,
        ]),
        "13:00",
        "24:00",
        100,
        { stackingGroup: "calendar" },
      ),
    ];
    const overtime = standardOvertime(hours, "00:00", "00:00", true);
    overtime.rules.push({
      days: allDays,
      from: "00:00",
      to: "24:00",
      percent: 100,
      appliesOnHolidays: true,
      dates: holidayDates.map((date) => dateOffset(date, -1)),
    });
    const adult = tariff({
      id: `cleaning_${employer}_${String(hours).replace(".", "")}`,
      en: `Cleaning, ${employer === "nho" ? "NHO" : "Virke"}, ${hours} h`,
      nb: `Renhold, ${employer === "nho" ? "NHO" : "Virke"}, ${String(hours).replace(".", ",")} t`,
      legalDate: employer === "nho" ? "2026-06-01" : "2026-05-01",
      source:
        employer === "nho"
          ? "https://www.nhosh.no/contentassets/38c2c52065f34c9c8efb8ba648fcef41/tariffbrev-2026-renhold.pdf"
          : "https://www.virke.no/tariff-og-lonn/finn-tariffavtale/renholdsoverenskomsten/",
      sources: [
        employer === "nho"
          ? "https://arbeidsmandsforbundet.no/wp-content/uploads/2025/01/Renholdsbedrifter%E2%80%93NHO-Service-og-Handel%E2%80%93overenskomst-2024-2026.pdf"
          : "https://www.virke.no/globalassets/6.tariff-og-lonn/tariffavtaler/renholdsoverenskomsten-2024-2026-virke-naf.pdf",
      ],
      categories,
      rules,
      overtime,
      noteEn: `${scopeEn} Qualified categories include fagbrev. Reduced-week rates include statutory conversion. Weekly overtime only. Daily work-plan thresholds, notice-related premiums, rammetimetall and minimum call-outs need manual adjustment.`,
      noteNb: `${scopeNb} Fagbrev er inkludert i fagarbeidersatsene. Redusert uke er omregnet etter avtalen. Bare ukentlig overtid. Daglig arbeidsplan, varslingsrelaterte tillegg, rammetimetall og minstebetaling ved tilkalling må tilpasses manuelt.`,
    });
    cleaningTariffs.push(adult);
    if (hours === 37.5) {
      cleaningTariffs.push(
        tariff({
          id: `cleaning_${employer}_apprentice`,
          en: `Cleaning, ${employer === "nho" ? "NHO" : "Virke"}, apprentices, 37.5 h`,
          nb: `Renhold, ${employer === "nho" ? "NHO" : "Virke"}, lærlinger, 37,5 t`,
          legalDate: adult.version.legal_effective_date,
          source: adult.version.source_url,
          sources: adult.version.source_urls,
          categories: [
            [21, "Apprentice, year 1", "Lærling, første år", 133.08],
            [22, "Apprentice, year 2", "Lærling, andre år", 133.08],
          ],
          rules,
          overtime: {
            ...overtime,
            baseRate: bands[0],
            retainedSupplements: rules,
          },
          noteEn:
            "Published apprentice rates for 37.5-hour weeks. Overtime uses the unskilled adult entry wage, including its supplements. Work-plan triggers and local arrangements require manual adjustment.",
          noteNb:
            "Publiserte lærlingesatser for 37,5-timersuke. Overtid bruker begynnerlønnen for ufaglærte voksne, med tilhørende tillegg. Arbeidsplan og lokale avtaler må tilpasses manuelt.",
        }),
      );
    }
  }
