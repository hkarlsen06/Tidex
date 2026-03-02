import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getUserJobs: vi.fn(),
  updateJob: vi.fn(),
  createJob: vi.fn(),
  archiveJob: vi.fn(),
  deleteJob: vi.fn(),
  getAllFriends: vi.fn(),
  getSharedUserShifts: vi.fn(),
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
vi.mock("@/data-access/stats", () => ({ getStatsDataForApi: vi.fn() }));
vi.mock("@/data-access/tariff", () => ({
  getLatestTariffVersion: vi.fn(),
  getTariffVersionForDate: vi.fn(),
}));

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
    mocks.verifySession.mockResolvedValue({
      user: {
        id: userId,
        email: "user@example.com",
        phone: null,
        user_metadata: { full_name: "Tester" },
      },
    });
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

  it("treats workplace reorder as unsupported chat input", async () => {
    const result = await executeTool(
      "manage_workplace",
      JSON.stringify({ action: "reorder", jobId: jobA, direction: "down" }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("Invalid option");
    expect(mocks.updateJob).not.toHaveBeenCalled();
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

  it("returns explicit no-access and blocked friend states", async () => {
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

    const blocked = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId }),
      userId,
      "en"
    );

    expect(blocked.success).toBe(true);
    expect((blocked.data as any).access).toBe("blocked");
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
});
