/**
 * sessionStorage persistence for recurring shift drafts
 *
 * Allows users to resume building their recurring shift if they navigate away within the same session
 */

import type { RecurringDraft } from './types';

const STORAGE_KEY = 'tidex.recurringDraft';

/**
 * Save recurring draft to sessionStorage
 *
 * @param draft - Recurring draft to persist
 */
export function saveRecurringDraft(draft: RecurringDraft): void {
  if (typeof window === 'undefined') return;

  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(draft));
  } catch (error) {
    console.warn('Failed to save recurring draft to sessionStorage:', error);
  }
}

/**
 * Load recurring draft from sessionStorage
 *
 * @returns Saved draft or null if not found/invalid
 */
export function loadRecurringDraft(): RecurringDraft | null {
  if (typeof window === 'undefined') return null;

  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;

    const parsed = JSON.parse(raw) as RecurringDraft;

    // Basic validation
    if (
      typeof parsed.start_time !== 'string' ||
      typeof parsed.end_time !== 'string' ||
      typeof parsed.repeat_interval_weeks !== 'number' ||
      typeof parsed.selected_days !== 'object' ||
      !Array.isArray(parsed.exclusions)
    ) {
      console.warn('Invalid recurring draft in sessionStorage, clearing');
      clearRecurringDraft();
      return null;
    }

    return parsed;
  } catch (error) {
    console.warn('Failed to load recurring draft from sessionStorage:', error);
    return null;
  }
}

/**
 * Clear recurring draft from sessionStorage
 */
export function clearRecurringDraft(): void {
  if (typeof window === 'undefined') return;

  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch (error) {
    console.warn('Failed to clear recurring draft from sessionStorage:', error);
  }
}

/**
 * Check if a saved draft exists
 *
 * @returns true if a draft exists in sessionStorage
 */
export function hasSavedDraft(): boolean {
  if (typeof window === 'undefined') return false;

  try {
    return sessionStorage.getItem(STORAGE_KEY) !== null;
  } catch {
    return false;
  }
}
