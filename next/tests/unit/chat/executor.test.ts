import { beforeEach, describe, expect, it, vi } from "vitest";
import { Effect, Layer } from "effect";

const mocks = vi.hoisted(() => ({
  getUserJobs: vi.fn(),
  updateJob: vi.fn(),
  createJob: vi.fn(),
  archiveJob: vi.fn(),
  deleteJob: vi.fn(),
  getAllFriends: vi.fn(),
  getSharedUserShifts: vi.fn(),
  getSharerShiftPreviews: vi.fn(),
  createShare: vi.fn(),
  removeShare: vi.fn(),
  toggleShareEarnings: vi.fn(),
  blockSharer: vi.fn(),
  unblockSharer: vi.fn(),
  shareBack: vi.fn(),
  toggleSharerMuted: vi.fn(),
  removeSharer: vi.fn(),
  updateProfileSettings: vi.fn(),
  verifySession: vi.fn(),
  getComputedShiftsForApi: vi.fn(),
  getStatsDataForApi: vi.fn(),
  getUserWageSnapshots: vi.fn(),
  getUserSettings: vi.fn(),
  getTariffTypes: vi.fn(),
}));

vi.mock("@/data-access/jobs", () => ({
  getUserJobs: mocks.getUserJobs,
  updateJob: mocks.updateJob,
  createJob: mocks.createJob,
  archiveJob: mocks.archiveJob,
  deleteJob: mocks.deleteJob,
}));

vi.mock("@/data-access/sharing", () => ({
  getAllFriends: mocks.getAllFriends,
  getSharedUserShifts: mocks.getSharedUserShifts,
  getSharerShiftPreviews: mocks.getSharerShiftPreviews,
}));

vi.mock("@/app/[locale]/(app)/sharing/_actions/sharing", () => ({
  createShare: mocks.createShare,
  removeShare: mocks.removeShare,
  toggleShareEarnings: mocks.toggleShareEarnings,
  blockSharer: mocks.blockSharer,
  unblockSharer: mocks.unblockSharer,
  shareBack: mocks.shareBack,
  toggleSharerMuted: mocks.toggleSharerMuted,
  removeSharer: mocks.removeSharer,
}));

vi.mock("@/app/[locale]/(app)/settings/_actions/updateSettings", () => ({
  updateProfileSettings: mocks.updateProfileSettings,
}));

vi.mock("@/data-access/auth", () => ({
  verifySession: mocks.verifySession,
}));

vi.mock("@/data-access/shifts", () => ({
  getComputedShiftsForApi: mocks.getComputedShiftsForApi,
}));

vi.mock("@/app/[locale]/(app)/shifts/add/actions", () => ({ createShifts: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateShift", () => ({ updateShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/deleteShift", () => ({ deleteShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/add/_actions/draftRecurringShift", () => ({ draftRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/add/_actions/createRecurringShift", () => ({ createRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateRecurringShift", () => ({ updateRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/deleteRecurringShift", () => ({ deleteRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/copyShifts", () => ({ copyShifts: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateCustomSupplements", () => ({ updateCustomSupplements: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/convertRecurringShiftToStandalone", () => ({ convertRecurringShiftToStandalone: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/moveRecurringShift", () => ({ moveRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/clearShiftSnapshots", () => ({ clearShiftSnapshots: vi.fn() }));
vi.mock("@/app/[locale]/(app)/settings/feedback/_actions/submitFeedback", () => ({ submitFeedback: vi.fn() }));
vi.mock("@/app/[locale]/(app)/settings/feedback/_actions/getUserFeedback", () => ({ getUserFeedback: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: vi.fn() }));
vi.mock("@/data-access/stats", () => ({ getStatsDataForApi: mocks.getStatsDataForApi }));
vi.mock("@/data-access/tariff", () => ({
  getTariffTypes: mocks.getTariffTypes,
  getLatestTariffVersion: vi.fn(),
  getTariffVersionForDate: vi.fn(),
}));

vi.mock("@/lib/layers/app", async () => {
  const { SnapshotsService } = await import("@/lib/services/snapshots");
  const { SettingsService } = await import("@/lib/services/settings");

  return {
    AuthSnapshotsLive: Layer.succeed(
      SnapshotsService,
      {
        getUserWageSnapshots: (userId: string) =>
          Effect.tryPromise(() => Promise.resolve(mocks.getUserWageSnapshots(userId))),
      } as any
    ),
    AuthSettingsLive: Layer.succeed(
      SettingsService,
      {
        getUserSettings: (userId: string) =>
          Effect.tryPromise(() => Promise.resolve(mocks.getUserSettings(userId))),
      } as any
    ),
  };
});

import { executeTool } from "@/lib/chat/executor";

const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
const jobA = "11111111-1111-4111-8111-111111111111";
const jobB = "22222222-2222-4222-8222-222222222222";
const friendId = "33333333-3333-4333-8333-333333333333";

function makeJob(overrides: Record<string, unknown>) {
  return {
    id: jobA,
    name: "Job",
    is_default: false,
    archived_at: null,
    deleted_at: null,
    sort_order: 0,
    color: null,
    created_at: "2026-03-01T10:00:00.000Z",
    ...overrides,
  };
}

describe("chat executor guardrails", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getAllFriends.mockResolvedValue([]);
    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [],
      settings: {},
      jobs: [],
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });
    mocks.getSharerShiftPreviews.mockResolvedValue([]);
    mocks.verifySession.mockResolvedValue({
      user: {
        id: userId,
        email: "user@example.com",
        phone: null,
        user_metadata: { full_name: "Tester" },
      },
    });
    mocks.getUserWageSnapshots.mockResolvedValue([]);
    mocks.getUserSettings.mockResolvedValue(null);
    mocks.getTariffTypes.mockResolvedValue([]);
  });

  it("blocks deleting default workplace", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
      makeJob({ id: jobB, name: "Secondary" }),
    ]);

    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({ action: "delete", jobId: jobA }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("Cannot delete the default workplace");
    expect(mocks.deleteJob).not.toHaveBeenCalled();
  });

  it("blocks deleting last active workplace", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Archived", is_default: true, archived_at: "2026-03-01T00:00:00.000Z" }),
      makeJob({ id: jobB, name: "Only active", is_default: false }),
    ]);

    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({ action: "delete", jobId: jobB }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("Cannot delete the last active workplace");
    expect(mocks.deleteJob).not.toHaveBeenCalled();
  });

  it("reorders workplaces among active entries", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "First", sort_order: 0 }),
      makeJob({ id: jobB, name: "Second", sort_order: 1 }),
    ]);

    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({ action: "reorder", jobId: jobA, direction: "down" }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(mocks.updateJob).toHaveBeenCalledTimes(2);
  });

  it("includes archived workplaces by default when listing workplaces", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Active", archived_at: null }),
      makeJob({ id: jobB, name: "Archived", archived_at: "2026-03-01T00:00:00.000Z" }),
    ]);

    const result = await executeTool(
      "list_workplaces",
      JSON.stringify({}),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any)).toHaveLength(2);
    expect(result.message).toContain("archived");
  });

  it("can list only active workplaces when includeArchived is false", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Active", archived_at: null }),
      makeJob({ id: jobB, name: "Archived", archived_at: "2026-03-01T00:00:00.000Z" }),
    ]);

    const result = await executeTool(
      "list_workplaces",
      JSON.stringify({ includeArchived: false }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any)).toHaveLength(1);
    expect((result.data as any)[0].name).toBe("Active");
  });

  it("prompts wage setup after creating a workplace", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
    ]);
    mocks.createJob.mockResolvedValue({
      id: jobB,
      name: "Telenor",
      color: "#3B82F6",
      is_default: false,
      archived_at: null,
    });

    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({
        action: "create",
        name: "Telenor",
        color: "#3B82F6",
        payrollDay: 15,
        monthlyGoal: null,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(result.message).toContain("no wage setup yet");
    expect((result.data as any).wageSetup.needed).toBe(true);
    expect((result.data as any).wageSetup.suggestedAction.arguments).toEqual({
      action: "create",
      jobId: jobB,
      from_date: null,
    });
  });

  it("requires payrollDay and monthlyGoal when creating workplace", async () => {
    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({ action: "create", name: "Telenor" }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("payrollDay");
    expect(result.message).toContain("monthlyGoal");
    expect(mocks.createJob).not.toHaveBeenCalled();
  });

  it("includes hidden sharers in list_friends by default", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: true,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    const result = await executeTool("list_friends", "{}", userId, "en");

    expect(result.success).toBe(true);
    expect((result.data as any)).toHaveLength(1);
    expect((result.data as any)[0].blocked).toBe(true);
  });

  it("enforces recipient-direction protections", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    const result = await executeTool(
      "manage_friend_sharing",
      JSON.stringify({ action: "remove_recipient", friendId }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("recipient");
    expect(mocks.removeShare).not.toHaveBeenCalled();
  });

  it("returns no_access only for non-sharers and still queries hidden sharers", async () => {
    const noAccess = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(noAccess.success).toBe(true);
    expect((noAccess.data as any).access).toBe("no_access");

    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: null,
        phone: null,
        sharesWithMe: {
          blocked: true,
          showEarningsToMe: false,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [
        {
          id: "44444444-4444-4444-8444-444444444444",
          shift_date: "2026-03-02",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 8,
            gross: 2000,
            basePay: 1800,
            supplementPay: 200,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: false,
          tax_percentage: 0,
        },
      ],
      settings: {},
      jobs: [],
      aggregates: { totalHours: 8, totalEarnings: 2000 },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const hidden = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(hidden.success).toBe(true);
    expect((hidden.data as any).access).toBeUndefined();
    expect((hidden.data as any).shifts).toHaveLength(1);
  });

  it("never returns earnings when friend hides earnings", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: false,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [
        {
          id: "44444444-4444-4444-8444-444444444444",
          shift_date: "2026-03-02",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 8,
            gross: 2000,
            basePay: 1800,
            supplementPay: 200,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: true,
          tax_percentage: 20,
        },
      ],
      settings: {},
      jobs: [],
      aggregates: { totalHours: 8, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const result = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any).summary.totalEarnings).toBeNull();
    expect((result.data as any).shifts[0].gross).toBeUndefined();
    expect((result.data as any).shifts[0].net).toBeUndefined();
  });

  it("uses the sharer's currency for friend shift responses", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [],
      settings: { currency: "USD", half_tax_month: null },
      jobs: [],
      aggregates: { totalHours: 0, totalEarnings: 0 },
      showEarnings: true,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const result = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(result.currency).toBe("USD");
  });

  it("returns newest shift when sorting by date with limit 1", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [
        {
          id: "11111111-1111-4111-8111-111111111111",
          shift_date: "2025-01-02",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 7.5,
            gross: 974.33,
            basePay: 900,
            supplementPay: 74.33,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: true,
          tax_percentage: 20,
        },
        {
          id: "22222222-2222-4222-8222-222222222222",
          shift_date: "2025-02-27",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 7.5,
            gross: 1500,
            basePay: 1400,
            supplementPay: 100,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: true,
          tax_percentage: 20,
        },
      ],
      settings: { currency: "NOK", half_tax_month: null },
      jobs: [],
      aggregates: { totalHours: 15, totalEarnings: 2474.33 },
      showEarnings: true,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const result = await executeTool(
      "query_friend_shifts",
      JSON.stringify({
        friendId,
        startDate: "2025-01-01",
        endDate: "2026-03-01",
        sortBy: "date",
        limit: 1,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any).shifts[0].date).toBe("2025-02-27");
  });

  it("returns earliest shift when sorting by date_earliest with limit 1", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);

    mocks.getSharedUserShifts.mockResolvedValue({
      shifts: [
        {
          id: "11111111-1111-4111-8111-111111111111",
          shift_date: "2025-01-02",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 7.5,
            gross: 974.33,
            basePay: 900,
            supplementPay: 74.33,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: true,
          tax_percentage: 20,
        },
        {
          id: "22222222-2222-4222-8222-222222222222",
          shift_date: "2025-02-27",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 7.5,
            gross: 1500,
            basePay: 1400,
            supplementPay: 100,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: true,
          tax_percentage: 20,
        },
      ],
      settings: { currency: "NOK", half_tax_month: null },
      jobs: [],
      aggregates: { totalHours: 15, totalEarnings: 2474.33 },
      showEarnings: true,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const result = await executeTool(
      "query_friend_shifts",
      JSON.stringify({
        friendId,
        startDate: "2025-01-01",
        endDate: "2026-03-01",
        sortBy: "date_earliest",
        limit: 1,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any).shifts[0].date).toBe("2025-01-02");
  });

  it("normalizes empty optional query_shifts filters instead of failing validation", async () => {
    mocks.getComputedShiftsForApi.mockResolvedValue({
      shifts: [
        {
          id: "11111111-1111-4111-8111-111111111111",
          shift_date: "2026-03-03",
          start_time: "16:00",
          end_time: "23:15",
          job_id: jobA,
          computed: {
            paidHours: 6.75,
            gross: 1410.11,
            basePay: 1300,
            supplementPay: 110.11,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: false,
          tax_percentage: null,
        },
      ],
      settings: { currency: "NOK", half_tax_month: null },
      jobs: [{ id: jobA, name: "Extra" }],
      aggregates: { totalHours: 6.75, totalEarnings: 1410.11 },
      showEarnings: true,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const result = await executeTool(
      "query_shifts",
      JSON.stringify({
        startDate: "2026-03-02",
        endDate: "2026-03-08",
        minTime: "",
        maxTime: "",
        sortBy: "date_earliest",
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(result.message).toContain("Found 1 shift");
    expect((result.summary as any).totalHours).toBe(6.75);
  });

  it("strips strict-mode null placeholders but preserves semantic nulls", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
    ]);
    mocks.updateJob.mockResolvedValue(
      makeJob({ id: jobA, name: "Default", is_default: true, half_tax_month: null })
    );

    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({
        action: "update",
        jobId: jobA,
        name: null,
        payrollDay: null,
        halfTaxMonth: null,
        monthlyGoal: null,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(mocks.updateJob).toHaveBeenCalledWith(userId, jobA, {
      half_tax_month: null,
      monthly_goal: null,
    });
  });

  it("rejects empty profile names", async () => {
    const result = await executeTool(
      "manage_profile",
      JSON.stringify({ action: "update_name", firstName: "   " }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("cannot be empty");
    expect(mocks.updateProfileSettings).not.toHaveBeenCalled();
  });

  it("uses featured friend shift preview selection from sharing DAL", async () => {
    mocks.getAllFriends.mockResolvedValue([
      {
        id: friendId,
        firstName: "Robin",
        email: "robin@example.com",
        phone: null,
        sharesWithMe: {
          blocked: false,
          showEarningsToMe: true,
          sharedAt: "2026-03-01",
          notificationFrequency: "instant",
        },
        iShareWith: null,
      },
    ]);
    mocks.getSharerShiftPreviews.mockResolvedValue([
      {
        sharerId: friendId,
        status: "upcoming",
        showEarnings: true,
        shift: {
          id: "44444444-4444-4444-8444-444444444444",
          shift_date: "2026-03-03",
          start_time: "10:00",
          end_time: "18:00",
          computed: { paidHours: 8, gross: 2300 },
        },
      },
    ]);

    const result = await executeTool(
      "query_friend_featured_shift",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(mocks.getSharerShiftPreviews).toHaveBeenCalledWith([friendId]);
    expect((result.data as any).status).toBe("upcoming");
    expect((result.data as any).featuredShift.gross).toBe(2300);
  });

  it("rejects unknown workplace for get_wage_info job scoping", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
    ]);

    const result = await executeTool(
      "get_wage_info",
      JSON.stringify({ jobId: jobB }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain(jobB);
  });

  it("includes tariff metadata for tariff-backed wage snapshots", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
    ]);
    mocks.getUserWageSnapshots.mockResolvedValue([
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        user_id: userId,
        job_id: jobA,
        from_date: null,
        hourly_wage: 187.46,
        wage_level: 3,
        tariff_type_id: "hk_retail",
        supplements: { rules: [] },
        tax_enabled: true,
        tax_percentage: 7,
        break_enabled: false,
        break_method: "none",
        break_threshold_hours: 0,
        break_deduction_minutes: 0,
      },
    ]);
    mocks.getUserSettings.mockResolvedValue({
      half_tax_month: 12,
      payroll_day: 10,
      monthly_goal: 15000,
    });
    mocks.getTariffTypes.mockResolvedValue([
      {
        id: "hk_retail",
        display_name: "HK - Virke",
        description: "Retail collective agreement",
        country: "NO",
        is_default: true,
      },
    ]);

    const result = await executeTool(
      "get_wage_info",
      JSON.stringify({ jobId: jobA }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect((result.data as any).tariffs).toEqual([
      {
        id: "hk_retail",
        displayName: "HK - Virke",
        description: "Retail collective agreement",
        country: "NO",
        isDefault: true,
      },
    ]);
    expect((result.data as any).current.tariffTypeId).toBe("hk_retail");
    expect((result.data as any).current.tariff).toEqual({
      id: "hk_retail",
      displayName: "HK - Virke",
      description: "Retail collective agreement",
      country: "NO",
      isDefault: true,
    });
  });

  it("rejects unknown workplace for manage_wage_snapshots create job scoping", async () => {
    mocks.getUserJobs.mockResolvedValue([
      makeJob({ id: jobA, name: "Default", is_default: true }),
    ]);

    const result = await executeTool(
      "manage_wage_snapshots",
      JSON.stringify({
        action: "create",
        jobId: jobB,
        from_date: "2026-03-10",
        tax_enabled: false,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain(jobB);
  });

  it("omits empty optional jobId in get_statistics tool args", async () => {
    mocks.getStatsDataForApi.mockResolvedValue({
      currentMonth: { gross: 0, hours: 0, shifts: 0 },
      lastMonth: { gross: 0, hours: 0, shifts: 0 },
      yearToDate: { gross: 0, hours: 0, shifts: 0 },
      fullYear: { gross: 0, hours: 0, shifts: 0 },
      yearlyMonths: [],
      thisWeek: [],
      monthlyGoal: null,
      currentMonthBreakdown: [],
    });

    const result = await executeTool(
      "get_statistics",
      JSON.stringify({
        metric: "current_month",
        year: 2026,
        month: 3,
        jobId: "",
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(mocks.getStatsDataForApi).toHaveBeenCalledWith(
      userId,
      expect.objectContaining({
        year: 2026,
        month: 3,
        locale: "en",
        jobId: undefined,
      })
    );
  });
});
