"use client";

import { useRouter } from "next/navigation";
import { Card, CardHeader } from "@/components/app/Card";
import { useTranslations, useLocale } from "@/lib/i18n/client";
import { getDateFormatter } from "@/lib/i18n/locale";
import { useCurrency } from "@/components/providers/CurrencyProvider";

/**
 * TodayPlaceholderCard - Shows today's date when no shifts exist for today
 *
 * Visually matches ShiftCard styling but shows placeholder dashes for earnings.
 * Appears in chronological position within the shifts list.
 * Clicking navigates to /shifts/add with today's date pre-selected.
 */
export function TodayPlaceholderCard() {
  const { t } = useTranslations();
  const locale = useLocale();
  const router = useRouter();
  const { symbol: currencySymbol, display: currencyDisplay } = useCurrency();

  // Get today's date in local timezone
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  const todayDateString = `${year}-${month}-${day}`;

  // Parse and format the date (same as ShiftCard)
  const parsed = new Date(`${todayDateString}T00:00:00Z`);
  const weekday = parsed.getUTCDay();

  const dateFormatter = getDateFormatter(locale, {
    day: "numeric",
    month: "long",
  });
  const dateLabel = dateFormatter.format(parsed);

  const dayName = t.dateTime.daysShort[weekday];

  const handleClick = () => {
    router.push(`/${locale}/shifts/add?date=${todayDateString}`);
  };

  return (
    <Card
      className="bg-surface-primary rounded-3xl ring-2 ring-brand-highlight cursor-pointer transition-colors hover:bg-surface-secondary"
      onClick={handleClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          handleClick();
        }
      }}
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-4">
        <div>
          <p className="text-lg font-medium text-text-muted">
            <span className="text-text-muted">
              {dayName}
            </span>
            <span className="text-text-muted"> · </span>
            {dateLabel}
          </p>
        </div>
        <div className="text-right">
          <p className="text-2xl font-semibold tracking-tight text-text-muted">
            {currencyDisplay === "prefix" ? `${currencySymbol}——` : `—— ${currencySymbol}`}
          </p>
        </div>
      </CardHeader>
    </Card>
  );
}
