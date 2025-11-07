"use client";

import { Card, CardHeader } from "@/components/app/Card";
import { useTranslations } from "@/lib/i18n/client";
import { getDateFormatter } from "@/lib/i18n/locale";

/**
 * TodayPlaceholderCard - Shows today's date when no shifts exist for today
 *
 * Visually matches ShiftCard styling but shows placeholder dashes for earnings.
 * Appears in chronological position within the shifts list.
 */
export function TodayPlaceholderCard() {
  const { t, locale } = useTranslations();

  // Get today's date in local timezone
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  const todayDateString = `${year}-${month}-${day}`;

  // Parse and format the date (same as ShiftCard)
  // Use local time parsing (not UTC) to match shift_date format
  const parsed = new Date(todayDateString);
  const weekday = parsed.getDay();

  const dateFormatter = getDateFormatter(locale, {
    day: "numeric",
    month: "long",
  });
  const dateLabel = dateFormatter.format(parsed);

  const dayName = t.dateTime.daysShort[weekday];
  const displayDayName = locale === 'no' ? dayName.toLowerCase() : dayName;

  return (
    <Card
      className="bg-surface-primary rounded-3xl ring-2 ring-brand-highlight"
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-4">
        <div>
          <p className="text-lg font-medium text-text-muted">
            {dateLabel}
            <span className="text-text-muted"> · </span>
            <span className="text-text-muted">
              {displayDayName}
            </span>
          </p>
        </div>
        <div className="text-right">
          <p className="text-2xl font-semibold tracking-tight text-text-muted">
            —— kr
          </p>
        </div>
      </CardHeader>
    </Card>
  );
}
