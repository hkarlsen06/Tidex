import { PRESET_WAGE_RATES } from "./calc";
import { PRESET_SUPPLEMENT_RULES } from "./presets";
import { SupplementRule } from "./types";

/**
 * Prepare shift snapshots for database insert
 * Captures current wage and supplement rules to preserve historical accuracy
 */
export function prepareShiftSnapshots(settings: {
  use_preset?: boolean | null;
  current_wage_level?: number | null;
  custom_wage?: number | null;
  custom_supplements?: { rules: SupplementRule[] } | null;
}): {
  hourly_wage_snapshot: number | null;
  supplement_rules_snapshot: { rules: SupplementRule[] } | null;
} {
  // Snapshot hourly wage
  let hourly_wage_snapshot: number | null = null;
  if (settings.use_preset && settings.current_wage_level != null) {
    const key = String(settings.current_wage_level);
    hourly_wage_snapshot = PRESET_WAGE_RATES[key] ?? null;
  } else if (settings.custom_wage && settings.custom_wage > 0) {
    hourly_wage_snapshot = settings.custom_wage;
  }

  // Snapshot supplement rules
  let supplement_rules_snapshot: { rules: SupplementRule[] } | null = null;
  if (settings.use_preset) {
    supplement_rules_snapshot = { rules: PRESET_SUPPLEMENT_RULES };
  } else if (settings.custom_supplements?.rules?.length) {
    supplement_rules_snapshot = { rules: settings.custom_supplements.rules };
  }

  return {
    hourly_wage_snapshot,
    supplement_rules_snapshot,
  };
}
