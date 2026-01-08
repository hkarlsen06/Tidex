import { registerPlugin } from "@capacitor/core";

export interface ShiftActivityData {
  shiftId: string;
  shiftDate: string; // "2025-01-08"
  startTime: string; // "08:00"
  endTime: string; // "16:00"
  hourlyWage: number;
  supplementRatePerHour: number;
  totalGrossEstimate: number;
  locale: string;
  currencySymbol?: string; // e.g., "kr", "$", "€"
  // Initial state
  initialProgress?: number;
  initialEarnings?: number;
  remainingMinutes?: number;
}

export interface StoredShiftData {
  shiftId: string;
  shiftDate: string;
  startTime: string;
  endTime: string;
  hourlyWage: number;
  supplementRatePerHour: number;
  totalGrossEstimate: number;
  locale: string;
}

export interface StartActivityResult {
  activityId: string;
  success: boolean;
}

export interface ActiveActivityResult {
  hasActivity: boolean;
  activityId?: string;
  shiftId?: string;
}

export interface AvailabilityResult {
  available: boolean;
  frequentUpdatesEnabled: boolean;
}

export interface ShiftActivityPlugin {
  /**
   * Start a new Live Activity for an ongoing shift
   */
  startActivity(data: ShiftActivityData): Promise<StartActivityResult>;

  /**
   * Manually update the activity's earnings and progress
   */
  updateActivity(data: {
    activityId?: string;
    earnings: number;
    progress: number;
    remainingMinutes: number;
  }): Promise<{ success: boolean }>;

  /**
   * End a specific activity or the current one
   */
  endActivity(data?: { activityId?: string }): Promise<{ success: boolean }>;

  /**
   * End all active shift activities
   */
  endAllActivities(): Promise<{ success: boolean }>;

  /**
   * Get the currently active shift activity
   */
  getActiveActivity(): Promise<ActiveActivityResult>;

  /**
   * Check if Live Activities are available on this device
   */
  isAvailable(): Promise<AvailabilityResult>;

  /**
   * Save upcoming shifts to shared storage for background task access
   */
  saveShiftsToSharedStorage(data: {
    shifts: string;
  }): Promise<{ success: boolean }>;
}

// Register plugin with web stub
export const ShiftActivity = registerPlugin<ShiftActivityPlugin>(
  "ShiftActivity",
  {
    web: () =>
      import("./shift-activity-web").then((m) => new m.ShiftActivityWeb()),
  }
);
