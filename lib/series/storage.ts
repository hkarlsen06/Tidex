/**
 * sessionStorage persistence for series shift drafts
 *
 * Allows users to resume building their series if they navigate away within the same session
 */

import type { SeriesDraft } from './types';

const STORAGE_KEY = 'tidex.seriesDraft';

/**
 * Save series draft to sessionStorage
 *
 * @param draft - Series draft to persist
 */
export function saveSeriesDraft(draft: SeriesDraft): void {
  if (typeof window === 'undefined') return;

  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(draft));
  } catch (error) {
    console.warn('Failed to save series draft to sessionStorage:', error);
  }
}

/**
 * Load series draft from sessionStorage
 *
 * @returns Saved draft or null if not found/invalid
 */
export function loadSeriesDraft(): SeriesDraft | null {
  if (typeof window === 'undefined') return null;

  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;

    const parsed = JSON.parse(raw) as SeriesDraft;

    // Basic validation
    if (
      typeof parsed.start_time !== 'string' ||
      typeof parsed.end_time !== 'string' ||
      typeof parsed.repeat_interval_weeks !== 'number' ||
      typeof parsed.selected_days !== 'object' ||
      !Array.isArray(parsed.exclusions)
    ) {
      console.warn('Invalid series draft in sessionStorage, clearing');
      clearSeriesDraft();
      return null;
    }

    return parsed;
  } catch (error) {
    console.warn('Failed to load series draft from sessionStorage:', error);
    return null;
  }
}

/**
 * Clear series draft from sessionStorage
 */
export function clearSeriesDraft(): void {
  if (typeof window === 'undefined') return;

  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch (error) {
    console.warn('Failed to clear series draft from sessionStorage:', error);
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
