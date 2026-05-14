// deno-lint-ignore-file no-import-prefix
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadCalendarData, projectRecurringShifts } from "./data.ts";
import type { CalendarSupabaseClient } from "./types.ts";

type Operation = {
  table: string;
  method: string;
  args: unknown[];
};

class MockQuery {
  constructor(
    private readonly table: string,
    private readonly rows: unknown[],
    private readonly operations: Operation[],
  ) {}

  private record(method: string, args: unknown[]): this {
    this.operations.push({ table: this.table, method, args });
    return this;
  }

  select(...args: unknown[]): this {
    return this.record("select", args);
  }

  eq(...args: unknown[]): this {
    return this.record("eq", args);
  }

  is(...args: unknown[]): this {
    return this.record("is", args);
  }

  gte(...args: unknown[]): this {
    return this.record("gte", args);
  }

  lte(...args: unknown[]): this {
    return this.record("lte", args);
  }

  order(...args: unknown[]): this {
    return this.record("order", args);
  }

  then<TResult1 = unknown, TResult2 = never>(
    onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve({ data: this.rows, error: null }).then(
      onfulfilled,
      onrejected,
    );
  }
}

function createMockClient(rows: Record<string, unknown[]> = {}) {
  const operations: Operation[] = [];
  const client: CalendarSupabaseClient = {
    from(table: string) {
      return new MockQuery(table, rows[table] ?? [], operations);
    },
    rpc() {
      return { data: [], error: null };
    },
  };

  return { client, operations };
}

function hasOperation(
  operations: Operation[],
  table: string,
  method: string,
  args: unknown[],
): boolean {
  return operations.some((operation) =>
    operation.table === table &&
    operation.method === method &&
    JSON.stringify(operation.args) === JSON.stringify(args)
  );
}

Deno.test("loadCalendarData loads only events for events_only and applies overlap/deleted/user filters", async () => {
  const { client, operations } = createMockClient();

  await loadCalendarData(client, "user-1", "events_only", {
    startDate: "2026-02-14",
    endDate: "2027-05-14",
  });

  assertEquals(
    new Set(operations.map((operation) => operation.table)),
    new Set(["events"]),
  );
  assert(hasOperation(operations, "events", "eq", ["user_id", "user-1"]));
  assert(hasOperation(operations, "events", "is", ["deleted_at", null]));
  assert(hasOperation(operations, "events", "gte", ["end_date", "2026-02-14"]));
  assert(
    hasOperation(operations, "events", "lte", ["start_date", "2027-05-14"]),
  );
});

Deno.test("loadCalendarData loads shifts, recurring shifts, and jobs only for shifts_only", async () => {
  const { client, operations } = createMockClient();

  await loadCalendarData(client, "user-1", "shifts_only", {
    startDate: "2026-02-14",
    endDate: "2027-05-14",
  });

  assertEquals(
    new Set(operations.map((operation) => operation.table)),
    new Set(["user_shifts", "recurring_shifts", "jobs"]),
  );
  for (const table of ["user_shifts", "recurring_shifts", "jobs"]) {
    assert(hasOperation(operations, table, "eq", ["user_id", "user-1"]));
    assert(hasOperation(operations, table, "is", ["deleted_at", null]));
  }
});

Deno.test("loadCalendarData loads both content groups for shifts_and_events", async () => {
  const { client, operations } = createMockClient();

  await loadCalendarData(client, "user-1", "shifts_and_events", {
    startDate: "2026-02-14",
    endDate: "2027-05-14",
  });

  assertEquals(
    new Set(operations.map((operation) => operation.table)),
    new Set(["user_shifts", "recurring_shifts", "jobs", "events"]),
  );
});

Deno.test("projectRecurringShifts projects null-end recurring shifts beyond six months and clips to feed window", () => {
  const projected = projectRecurringShifts([
    {
      id: "recurring-1",
      start_time: "09:00",
      end_time: "17:00",
      repeat_interval_weeks: 0,
      selected_days: { "1": "2026-01-05" },
      end_condition: null,
      exclusions: ["2026-09-07"],
      date_specific_notes: { "2026-10-05": "Inventory" },
      job_id: "job-1",
      updated_at: "2026-01-01T00:00:00Z",
    },
  ], {
    startDate: "2026-05-01",
    endDate: "2027-05-15",
  });

  assert(projected.some((shift) => shift.occurrenceDate === "2026-10-05"));
  assertEquals(
    projected.find((shift) => shift.occurrenceDate === "2026-10-05")?.note,
    "Inventory",
  );
  assert(!projected.some((shift) => shift.occurrenceDate === "2026-09-07"));
  assert(!projected.some((shift) => shift.occurrenceDate < "2026-05-01"));
  assert(!projected.some((shift) => shift.occurrenceDate > "2027-05-15"));
});

Deno.test("projectRecurringShifts respects every-other-week patterns and end conditions", () => {
  const projected = projectRecurringShifts([
    {
      id: "recurring-1",
      start_time: "09:00",
      end_time: "17:00",
      repeat_interval_weeks: 1,
      selected_days: { "1": "2026-05-04" },
      end_condition: { type: "end_date", date: "2026-05-31" },
      exclusions: [],
      date_specific_notes: null,
      job_id: null,
      updated_at: null,
    },
  ], {
    startDate: "2026-05-01",
    endDate: "2026-06-30",
  });

  assertEquals(projected.map((shift) => shift.occurrenceDate), [
    "2026-05-04",
    "2026-05-18",
  ]);
});
