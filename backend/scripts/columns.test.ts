import { describe, expect, test } from "bun:test";
import { checkColumns } from "../convex/lib/columns";

const accepts = (row: Record<string, unknown>) => {
  const sent = { ...row };
  checkColumns("recurring_shifts", row);
  expect(row).toEqual(sent);
};
const rejects = (row: Record<string, unknown>) =>
  expect(() => checkColumns("recurring_shifts", row)).toThrow();

// The app sends a recurring shift that ends at midnight with end_time 24:00, and the
// Postgres timetz column it was written for stored that as 24:00:00+00.
describe("recurring shift times", () => {
  test("a shift ending at midnight syncs, unchanged, in the forms Postgres accepted", () => {
    accepts({ start_time: "16:00", end_time: "24:00" });
    accepts({ end_time: "24:00:00" });
    accepts({ end_time: "24:00:00+00" });
    accepts({ end_time: "24:00:00.000000+02:00" });
  });

  test("times past the end of the day are still rejected, as Postgres rejects them", () => {
    rejects({ end_time: "24:01" });
    rejects({ end_time: "24:00:01" });
    rejects({ end_time: "24:00:00.5" });
    rejects({ end_time: "25:00" });
  });
});
