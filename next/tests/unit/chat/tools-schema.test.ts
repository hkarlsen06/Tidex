import { describe, expect, it } from "vitest";
import {
  getWageInfoSchema,
  listWorkplacesSchema,
  listFriendsSchema,
  manageFeedbackSchema,
  manageFriendSharingSchema,
  manageProfileSchema,
  manageShiftAdvancedSchema,
  manageWageSnapshotsSchema,
  manageWorkplaceSchema,
  queryFriendFeaturedShiftSchema,
  queryFriendShiftsSchema,
  queryShiftsSchema,
} from "@/lib/chat/tools";

const friendId = "11111111-1111-4111-8111-111111111111";
const jobId = "22222222-2222-4222-8222-222222222222";

describe("chat tool schemas", () => {
  it("validates extended manage_workplace actions", () => {
    const setDefault = manageWorkplaceSchema.safeParse({
      action: "set_default",
      jobId,
    });
    const remove = manageWorkplaceSchema.safeParse({
      action: "delete",
      jobId,
    });
    const reorder = manageWorkplaceSchema.safeParse({
      action: "reorder",
      jobId,
    });
    const createWithNullableGoal = manageWorkplaceSchema.safeParse({
      action: "create",
      name: "Telenor",
      payrollDay: 15,
      monthlyGoal: null,
    });

    expect(setDefault.success).toBe(true);
    expect(remove.success).toBe(true);
    expect(reorder.success).toBe(true);
    expect(createWithNullableGoal.success).toBe(true);
  });

  it("applies list_friends defaults", () => {
    const parsed = listFriendsSchema.parse({});
    expect(parsed.includeBlocked).toBe(true);
  });

  it("applies list_workplaces defaults", () => {
    const parsed = listWorkplacesSchema.parse({});
    expect(parsed.includeArchived).toBe(true);
  });

  it("validates manage_friend_sharing actions", () => {
    const parsed = manageFriendSharingSchema.safeParse({
      action: "toggle_recipient_earnings",
      friendId,
      showEarnings: true,
    });

    expect(parsed.success).toBe(true);
  });

  it("requires friendId in query_friend_shifts", () => {
    const missingFriend = queryFriendShiftsSchema.safeParse({});
    const valid = queryFriendShiftsSchema.safeParse({
      friendId,
      sortBy: "hours",
      weekdays: [1, 5],
    });
    const latest = queryFriendShiftsSchema.safeParse({
      friendId,
      sortBy: "date_latest",
    });
    const earliest = queryFriendShiftsSchema.safeParse({
      friendId,
      sortBy: "date_earliest",
    });

    expect(missingFriend.success).toBe(false);
    expect(valid.success).toBe(true);
    expect(latest.success).toBe(true);
    expect(earliest.success).toBe(true);
  });

  it("supports explicit date sort modes for query_shifts", () => {
    expect(queryShiftsSchema.safeParse({ sortBy: "date_latest" }).success).toBe(true);
    expect(queryShiftsSchema.safeParse({ sortBy: "date_earliest" }).success).toBe(true);
  });

  it("requires friendId in query_friend_featured_shift", () => {
    const missingFriend = queryFriendFeaturedShiftSchema.safeParse({});
    const valid = queryFriendFeaturedShiftSchema.safeParse({ friendId });

    expect(missingFriend.success).toBe(false);
    expect(valid.success).toBe(true);
  });

  it("validates manage_shift_advanced actions", () => {
    const copy = manageShiftAdvancedSchema.safeParse({
      action: "copy_shifts",
      shiftIds: ["abcde"],
      targetDate: "2026-03-10",
    });
    const clear = manageShiftAdvancedSchema.safeParse({
      action: "clear_shift_snapshots",
      shiftId: "abcde",
    });

    expect(copy.success).toBe(true);
    expect(clear.success).toBe(true);
  });

  it("validates manage_feedback actions", () => {
    expect(manageFeedbackSchema.safeParse({ action: "submit", message: "Hey" }).success).toBe(true);
    expect(manageFeedbackSchema.safeParse({ action: "list" }).success).toBe(true);
  });

  it("validates manage_profile actions", () => {
    expect(manageProfileSchema.safeParse({ action: "view" }).success).toBe(true);
    expect(manageProfileSchema.safeParse({ action: "update_name", firstName: "Alex" }).success).toBe(true);
  });

  it("supports workplace-scoped wage tools", () => {
    expect(getWageInfoSchema.safeParse({ jobId }).success).toBe(true);
    expect(manageWageSnapshotsSchema.safeParse({
      action: "create",
      jobId,
      from_date: "2026-03-10",
    }).success).toBe(true);
  });

  it("accepts wage snapshot supplements in alias format", () => {
    const parsed = manageWageSnapshotsSchema.safeParse({
      action: "create",
      jobId,
      from_date: null,
      hourly_wage: 174.65,
      supplements: [
        {
          days: [1, 2, 3, 4],
          startTime: "16:00",
          endTime: "20:00",
          amount: 45,
          type: "time_of_day",
        },
      ],
    });

    expect(parsed.success).toBe(true);
  });
});
