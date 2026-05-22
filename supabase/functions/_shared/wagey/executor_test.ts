import { assert, assertEquals } from "jsr:@std/assert";

import type { WageyRequestContext } from "./context.ts";
import { executeTool } from "./executor.ts";

const USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

type TableName =
  | "events"
  | "user_shifts"
  | "user_settings"
  | "jobs"
  | "wage_snapshots"
  | "recurring_shifts"
  | "payroll_adjustments";

type MockDb = Record<TableName, Array<Record<string, unknown>>>;

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function makeUuid(index: number): string {
  return `00000000-0000-0000-0000-${String(index).padStart(12, "0")}`;
}

class MockQueryBuilder
  implements PromiseLike<{ data: any; error: any; count?: number | null }> {
  private mode: "select" | "insert" | "update" = "select";
  private insertedRows: Array<Record<string, unknown>> = [];
  private updateData: Record<string, unknown> = {};
  private selectAfterWrite = false;
  private singleMode: "many" | "single" | "maybeSingle" = "many";
  private filters: Array<(row: Record<string, unknown>) => boolean> = [];
  private orders: Array<
    { column: string; ascending: boolean; nullsFirst?: boolean }
  > = [];
  private limitCount: number | null = null;
  private head = false;
  private countExact = false;

  constructor(
    private readonly db: MockDb,
    private readonly table: TableName,
    private readonly nextId: () => string,
  ) {}

  select(_columns?: string, options?: { head?: boolean; count?: string }) {
    this.selectAfterWrite = true;
    this.head = options?.head ?? false;
    this.countExact = options?.count === "exact";
    return this;
  }

  insert(rows: Record<string, unknown> | Array<Record<string, unknown>>) {
    this.mode = "insert";
    this.insertedRows = Array.isArray(rows) ? rows : [rows];
    return this;
  }

  update(data: Record<string, unknown>) {
    this.mode = "update";
    this.updateData = data;
    return this;
  }

  eq(column: string, value: unknown) {
    this.filters.push((row) => row[column] === value);
    return this;
  }

  is(column: string, value: unknown) {
    this.filters.push((row) => (row[column] ?? null) === value);
    return this;
  }

  gte(column: string, value: unknown) {
    this.filters.push((row) => String(row[column] ?? "") >= String(value));
    return this;
  }

  lte(column: string, value: unknown) {
    this.filters.push((row) => String(row[column] ?? "") <= String(value));
    return this;
  }

  order(
    column: string,
    options?: { ascending?: boolean; nullsFirst?: boolean },
  ) {
    this.orders.push({
      column,
      ascending: options?.ascending ?? true,
      nullsFirst: options?.nullsFirst,
    });
    return this;
  }

  limit(value: number) {
    this.limitCount = value;
    return this;
  }

  single() {
    this.singleMode = "single";
    return this;
  }

  maybeSingle() {
    this.singleMode = "maybeSingle";
    return this;
  }

  then<
    TResult1 = { data: any; error: any; count?: number | null },
    TResult2 = never,
  >(
    onfulfilled?:
      | ((
        value: { data: any; error: any; count?: number | null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return this.execute().then(
      onfulfilled ?? undefined,
      onrejected ?? undefined,
    );
  }

  private async execute(): Promise<
    { data: any; error: any; count?: number | null }
  > {
    const rows = this.db[this.table];

    if (this.mode === "insert") {
      const inserted = this.insertedRows.map((row) => {
        const next = clone(row);
        next.id = next.id ?? this.nextId();
        next.created_at = next.created_at ?? "2026-04-15T12:00:00Z";
        next.updated_at = next.updated_at ?? "2026-04-15T12:00:00Z";
        next.deleted_at = next.deleted_at ?? null;
        rows.push(next);
        return clone(next);
      });
      return this.formatResult(inserted);
    }

    const filteredRows = rows.filter((row) =>
      this.filters.every((filter) => filter(row))
    );

    if (this.mode === "update") {
      for (const row of filteredRows) {
        Object.assign(row, clone(this.updateData));
      }
      return this.selectAfterWrite
        ? this.formatResult(filteredRows.map(clone))
        : { data: null, error: null };
    }

    let result = filteredRows.map(clone);
    for (const order of [...this.orders].reverse()) {
      result.sort((left, right) => {
        const a = left[order.column] ?? null;
        const b = right[order.column] ?? null;
        if (a === b) return 0;
        if (a === null) return order.nullsFirst ? -1 : 1;
        if (b === null) return order.nullsFirst ? 1 : -1;
        const comparison = String(a).localeCompare(String(b));
        return order.ascending ? comparison : -comparison;
      });
    }
    if (this.limitCount !== null) {
      result = result.slice(0, this.limitCount);
    }

    if (this.head && this.countExact) {
      return { data: null, error: null, count: result.length };
    }

    return this.formatResult(result);
  }

  private formatResult(rows: Array<Record<string, unknown>>) {
    if (this.singleMode === "single") {
      if (rows.length !== 1) {
        return {
          data: null,
          error: { message: `Expected single row, got ${rows.length}` },
        };
      }
      return { data: rows[0], error: null };
    }

    if (this.singleMode === "maybeSingle") {
      if (rows.length > 1) {
        return {
          data: null,
          error: { message: `Expected at most one row, got ${rows.length}` },
        };
      }
      return { data: rows[0] ?? null, error: null };
    }

    return { data: rows, error: null };
  }
}

function createMockClient(db: MockDb, userId: string) {
  let idCounter = 100;

  const resolveShortId = (
    table: TableName,
    shortOrFullId: string,
  ): string | null => {
    const rows = db[table].filter((row) =>
      row.user_id === userId && (row.deleted_at ?? null) === null
    );
    const fullMatch = rows.find((row) => row.id === shortOrFullId);
    if (fullMatch) return String(fullMatch.id);
    if (!/^[a-f0-9]{4,8}$/i.test(shortOrFullId)) return null;
    const matches = rows
      .filter((row) => String(row.id).startsWith(shortOrFullId.toLowerCase()))
      .slice(0, 2);
    return matches.length === 1 ? String(matches[0].id) : null;
  };

  return {
    from(table: string) {
      return new MockQueryBuilder(
        db,
        table as TableName,
        () => makeUuid(idCounter++),
      );
    },
    async rpc(name: string, args: { p_short_or_full_id?: string }) {
      switch (name) {
        case "resolve_user_event_id":
          return {
            data: resolveShortId("events", args.p_short_or_full_id ?? ""),
            error: null,
          };
        case "resolve_user_shift_id":
          return {
            data: resolveShortId("user_shifts", args.p_short_or_full_id ?? ""),
            error: null,
          };
        case "resolve_recurring_shift_id":
          return {
            data: resolveShortId(
              "recurring_shifts",
              args.p_short_or_full_id ?? "",
            ),
            error: null,
          };
        case "resolve_wage_snapshot_id":
          return {
            data: resolveShortId(
              "wage_snapshots",
              args.p_short_or_full_id ?? "",
            ),
            error: null,
          };
        case "resolve_payroll_adjustment_id":
          return {
            data: resolveShortId(
              "payroll_adjustments",
              args.p_short_or_full_id ?? "",
            ),
            error: null,
          };
        case "get_tariff_version_for_date": {
          const targetDate = (args as { p_target_date?: string })
            .p_target_date ?? "";
          return {
            data: [{
              rates: targetDate >= "2026-05-01" ? { "3": 195.25 } : {
                "3": 187.46,
              },
            }],
            error: null,
          };
        }
        case "get_tariff_versions":
          return { data: [{ rates: { "3": 195.25 } }], error: null };
        default:
          throw new Error(`Unexpected rpc: ${name}`);
      }
    },
  };
}

function createContext(dbOverrides: Partial<MockDb> = {}): WageyRequestContext {
  const db: MockDb = {
    events: [],
    user_shifts: [],
    user_settings: [{
      user_id: USER_ID,
      currency: "NOK",
      payroll_day: 15,
      half_tax_month: null,
    }],
    jobs: [],
    wage_snapshots: [],
    recurring_shifts: [],
    payroll_adjustments: [],
    ...dbOverrides,
  };

  const client = createMockClient(db, USER_ID);
  return {
    user: { id: USER_ID } as WageyRequestContext["user"],
    cache: new Map(),
    supabase: client as unknown as WageyRequestContext["supabase"],
    supabaseAdmin: client as unknown as WageyRequestContext["supabaseAdmin"],
  };
}

function currentWeekRange(): { startDate: string; endDate: string } {
  const now = new Date();
  const day = now.getUTCDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const start = new Date(
    Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() + diffToMonday,
    ),
  );
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 6);
  return {
    startDate: start.toISOString().slice(0, 10),
    endDate: end.toISOString().slice(0, 10),
  };
}

Deno.test("manage_wage_snapshots create copies current default workplace snapshot", async () => {
  const jobId = "11111111-2222-4333-8444-555555555555";
  const db: Partial<MockDb> = {
    jobs: [{
      id: jobId,
      user_id: USER_ID,
      name: "Extra",
      is_default: true,
      sort_order: 0,
      archived_at: null,
      deleted_at: null,
    }],
    wage_snapshots: [
      {
        id: "baseline",
        user_id: USER_ID,
        job_id: jobId,
        from_date: null,
        hourly_wage: 184.54,
        wage_level: 1,
        tariff_type_id: "hk_retail",
        supplements: {
          rules: [{
            days: [1, 2, 3, 4, 5],
            from: "18:00",
            to: "21:00",
            rate: 22,
          }],
        },
        tax_enabled: true,
        tax_percentage: 5,
        break_enabled: true,
        break_method: "proportional",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      },
      {
        id: "current",
        user_id: USER_ID,
        job_id: jobId,
        from_date: "2026-04-01",
        hourly_wage: 187.46,
        wage_level: 3,
        tariff_type_id: "hk_retail",
        supplements: {
          rules: [{ days: [6], from: "18:00", to: "24:00", rate: 110 }],
        },
        tax_enabled: false,
        tax_percentage: 7,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      },
    ],
  };
  const ctx = createContext(db);

  const result = await executeTool(
    ctx,
    "manage_wage_snapshots",
    JSON.stringify({
      action: "create",
      from_date: "2026-06-01",
      tax_enabled: true,
      tax_percentage: 5,
    }),
  );

  assert(result.success);
  const created = db.wage_snapshots?.find((snapshot) =>
    snapshot.from_date === "2026-06-01"
  );
  assertEquals(created?.job_id, jobId);
  assertEquals(created?.hourly_wage, 187.46);
  assertEquals(created?.wage_level, 3);
  assertEquals(created?.tariff_type_id, "hk_retail");
  assertEquals(created?.supplements, {
    rules: [{ days: [6], from: "18:00", to: "24:00", rate: 110 }],
  });
  assertEquals(created?.tax_enabled, true);
  assertEquals(created?.tax_percentage, 5);
  assertEquals(created?.break_enabled, false);
  assertEquals(created?.break_method, "none");
});

Deno.test("manage_wage_snapshots update hourly_wage switches to custom", async () => {
  const db: Partial<MockDb> = {
    wage_snapshots: [{
      id: "aaaaa000-0000-0000-0000-000000000001",
      user_id: USER_ID,
      job_id: null,
      from_date: "2026-04-01",
      hourly_wage: 187.46,
      wage_level: 3,
      tariff_type_id: "hk_retail",
      supplements: { rules: [] },
      tax_enabled: false,
      tax_percentage: 7,
      break_enabled: false,
      break_method: "none",
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      deleted_at: null,
    }],
  };
  const ctx = createContext(db);

  const result = await executeTool(
    ctx,
    "manage_wage_snapshots",
    JSON.stringify({
      action: "update",
      snapshot_id: "aaaaa",
      hourly_wage: 210,
    }),
  );

  assert(result.success);
  assertEquals(db.wage_snapshots?.[0].hourly_wage, 210);
  assertEquals(db.wage_snapshots?.[0].wage_level, null);
  assertEquals(db.wage_snapshots?.[0].tariff_type_id, null);
});

Deno.test("manage_wage_snapshots update date recalculates tariff wage", async () => {
  const db: Partial<MockDb> = {
    wage_snapshots: [{
      id: "aaaaa000-0000-0000-0000-000000000001",
      user_id: USER_ID,
      job_id: null,
      from_date: "2026-04-01",
      hourly_wage: 187.46,
      wage_level: 3,
      tariff_type_id: "hk_retail",
      supplements: { rules: [] },
      tax_enabled: false,
      tax_percentage: 7,
      break_enabled: false,
      break_method: "none",
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      deleted_at: null,
    }],
  };
  const ctx = createContext(db);

  const result = await executeTool(
    ctx,
    "manage_wage_snapshots",
    JSON.stringify({
      action: "update",
      snapshot_id: "aaaaa",
      from_date: "2026-06-01",
    }),
  );

  assert(result.success);
  assertEquals(db.wage_snapshots?.[0].from_date, "2026-06-01");
  assertEquals(db.wage_snapshots?.[0].hourly_wage, 195.25);
  assertEquals(db.wage_snapshots?.[0].wage_level, 3);
  assertEquals(db.wage_snapshots?.[0].tariff_type_id, "hk_retail");
});

Deno.test("query_shifts ignores null and placeholder optional filters", async () => {
  const ctx = createContext({
    user_shifts: [{
      id: "11111111-2222-3333-4444-555555555555",
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-04-16",
      start_time: "12:00",
      end_time: "18:00",
      custom_supplements: null,
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "query_shifts",
    JSON.stringify({
      startDate: "2026-04-01",
      endDate: "2026-04-30",
      minTime: null,
      maxTime: "none",
      jobId: "all",
      limit: 10,
    }),
  );

  assert(result.success, result.message);
  const rows = result.data as Array<Record<string, unknown>>;
  assertEquals(rows.length, 1);
  assertEquals(rows[0].date, "2026-04-16");
});

Deno.test("manage_account routes profile and settings actions", async () => {
  const ctx = createContext();

  const profileResult = await executeTool(
    ctx,
    "manage_account",
    JSON.stringify({ action: "view_profile" }),
  );
  assertEquals(profileResult.success, true);
  assertEquals((profileResult.data as { id: string }).id, USER_ID);

  const settingsResult = await executeTool(
    ctx,
    "manage_account",
    JSON.stringify({ action: "view_settings" }),
  );
  assertEquals(settingsResult.success, true);
  assertEquals(
    (settingsResult.data as { goals: { payrollDay: number } }).goals
      .payrollDay,
    15,
  );
});

Deno.test("manage_payroll_adjustment rejects create without essentials", async () => {
  const result = await executeTool(
    createContext(),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: null,
      currency: null,
      category: null,
      taxTreatment: null,
      description: null,
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assertEquals(result.success, false);
  assertEquals(result.action, "create");
  assertEquals(result.missingRequiredFields, [
    "amount",
    "description",
    "payoutDate",
  ]);
});

Deno.test("manage_payroll_adjustment requires tax treatment when payout has tax", async () => {
  const result = await executeTool(
    createContext({
      user_shifts: [{
        id: "11111111-2222-3333-4444-555555555555",
        user_id: USER_ID,
        job_id: null,
        shift_date: "2026-05-20",
        start_time: "09:00",
        end_time: "17:00",
        custom_supplements: null,
        deleted_at: null,
      }],
      wage_snapshots: [{
        id: "99999999-9999-4999-8999-999999999999",
        user_id: USER_ID,
        job_id: null,
        from_date: null,
        hourly_wage: 200,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: true,
        tax_percentage: 35,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      }],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: "2026-06-15",
      payoutMonth: null,
      jobId: null,
      amount: 2000,
      currency: null,
      category: "bonus",
      taxTreatment: null,
      description: "Bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assertEquals(result.success, false);
  assertEquals(result.missingRequiredFields, ["taxTreatment"]);
});

Deno.test("manage_payroll_adjustment defaults to net manual when payout has no taxed payroll", async () => {
  const result = await executeTool(
    createContext({
      wage_snapshots: [{
        id: "99999999-9999-4999-8999-999999999999",
        user_id: USER_ID,
        job_id: null,
        from_date: null,
        hourly_wage: 200,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: true,
        tax_percentage: 35,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      }],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-06",
      jobId: null,
      amount: 2000,
      currency: null,
      category: "bonus",
      taxTreatment: null,
      description: "Bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.taxTreatment, "net_manual");
  assertEquals(data.adjustment.payoutDate, "2026-06-15");
});

Deno.test("manage_payroll_adjustment ignores older taxed snapshots when latest earning snapshot has no tax", async () => {
  const defaultJobId = "11111111-2222-4333-8444-555555555555";
  const result = await executeTool(
    createContext({
      jobs: [{
        id: defaultJobId,
        user_id: USER_ID,
        name: "Kafe",
        color: "#112233",
        payroll_day: 10,
        half_tax_month: 12,
        monthly_goal: null,
        sort_order: 0,
        is_default: true,
        archived_at: null,
        deleted_at: null,
      }],
      user_shifts: [{
        id: "11111111-2222-3333-4444-555555555555",
        user_id: USER_ID,
        job_id: defaultJobId,
        shift_date: "2026-05-08",
        start_time: "16:00",
        end_time: "23:15",
        custom_supplements: null,
        deleted_at: null,
      }],
      wage_snapshots: [
        {
          id: "99999999-9999-4999-8999-999999999999",
          user_id: USER_ID,
          job_id: defaultJobId,
          from_date: null,
          hourly_wage: 200,
          wage_level: null,
          tariff_type_id: null,
          supplements: { rules: [] },
          tax_enabled: true,
          tax_percentage: 35,
          break_enabled: false,
          break_method: "none",
          break_threshold_hours: 5.5,
          break_deduction_minutes: 30,
          deleted_at: null,
        },
        {
          id: "88888888-8888-4888-8888-888888888888",
          user_id: USER_ID,
          job_id: defaultJobId,
          from_date: "2026-04-01",
          hourly_wage: 200,
          wage_level: null,
          tariff_type_id: null,
          supplements: { rules: [] },
          tax_enabled: false,
          tax_percentage: 35,
          break_enabled: false,
          break_method: "none",
          break_threshold_hours: 5.5,
          break_deduction_minutes: 30,
          deleted_at: null,
        },
      ],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-06",
      jobId: null,
      amount: 2000,
      currency: null,
      category: "bonus",
      taxTreatment: null,
      description: "Bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.taxTreatment, "net_manual");
});

Deno.test("manage_payroll_adjustment defaults to net manual when payout has no tax", async () => {
  const result = await executeTool(
    createContext({
      wage_snapshots: [{
        id: "99999999-9999-4999-8999-999999999999",
        user_id: USER_ID,
        job_id: null,
        from_date: null,
        hourly_wage: 200,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: false,
        tax_percentage: 0,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      }],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-06",
      jobId: null,
      amount: 2000,
      currency: null,
      category: "bonus",
      taxTreatment: null,
      description: "Bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.taxTreatment, "net_manual");
  assertEquals(data.adjustment.payoutDate, "2026-06-15");
});

Deno.test("manage_payroll_adjustment uses default job tax settings for unscoped create", async () => {
  const defaultJobId = "11111111-2222-4333-8444-555555555555";
  const result = await executeTool(
    createContext({
      jobs: [{
        id: defaultJobId,
        user_id: USER_ID,
        name: "Kafe",
        color: "#112233",
        payroll_day: 20,
        half_tax_month: null,
        monthly_goal: null,
        sort_order: 0,
        is_default: true,
        archived_at: null,
        deleted_at: null,
      }],
      wage_snapshots: [
        {
          id: "99999999-9999-4999-8999-999999999999",
          user_id: USER_ID,
          job_id: null,
          from_date: null,
          hourly_wage: 200,
          wage_level: null,
          tariff_type_id: null,
          supplements: { rules: [] },
          tax_enabled: true,
          tax_percentage: 35,
          break_enabled: false,
          break_method: "none",
          break_threshold_hours: 5.5,
          break_deduction_minutes: 30,
          deleted_at: null,
        },
        {
          id: "88888888-8888-4888-8888-888888888888",
          user_id: USER_ID,
          job_id: defaultJobId,
          from_date: null,
          hourly_wage: 200,
          wage_level: null,
          tariff_type_id: null,
          supplements: { rules: [] },
          tax_enabled: false,
          tax_percentage: 0,
          break_enabled: false,
          break_method: "none",
          break_threshold_hours: 5.5,
          break_deduction_minutes: 30,
          deleted_at: null,
        },
      ],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-06",
      jobId: null,
      amount: 2000,
      currency: null,
      category: "bonus",
      taxTreatment: null,
      description: "Bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.taxTreatment, "net_manual");
  assertEquals(data.adjustment.payoutDate, "2026-06-15");
});

Deno.test("manage_payroll_adjustment creates with derived payout date", async () => {
  const jobId = "11111111-2222-4333-8444-555555555555";
  const db: Partial<MockDb> = {
    jobs: [{
      id: jobId,
      user_id: USER_ID,
      name: "Kafe",
      color: "#112233",
      payroll_day: 31,
      half_tax_month: null,
      monthly_goal: null,
      sort_order: 0,
      is_default: true,
      archived_at: null,
      deleted_at: null,
    }],
  };

  const result = await executeTool(
    createContext(db),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-02",
      jobId,
      amount: 1200,
      currency: null,
      category: "retro_pay",
      taxTreatment: "gross_taxable",
      description: "Retro pay April",
      note: "Back pay",
      earnedFromDate: "2026-04-01",
      earnedToDate: "2026-04-30",
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.payoutDate, "2026-02-28");
  assertEquals(data.adjustment.currency, "NOK");
  assertEquals(data.adjustment.taxTreatment, "gross_taxable");
});

Deno.test("manage_payroll_adjustment uses global payroll day without workplace", async () => {
  const result = await executeTool(
    createContext({
      jobs: [{
        id: "11111111-2222-4333-8444-555555555555",
        user_id: USER_ID,
        name: "Kafe",
        color: "#112233",
        payroll_day: 31,
        half_tax_month: null,
        monthly_goal: null,
        sort_order: 0,
        is_default: true,
        archived_at: null,
        deleted_at: null,
      }],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "create",
      adjustmentId: null,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: "2026-02",
      jobId: null,
      amount: 500,
      currency: null,
      category: "correction",
      taxTreatment: "net_manual",
      description: "General correction",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as { adjustment: Record<string, unknown> };
  assertEquals(data.adjustment.jobId, null);
  assertEquals(data.adjustment.payoutDate, "2026-02-15");
});

Deno.test("manage_payroll_adjustment lists payout range and excludes deleted", async () => {
  const ctx = createContext({
    payroll_adjustments: [
      {
        id: "11111111-1111-4111-8111-111111111111",
        user_id: USER_ID,
        job_id: null,
        amount: 500,
        currency: "NOK",
        category: "bonus",
        tax_treatment: "gross_taxable",
        description: "Bonus",
        note: null,
        earned_from_date: null,
        earned_to_date: null,
        payout_date: "2026-05-15",
        created_at: "2026-05-01T10:00:00Z",
        updated_at: "2026-05-01T10:00:00Z",
        deleted_at: null,
      },
      {
        id: "22222222-2222-4222-8222-222222222222",
        user_id: USER_ID,
        job_id: null,
        amount: 200,
        currency: "NOK",
        category: "correction",
        tax_treatment: "net_manual",
        description: "Old correction",
        note: null,
        earned_from_date: null,
        earned_to_date: null,
        payout_date: "2026-05-20",
        deleted_at: "2026-05-02T10:00:00Z",
      },
      {
        id: "33333333-3333-4333-8333-333333333333",
        user_id: USER_ID,
        job_id: null,
        amount: 300,
        currency: "NOK",
        category: "correction",
        tax_treatment: "net_manual",
        description: "June correction",
        note: null,
        earned_from_date: null,
        earned_to_date: null,
        payout_date: "2026-06-15",
        deleted_at: null,
      },
    ],
  });

  const result = await executeTool(
    ctx,
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "list",
      adjustmentId: null,
      payoutStart: "2026-05-01",
      payoutEnd: "2026-05-31",
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: null,
      currency: null,
      category: null,
      taxTreatment: null,
      description: null,
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: 10,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as {
    adjustments: Array<Record<string, unknown>>;
    count: number;
  };
  assertEquals(data.count, 1);
  assertEquals(data.adjustments[0].description, "Bonus");
});

Deno.test("manage_payroll_adjustment updates by short ID", async () => {
  const adjustmentId = "abcdef12-1111-4111-8111-111111111111";
  const db: Partial<MockDb> = {
    payroll_adjustments: [{
      id: adjustmentId,
      user_id: USER_ID,
      job_id: null,
      amount: 500,
      currency: "NOK",
      category: "bonus",
      tax_treatment: "gross_taxable",
      description: "Bonus",
      note: null,
      earned_from_date: null,
      earned_to_date: null,
      payout_date: "2026-05-15",
      deleted_at: null,
    }],
  };

  const result = await executeTool(
    createContext(db),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "update",
      adjustmentId: "abcdef",
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: 750,
      currency: null,
      category: null,
      taxTreatment: null,
      description: "Updated bonus",
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  assertEquals(db.payroll_adjustments?.[0].amount, 750);
  assertEquals(db.payroll_adjustments?.[0].description, "Updated bonus");
});

Deno.test("manage_payroll_adjustment clears nullable fields explicitly", async () => {
  const adjustmentId = "abcdef12-1111-4111-8111-111111111111";
  const jobId = "11111111-2222-4333-8444-555555555555";
  const db: Partial<MockDb> = {
    payroll_adjustments: [{
      id: adjustmentId,
      user_id: USER_ID,
      job_id: jobId,
      amount: 500,
      currency: "NOK",
      category: "bonus",
      tax_treatment: "gross_taxable",
      description: "Bonus",
      note: "Temporary note",
      earned_from_date: "2026-04-01",
      earned_to_date: "2026-04-30",
      payout_date: "2026-05-15",
      deleted_at: null,
    }],
  };

  const result = await executeTool(
    createContext(db),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "update",
      adjustmentId,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: null,
      currency: null,
      category: null,
      taxTreatment: null,
      description: null,
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: ["jobId", "note", "earnedFromDate", "earnedToDate"],
      limit: null,
    }),
  );

  assert(result.success, result.message);
  assertEquals(db.payroll_adjustments?.[0].job_id, null);
  assertEquals(db.payroll_adjustments?.[0].note, null);
  assertEquals(db.payroll_adjustments?.[0].earned_from_date, null);
  assertEquals(db.payroll_adjustments?.[0].earned_to_date, null);
});

Deno.test("manage_payroll_adjustment rejects ambiguous delete reference", async () => {
  const result = await executeTool(
    createContext({
      payroll_adjustments: [
        {
          id: "aaaaaaaa-1111-4111-8111-111111111111",
          user_id: USER_ID,
          job_id: null,
          amount: 100,
          currency: "NOK",
          category: "other",
          tax_treatment: "net_manual",
          description: "First",
          note: null,
          earned_from_date: null,
          earned_to_date: null,
          payout_date: "2026-05-15",
          deleted_at: null,
        },
        {
          id: "aaaaaaaa-2222-4222-8222-222222222222",
          user_id: USER_ID,
          job_id: null,
          amount: 200,
          currency: "NOK",
          category: "other",
          tax_treatment: "net_manual",
          description: "Second",
          note: null,
          earned_from_date: null,
          earned_to_date: null,
          payout_date: "2026-05-15",
          deleted_at: null,
        },
      ],
    }),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "delete",
      adjustmentId: "aaaa",
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: null,
      currency: null,
      category: null,
      taxTreatment: null,
      description: null,
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assertEquals(result.success, false);
  assertEquals(result.validationErrors?.[0].field, "adjustmentId");
  assertEquals(result.validationErrors?.[0].message, "not found or ambiguous");
});

Deno.test("manage_payroll_adjustment deletes by full ID", async () => {
  const adjustmentId = "abcdef12-1111-4111-8111-111111111111";
  const db: Partial<MockDb> = {
    payroll_adjustments: [{
      id: adjustmentId,
      user_id: USER_ID,
      job_id: null,
      amount: 500,
      currency: "NOK",
      category: "bonus",
      tax_treatment: "gross_taxable",
      description: "Bonus",
      note: null,
      earned_from_date: null,
      earned_to_date: null,
      payout_date: "2026-05-15",
      deleted_at: null,
    }],
  };

  const result = await executeTool(
    createContext(db),
    "manage_payroll_adjustment",
    JSON.stringify({
      action: "delete",
      adjustmentId,
      payoutStart: null,
      payoutEnd: null,
      payoutDate: null,
      payoutMonth: null,
      jobId: null,
      amount: null,
      currency: null,
      category: null,
      taxTreatment: null,
      description: null,
      note: null,
      earnedFromDate: null,
      earnedToDate: null,
      clearFields: null,
      limit: null,
    }),
  );

  assert(result.success, result.message);
  assert(typeof db.payroll_adjustments?.[0].deleted_at === "string");
});

Deno.test("get_statistics shift_gaps returns longest gaps between shifts", async () => {
  const ctx = createContext({
    user_shifts: [
      {
        id: "11111111-2222-3333-4444-555555555555",
        user_id: USER_ID,
        job_id: null,
        shift_date: "2026-01-01",
        start_time: "08:00",
        end_time: "16:00",
        custom_supplements: null,
        deleted_at: null,
      },
      {
        id: "22222222-3333-4444-5555-666666666666",
        user_id: USER_ID,
        job_id: null,
        shift_date: "2026-01-05",
        start_time: "08:00",
        end_time: "16:00",
        custom_supplements: null,
        deleted_at: null,
      },
      {
        id: "33333333-4444-5555-6666-777777777777",
        user_id: USER_ID,
        job_id: null,
        shift_date: "2026-01-06",
        start_time: "08:00",
        end_time: "16:00",
        custom_supplements: null,
        deleted_at: null,
      },
    ],
  });

  const result = await executeTool(
    ctx,
    "get_statistics",
    JSON.stringify({
      metric: "shift_gaps",
      startDate: "2026-01-01",
      endDate: "2026-01-31",
      limit: 2,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as {
    shiftCount: number;
    gapCount: number;
    longestGap: { gapHours: number; gapDays: number };
    gaps: Array<{ rank: number; gapHours: number }>;
  };
  assertEquals(data.shiftCount, 3);
  assertEquals(data.gapCount, 2);
  assertEquals(data.longestGap.gapHours, 88);
  assertEquals(data.longestGap.gapDays, 3.67);
  assertEquals(data.gaps.length, 2);
  assertEquals(data.gaps[0].rank, 1);
});

Deno.test("get_statistics shift_gaps formats virtual shift IDs and rounded gaps", async () => {
  const recurringId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
  const ctx = createContext({
    recurring_shifts: [{
      id: recurringId,
      user_id: USER_ID,
      job_id: null,
      start_time: "16:00",
      end_time: "23:15",
      repeat_interval_weeks: 1,
      selected_days: { "3": "2026-04-22" },
      end_condition: { type: "months", value: 1 },
      exclusions: [],
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "get_statistics",
    JSON.stringify({
      metric: "shift_gaps",
      startDate: "2026-04-01",
      endDate: "2026-05-16",
      limit: 1,
    }),
  );

  assert(result.success, result.message);
  const data = result.data as {
    longestGap: {
      gapHours: number;
      gapDays: number;
      previousShift: { id: string };
      nextShift: { id: string };
    };
  };
  assertEquals(data.longestGap.gapHours, 328.75);
  assertEquals(data.longestGap.gapDays, 13.7);
  assertEquals(data.longestGap.previousShift.id, "virtual-aaaaa-2026-04-22");
  assertEquals(data.longestGap.nextShift.id, "virtual-aaaaa-2026-05-06");
});

Deno.test("manage_workplace preserves explicit null clears", async () => {
  const jobId = "11111111-2222-4333-8444-555555555555";
  const db: Partial<MockDb> = {
    jobs: [{
      id: jobId,
      user_id: USER_ID,
      name: "Kafe",
      color: "#112233",
      payroll_day: 15,
      half_tax_month: 12,
      monthly_goal: 12000,
      sort_order: 0,
      is_default: true,
      archived_at: null,
      deleted_at: null,
    }],
  };
  const ctx = createContext(db);

  const result = await executeTool(
    ctx,
    "manage_workplace",
    JSON.stringify({
      action: "update",
      jobId,
      color: null,
      halfTaxMonth: null,
      monthlyGoal: null,
    }),
  );

  assert(result.success, result.message);
  const [job] = db.jobs!;
  assertEquals(job.color, null);
  assertEquals(job.half_tax_month, null);
  assertEquals(job.monthly_goal, null);
});

Deno.test("manage_event creates a timed event", async () => {
  const ctx = createContext();

  const result = await executeTool(
    ctx,
    "manage_event",
    JSON.stringify({
      action: "create",
      note: "Doctor appointment",
      startDate: "2026-04-18",
      endDate: "2026-04-18",
      isAllDay: false,
      startTime: "14:00",
      endTime: "15:00",
    }),
  );

  assert(result.success);
  assertEquals(
    (result.data as Record<string, unknown>).note,
    "Doctor appointment",
  );
  assertEquals((result.data as Record<string, unknown>).startTime, "14:00");
  assertEquals((result.data as Record<string, unknown>).endTime, "15:00");
});

Deno.test("manage_event creates a multi-day all-day event and updates reminders by short ID", async () => {
  const eventId = "aaaaaaaa-1111-1111-1111-111111111111";
  const ctx = createContext({
    events: [{
      id: eventId,
      user_id: USER_ID,
      start_date: "2026-04-17",
      end_date: "2026-04-19",
      is_all_day: true,
      start_time: null,
      end_time: null,
      note: "Trip",
      notification_minutes_array: null,
      notification_anchor_time: null,
      deleted_at: null,
    }],
  });

  const updateResult = await executeTool(
    ctx,
    "manage_event",
    JSON.stringify({
      action: "update",
      eventId: "aaaaaaaa",
      notificationMinutesArray: [15, 60, 15],
      notificationAnchorTime: "09:00",
    }),
  );

  assert(updateResult.success);
  assertEquals((updateResult.data as Record<string, unknown>).reminderMinutes, [
    60,
    15,
  ]);
  assertEquals(
    (updateResult.data as Record<string, unknown>).reminderAnchorTime,
    "09:00",
  );
});

Deno.test("manage_event rejects invalid timed multi-day payloads", async () => {
  const ctx = createContext();

  const result = await executeTool(
    ctx,
    "manage_event",
    JSON.stringify({
      action: "create",
      note: "Invalid",
      startDate: "2026-04-18",
      endDate: "2026-04-19",
      isAllDay: false,
      startTime: "14:00",
      endTime: "15:00",
    }),
  );

  assertEquals(result.success, false);
  assert(String(result.message).includes("same date"));
});

Deno.test("manage_event deletes by short ID", async () => {
  const eventId = "bbbbbbbb-1111-1111-1111-111111111111";
  const db = {
    events: [{
      id: eventId,
      user_id: USER_ID,
      start_date: "2026-04-18",
      end_date: "2026-04-18",
      is_all_day: false,
      start_time: "14:00",
      end_time: "15:00",
      note: "Lunch",
      notification_minutes_array: null,
      notification_anchor_time: null,
      deleted_at: null,
    }],
  };
  const ctx = createContext(db);

  const result = await executeTool(
    ctx,
    "manage_event",
    JSON.stringify({
      action: "delete",
      eventId: "bbbb",
    }),
  );

  assert(result.success);
  assert((db.events[0].deleted_at as string | null) !== null);
});

Deno.test("query_events applies default week filtering, kind filtering, sorting, and reminder formatting", async () => {
  const week = currentWeekRange();
  const outsideWeek = week.endDate < "2026-12-31" ? "2026-12-31" : "2025-01-01";
  const ctx = createContext({
    events: [
      {
        id: "cccccccc-1111-1111-1111-111111111111",
        user_id: USER_ID,
        start_date: week.startDate,
        end_date: week.startDate,
        is_all_day: false,
        start_time: "18:00",
        end_time: "19:00",
        note: "Evening",
        notification_minutes_array: [30, 5, 30],
        notification_anchor_time: null,
        deleted_at: null,
      },
      {
        id: "dddddddd-1111-1111-1111-111111111111",
        user_id: USER_ID,
        start_date: week.startDate,
        end_date: week.endDate,
        is_all_day: true,
        start_time: null,
        end_time: null,
        note: "Festival",
        notification_minutes_array: [120],
        notification_anchor_time: "09:00",
        deleted_at: null,
      },
      {
        id: "eeeeeeee-1111-1111-1111-111111111111",
        user_id: USER_ID,
        start_date: outsideWeek,
        end_date: outsideWeek,
        is_all_day: false,
        start_time: "10:00",
        end_time: "11:00",
        note: "Outside week",
        notification_minutes_array: null,
        notification_anchor_time: null,
        deleted_at: null,
      },
    ],
  });

  const defaultResult = await executeTool(
    ctx,
    "query_events",
    JSON.stringify({}),
  );
  assert(defaultResult.success);
  const defaultRows = defaultResult.data as Array<Record<string, unknown>>;
  assertEquals(defaultRows.length, 2);

  const specificResult = await executeTool(
    ctx,
    "query_events",
    JSON.stringify({
      startDate: week.startDate,
      endDate: week.endDate,
      kind: "timed",
      sortBy: "start_latest",
    }),
  );
  const timedRows = specificResult.data as Array<Record<string, unknown>>;
  assertEquals(timedRows.length, 1);
  assertEquals(timedRows[0].note, "Evening");
  assertEquals(timedRows[0].reminderMinutes, [30, 5]);
});

Deno.test("query_events preserves one-sided date filters instead of clamping to current week", async () => {
  const week = currentWeekRange();
  const futureDate = week.endDate < "2026-12-31" ? "2026-12-31" : "2027-01-01";
  const pastDate = week.startDate > "2026-01-01" ? "2026-01-01" : "2025-01-01";
  const ctx = createContext({
    events: [
      {
        id: "abababab-1111-1111-1111-111111111111",
        user_id: USER_ID,
        start_date: pastDate,
        end_date: pastDate,
        is_all_day: false,
        start_time: "08:00",
        end_time: "09:00",
        note: "Past event",
        notification_minutes_array: null,
        notification_anchor_time: null,
        deleted_at: null,
      },
      {
        id: "cdcdcdcd-1111-1111-1111-111111111111",
        user_id: USER_ID,
        start_date: futureDate,
        end_date: futureDate,
        is_all_day: false,
        start_time: "10:00",
        end_time: "11:00",
        note: "Future event",
        notification_minutes_array: null,
        notification_anchor_time: null,
        deleted_at: null,
      },
    ],
  });

  const futureOnlyResult = await executeTool(
    ctx,
    "query_events",
    JSON.stringify({ startDate: futureDate }),
  );
  assert(futureOnlyResult.success);
  assertEquals(
    (futureOnlyResult.data as Array<Record<string, unknown>>).map((event) =>
      event.note
    ),
    ["Future event"],
  );

  const pastOnlyResult = await executeTool(
    ctx,
    "query_events",
    JSON.stringify({ endDate: pastDate }),
  );
  assert(pastOnlyResult.success);
  assertEquals(
    (pastOnlyResult.data as Array<Record<string, unknown>>).map((event) =>
      event.note
    ),
    ["Past event"],
  );
});

Deno.test("plan_schedule agenda merges events and shifts chronologically", async () => {
  const ctx = createContext({
    events: [{
      id: "ffffffff-1111-1111-1111-111111111111",
      user_id: USER_ID,
      start_date: "2026-04-16",
      end_date: "2026-04-16",
      is_all_day: false,
      start_time: "09:00",
      end_time: "10:00",
      note: "Standup",
      notification_minutes_array: null,
      notification_anchor_time: null,
      deleted_at: null,
    }],
    user_shifts: [{
      id: "11111111-2222-3333-4444-555555555555",
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-04-16",
      start_time: "12:00",
      end_time: "18:00",
      custom_supplements: null,
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "plan_schedule",
    JSON.stringify({
      action: "agenda",
      startDate: "2026-04-16",
      endDate: "2026-04-16",
    }),
  );

  assert(result.success);
  const items =
    (result.data as { items: Array<Record<string, unknown>> }).items;
  assertEquals(items.map((item) => item.type), ["event", "shift"]);
});

Deno.test("plan_schedule conflicts detects overlaps against events and shifts", async () => {
  const ctx = createContext({
    events: [{
      id: "12121212-2222-3333-4444-555555555555",
      user_id: USER_ID,
      start_date: "2026-04-18",
      end_date: "2026-04-18",
      is_all_day: false,
      start_time: "14:00",
      end_time: "15:00",
      note: "Doctor",
      notification_minutes_array: null,
      notification_anchor_time: null,
      deleted_at: null,
    }],
    user_shifts: [{
      id: "34343434-2222-3333-4444-555555555555",
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-04-18",
      start_time: "15:00",
      end_time: "22:00",
      custom_supplements: null,
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "plan_schedule",
    JSON.stringify({
      action: "conflicts",
      startDate: "2026-04-18",
      endDate: "2026-04-18",
      isAllDay: false,
      startTime: "14:30",
      endTime: "16:00",
    }),
  );

  assert(result.success);
  const conflicts =
    (result.data as { conflicts: Array<Record<string, unknown>> }).conflicts;
  assertEquals(conflicts.length, 2);
  assertEquals(conflicts.map((item) => item.type), ["event", "shift"]);
});

Deno.test("plan_schedule checks conflicts against shifts beyond the first 1000 loaded rows", async () => {
  const totalShifts = 1001;
  const firstDate = "2024-01-01";
  const userShifts = Array.from({ length: totalShifts }, (_, index) => {
    const date = new Date(`${firstDate}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + index);
    const shiftDate = date.toISOString().slice(0, 10);

    return {
      id: `${String(index + 1).padStart(8, "0")}-2222-3333-4444-555555555555`,
      user_id: USER_ID,
      job_id: null,
      shift_date: shiftDate,
      start_time: "09:00",
      end_time: "17:00",
      custom_supplements: null,
      deleted_at: null,
    };
  });
  const lastDate = String(userShifts[userShifts.length - 1].shift_date);
  const ctx = createContext({ user_shifts: userShifts });

  const result = await executeTool(
    ctx,
    "plan_schedule",
    JSON.stringify({
      action: "conflicts",
      startDate: firstDate,
      endDate: lastDate,
      isAllDay: true,
    }),
  );

  assert(result.success);
  const conflicts =
    (result.data as { conflicts: Array<Record<string, unknown>> }).conflicts;
  assertEquals(conflicts.length, totalShifts);
  assertEquals(conflicts[0].date, firstDate);
});

Deno.test("plan_schedule free_slots finds gaps after subtracting events and shifts", async () => {
  const ctx = createContext({
    events: [{
      id: "56565656-2222-3333-4444-555555555555",
      user_id: USER_ID,
      start_date: "2026-04-19",
      end_date: "2026-04-19",
      is_all_day: false,
      start_time: "09:00",
      end_time: "10:00",
      note: "Breakfast",
      notification_minutes_array: null,
      notification_anchor_time: null,
      deleted_at: null,
    }],
    user_shifts: [{
      id: "78787878-2222-3333-4444-555555555555",
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-04-19",
      start_time: "13:00",
      end_time: "17:00",
      custom_supplements: null,
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "plan_schedule",
    JSON.stringify({
      action: "free_slots",
      startDate: "2026-04-19",
      endDate: "2026-04-19",
      durationMinutes: 90,
      windowStart: "08:00",
      windowEnd: "20:00",
    }),
  );

  assert(result.success);
  const slots =
    (result.data as { slots: Array<Record<string, unknown>> }).slots;
  assertEquals(slots, [
    {
      date: "2026-04-19",
      startTime: "10:00",
      endTime: "13:00",
      durationMinutes: 180,
    },
    {
      date: "2026-04-19",
      startTime: "17:00",
      endTime: "20:00",
      durationMinutes: 180,
    },
  ]);
});

Deno.test("manage_shift_advanced updates recurring custom pause windows without materializing a shift", async () => {
  const recurringId = makeUuid(1);
  const ctx = createContext({
    recurring_shifts: [{
      id: recurringId,
      user_id: USER_ID,
      start_time: "08:00",
      end_time: "16:00",
      repeat_interval_weeks: 0,
      selected_days: { "1": "2026-04-20" },
      end_condition: null,
      exclusions: [],
      date_specific_pause_windows: null,
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "manage_shift_advanced",
    JSON.stringify({
      action: "update_custom_pause_windows",
      shiftId: `virtual-${recurringId}-2026-04-20`,
      customPauseWindows: {
        windows: [{ start: "12:00", end: "12:30" }],
      },
    }),
  );

  assert(result.success);

  const recurring = (
    await ctx.supabase
      .from("recurring_shifts")
      .select("date_specific_pause_windows")
      .eq("id", recurringId)
      .single()
  ).data as { date_specific_pause_windows: Record<string, unknown> | null };

  assertEquals(recurring.date_specific_pause_windows, {
    "2026-04-20": {
      windows: [{ start: "12:00", end: "12:30" }],
    },
  });
});

Deno.test("manage_shift_advanced rejects invalid custom pause window payloads", async () => {
  const ctx = createContext();

  const result = await executeTool(
    ctx,
    "manage_shift_advanced",
    JSON.stringify({
      action: "update_custom_pause_windows",
      shiftId: "shift-1",
      customPauseWindows: {
        windows: [{ start: "12:00", end: "12:00" }],
      },
    }),
  );

  assertEquals(result.success, false);
  assert(
    String(result.message).includes(
      "Pause windows require different start and end times",
    ),
  );
});

Deno.test("calculate_wages includes adjustments in the following payout month", async () => {
  const ctx = createContext({
    user_settings: [{
      user_id: USER_ID,
      currency: "NOK",
      payroll_day: 10,
      half_tax_month: null,
    }],
    wage_snapshots: [{
      id: "99999999-9999-4999-8999-999999999999",
      user_id: USER_ID,
      job_id: null,
      from_date: null,
      hourly_wage: 100,
      wage_level: null,
      tariff_type_id: null,
      supplements: { rules: [] },
      tax_enabled: false,
      tax_percentage: 0,
      break_enabled: false,
      break_method: "none",
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      deleted_at: null,
    }],
    user_shifts: [{
      id: "11111111-2222-3333-4444-555555555555",
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-06-05",
      start_time: "10:00",
      end_time: "18:00",
      custom_supplements: null,
      deleted_at: null,
    }],
    payroll_adjustments: [
      {
        id: "22222222-2222-4222-8222-222222222222",
        user_id: USER_ID,
        job_id: null,
        amount: 2000,
        currency: "NOK",
        category: "bonus",
        tax_treatment: "net_manual",
        description: "Bonus",
        note: null,
        earned_from_date: null,
        earned_to_date: null,
        payout_date: "2026-07-10",
        created_at: "2026-05-16T12:00:00Z",
        updated_at: "2026-05-16T12:00:00Z",
        deleted_at: null,
      },
      {
        id: "33333333-3333-4333-8333-333333333333",
        user_id: USER_ID,
        job_id: null,
        amount: 500,
        currency: "NOK",
        category: "bonus",
        tax_treatment: "net_manual",
        description: "June payout bonus",
        note: null,
        earned_from_date: null,
        earned_to_date: null,
        payout_date: "2026-06-10",
        deleted_at: null,
      },
    ],
  });

  const result = await executeTool(
    ctx,
    "calculate_wages",
    JSON.stringify({
      startDate: "2026-06-01",
      endDate: "2026-06-30",
    }),
  );

  assert(result.success, result.message);
  const data = result.data as Record<string, unknown>;
  assertEquals(data.totalShifts, 1);
  assertEquals(data.shiftGross, 800);
  assertEquals(data.adjustmentCount, 1);
  assertEquals(data.adjustmentGross, 2000);
  assertEquals(data.totalGross, 2800);
  assertEquals(data.totalNet, 2800);
  assertEquals(data.payoutStart, "2026-07-10");
  assertEquals(data.payoutEnd, "2026-07-10");
  const adjustments = data.adjustments as Array<Record<string, unknown>>;
  assertEquals(adjustments[0].description, "Bonus");
});

Deno.test("calculate_wages returns payout adjustments even when no shifts exist", async () => {
  const ctx = createContext({
    user_settings: [{
      user_id: USER_ID,
      currency: "NOK",
      payroll_day: 10,
      half_tax_month: null,
    }],
    payroll_adjustments: [{
      id: "22222222-2222-4222-8222-222222222222",
      user_id: USER_ID,
      job_id: null,
      amount: 2000,
      currency: "NOK",
      category: "bonus",
      tax_treatment: "net_manual",
      description: "Bonus",
      note: null,
      earned_from_date: null,
      earned_to_date: null,
      payout_date: "2026-07-10",
      created_at: "2026-05-16T12:00:00Z",
      updated_at: "2026-05-16T12:00:00Z",
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "calculate_wages",
    JSON.stringify({
      startDate: "2026-06-01",
      endDate: "2026-06-30",
    }),
  );

  assert(result.success, result.message);
  const data = result.data as Record<string, unknown>;
  assertEquals(data.totalShifts, 0);
  assertEquals(data.adjustmentCount, 1);
  assertEquals(data.totalGross, 2000);
  assertEquals(data.totalNet, 2000);
});

Deno.test("calculate_earnings hypothetical_change preserves custom pause windows on the source shift", async () => {
  const shiftId = "cccccccc-1111-1111-1111-111111111111";
  const ctx = createContext({
    user_shifts: [{
      id: shiftId,
      user_id: USER_ID,
      job_id: null,
      shift_date: "2026-04-21",
      start_time: "08:00",
      end_time: "16:00",
      custom_pause_windows: {
        windows: [{ start: "12:00", end: "12:30" }],
      },
      deleted_at: null,
    }],
  });

  const result = await executeTool(
    ctx,
    "calculate_earnings",
    JSON.stringify({
      hypothetical_change: {
        shift_id: "cccccccc",
        changes: {},
      },
    }),
  );

  assert(result.success);

  const original =
    (result.data as { original: { breakdown: Record<string, unknown> } })
      .original;
  assertEquals(original.breakdown.break_deducted_minutes, 30);
  assertEquals(original.breakdown.break_source, "custom_pause_windows");
  assertEquals(original.breakdown.applied_pause_windows, [
    { start: "12:00", end: "12:30" },
  ]);
});

Deno.test("calculate_earnings uses default workplace scoped snapshots and payroll settings", async () => {
  const jobId = "11111111-2222-4333-8444-555555555555";
  const ctx = createContext({
    user_settings: [{
      user_id: USER_ID,
      currency: "NOK",
      payroll_day: 15,
      half_tax_month: null,
    }],
    jobs: [{
      id: jobId,
      user_id: USER_ID,
      name: "Cafe",
      is_default: true,
      sort_order: 0,
      payroll_day: 31,
      half_tax_month: 2,
      monthly_goal: null,
      archived_at: null,
      deleted_at: null,
    }],
    wage_snapshots: [
      {
        id: "legacy-baseline",
        user_id: USER_ID,
        job_id: null,
        from_date: null,
        hourly_wage: 300,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: false,
        tax_percentage: 0,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      },
      {
        id: "job-baseline",
        user_id: USER_ID,
        job_id: jobId,
        from_date: null,
        hourly_wage: 100,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: false,
        tax_percentage: 0,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      },
      {
        id: "job-payout-tax",
        user_id: USER_ID,
        job_id: jobId,
        from_date: "2026-02-20",
        hourly_wage: 100,
        wage_level: null,
        tariff_type_id: null,
        supplements: { rules: [] },
        tax_enabled: true,
        tax_percentage: 50,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        deleted_at: null,
      },
    ],
  });

  const result = await executeTool(
    ctx,
    "calculate_earnings",
    JSON.stringify({
      hypothetical: {
        date: "2026-01-31",
        start_time: "08:00",
        end_time: "18:00",
      },
    }),
  );

  assert(result.success);
  const scenario =
    (result.data as { scenarios: Array<Record<string, unknown>> }).scenarios[0];
  assertEquals(scenario.gross, 1000);
  assertEquals(scenario.net, 750);
});

Deno.test("web_fetch returns truncated public URL content", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      "<html><title>Tariff</title><body>Updated rates</body></html>",
      {
        status: 200,
        headers: { "Content-Type": "text/html" },
      },
    );

  try {
    const result = await executeTool(
      createContext(),
      "web_fetch",
      JSON.stringify({ url: "https://example.com/tariff" }),
    );

    assertEquals(result.success, true);
    const data = result.data as Record<string, unknown>;
    assertEquals(data.url, "https://example.com/tariff");
    assertEquals(data.title, "Tariff");
    assertEquals(data.truncated, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
