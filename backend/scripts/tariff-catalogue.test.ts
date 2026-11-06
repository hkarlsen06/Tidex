import { describe, expect, test } from "bun:test";
import {
  CATALOGUE_REVISION,
  exportCatalogue,
  overdueTariffs,
  requireCatalogueRevision,
  tariffCatalogue,
  validateCatalogue,
} from "../convex/lib/tariffCatalogue";
import {
  applyWeeklyOvertime,
  computeShift,
} from "../convex/lib/shared/payroll/calc";
import type {
  WageSnapshot,
  ShiftRow,
} from "../convex/lib/shared/payroll/types";
import { buildWagePeriods } from "../convex/lib/shared/payroll/periods";
import type { CatalogueEntry } from "../convex/lib/tariffCatalogue/model";
import { withPresentation } from "../convex/lib/tariffCatalogue/presentation";

function entry(id: string): CatalogueEntry {
  const result = tariffCatalogue.find((e) => e.type.id === id);
  if (!result) throw new Error(`Missing ${id}`);
  return result;
}
function supplement(
  id: string,
  date: string,
  start: string,
  end: string,
  level = 1,
) {
  const t = entry(id).version;
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  const periods = buildWagePeriods(
    start,
    end,
    day === 0 ? 7 : day,
    t.rates[String(level)],
    t.supplements.rules,
    date,
  );
  return periods.reduce(
    (sum, p) => sum + ((p.toMin - p.fromMin) / 60) * p.supplementRate,
    0,
  );
}
function overtimeOutcome(
  id: string,
  date: string,
  start: string,
  end: string,
  level = 1,
) {
  const t = entry(id).version;
  const wage: WageSnapshot = {
    id: "wage",
    user_id: "user",
    job_id: "job",
    from_date: null,
    hourly_wage: t.rates[String(level)],
    wage_level: level,
    tariff_type_id: id,
    supplements: t.supplements,
    overtime: { ...t.overtime, weeklyThresholdHours: 1 },
    tax_enabled: false,
    tax_percentage: 0,
    break_enabled: false,
    break_method: "none",
    break_threshold_hours: 0,
    break_deduction_minutes: 0,
  };
  const shift: ShiftRow = {
    id: "shift",
    user_id: "user",
    job_id: "job",
    shift_date: date,
    start_time: start,
    end_time: end,
  };
  return applyWeeklyOvertime(
    [{ ...shift, computed: computeShift(shift, {}, [], wage) }],
    { snapshotForShift: () => wage, effectiveJobIdForShift: () => "job" },
  )[0].computed;
}
describe("reviewed catalogue payroll outcomes", () => {
  test("cleaning apprentices receive the adult unskilled wage for overtime hours", () => {
    for (const id of ["cleaning_nho_apprentice", "cleaning_virke_apprentice"]) {
      const result = overtimeOutcome(id, "2026-11-09", "09:00", "11:00", 21);
      expect(result.wagePeriods.at(-1)?.baseRate).toBe(247.29);
      expect(result.wagePeriods.at(-1)?.totalRate).toBeCloseTo(370.935, 8);
    }
  });
  test("Handel retains holiday-eve pay during overtime but ordinary UB stops", () => {
    const holiday = overtimeOutcome(
      "handel_nho",
      "2027-03-27",
      "09:00",
      "11:00",
    );
    expect(holiday.wagePeriods.at(-1)?.totalRate).toBeCloseTo(489.5, 8);
    const ordinary = overtimeOutcome(
      "handel_nho",
      "2026-11-09",
      "18:00",
      "20:00",
    );
    expect(ordinary.wagePeriods.at(-1)?.totalRate).toBeCloseTo(293.7, 8);
  });
  test("security apprentices receive half adult supplements within their training plan", () => {
    const id = "vekter_apprentice_375";
    const wage = entry(id).version.rates["21"];
    expect(
      wage + supplement(id, "2026-11-08", "22:00", "23:00", 21),
    ).toBeCloseTo(142.29, 8);
    expect(supplement(id, "2026-12-25", "12:00", "13:00", 21)).toBeCloseTo(
      40008.29 / 162.5 / 2,
      8,
    );
  });
  test("energy holiday-eve pay begins at fifteen and morning overtime switches at six", () => {
    expect(supplement("energy_hk_virke", "2027-03-27", "10:00", "11:00")).toBe(
      0,
    );
    expect(supplement("energy_hk_virke", "2027-03-27", "15:00", "16:00")).toBe(
      196.08,
    );
    const morning = overtimeOutcome(
      "energy_hk_virke",
      "2026-11-09",
      "05:00",
      "07:00",
    );
    expect(morning.wagePeriods.at(-1)?.totalRate).toBeCloseTo(294.12, 8);
  });
  test("Riks night guards starting after holiday midnight keep premium through the whole shift", () => {
    expect(
      supplement("riksavtalen_guard_375", "2027-01-02", "00:00", "08:00"),
    ).toBeCloseTo(215.29 * 8, 8);
    expect(
      supplement("riksavtalen_guard_375", "2027-01-02", "22:00", "02:00"),
    ).toBeCloseTo(31.52 * 2 + 43.94 * 2, 8);
  });

  test("Riksavtalen evening and night boundaries use the correct role", () => {
    expect(
      supplement("riksavtalen_hotel", "2026-11-09", "18:00", "19:00"),
    ).toBe(0);
    expect(
      supplement("riksavtalen_hotel", "2026-11-09", "22:00", "23:00"),
    ).toBe(16.59);
    expect(
      supplement("riksavtalen_hotel", "2026-11-10", "02:00", "03:00"),
    ).toBe(58.04);
    expect(
      supplement("riksavtalen_guard_375", "2026-11-10", "02:00", "03:00"),
    ).toBe(43.94);
    expect(
      supplement("riksavtalen_manual_375", "2026-11-10", "02:00", "03:00"),
    ).toBeCloseTo(43.94 + 24.87, 8);
  });
  test("Riksavtalen holiday premium follows the shift start across midnight", () => {
    expect(
      supplement("riksavtalen_hotel", "2026-12-25", "23:00", "02:00"),
    ).toBeCloseTo(215.29 * 3, 8);
    expect(
      supplement("riksavtalen_hotel", "2026-12-31", "22:00", "02:00"),
    ).toBeCloseTo(215.29 * 4, 8);
  });
  test("security night and weekend payments coexist and qualification is in base pay", () => {
    expect(
      supplement("vekteroverenskomst", "2026-11-08", "22:00", "23:00"),
    ).toBe(76);
    expect(entry("vekter_355").version.rates["1"]).toBe(260.08);
    expect(entry("vekter_336").version.rates["11"]).toBeCloseTo(
      274.81 + 14.5,
      8,
    );
  });
  test("security retains night and weekend entitlements during their applicable overtime", () => {
    expect(
      overtimeOutcome("vekteroverenskomst", "2026-11-09", "21:00", "23:00")
        .gross,
    ).toBe(671.55);
    expect(
      overtimeOutcome("vekteroverenskomst", "2026-11-08", "21:00", "23:00")
        .gross,
    ).toBe(890.66);
  });
  test("cleaning night entitlement continues during premium hours", () => {
    expect(
      overtimeOutcome("cleaning_nho_375", "2026-11-09", "21:00", "23:00").gross,
    ).toBe(799.87);
    expect(
      overtimeOutcome("cleaning_virke_375", "2026-11-09", "21:00", "23:00")
        .gross,
    ).toBe(799.87);
  });
  test("KS and PBL holiday-eve overtime uses1331/3 instead of the weekday premium", () => {
    for (const id of ["ks_ch4_375", "pbl_day"]) {
      const result = overtimeOutcome(id, "2026-12-24", "11:00", "13:00");
      expect(result.wagePeriods.at(-1)?.supplementRate).toBeCloseTo(
        (((entry(id).version.rates["1"] * 1950) / 1850) * 4) / 3,
        8,
      );
    }
  });
  test("statutory hospitality does not inherit Riksavtalen UB", () => {
    expect(
      supplement("hospitality_allmenngjort", "2026-11-08", "22:00", "23:00"),
    ).toBe(0);
    expect(entry("hospitality_allmenngjort").version.rates["1"]).toBe(204.79);
  });
  test("retail agreements have distinct Saturday payments", () => {
    expect(supplement("hk_retail", "2026-11-07", "16:00", "17:00")).toBe(55);
    expect(supplement("handel_nho", "2026-11-07", "16:00", "17:00")).toBe(65);
    expect(supplement("butikk_nho", "2026-11-07", "16:00", "17:00")).toBe(84);
  });
  test("KS uses October supplement floors and annual salary conversion", () => {
    expect(entry("ks_ch4_375").version.rates["1"]).toBeCloseTo(
      418600 / 1950,
      10,
    );
    expect(supplement("ks_ch4_355", "2026-11-07", "18:00", "19:00")).toBe(
      73 + 60,
    );
    expect(supplement("ks_ch4_355", "2026-11-09", "22:00", "23:00")).toBe(70);
    expect(entry("ks_ch4_355").version.overtime.enabled).toBe(false);
  });
  test("PBL converts each published annual salary without assuming a KS table", () => {
    expect(entry("pbl_day").version.rates["1"]).toBeCloseTo(420500 / 1950, 10);
    expect(entry("pbl_day").version.rates["11"]).toBeCloseTo(478400 / 1950, 10);
    expect(entry("pbl_day").version.overtime.premiumBaseMultiplier).toBe(
      1950 / 1850,
    );
  });
});
describe("agreement selection metadata", () => {
  test("every published variant can be selected by its family and answers alone", () => {
    for (const { type } of tariffCatalogue) {
      const selected = type.presentation;
      if (!selected) throw new Error(`Missing presentation for ${type.id}`);
      const matching = tariffCatalogue.filter(({ type: candidate }) => {
        const presentation = candidate.presentation;
        return (
          presentation?.family_id === selected.family_id &&
          selected.options.every((answer) =>
            presentation.options.some(
              (option) =>
                option.dimension_id === answer.dimension_id &&
                option.value === answer.value,
            ),
          )
        );
      });
      expect(matching.map(({ type }) => type.id)).toEqual([type.id]);
    }
  });

  test("hotel workweek and night role remain independent choices within one agreement", () => {
    const hotel = tariffCatalogue.filter(
      ({ type }) => type.presentation?.family_id === "riksavtalen",
    );
    const weeks = new Set(
      hotel.flatMap(
        ({ type }) =>
          type.presentation?.options
            .filter((option) => option.dimension_id === "week")
            .map((option) => option.value) ?? [],
      ),
    );
    for (const week of weeks) {
      const variants = hotel.filter(({ type }) =>
        type.presentation?.options.some(
          (option) => option.dimension_id === "week" && option.value === week,
        ),
      );
      expect(
        new Set(
          variants.flatMap(
            ({ type }) =>
              type.presentation?.options
                .filter((option) => option.dimension_id === "night_role")
                .map((option) => option.value) ?? [],
          ),
        ),
      ).toEqual(new Set(["other", "guard", "manual"]));
    }
  });

  test("apprentice selection exposes only the published workweek and changes category meaning", () => {
    for (const id of [
      "cleaning_nho_apprentice",
      "cleaning_virke_apprentice",
      "vekter_apprentice_375",
    ]) {
      const apprentice = entry(id).type.presentation;
      if (!apprentice) throw new Error(`Missing ${id}`);
      const family = tariffCatalogue.filter(
        ({ type }) => type.presentation?.family_id === apprentice.family_id,
      );
      const apprenticeOptions = family.filter(({ type }) =>
        type.presentation?.options.some(
          (option) =>
            option.dimension_id === "employment" &&
            option.value === "apprentice",
        ),
      );
      expect(apprenticeOptions.map(({ type }) => type.id)).toEqual([id]);
      expect(apprentice.options.map((option) => option.dimension_id)).toEqual([
        "employment",
        "week",
      ]);
      expect(
        apprentice.options.find((option) => option.dimension_id === "week")
          ?.value,
      ).toBe("37.5");
      for (const { type } of family.filter(({ type }) => type.id !== id)) {
        expect(type.presentation?.category_group).not.toBe(
          apprentice.category_group,
        );
      }
    }
  });

  test("statutory minima and employer agreements cannot be mistaken for the same agreement", () => {
    const ids = [
      "cleaning_nho_375",
      "cleaning_virke_375",
      "renhold_allmenngjort",
    ];
    expect(
      new Set(ids.map((id) => entry(id).type.presentation?.family_id)).size,
    ).toBe(ids.length);
    expect(entry("renhold_allmenngjort").type.presentation?.kind).toBe(
      "statutory",
    );
    expect(entry("cleaning_nho_375").type.presentation?.kind).toBe("agreement");
    expect(
      entry("hospitality_allmenngjort").type.presentation?.family_id,
    ).not.toBe(entry("riksavtalen_hotel").type.presentation?.family_id);
  });

  test("agriculture coverage is chosen within one family without reusing seasonal category meanings", () => {
    const seasonal = entry("agriculture_seasonal_allmenngjort").type
      .presentation;
    const permanent = entry("agriculture_permanent_allmenngjort").type
      .presentation;
    const relief = entry("agriculture_relief_allmenngjort").type.presentation;
    expect(seasonal?.family_id).toBe(permanent?.family_id);
    expect(relief?.family_id).toBe(permanent?.family_id);
    expect(seasonal?.category_group).not.toBe(permanent?.category_group);
  });

  test("adding presentation preserves stored identifiers and the complete monetary contract", () => {
    for (const published of tariffCatalogue) {
      const unannotated = structuredClone(published);
      delete unannotated.type.presentation;
      const before = structuredClone(unannotated);
      const annotated = withPresentation(unannotated);
      const { presentation, ...type } = annotated.type;
      expect(presentation).toBeDefined();
      expect({ ...annotated, type }).toEqual(before);
      expect(unannotated).toEqual(before);
    }
  });

  test("ambiguous, inconsistent and untranslated selections cannot be published", () => {
    for (const mutate of [
      (entries: CatalogueEntry[]) => {
        delete entries[0].type.presentation;
      },
      (entries: CatalogueEntry[]) => {
        Object.assign(entries[0].type.presentation ?? {}, { kind: "unknown" });
      },
      (entries: CatalogueEntry[]) => {
        Object.assign(entries[0].type.presentation ?? {}, { name_nb: " " });
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_guard_375",
        )?.type.presentation;
        if (!hotel) throw new Error("Missing hotel");
        hotel.name_en = "Different family name";
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_guard_375",
        )?.type.presentation;
        if (!hotel) throw new Error("Missing hotel");
        hotel.options.reverse();
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_hotel",
        )?.type.presentation;
        if (!hotel) throw new Error("Missing hotel");
        hotel.options.push(hotel.options[0]);
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_guard_375",
        )?.type.presentation;
        const ordinary = entries.find(
          ({ type }) => type.id === "riksavtalen_hotel",
        )?.type.presentation;
        if (!hotel || !ordinary) throw new Error("Missing hotel");
        hotel.options = ordinary.options;
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_guard_375",
        )?.type.presentation;
        if (!hotel) throw new Error("Missing hotel");
        hotel.options[0].value_en = " ";
      },
      (entries: CatalogueEntry[]) => {
        const hotel = entries.find(
          ({ type }) => type.id === "riksavtalen_guard_375",
        );
        if (!hotel) throw new Error("Missing hotel");
        hotel.version.categories[0].label_nb = "Different category meaning";
      },
    ]) {
      const copy = structuredClone(tariffCatalogue);
      mutate(copy);
      expect(() => validateCatalogue(copy)).toThrow();
    }
  });
});

describe("catalogue trust boundaries", () => {
  test("duplicate categories and missing rates cannot be published", () => {
    const duplicate = structuredClone(tariffCatalogue);
    duplicate[0].version.categories.push(duplicate[0].version.categories[0]);
    expect(() => validateCatalogue(duplicate)).toThrow();
    const missing = structuredClone(tariffCatalogue);
    delete missing[0].version.rates["1"];
    expect(() => validateCatalogue(missing)).toThrow();
  });
  test("invalid money, times and provenance dates cannot be published", () => {
    for (const mutate of [
      (e: CatalogueEntry) => {
        e.version.rates["1"] = NaN;
      },
      (e: CatalogueEntry) => {
        e.version.supplements.rules[0].from = "25:00";
      },
      (e: CatalogueEntry) => {
        e.version.verified_on = "2026-02-30";
      },
    ]) {
      const copy = structuredClone(tariffCatalogue);
      mutate(copy[0]);
      expect(() => validateCatalogue(copy)).toThrow();
    }
  });
  test("unknown revisions fail instead of returning another agreement", () => {
    expect(() => requireCatalogueRevision("2025")).toThrow();
    expect(() => requireCatalogueRevision(CATALOGUE_REVISION)).not.toThrow();
  });
  test("overdue source reviews are visible and do not invent new rates", () => {
    expect(overdueTariffs("2026-11-06")).toEqual([]);
    expect(overdueTariffs("2026-12-01").length).toBe(tariffCatalogue.length);
    expect(
      exportCatalogue().versions.find((v) => v.tariff_type_id === "hk_retail")
        ?.rates["6"],
    ).toBe(271.64);
  });
  test("UI fixture is exactly the reviewed export", async () => {
    const fixture = await Bun.file(
      new URL(
        "../../ios/TidexApp/Storage/Testing/TariffCatalogueFixture.json",
        import.meta.url,
      ),
    ).json();
    expect(fixture).toEqual(exportCatalogue());
  });
});
