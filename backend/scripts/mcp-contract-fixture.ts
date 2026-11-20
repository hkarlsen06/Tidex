// Writes ios/TidexAppTests/Fixtures/MCPContractFixture.json: job and wage snapshot rows built
// by the MCP pay tools' builders, shifts as add_shift stores them, and the gross pay that
// get_earnings computes for them. MCPContractFixtureTests decodes the rows with the app's
// sync types and prices the shifts with the app's payroll code, so a row the app can't
// decode, or pay the two sides compute differently, fails a test.
//
//   bun backend/scripts/mcp-contract-fixture.ts         rewrite the fixture
//
// mcp-pay.test.ts fails while the committed file differs from what this builds.

import type { Doc } from "../convex/_generated/dataModel";
import { shiftEarnings } from "../convex/lib/mcp/earnings";
import { jobRow, placement, setPay, snapshotFields, snapshotInEffect, snapshotRow } from "../convex/lib/mcp/pay";
import { shiftTimes } from "../convex/lib/mcp/shiftTimes";
import { applicableWageSnapshot, asRegularShift, asSnapshot } from "../convex/liveActivities";

export const FIXTURE_PATH = new URL("../../ios/TidexAppTests/Fixtures/MCPContractFixture.json", import.meta.url);

const USER_ID = "00000000-0000-4000-8000-000000000001";
const WRITTEN_AT = "2026-11-20T12:00:00.000Z";
const TODAY = "2026-11-20";
const FROM = "2026-12-07";
const TO = "2026-12-31";

let nextId = 100;
const uuid = () => `00000000-0000-4000-8000-${String(nextId++).padStart(12, "0")}`;
let nextRevision = 1;

/** A row as the server stores and the app pulls it. */
function stored<R extends object>(row: R) {
  return { ...row, user_id: USER_ID, created_at: WRITTEN_AT, updated_at: WRITTEN_AT, revision: nextRevision++ };
}

/** jobs.ts defaults: monthly_goal is the one column the app leaves to the server. */
const storedJob = (row: ReturnType<typeof jobRow>) => stored({ monthly_goal: 20000, ...row });
type StoredSnapshot = ReturnType<typeof stored<ReturnType<typeof snapshotRow>>>;

/** pay, tax and breaks as an agent passes them to set_pay. */
const settingsFrom = (args: Record<string, unknown>) => setPay.parse({ job_id: "fixture", ...args }).settings;

function job(name: string, currency: string, args: Record<string, unknown>, active: { sort_order: number }[]) {
  const { sortOrder, isDefault } = placement(active);
  const row = storedJob(
    jobRow({
      id: uuid(),
      name,
      color: "#22C55E",
      currency,
      isDefault,
      sortOrder,
      payrollDay: 20,
      payPeriod: { type: "monthly", startDay: 16, payoutMonthOffset: 1 },
    }),
  );
  const fields = snapshotFields(settingsFrom(args), null, { date: TODAY, currency });
  return { row, baseline: stored(snapshotRow(uuid(), row.id, undefined, fields)) };
}

function raise(job: { id: string; currency: string }, snapshots: StoredSnapshot[], fromDate: string, args: Record<string, unknown>) {
  const fields = snapshotFields(settingsFrom(args), snapshotInEffect(snapshots, fromDate), { date: fromDate, currency: job.currency });
  return stored(snapshotRow(uuid(), job.id, fromDate, fields));
}

function shift(jobId: string, date: string, start: string, end: string) {
  return stored({ id: uuid(), job_id: jobId, shift_date: date, ...shiftTimes(start, end) });
}

export function buildFixture() {
  nextId = 100;
  nextRevision = 1;

  const custom = job(
    "Café",
    "$",
    {
      pay: {
        type: "custom",
        hourly_wage: 18.5,
        supplements: [
          { days: [1, 2, 3, 4, 5], from: "18:00", to: "24:00", amount: 2.5 },
          { days: [6, 7], from: "00:00", to: "24:00", percent: 30 },
        ],
        overtime: { enabled: true, weekly_threshold_hours: 40 },
      },
      tax: { enabled: true, percentage: 18 },
      breaks: { enabled: true },
    },
    [],
  );
  const customRaise = raise(custom.row, [custom.baseline], "2026-12-15", { pay: { type: "custom", hourly_wage: 20 } });

  const tariff = job(
    "Renhold",
    "kr",
    { pay: { type: "tariff", tariff_type_id: "cleaning_nho_375", level: 1 } },
    [custom.row],
  );
  const tariffRaise = raise(tariff.row, [tariff.baseline], "2026-12-14", {
    pay: { type: "tariff", tariff_type_id: "cleaning_nho_375", level: 2 },
  });

  const shifts = [
    // Café: a week over 40 hours with evening and weekend hours, then shifts after the raise.
    shift(custom.row.id, "2026-12-07", "10:00", "19:00"),
    shift(custom.row.id, "2026-12-08", "10:00", "19:00"),
    shift(custom.row.id, "2026-12-09", "10:00", "19:00"),
    shift(custom.row.id, "2026-12-10", "10:00", "19:00"),
    shift(custom.row.id, "2026-12-11", "14:00", "23:00"),
    shift(custom.row.id, "2026-12-12", "09:00", "15:00"),
    shift(custom.row.id, "2026-12-15", "16:00", "00:00"),
    shift(custom.row.id, "2026-12-20", "11:00", "17:00"),
    // Renhold: a night shift before the raise, then Christmas Eve, Christmas Day and New Year's Eve.
    shift(tariff.row.id, "2026-12-08", "22:00", "06:00"),
    shift(tariff.row.id, "2026-12-13", "08:00", "14:00"),
    shift(tariff.row.id, "2026-12-24", "10:00", "18:00"),
    shift(tariff.row.id, "2026-12-25", "12:00", "20:00"),
    shift(tariff.row.id, "2026-12-31", "21:00", "03:00"),
  ];

  const jobs = [custom.row, tariff.row];
  const snapshots = [custom.baseline, customRaise, tariff.baseline, tariffRaise];
  // The same steps as mcpShifts.earnings, on the same rows.
  const priced = snapshots.map((s) => asSnapshot(s as unknown as Doc<"wage_snapshots">));
  const earnings = shiftEarnings({
    from: FROM,
    to: TO,
    regular: shifts.map((s) => asRegularShift(s as unknown as Doc<"user_shifts">)),
    recurring: [],
    snapshotFor: (s) => applicableWageSnapshot(s, priced),
    currencyFor: (jobId) => jobs.find((j) => j.id === jobId)?.currency ?? "NOK",
  });

  return { user_id: USER_ID, jobs, wage_snapshots: snapshots, shifts, earnings: { from: FROM, to: TO, ...earnings } };
}

export const fixtureJSON = () => `${JSON.stringify(buildFixture(), null, 2)}\n`;

if (import.meta.main) {
  await Bun.write(FIXTURE_PATH, fixtureJSON());
  console.log(`Wrote ${FIXTURE_PATH.pathname}`);
}
