/**
 * Custom supplement types for shift-specific supplement overrides
 *
 * When a user edits supplements for a shift, ALL supplements for that shift
 * are stored (both kept tariff supplements and custom-added ones).
 * This replaces the old mode-based approach (merge/replace).
 *
 * Allows users to:
 * 1. Override supplements for individual shifts (user_shifts.custom_supplements)
 * 2. Override supplements for specific dates in a recurring shift (recurring_shifts.date_specific_supplements)
 */

import type { SupplementRule, CustomSupplementRuleSaved, CustomSupplementsData } from '@/lib/payroll/types';

// Re-export core types from payroll/types for convenience
export type { CustomSupplementRuleSaved, CustomSupplementsData };

/**
 * Date-specific supplement overrides for a recurring shift
 * Stored in recurring_shifts.date_specific_supplements (JSONB)
 *
 * Example:
 * {
 *   "2025-12-24": { rules: [...] },  // Christmas Eve
 *   "2025-12-31": { rules: [...] }   // New Year's Eve
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
  inputMode?: 'percent' | 'rate'; // Track selected input mode for UI
  isCustom?: boolean; // true = user-added, false/undefined = from tariff
};

/**
 * Data for the custom supplements editor component
 */
export type CustomSupplementsEditorData = {
  rules: CustomSupplementRuleWithId[];
};
