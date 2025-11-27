"use client";

import { useState, useEffect } from "react";
import { ShiftWithComputations } from "@/lib/payroll";
import { Card, CardHeader } from "@/components/app/Card";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import {
  formatPlainAmount as formatPlainAmountValue,
  formatHours as formatHoursValue,
} from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { getDateFormatter } from "@/lib/i18n/locale";

type ShiftCardProps = {
  shift: ShiftWithComputations;
  onClick?: () => void;
  isToday?: boolean;
  /** Progress through the shift (0-100), shows a subtle progress bar when provided */
  progress?: number;
};

export function formatDateParts(date: string, locale: string, daysShort: readonly string[]) {
  const parsed = new Date(`${date}T00:00:00Z`);
  const weekday = parsed.getUTCDay();

  // Use Intl.DateTimeFormat for locale-aware date formatting (consistent with NextPayrollCard)
  const dateFormatter = getDateFormatter(locale, {
    day: "numeric",
    month: "long",
  });
  const dateLabel = dateFormatter.format(parsed);

  return {
    dayName: daysShort[weekday],
    dateLabel,
    isWeekend: weekday === 0 || weekday === 6,
  };
}

export function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

export function formatHours(value: number) {
  return formatHoursValue(value);
}

export function formatPlainAmount(value: number) {
  return formatPlainAmountValue(value);
}

export function ShiftCard({ shift, onClick, isToday = false, progress }: ShiftCardProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const { computed } = shift;
  const { dayName, dateLabel } = formatDateParts(shift.shift_date, locale, t.dateTime.daysShort);
  const { basePay, supplementPay, gross, paidHours } = computed;

  const breakdown = `${formatPlainAmount(basePay)}${supplementPay > 0 ? ` + ${formatPlainAmount(supplementPay)}` : ""}`;

  // Lowercase day names for Norwegian locale
  const displayDayName = locale === 'no' ? dayName.toLowerCase() : dayName;

  const isActive = typeof progress === 'number' && progress >= 0 && progress <= 100;

  // Animated progress state: starts at 0 and animates to actual progress
  const [animatedProgress, setAnimatedProgress] = useState(0);

  useEffect(() => {
    if (!isActive) {
      setAnimatedProgress(0);
      return;
    }

    // Use requestAnimationFrame to ensure we start from 0 before animating
    // This allows the CSS transition to animate smoothly from 0 to the actual value
    const frame = requestAnimationFrame(() => {
      setAnimatedProgress(progress ?? 0);
    });

    return () => cancelAnimationFrame(frame);
  }, [isActive, progress]);

  return (
    <Card
      className={cn(
        "bg-surface-primary rounded-3xl relative overflow-hidden",
        onClick && "cursor-pointer transition-colors hover:bg-surface-secondary",
        isToday && "ring-2 ring-brand-highlight"
      )}
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
    >
      {/* Progress bar background for active shifts - animates from 0 to current progress */}
      {isActive && (
        <div
          className="absolute inset-0 bg-brand-highlight/10 transition-[width] duration-1000 ease-linear"
          style={{ width: `${animatedProgress}%` }}
          aria-hidden="true"
        />
      )}
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6 relative z-10">
        <div className="space-y-1">
          <p className="text-lg font-medium text-text-primary">
            {dateLabel}
            <span className="text-text-muted"> · </span>
            <span className="text-text-secondary">
              {displayDayName}
            </span>
          </p>
          <div className="flex items-center gap-3 text-sm text-text-secondary">
            <span className="inline-flex items-center gap-1 text-text-primary">
              <svg
                aria-hidden="true"
                className="h-4 w-4 text-text-muted"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <circle cx="12" cy="12" r="9" />
                <path d="M12 7v5l3 2" />
              </svg>
              {formatTimeRange(shift.start_time, shift.end_time)}
            </span>
            <span className="text-text-muted">→</span>
            <span className="font-medium text-text-primary">{formatHours(paidHours)}</span>
          </div>
        </div>
        <div className="text-right">
          <p className="text-2xl font-semibold tracking-tight text-text-primary">
            {formatCurrency(gross)}
          </p>
          <p className="text-xs">{breakdown}</p>
        </div>
      </CardHeader>
    </Card>
  );
}

export default ShiftCard;
