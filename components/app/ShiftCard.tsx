"use client";

import type React from "react";
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
import { useCurrency } from "@/components/providers/CurrencyProvider";

export type TaxSettings = {
  enabled: boolean;
  percentage: number;
  halfTaxMonth?: number | null;
};

type ShiftCardProps = {
  shift: ShiftWithComputations;
  onClick?: () => void;
  isToday?: boolean;
  /** Progress through the shift (0-100), shows a subtle progress bar when provided */
  progress?: number;
  /** Tax settings for displaying net earnings */
  taxSettings?: TaxSettings;
  /** When false, hides earnings-related data (for shared shifts with earnings hidden) */
  showEarnings?: boolean;
};

export function formatDateParts(date: string, locale: string, daysShort: readonly string[]) {
  const parsed = new Date(`${date}T00:00:00Z`);
  const weekday = parsed.getUTCDay();

  // Use Intl.DateTimeFormat for locale-aware date formatting
  const dayFormatter = getDateFormatter(locale, { day: "numeric" });
  const monthFormatter = getDateFormatter(locale, { month: "long" });

  const dayNumber = dayFormatter.format(parsed);
  const monthName = monthFormatter.format(parsed);

  return {
    dayName: daysShort[weekday],
    dayNumber,
    monthName,
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

export function ShiftCard({ shift, onClick, isToday = false, progress, taxSettings, showEarnings = true }: ShiftCardProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const { symbol: currencySymbol, display: currencyDisplay } = useCurrency();
  const { computed } = shift;
  const { dayName, dayNumber, monthName } = formatDateParts(shift.shift_date, locale, t.dateTime.daysShort);
  const { basePay, supplementPay, gross, paidHours } = computed;

  // Calculate tax for this shift
  const taxEnabled = taxSettings?.enabled ?? false;
  let taxPercentage = taxEnabled ? Number(taxSettings?.percentage ?? 0) : 0;

  // Check for half tax month
  const shiftMonth = parseInt(shift.shift_date.substring(5, 7), 10);
  if (taxEnabled && taxSettings?.halfTaxMonth && shiftMonth === taxSettings.halfTaxMonth) {
    taxPercentage = taxPercentage / 2;
  }

  const taxAmount = taxEnabled ? gross * (taxPercentage / 100) : 0;
  const netAmount = gross - taxAmount;

  // Show different breakdown based on tax settings
  const displayAmount = taxEnabled ? netAmount : gross;
  const breakdown = taxEnabled
    ? `${formatPlainAmount(gross)} − ${formatPlainAmount(taxAmount)}`
    : `${formatPlainAmount(basePay)}${supplementPay > 0 ? ` + ${formatPlainAmount(supplementPay)}` : ""}`;

  const isActive = typeof progress === 'number' && progress >= 0 && progress <= 100;

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
      {/* Progress bar background for active shifts - uses CSS animation to animate from 0 to current progress */}
      {isActive && (
        <div
          className="absolute inset-0 bg-brand-highlight/10 animate-progress-grow"
          style={{ '--progress-target': `${progress}%` } as React.CSSProperties}
          aria-hidden="true"
        />
      )}
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6 relative z-10">
        <div className="space-y-1">
          <p className="text-lg font-medium text-text-primary">
            {dayName} · {dayNumber}{" "}
            <span className="text-text-muted">{monthName}</span>
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
          {showEarnings ? (
            <>
              <p className="text-2xl font-semibold tracking-tight text-text-primary">
                {formatCurrency(displayAmount)}
              </p>
              <p className="text-xs">{breakdown}</p>
            </>
          ) : (
            <>
              <p className="text-2xl font-semibold tracking-tight text-text-muted">
                {currencyDisplay === "prefix" ? `${currencySymbol}——` : `—— ${currencySymbol}`}
              </p>
              <p className="text-xs text-text-muted">——</p>
            </>
          )}
        </div>
      </CardHeader>
    </Card>
  );
}

export default ShiftCard;
