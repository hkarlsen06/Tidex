'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { IconPlus, IconEdit } from '@tabler/icons-react';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface WageHistoryTimelineProps {
  snapshots: WageSnapshot[];
  t: Dictionary;
}

interface TimelineEntry {
  snapshot: WageSnapshot;
  type: 'future' | 'current' | 'past';
  dateRange: string;
  endDate: string | null;
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
 * Categorize snapshots into timeline entries
 */
function categorizeSnapshots(snapshots: WageSnapshot[], nowText: string, locale: string): TimelineEntry[] {
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
  const currentEntry = entriesWithTypes.find(e => e.type === 'current');
  const hasFutureEntries = entriesWithTypes.some(e => e.type === 'future');

  // Second pass: format date ranges
  return entriesWithTypes.map((entry) => {
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

    return {
      snapshot,
      type,
      dateRange: formatDateRange(fromDate, displayEndDate, nowText, locale, isPast),
      endDate,
    };
  });
}

export function WageHistoryTimeline({
  snapshots,
  t,
}: WageHistoryTimelineProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState<'create' | 'edit'>('create');
  const [selectedSnapshot, setSelectedSnapshot] = useState<WageSnapshot | null>(null);

  const locale = t.common.currency === 'kr' ? 'no-NO' : 'en-US';
  const nowText = t.pages.settings.pay.wageHistory.now;

  const handleAddNew = () => {
    setSelectedSnapshot(null);
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
  const entries = categorizeSnapshots(snapshots, nowText, locale);

  // Find current entry index
  const currentIndex = entries.findIndex(e => e.type === 'current');
  const hasFutureEntries = entries.some(e => e.type === 'future');

  return (
    <div className="space-y-6">
      {/* Timeline Card */}
      <Card className="overflow-hidden">
        {/* Header */}
        <div className="p-6 pb-4 flex items-center justify-between">
          <h3 className="text-lg font-semibold text-text-primary">
            {t.pages.settings.pay.wageHistory.timelineTitle}
          </h3>
          <Button onClick={handleAddNew} variant="outline" size="sm">
            <IconPlus className="h-4 w-4 mr-2" />
            {t.pages.settings.pay.wageHistory.addNew}
          </Button>
        </div>

        {/* Timeline */}
        <div className="relative px-6 pb-6">
          {/* Timeline entries */}
          <div className="space-y-0 relative">
            {entries.map((entry, index) => {
              const { snapshot, type, dateRange } = entry;
              const isCurrent = type === 'current';
              const isFuture = type === 'future';
              const isPast = type === 'past';
              const supplementCount = snapshot.supplements?.rules?.length || 0;
              const isLast = index === entries.length - 1;
              // Check if any previous entry (index < current) is future
              const hasFutureAbove = entries.slice(0, index).some(e => e.type === 'future');
              // Only show dashed line for future entries and current entry if there's a future above
              const shouldBeDashed = isFuture || (isCurrent && hasFutureAbove);

              return (
                <div
                  key={snapshot.id}
                  className={`relative ${isLast ? 'pb-0' : 'pb-4'}`}
                >
                  {/* Vertical line - full height solid for non-future, non-current */}
                  {!isCurrent && !isFuture && (
                    <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-border z-[5]" />
                  )}

                  {/* Future entry - fully dashed */}
                  {isFuture && (
                    <div className="absolute left-0 top-0 bottom-0 w-0.5 border-l-2 border-dashed border-border z-[5]" />
                  )}

                  {/* Content wrapper - excludes bottom spacing */}
                  <div className="relative">
                    {/* Current wage background - full width, no border radius */}
                    {isCurrent && (
                      <div className="absolute inset-0 -left-6 -right-6 bg-wage-current z-[1]" />
                    )}

                    {/* Current entry lines - split at dot */}
                    {isCurrent && (
                      <>
                        {/* Line from top to dot - dashed if future above, solid otherwise */}
                        <div className={`absolute left-0 top-0 bottom-1/2 w-0.5 z-[5] ${
                          hasFutureAbove
                            ? 'border-l-2 border-dashed border-border'
                            : 'bg-border'
                        }`} />
                        {/* Line from dot to bottom of content - always solid */}
                        <div className="absolute left-0 top-1/2 bottom-0 w-0.5 bg-border z-[5]" />
                      </>
                    )}

                    {/* Line from bottom of content to next entry - only for current with spacing */}
                    {isCurrent && !isLast && (
                      <div className="absolute left-0 top-full h-4 w-0.5 bg-border z-[5]" />
                    )}

                    {/* Timeline dot - centered vertically within content */}
                    <div
                      className={`absolute z-20 rounded-full bg-brand-gradientStart border-2 left-[1px] top-1/2 -translate-y-1/2 ${
                        isCurrent
                          ? 'w-5 h-5 -translate-x-1/2 border-surface-secondary'
                          : 'w-3 h-3 -translate-x-1/2 border-background'
                      }`}
                    />

                    {/* Content */}
                    <div
                      className={`relative pl-6 pr-2 ${
                        isCurrent ? 'py-4' : 'py-2'
                      } flex items-center justify-between gap-4 z-[2]`}
                    >
                    {/* Left: Wage info */}
                    <div className="flex-1 min-w-0">
                      {/* Wage rate + supplements */}
                      <div
                        className={`font-semibold text-text-primary ${
                          isCurrent ? 'text-2xl' : 'text-base'
                        }`}
                      >
                        {snapshot.hourly_wage.toFixed(2)} kr/t
                        {!isCurrent && supplementCount > 0 && (
                          <span className="text-text-secondary">
                            {' '}
                            •{' '}
                            {t.pages.settings.pay.wageHistory.supplementsCountShort.replace(
                              '{count}',
                              String(supplementCount)
                            )}
                          </span>
                        )}
                      </div>

                      {/* Date range */}
                      <div
                        className="text-text-secondary mt-1 text-sm pl-[1ch]"
                      >
                        {dateRange}
                      </div>
                    </div>

                    {/* Right: Edit button */}
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleEdit(snapshot)}
                      className="flex-shrink-0"
                    >
                      <IconEdit className="h-4 w-4 mr-2" />
                      {t.pages.settings.pay.wageHistory.edit}
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
      />
    </div>
  );
}
