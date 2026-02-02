'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Plus, Pencil } from 'lucide-react';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';
import type { TariffVersion } from '@/data-access/tariff';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface WageHistoryTimelineProps {
  snapshots: WageSnapshot[];
  t: Dictionary;
  /**
   * Initial tariff version to use when creating new snapshots.
   * If not provided, the modal will fetch the latest version when opened.
   */
  initialTariffVersion?: TariffVersion | null;
}

interface TimelineEntry {
  snapshot: WageSnapshot;
  type: 'future' | 'current' | 'past';
  dateRange: string;
  endDate: string | null;
  changes: string[]; // What changed from previous entry
}

/**
 * Format a date with smart year display
 * Only show year if it differs from current year
 */
function formatDateSmart(isoDate: string, locale: string = 'no-NO'): string {
  const date = new Date(isoDate + 'T00:00:00');
  const currentYear = new Date().getFullYear();
  const dateYear = date.getFullYear();

  if (dateYear === currentYear) {
    return date.toLocaleDateString(locale, {
      day: 'numeric',
      month: 'long',
    });
  }

  return date.toLocaleDateString(locale, {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}

/**
 * Format date range for display
 * Smart year handling: only show year if different from current year
 */
function formatDateRange(
  fromDate: string | null,
  toDate: string | null,
  nowText: string,
  locale: string = 'no-NO',
  isPast: boolean = false
): string {
  if (fromDate === null) {
    // Baseline snapshot - show as ended at toDate if it exists
    if (toDate && isPast) {
      const toFormatted = formatDateSmart(toDate, locale);
      return `- ${toFormatted}`;
    }
    return nowText;
  }

  const fromFormatted = formatDateSmart(fromDate, locale);

  if (toDate === null) {
    // Current entry (no end date)
    return `${fromFormatted} - ${nowText}`;
  }

  // Has both dates
  const toFormatted = formatDateSmart(toDate, locale);
  return `${fromFormatted} - ${toFormatted}`;
}

/**
 * Determine the end date for a snapshot based on the next snapshot
 */
function getEndDate(snapshots: WageSnapshot[], currentIndex: number): string | null {
  if (currentIndex === 0) {
    // Most recent snapshot - no end date
    return null;
  }

  const nextSnapshot = snapshots[currentIndex - 1];
  if (!nextSnapshot?.from_date) {
    return null;
  }

  // The previous wage is valid up to and including the day before the new wage starts
  // If new wage starts Aug 1, previous wage ends July 31
  // Parse the date string directly to avoid timezone issues
  const [year, month, day] = nextSnapshot.from_date.split('-').map(Number);
  const previousEndDate = new Date(year, month - 1, day - 1);

  // Format as YYYY-MM-DD
  const endYear = previousEndDate.getFullYear();
  const endMonth = String(previousEndDate.getMonth() + 1).padStart(2, '0');
  const endDay = String(previousEndDate.getDate()).padStart(2, '0');
  return `${endYear}-${endMonth}-${endDay}`;
}

/**
 * Detect what changed between two snapshots
 * Returns array of change descriptions
 */
function detectChanges(
  current: WageSnapshot,
  previous: WageSnapshot | null,
  t: Dictionary
): string[] {
  if (!previous) return [];

  const changes: string[] = [];

  // Hourly wage change
  if (current.hourly_wage !== previous.hourly_wage) {
    changes.push(`${t.pages.settings.pay.wageHistory.changes.wage}: ${previous.hourly_wage} → ${current.hourly_wage} kr/t`);
  }

  // Wage level change (tariff level)
  if (current.wage_level !== previous.wage_level) {
    if (current.wage_level === null && previous.wage_level !== null) {
      changes.push(t.pages.settings.pay.wageHistory.changes.toCustomWage);
    } else if (current.wage_level !== null && previous.wage_level === null) {
      changes.push(t.pages.settings.pay.wageHistory.changes.toTariff);
    } else if (current.wage_level !== null && previous.wage_level !== null) {
      changes.push(`${t.pages.settings.pay.wageHistory.changes.tariffLevel}: ${previous.wage_level} → ${current.wage_level}`);
    }
  }

  // Tax enabled change
  if (current.tax_enabled !== previous.tax_enabled) {
    changes.push(current.tax_enabled
      ? t.pages.settings.pay.wageHistory.changes.taxEnabled
      : t.pages.settings.pay.wageHistory.changes.taxDisabled);
  } else if (current.tax_enabled && current.tax_percentage !== previous.tax_percentage) {
    // Tax percentage change (only if tax is enabled)
    changes.push(`${t.pages.settings.pay.wageHistory.changes.taxRate}: ${previous.tax_percentage}% → ${current.tax_percentage}%`);
  }

  // Break enabled change
  if (current.break_enabled !== previous.break_enabled) {
    changes.push(current.break_enabled
      ? t.pages.settings.pay.wageHistory.changes.breakEnabled
      : t.pages.settings.pay.wageHistory.changes.breakDisabled);
  } else if (current.break_enabled) {
    // Break settings changes (only if break is enabled)
    if (current.break_method !== previous.break_method) {
      changes.push(t.pages.settings.pay.wageHistory.changes.breakMethod);
    }
    if (current.break_threshold_hours !== previous.break_threshold_hours ||
        current.break_deduction_minutes !== previous.break_deduction_minutes) {
      changes.push(t.pages.settings.pay.wageHistory.changes.breakSettings);
    }
  }

  // Supplements change (simple check - compare rule count)
  const currentRules = current.supplements?.rules?.length || 0;
  const previousRules = previous.supplements?.rules?.length || 0;
  if (currentRules !== previousRules) {
    changes.push(t.pages.settings.pay.wageHistory.changes.supplements);
  }

  return changes;
}

/**
 * Categorize snapshots into timeline entries
 */
function categorizeSnapshots(snapshots: WageSnapshot[], nowText: string, locale: string, t: Dictionary): TimelineEntry[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // First pass: determine types and end dates
  const entriesWithTypes = snapshots.map((snapshot, index) => {
    const fromDate = snapshot.from_date;
    const endDate = getEndDate(snapshots, index);

    // Determine type
    let type: 'future' | 'current' | 'past';

    if (fromDate === null) {
      // Baseline is always in the past
      type = 'past';
    } else {
      const from = new Date(fromDate + 'T00:00:00');

      if (from > today) {
        type = 'future';
      } else if (endDate === null || new Date(endDate + 'T00:00:00') >= today) {
        type = 'current';
      } else {
        type = 'past';
      }
    }

    return {
      snapshot,
      type,
      fromDate,
      endDate,
    };
  });

  // Find the current entry (only one should exist)
  const hasFutureEntries = entriesWithTypes.some(e => e.type === 'future');

  // Second pass: format date ranges and detect changes
  return entriesWithTypes.map((entry, index) => {
    const { snapshot, type, fromDate, endDate } = entry;
    const isCurrent = type === 'current';
    const isPast = type === 'past';

    // Determine what to show for the end date
    let displayEndDate: string | null = endDate;

    if (isCurrent) {
      // Current entry: show "nå" unless there's a future entry
      if (hasFutureEntries && endDate) {
        displayEndDate = endDate; // Show the actual end date
      } else {
        displayEndDate = null; // Will show "nå"
      }
    } else if (isPast) {
      // Past entries should always show their actual end date, never "nå"
      displayEndDate = endDate;
    }

    // Detect changes from previous entry (next in array since sorted newest first)
    const previousSnapshot = index < entriesWithTypes.length - 1
      ? entriesWithTypes[index + 1].snapshot
      : null;
    const changes = detectChanges(snapshot, previousSnapshot, t);

    return {
      snapshot,
      type,
      dateRange: formatDateRange(fromDate, displayEndDate, nowText, locale, isPast),
      endDate,
      changes,
    };
  });
}

export function WageHistoryTimeline({
  snapshots,
  t,
  initialTariffVersion,
}: WageHistoryTimelineProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState<'create' | 'edit'>('create');
  const [selectedSnapshot, setSelectedSnapshot] = useState<WageSnapshot | null>(null);

  const locale = t.common.currency === 'kr' ? 'no-NO' : 'en-US';
  const nowText = t.pages.settings.pay.wageHistory.now;

  // Find the most recent snapshot (first in array since sorted by date desc)
  const mostRecentSnapshot = snapshots.length > 0 ? snapshots[0] : null;

  const handleAddNew = () => {
    // Pre-fill with the most recent snapshot's values
    setSelectedSnapshot(mostRecentSnapshot);
    setModalMode('create');
    setModalOpen(true);
  };

  const handleEdit = (snapshot: WageSnapshot) => {
    setSelectedSnapshot(snapshot);
    setModalMode('edit');
    setModalOpen(true);
  };

  const handleCloseModal = () => {
    setModalOpen(false);
    setSelectedSnapshot(null);
  };

  // Categorize all snapshots
  const entries = categorizeSnapshots(snapshots, nowText, locale, t);

  // Find current entry and its wage
  const currentEntry = entries.find(e => e.type === 'current');
  const currentWage = currentEntry?.snapshot.hourly_wage;

  // Find which past entry first introduced the current wage (if the current entry only changed settings)
  // This is the entry that should be highlighted in blue
  const currentEntryIndex = entries.findIndex(e => e.type === 'current');
  const currentEntryChangedWage = currentEntry && currentEntryIndex < entries.length - 1 &&
    currentEntry.snapshot.hourly_wage !== entries[currentEntryIndex + 1]?.snapshot.hourly_wage;

  // If current entry didn't introduce the wage, find the past entry that did
  let highlightedEntryIndex: number | null = null;
  if (!currentEntryChangedWage && currentWage !== undefined && currentEntryIndex !== -1) {
    // Look through past entries (after current in array) to find where this wage was introduced
    for (let i = currentEntryIndex + 1; i < entries.length; i++) {
      const entry = entries[i];
      const prevEntry = i < entries.length - 1 ? entries[i + 1] : null;

      // This entry introduced the current wage if it has the current wage and the previous one doesn't
      if (entry.snapshot.hourly_wage === currentWage &&
          (!prevEntry || prevEntry.snapshot.hourly_wage !== currentWage)) {
        highlightedEntryIndex = i;
        break;
      }
    }
  }

  return (
    <div className="space-y-6">
      {/* Timeline Card */}
      <Card className="overflow-hidden">
        {/* Header */}
        <div className="p-6 pb-4 flex items-center justify-between">
          <h3 className="text-lg font-semibold text-text-primary">
            {t.pages.settings.pay.wageHistory.timelineTitle}
          </h3>
          <Button onClick={handleAddNew} variant="outline" size="sm" className="w-9 md:w-auto md:px-3">
            <Plus className="h-5 w-5 md:h-4 md:w-4 md:mr-2" />
            <span className="hidden md:inline">{t.pages.settings.pay.wageHistory.addNew}</span>
          </Button>
        </div>

        {/* Timeline */}
        <div className="relative px-6 pb-6">
          {/* Timeline entries */}
          <div className="space-y-0 relative">
            {entries.map((entry, index) => {
              const { snapshot, type, dateRange, changes } = entry;
              const isCurrent = type === 'current';
              const isFuture = type === 'future';
              const _isPast = type === 'past';
              const isLast = index === entries.length - 1;
              // Check if any previous entry (index < current) is future
              const hasFutureAbove = entries.slice(0, index).some(e => e.type === 'future');
              // Only show dashed line for future entries and current entry if there's a future above
              const _shouldBeDashed = isFuture || (isCurrent && hasFutureAbove);

              // Check if this entry introduced a new hourly rate (different from previous/older entry)
              const previousEntry = index < entries.length - 1 ? entries[index + 1] : null;
              const wageChanged = previousEntry && snapshot.hourly_wage !== previousEntry.snapshot.hourly_wage;

              // Should this entry's wage be highlighted in blue?
              // - Never highlight future entries
              // - Highlight past entries that introduced the current wage (when current entry only changed settings)
              const shouldHighlightWage = !isFuture && !isCurrent && index === highlightedEntryIndex;

              // Filter out wage change from displayed changes (since we show wage as title when it changes)
              const nonWageChanges = changes.filter(c => !c.includes('kr/t'));

              return (
                <div
                  key={snapshot.id}
                  className={`relative ${isLast ? 'pb-0' : 'pb-4'}`}
                >
                  {/* Vertical line - full height solid for non-future, non-current */}
                  {/* For last entry, line stops at the dot (50%) instead of going to the bottom */}
                  {!isCurrent && !isFuture && (
                    <div className={`absolute left-0 top-0 w-0.5 bg-border z-5 ${isLast ? 'bottom-1/2' : 'bottom-0'}`} />
                  )}

                  {/* Future entry - fully dashed */}
                  {/* For last entry, line stops at the dot (50%) instead of going to the bottom */}
                  {isFuture && (
                    <div className={`absolute left-0 top-0 w-0.5 border-l-2 border-dashed border-border z-5 ${isLast ? 'bottom-1/2' : 'bottom-0'}`} />
                  )}

                  {/* Content wrapper - excludes bottom spacing */}
                  <div className="relative">
                    {/* Current wage background - full width, no border radius */}
                    {isCurrent && (
                      <div className="absolute inset-0 -left-6 -right-6 bg-wage-current z-1" />
                    )}

                    {/* Current entry lines - split at dot */}
                    {isCurrent && (
                      <>
                        {/* Line from top to dot - dashed if future above, solid otherwise */}
                        <div className={`absolute left-0 top-0 bottom-1/2 w-0.5 z-5 ${
                          hasFutureAbove
                            ? 'border-l-2 border-dashed border-border'
                            : 'bg-border'
                        }`} />
                        {/* Line from dot to bottom of content - always solid, but only if not last entry */}
                        {!isLast && (
                          <div className="absolute left-0 top-1/2 bottom-0 w-0.5 bg-border z-5" />
                        )}
                      </>
                    )}

                    {/* Line from bottom of content to next entry - only for current with spacing */}
                    {isCurrent && !isLast && (
                      <div className="absolute left-0 top-full h-4 w-0.5 bg-border z-5" />
                    )}

                    {/* Timeline dot - centered vertically within content */}
                    <div
                      className={`absolute z-20 rounded-full bg-brand-gradient-start border-2 left-px top-1/2 -translate-y-1/2 ${
                        isCurrent
                          ? 'w-5 h-5 -translate-x-1/2 border-surface-secondary'
                          : 'w-3 h-3 -translate-x-1/2 border-background'
                      }`}
                    />

                    {/* Content */}
                    <div
                      className={`relative pl-6 pr-0 ${
                        isCurrent ? 'py-4' : 'py-2'
                      } flex items-center justify-between gap-4 z-2`}
                    >
                    {/* Left: Wage info */}
                    <div className="flex-1 min-w-0">
                      {/* Title: wage rate OR change description */}
                      <div
                        className={`font-semibold ${
                          // Larger text for wage display, smaller for change descriptions
                          wageChanged || shouldHighlightWage || nonWageChanges.length === 0
                            ? (isCurrent ? 'text-2xl' : 'text-base')
                            : (isCurrent ? 'text-lg' : 'text-sm')
                        }`}
                      >
                        {wageChanged || shouldHighlightWage ? (
                          // Entry that introduced a rate - highlight in blue if it's the one that introduced the current wage
                          <span className={shouldHighlightWage ? 'text-blue-500' : 'text-text-primary'}>
                            {snapshot.hourly_wage.toFixed(2)} kr/t
                          </span>
                        ) : nonWageChanges.length > 0 ? (
                          // Entry that only changed settings - show the changes as title
                          <span className="text-text-primary">
                            {nonWageChanges.map((change, i) => (
                              <span key={i} className="block">{change}</span>
                            ))}
                          </span>
                        ) : (
                          // Fallback to wage if no changes detected (baseline or first entry)
                          <span className="text-text-primary">
                            {snapshot.hourly_wage.toFixed(2)} kr/t
                          </span>
                        )}
                      </div>

                      {/* Date range */}
                      <div className="text-text-secondary mt-1 text-sm">
                        {dateRange}
                      </div>
                    </div>

                    {/* Right: Edit button */}
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleEdit(snapshot)}
                      className="shrink-0 w-9 md:w-auto md:px-3"
                    >
                      <Pencil className="h-5 w-5 md:h-4 md:w-4 md:mr-2" />
                      <span className="hidden md:inline">
                        {t.pages.settings.pay.wageHistory.edit}
                      </span>
                    </Button>
                  </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </Card>

      {/* Tip box */}
      <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-4">
        <p className="text-sm text-blue-800 dark:text-blue-200">
          <strong>Tips:</strong> {t.pages.settings.pay.wageHistory.infoTip}
        </p>
      </div>

      {/* Modal */}
      <WageHistoryModal
        key={selectedSnapshot?.id || 'new'}
        isOpen={modalOpen}
        onClose={handleCloseModal}
        snapshot={selectedSnapshot}
        mode={modalMode}
        t={t}
        locale={locale}
        initialTariffVersion={initialTariffVersion}
      />
    </div>
  );
}
