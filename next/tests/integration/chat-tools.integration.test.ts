import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getAllFriends: vi.fn(),
  getSharedUserShifts: vi.fn(),
  getSharerShiftPreviews: vi.fn(),
  getUserJobs: vi.fn(),
  createShare: vi.fn(),
  toggleSharerMuted: vi.fn(),
  copyShifts: vi.fn(),
  clearShiftSnapshots: vi.fn(),
  submitFeedback: vi.fn(),
  getUserFeedback: vi.fn(),
  createWageSnapshotAction: vi.fn(),
  getComputedShiftsForApi: vi.fn(),
  verifySession: vi.fn(),
}));

vi.mock("@/data-access/sharing", () => ({
  getAllFriends: mocks.getAllFriends,
  getSharedUserShifts: mocks.getSharedUserShifts,
  getSharerShiftPreviews: mocks.getSharerShiftPreviews,
}));

vi.mock("@/app/[locale]/(app)/sharing/_actions/sharing", () => ({
  createShare: mocks.createShare,
  removeShare: vi.fn(),
  toggleShareEarnings: vi.fn(),
  blockSharer: vi.fn(),
  unblockSharer: vi.fn(),
  shareBack: vi.fn(),
  toggleSharerMuted: mocks.toggleSharerMuted,
  removeSharer: vi.fn(),
}));

vi.mock("@/app/[locale]/(app)/shifts/_actions/copyShifts", () => ({
  copyShifts: mocks.copyShifts,
}));

vi.mock("@/app/[locale]/(app)/shifts/_actions/clearShiftSnapshots", () => ({
  clearShiftSnapshots: mocks.clearShiftSnapshots,
}));

vi.mock("@/app/[locale]/(app)/settings/feedback/_actions/submitFeedback", () => ({
  submitFeedback: mocks.submitFeedback,
}));

vi.mock("@/app/[locale]/(app)/settings/feedback/_actions/getUserFeedback", () => ({
  getUserFeedback: mocks.getUserFeedback,
}));

vi.mock("@/data-access/shifts", () => ({
  getComputedShiftsForApi: mocks.getComputedShiftsForApi,
}));

vi.mock("@/data-access/auth", () => ({
  verifySession: mocks.verifySession,
}));

vi.mock("@/data-access/jobs", () => ({
  getUserJobs: mocks.getUserJobs,
  updateJob: vi.fn(),
  createJob: vi.fn(),
  archiveJob: vi.fn(),
  deleteJob: vi.fn(),
}));

vi.mock("@/app/[locale]/(app)/settings/pay/_actions/wage-snapshots", () => ({
  createWageSnapshotAction: mocks.createWageSnapshotAction,
  updateWageSnapshotAction: vi.fn(),
  deleteWageSnapshotAction: vi.fn(),
}));

vi.mock("@/app/[locale]/(app)/shifts/add/actions", () => ({ createShifts: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateShift", () => ({ updateShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/deleteShift", () => ({ deleteShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/add/_actions/draftRecurringShift", () => ({ draftRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/add/_actions/createRecurringShift", () => ({ createRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateRecurringShift", () => ({ updateRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/deleteRecurringShift", () => ({ deleteRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/updateCustomSupplements", () => ({ updateCustomSupplements: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/convertRecurringShiftToStandalone", () => ({ convertRecurringShiftToStandalone: vi.fn() }));
vi.mock("@/app/[locale]/(app)/shifts/_actions/moveRecurringShift", () => ({ moveRecurringShift: vi.fn() }));
vi.mock("@/app/[locale]/(app)/settings/_actions/updateSettings", () => ({ updateProfileSettings: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: vi.fn() }));
vi.mock("@/data-access/stats", () => ({ getStatsDataForApi: vi.fn() }));
vi.mock("@/data-access/tariff", () => ({
  getLatestTariffVersion: vi.fn(),
  getTariffVersionForDate: vi.fn(),
}));

import { executeTool } from "@/lib/chat/executor";

const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
const friendId = "33333333-3333-4333-8333-333333333333";

describe("chat tool integration paths", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getUserJobs.mockResolvedValue([]);
    mocks.verifySession.mockResolvedValue({
      user: {
        id: userId,
        email: "user@example.com",
        phone: null,
        user_metadata: { full_name: "Tester" },
      },
    });
  });

  it("supports list_friends -> query_friend_shifts flow", async () => {
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
          id: "44444444-4444-4444-8444-444444444444",
          shift_date: "2026-03-02",
          start_time: "08:00",
          end_time: "16:00",
          job_id: null,
          computed: {
            paidHours: 8,
            gross: 2200,
            basePay: 2000,
            supplementPay: 200,
            wagePeriods: [],
            originalWagePeriods: [],
          },
          tax_enabled: false,
          tax_percentage: 0,
        },
      ],
      settings: { half_tax_month: null },
      jobs: [],
      aggregates: { totalHours: 8, totalEarnings: 2200 },
      showEarnings: true,
      payoutTaxSettings: null,
      wageSnapshots: [],
      defaultView: "calendar",
    });

    const friends = await executeTool("list_friends", "{}", userId, "en");
    expect(friends.success).toBe(true);
    const firstFriendId = (friends.data as any)[0].id;

    const shifts = await executeTool(
      "query_friend_shifts",
      JSON.stringify({ friendId: firstFriendId }),
      userId,
      "en"
    );

    expect(shifts.success).toBe(true);
    expect((shifts.data as any).shifts).toHaveLength(1);
    expect((shifts.data as any).summary.totalEarnings).toBe(2200);
  });

  it("maps manage_friend_sharing actions to sharing server actions", async () => {
    mocks.createShare.mockResolvedValue({ success: true });
    mocks.toggleSharerMuted.mockResolvedValue({ success: true });
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

    const shareByIdentifier = await executeTool(
      "manage_friend_sharing",
      JSON.stringify({ action: "share_by_identifier", identifier: "friend@example.com", showEarnings: true }),
      userId,
      "en"
    );
    expect(shareByIdentifier.success).toBe(true);
    expect(mocks.createShare).toHaveBeenCalledWith("friend@example.com", { showEarnings: true });

    const muteSharer = await executeTool(
      "manage_friend_sharing",
      JSON.stringify({ action: "set_sharer_muted", friendId, muted: true }),
      userId,
      "en"
    );
    expect(muteSharer.success).toBe(true);
    expect(mocks.toggleSharerMuted).toHaveBeenCalledWith(friendId, true);
  });

  it("maps manage_shift_advanced actions", async () => {
    mocks.getComputedShiftsForApi.mockResolvedValue({
      shifts: [
        {
          id: "aaaaa111-1111-4111-8111-111111111111",
          shift_date: "2026-03-02",
        },
      ],
      settings: {},
      jobs: [],
    });
    mocks.copyShifts.mockResolvedValue({ copied: 1 });
    mocks.clearShiftSnapshots.mockResolvedValue({ success: true });

    const copy = await executeTool(
      "manage_shift_advanced",
      JSON.stringify({ action: "copy_shifts", shiftIds: ["aaaaa"], targetDate: "2026-03-10" }),
      userId,
      "en"
    );
    expect(copy.success).toBe(true);
    expect(mocks.copyShifts).toHaveBeenCalledWith({
      shiftIds: ["aaaaa111-1111-4111-8111-111111111111"],
      targetDate: "2026-03-10",
    });

    const clear = await executeTool(
      "manage_shift_advanced",
      JSON.stringify({ action: "clear_shift_snapshots", shiftId: "aaaaa" }),
      userId,
      "en"
    );
    expect(clear.success).toBe(true);
    expect(mocks.clearShiftSnapshots).toHaveBeenCalledWith("aaaaa111-1111-4111-8111-111111111111");
  });

  it("maps manage_feedback submit/list actions", async () => {
    mocks.submitFeedback.mockResolvedValue({ success: true });
    mocks.getUserFeedback.mockResolvedValue([
      { id: "1", message: "Great app", created_at: "2026-03-01", response: null, responded_at: null },
    ]);

    const submit = await executeTool(
      "manage_feedback",
      JSON.stringify({ action: "submit", message: "Great app" }),
      userId,
      "en"
    );
    expect(submit.success).toBe(true);
    expect(mocks.submitFeedback).toHaveBeenCalledWith("Great app");

    const list = await executeTool(
      "manage_feedback",
      JSON.stringify({ action: "list" }),
      userId,
      "en"
    );
    expect(list.success).toBe(true);
    expect((list.data as any)).toHaveLength(1);
    expect(mocks.getUserFeedback).toHaveBeenCalledTimes(1);
  });

  it("maps query_friend_featured_shift to sharing preview DAL", async () => {
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
        status: "active",
        showEarnings: true,
        shift: {
          id: "44444444-4444-4444-8444-444444444444",
          shift_date: "2026-03-02",
          start_time: "08:00",
          end_time: "16:00",
          computed: { paidHours: 8, gross: 2200 },
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
    expect((result.data as any).status).toBe("active");
    expect((result.data as any).featuredShift.gross).toBe(2200);
  });

  it("normalizes wage supplement alias keys before creating snapshots", async () => {
    const jobId = "8702776f-48c3-49ff-81d7-bfd38bedd296";

    mocks.getUserJobs.mockResolvedValue([
      {
        id: jobId,
        name: "Telenor",
        is_default: false,
        archived_at: null,
        deleted_at: null,
      },
    ]);
    mocks.createWageSnapshotAction.mockResolvedValue({
      success: true,
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    });

    const result = await executeTool(
      "manage_wage_snapshots",
      JSON.stringify({
        action: "create",
        from_date: null,
        hourly_wage: 174.65,
        tax_enabled: true,
        tax_percentage: 25,
        jobId,
        supplements: [
          {
            days: [1, 2, 3, 4],
            startTime: "16:00",
            endTime: "23:59",
            amount: 45,
            type: "time_of_day",
          },
        ],
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(true);
    expect(mocks.createWageSnapshotAction).toHaveBeenCalledTimes(1);
    expect(mocks.createWageSnapshotAction).toHaveBeenCalledWith(
      expect.objectContaining({
        job_id: jobId,
        tax_enabled: true,
        tax_percentage: 25,
        supplements: {
          rules: [
            {
              days: [1, 2, 3, 4],
              from: "16:00",
              to: "24:00",
              rate: 45,
            },
          ],
        },
      })
    );
  });

  it("requires tax_enabled when creating wage snapshots", async () => {
    const jobId = "8702776f-48c3-49ff-81d7-bfd38bedd296";
    mocks.getUserJobs.mockResolvedValue([
      {
        id: jobId,
        name: "Telenor",
        is_default: false,
        archived_at: null,
        deleted_at: null,
      },
    ]);

    const result = await executeTool(
      "manage_wage_snapshots",
      JSON.stringify({
        action: "create",
        from_date: null,
        jobId,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("tax_enabled");
    expect(mocks.createWageSnapshotAction).not.toHaveBeenCalled();
  });

  it("requires tax_percentage when tax_enabled is true", async () => {
    const jobId = "8702776f-48c3-49ff-81d7-bfd38bedd296";
    mocks.getUserJobs.mockResolvedValue([
      {
        id: jobId,
        name: "Telenor",
        is_default: false,
        archived_at: null,
        deleted_at: null,
      },
    ]);

    const result = await executeTool(
      "manage_wage_snapshots",
      JSON.stringify({
        action: "create",
        from_date: null,
        tax_enabled: true,
        jobId,
      }),
      userId,
      "en"
    );

    expect(result.success).toBe(false);
    expect(result.message).toContain("tax_percentage");
    expect(mocks.createWageSnapshotAction).not.toHaveBeenCalled();
  });
});
