import { describe, expect, test } from "bun:test";
import type { Doc } from "../convex/_generated/dataModel";
import { shiftEarnings } from "../convex/lib/mcp/earnings";
import {
  addJob,
  archiveRefusal,
  getTariff,
  listTariffs,
  payPeriodView,
  payView,
  placement,
  setPay,
  snapshotFields,
  snapshotInEffect,
  snapshotRow,
  snapshotUpdate,
  type StoredSnapshot,
  updateJob,
} from "../convex/lib/mcp/pay";
import { ToolError } from "../convex/lib/mcp/shiftTimes";
import { tariffCatalogue } from "../convex/lib/tariffCatalogue";
import { applicableWageSnapshot, asRegularShift, asSnapshot } from "../convex/liveActivities";
import { buildFixture, FIXTURE_PATH } from "./mcp-contract-fixture";

const USER = "user-1";
const JOB = "job-1";
const settings = (args: Record<string, unknown>) => setPay.parse({ job_id: JOB, ...args }).settings;
const newPay = (args: Record<string, unknown>, currency = "kr") => snapshotFields(settings(args), null, { date: "2026-11-20", currency });

function storedSnapshot(id: string, fromDate: string | undefined, fields: ReturnType<typeof newPay>) {
  return { ...snapshotRow(id, JOB, fromDate, fields), user_id: USER, revision: 1, updated_at: "2026-11-20T00:00:00.000Z" };
}

/** Gross pay for one-off shifts, as get_earnings prices them. */
function gross(snapshots: ReturnType<typeof storedSnapshot>[], shifts: [date: string, start: string, end: string][]) {
  const priced = snapshots.map((s) => asSnapshot(s as unknown as Doc<"wage_snapshots">));
  const dates = shifts.map(([date]) => date).sort();
  return shiftEarnings({
    from: dates[0],
    to: dates.at(-1)!,
    regular: shifts.map(([date, start, end], i) =>
      asRegularShift({ id: `s${i}`, user_id: USER, job_id: JOB, shift_date: date, start_time: start, end_time: end } as Doc<"user_shifts">),
    ),
    recurring: [],
    snapshotFor: (shift) => applicableWageSnapshot(shift, priced),
    currencyFor: () => "kr",
  }).totals[0].gross_pay;
}

const refused = (run: () => unknown) => {
  try {
    run();
  } catch (error) {
    expect(error).toBeInstanceOf(ToolError);
    return (error as Error).message;
  }
  throw new Error("expected a refusal");
};

describe("tariff pay", () => {
  const retail = tariffCatalogue.find((e) => e.type.id === "hk_retail")!;
  const level = retail.version.categories.at(-1)!.level;

  test("a tariff level pays that level's rate with the agreement's supplements and overtime", () => {
    const pay = newPay({ pay: { type: "tariff", tariff_type_id: "hk_retail", level } });
    expect(pay.hourly_wage).toBe(retail.version.rates[String(level)]);
    expect(pay.wage_level).toBe(level);
    expect(pay.tariff_type_id).toBe("hk_retail");
    expect(pay.supplements).toEqual(retail.version.supplements);
    expect(pay.overtime).toEqual(retail.version.overtime);
  });

  test("negative and three-digit tariff levels are accepted when the tariff has them", () => {
    const entry = tariffCatalogue.find((e) => e.version.categories.some((c) => c.level >= 100))!;
    const high = entry.version.categories.find((c) => c.level >= 100)!.level;
    expect(newPay({ pay: { type: "tariff", tariff_type_id: entry.type.id, level: high } }).hourly_wage).toBe(entry.version.rates[String(high)]);
    expect(newPay({ pay: { type: "tariff", tariff_type_id: "hk_retail", level: -1 } }).wage_level).toBe(-1);
  });

  test("a level the tariff lacks is refused with the levels it has", () => {
    expect(refused(() => newPay({ pay: { type: "tariff", tariff_type_id: "hk_retail", level: 99 } }))).toContain("Levels:");
  });

  test("tariff pay is refused for a job paid in another currency", () => {
    expect(refused(() => newPay({ pay: { type: "tariff", tariff_type_id: "hk_retail", level } }, "$"))).toContain("kr");
    expect(refused(() => addJob.parse({ name: "Shop", currency: "€", pay: { type: "tariff", tariff_type_id: "hk_retail", level } }))).toContain("kr");
    expect(addJob.parse({ name: "Shop", pay: { type: "tariff", tariff_type_id: "hk_retail", level } }).currency).toBe("kr");
  });

  test("a date before the catalogue's rates is refused", () => {
    expect(
      refused(() => snapshotFields(settings({ pay: { type: "tariff", tariff_type_id: "hk_retail", level } }), null, { date: "2025-01-01", currency: "kr" })),
    ).toContain("custom pay");
  });

  test("get_tariff lists every level with its wage, and list_tariffs finds agreements by Norwegian name", () => {
    expect(getTariff("hk_retail").levels).toHaveLength(retail.version.categories.length);
    const found = listTariffs("renhold").tariffs.flatMap((f) => f.variants.map((v) => v.tariff_type_id));
    expect(found).toContain("cleaning_nho_375");
    expect(found).not.toContain("hk_retail");
  });
});

describe("custom pay", () => {
  test("a raise from a date pays the new wage from that date and the old one before it", () => {
    const baseline = storedSnapshot("w1", undefined, newPay({ pay: { type: "custom", hourly_wage: 200 }, breaks: { enabled: false } }));
    const raise = storedSnapshot(
      "w2",
      "2026-12-15",
      snapshotFields(settings({ pay: { type: "custom", hourly_wage: 230 } }), snapshotInEffect([baseline], "2026-12-15"), {
        date: "2026-12-15",
        currency: "kr",
      }),
    );
    expect(gross([baseline, raise], [["2026-12-14", "10:00", "14:00"]])).toBe(800);
    expect(gross([baseline, raise], [["2026-12-15", "10:00", "14:00"]])).toBe(920);
  });

  test("a raise keeps the supplements, overtime, tax and breaks of the pay in effect", () => {
    const base = newPay({
      pay: { type: "custom", hourly_wage: 200, supplements: [{ days: [6], from: "00:00", to: "24:00", amount: 50 }], overtime: { enabled: true } },
      tax: { enabled: true, percentage: 30 },
      breaks: { enabled: true, deduction_minutes: 45 },
    });
    const raised = snapshotFields(settings({ pay: { type: "custom", hourly_wage: 230 } }), base, { date: "2026-12-15", currency: "kr" });
    expect(raised).toEqual({ ...base, hourly_wage: 230 });
  });

  test("a supplement adds its amount per hour in its window, including across midnight", () => {
    const night = storedSnapshot(
      "w1",
      undefined,
      newPay({ pay: { type: "custom", hourly_wage: 100, supplements: [{ days: [1, 2, 3, 4, 5, 6, 7], from: "22:00", to: "06:00", amount: 20 }] }, breaks: { enabled: false } }),
    );
    expect(gross([night], [["2026-12-09", "20:00", "02:00"]])).toBe(6 * 100 + 4 * 20);
  });

  test("overtime pays 50% extra above the weekly threshold", () => {
    const pay = (overtime: unknown) =>
      storedSnapshot("w1", undefined, newPay({ pay: { type: "custom", hourly_wage: 100, overtime }, breaks: { enabled: false } }));
    const week: [string, string, string][] = ["07", "08", "09", "10"].map((d) => [`2026-12-${d}`, "08:00", "18:00"]);
    expect(gross([pay({ enabled: false })], week)).toBe(4000);
    expect(gross([pay({ enabled: true, weekly_threshold_hours: 37.5 })], week)).toBe(4000 + 2.5 * 50);
  });

  test("a new kr job deducts the app's default break and a job in another currency doesn't", () => {
    expect(newPay({ pay: { type: "custom", hourly_wage: 200 } }).break_enabled).toBe(true);
    expect(newPay({ pay: { type: "custom", hourly_wage: 20 } }, "$").break_enabled).toBe(false);
  });

  test("tax needs a percentage when it is turned on", () => {
    expect(refused(() => newPay({ pay: { type: "custom", hourly_wage: 200 }, tax: { enabled: true } }))).toContain("tax.percentage");
  });

  test("invalid supplement rules are refused with what to fix", () => {
    const supplement = (rule: Record<string, unknown>) => () =>
      settings({ pay: { type: "custom", hourly_wage: 200, supplements: [{ days: [1], from: "18:00", to: "21:00", ...rule }] } });
    expect(refused(supplement({ amount: 20, percent: 10 }))).toContain("exactly one of amount");
    expect(refused(supplement({}))).toContain("exactly one of amount");
    expect(refused(supplement({ days: [], amount: 20 }))).toContain("weekdays");
    expect(refused(supplement({ days: [8], amount: 20 }))).toContain("from 1 to 7");
    expect(refused(supplement({ to: "18:00", amount: 20 }))).toContain("same time");
    expect(refused(supplement({ from: "6pm", amount: 20 }))).toContain("time like");
    expect(refused(supplement({ amount: -5 }))).toContain("above 0");
    expect(refused(supplement({ amount: 20, rate: 20 }))).toContain("Unknown argument");
  });
});

describe("saving pay", () => {
  test("setting pay that is already stored changes nothing, so a retry keeps the revision", () => {
    const fields = newPay({ pay: { type: "custom", hourly_wage: 200 } });
    expect(snapshotUpdate(storedSnapshot("w1", undefined, fields), fields)).toBeNull();
  });

  test("switching from tariff to custom pay clears the tariff level", () => {
    const tariff = storedSnapshot("w1", undefined, newPay({ pay: { type: "tariff", tariff_type_id: "hk_retail", level: 1 } }));
    const custom = snapshotFields(settings({ pay: { type: "custom", hourly_wage: 250 } }), tariff, { date: "2026-11-20", currency: "kr" });
    const update = snapshotUpdate(tariff, custom);
    expect(update?.clear).toEqual(["wage_level", "tariff_type_id"]);
    expect(update?.set.supplements).toEqual({ rules: [] });
  });

  test("get_pay shows each change with the date the next one starts", () => {
    const fields = newPay({ pay: { type: "custom", hourly_wage: 200 } });
    const view = payView({ id: JOB, name: "Café", currency: "kr" }, [
      storedSnapshot("w3", "2027-01-01", fields),
      storedSnapshot("w1", undefined, fields),
      storedSnapshot("w2", "2026-12-15", fields),
    ]);
    expect(view.pay.map((p) => [p.snapshot_id, p.from_date, p.until_date])).toEqual([
      ["w1", null, "2026-12-15"],
      ["w2", "2026-12-15", "2027-01-01"],
      ["w3", "2027-01-01", null],
    ]);
  });
});

describe("jobs", () => {
  const active = [
    { id: "a", is_default: true, sort_order: 0 },
    { id: "b", is_default: false, sort_order: 3 },
  ];

  test("archiving refuses the default job and the only active job", () => {
    expect(archiveRefusal(active[0], active)).toContain("default job");
    expect(archiveRefusal(active[1], [active[1]])).toContain("only active job");
    expect(archiveRefusal(active[1], active)).toBeNull();
  });

  test("a new job goes last, and the first job becomes the default", () => {
    expect(placement(active)).toEqual({ sortOrder: 4, isDefault: false });
    expect(placement([])).toEqual({ sortOrder: 0, isDefault: true });
  });

  test("a calendar month is stored as no pay period, as the app stores it", () => {
    const parsed = (pay_period: unknown) => updateJob.parse({ job_id: JOB, revision: 1, pay_period }).pay_period;
    expect(parsed({ type: "calendar_month" })).toBeNull();
    expect(parsed({ type: "monthly", start_day: 1, payout_month_offset: 1 })).toBeNull();
    expect(parsed({ type: "monthly", start_day: 16, payout_month_offset: 0 })).toEqual({ type: "monthly", startDay: 16, payoutMonthOffset: 0 });
    expect(parsed({ type: "biweekly", period_end: "2026-11-29", payout_delay_days: 5 })).toEqual({
      type: "biweekly",
      anchorEnd: "2026-11-29",
      payoutDelayDays: 5,
    });
    expect(refused(() => parsed({ type: "monthly", start_day: 29, payout_month_offset: 0 }))).toContain("start_day");
  });

  test("a stored pay period the app can't read shows as a calendar month, as the app treats it", () => {
    expect(payPeriodView({ type: "monthly", startDay: "5", payoutMonthOffset: 1 })).toEqual({ type: "calendar_month" });
    expect(payPeriodView(undefined)).toEqual({ type: "calendar_month" });
  });

  test("a color outside the app's palette is refused", () => {
    expect(refused(() => addJob.parse({ name: "Bar", color: "#123456", pay: { type: "custom", hourly_wage: 200 } }))).toContain("color");
    expect(addJob.parse({ name: " Bar ", color: "#22c55e", pay: { type: "custom", hourly_wage: 200 } })).toMatchObject({
      name: "Bar",
      color: "#22C55E",
    });
  });

  test("make_default can't be combined with archiving", () => {
    expect(refused(() => updateJob.parse({ job_id: JOB, revision: 1, make_default: true, archived: true }))).toContain("archived");
  });
});

test("the committed MCP contract fixture is what the builders produce", async () => {
  // Rewrite it with: bun backend/scripts/mcp-contract-fixture.ts
  expect(await Bun.file(FIXTURE_PATH).json()).toEqual(buildFixture());
});

describe("changing one part of existing pay", () => {
  const stored = (fields: Partial<StoredSnapshot>): StoredSnapshot => ({
    hourly_wage: 20,
    supplements: { rules: [] },
    overtime: { enabled: false, retainSupplements: false, rules: [], weeklyThresholdHours: 40 },
    ...fields,
  });

  test("turning tax on leaves the break deduction the user had", () => {
    const noDeduction = stored({ break_enabled: true, break_method: "none" });
    const fields = snapshotFields(settings({ tax: { enabled: true, percentage: 30 } }), noDeduction, { date: "2026-12-01", currency: "kr" });
    expect(fields.break_method).toBe("none");
    expect(fields.tax_percentage).toBe(30);
  });

  test("pay in another currency keeps breaks on when the stored pay never said", () => {
    const fields = snapshotFields(settings({ tax: { enabled: false } }), stored({}), { date: "2026-12-01", currency: "$" });
    expect(fields.break_enabled).toBe(true);
  });

  test("switching breaks on replaces a stored 'none' method, as the pay editor does", () => {
    const fields = snapshotFields(settings({ breaks: { enabled: true } }), stored({ break_enabled: false, break_method: "none" }), {
      date: "2026-12-01",
      currency: "kr",
    });
    expect(fields.break_method).toBe("proportional");
  });
});
