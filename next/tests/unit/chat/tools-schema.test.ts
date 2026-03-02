import { describe, expect, it } from "vitest";
import {
  listFriendsSchema,
  manageFeedbackSchema,
  manageFriendSharingSchema,
  manageProfileSchema,
  manageShiftAdvancedSchema,
  manageWorkplaceSchema,
  queryFriendShiftsSchema,
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

    expect(setDefault.success).toBe(true);
    expect(remove.success).toBe(true);
    expect(reorder.success).toBe(false);
  });

  it("applies list_friends defaults", () => {
    const parsed = listFriendsSchema.parse({});
    expect(parsed.includeBlocked).toBe(false);
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
});
