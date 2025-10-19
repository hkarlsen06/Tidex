import { SupplementRule } from "./types";

/**
 * Tariff-based supplement rules applied when users rely on preset wages.
 * These mirror the standard agreements and are reused across the app.
 */
export const PRESET_SUPPLEMENT_RULES: SupplementRule[] = [
  { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];
