import { OvertimeConfig, SupplementRule } from "./types.ts";

/**
 * Tariff-based supplement rules applied when users rely on preset wages.
 * These mirror the standard agreements and are reused across the app.
 */
export const PRESET_SUPPLEMENT_RULES: SupplementRule[] = [
  { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1, 2, 3, 4, 5], from: "21:00", to: "24:00", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "24:00", rate: 110 },
  { days: [7], from: "00:00", to: "24:00", rate: 115 },
];

export const PRESET_OVERTIME_CONFIG: OvertimeConfig = {
  enabled: true,
  weeklyThresholdHours: 40,
  rules: [
    {
      days: [1, 2, 3, 4, 5, 6],
      appliesOnHolidays: false,
      from: "00:00",
      to: "21:00",
      percent: 50,
    },
    {
      days: [1, 2, 3, 4, 5, 6],
      appliesOnHolidays: false,
      from: "21:00",
      to: "24:00",
      percent: 100,
    },
    {
      days: [7],
      appliesOnHolidays: true,
      from: "00:00",
      to: "24:00",
      percent: 100,
    },
    {
      days: [1, 2, 3, 4, 5, 6, 7],
      appliesOnHolidays: true,
      from: "00:00",
      to: "24:00",
      percent: 100,
    },
  ],
};
