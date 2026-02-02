import type {
  ActiveActivityResult,
  AvailabilityResult,
  ShiftActivityData,
  ShiftActivityPlugin,
  StartActivityResult,
} from "./shift-activity";

/**
 * Web stub for ShiftActivity plugin
 * Live Activities are iOS-only, so this provides no-op implementations
 */
export class ShiftActivityWeb implements ShiftActivityPlugin {
  async startActivity(_data: ShiftActivityData): Promise<StartActivityResult> {
    console.log("[ShiftActivity] Web: Live Activities not available");
    return { activityId: "", success: false };
  }

  async updateActivity(): Promise<{ success: boolean }> {
    return { success: false };
  }

  async endActivity(): Promise<{ success: boolean }> {
    return { success: false };
  }

  async endAllActivities(): Promise<{ success: boolean }> {
    return { success: false };
  }

  async getActiveActivity(): Promise<ActiveActivityResult> {
    return { hasActivity: false };
  }

  async isAvailable(): Promise<AvailabilityResult> {
    return { available: false, frequentUpdatesEnabled: false };
  }

  async saveShiftsToSharedStorage(): Promise<{ success: boolean }> {
    return { success: false };
  }
}
