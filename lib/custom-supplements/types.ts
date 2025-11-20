/**
 * Custom supplement types for shift-specific supplement overrides
 *
 * Allows users to:
 * 1. Override supplements for individual shifts (user_shifts.custom_supplements)
 * 2. Override supplements for specific dates in a series (series_shifts.date_specific_supplements)
 */

import type { SupplementRule } from '@/lib/payroll/types';

/**
 * Mode for how custom supplements interact with pre-defined supplements
 * - "replace": Ignore all pre-defined supplements, use only custom rules
 * - "merge": Combine pre-defined + custom, taking highest rate where they overlap
 */
export type CustomSupplementMode = 'replace' | 'merge';

/**
 * Custom supplement data for a single shift
 * Stored in user_shifts.custom_supplements (JSONB)
 */
export type CustomSupplementsData = {
  mode: CustomSupplementMode;
  rules: Omit<SupplementRule, 'days'>[]; // No days field since it applies to one specific day
};

/**
 * Date-specific supplement overrides for a series
 * Stored in series_shifts.date_specific_supplements (JSONB)
 *
 * Example:
 * {
 *   "2025-12-24": { mode: "merge", rules: [...] },  // Christmas Eve
 *   "2025-12-31": { mode: "replace", rules: [...] } // New Year's Eve
 * }
 */
export type DateSpecificSupplements = {
  [isoDate: string]: CustomSupplementsData;
};

/**
 * Supplement rule without days field (for custom supplements on a single shift)
 */
export type CustomSupplementRule = Omit<SupplementRule, 'days'>;

/**
 * Internal representation with UI-specific fields for the editor
 */
export type CustomSupplementRuleWithId = {
  id: string; // Temporary ID for React key and editing
  from: string; // Allow empty during editing
  to: string; // Allow empty during editing
  rate?: number;
  percent?: number;
  mode?: 'percent' | 'rate'; // Track selected mode
};

/**
 * Data for the custom supplements editor component
 */
export type CustomSupplementsEditorData = {
  mode: CustomSupplementMode;
  rules: CustomSupplementRuleWithId[];
};
