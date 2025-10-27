"use client";

import { ShiftWithComputations } from "@/lib/payroll";
import { Card, CardHeader } from "@/components/app/Card";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";

type ShiftCardProps = {
  shift: ShiftWithComputations;
  onClick?: () => void;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const hoursFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

// Map our locale codes to BCP 47 locale tags for Intl.DateTimeFormat
function getDateLocale(locale: string): string {
  const localeMap: Record<string, string> = {
    no: 'nb-NO',
    en: 'en-US',
    de: 'de-DE',
  };
  return localeMap[locale] || 'en-US';
}

export function formatDateParts(date: string, locale: string, daysShort: readonly string[]) {
  const parsed = new Date(`${date}T00:00:00Z`);
  const weekday = parsed.getUTCDay();

  // Use Intl.DateTimeFormat for locale-aware date formatting (consistent with NextPayrollCard)
  const dateFormatter = new Intl.DateTimeFormat(getDateLocale(locale), {
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
  return `${hoursFormatter.format(value)}t`;
}

export function formatCurrency(value: number) {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

export function formatPlainAmount(value: number) {
  return numberFormatter.format(Math.round(value));
}

export function ShiftCard({ shift, onClick }: ShiftCardProps) {
  const { t, locale } = useTranslations();
  const { computed } = shift;
  const { dayName, dateLabel } = formatDateParts(shift.shift_date, locale, t.dateTime.daysShort);
  const { basePay, supplementPay, gross, paidHours } = computed;

  const breakdown = `${formatPlainAmount(basePay)}${supplementPay > 0 ? ` + ${formatPlainAmount(supplementPay)}` : ""}`;

  return (
    <Card
      className={cn(
        "rounded-3xl",
        onClick && "cursor-pointer transition-colors hover:bg-surface-secondary"
      )}
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          <p className="text-lg font-medium text-text-primary">
            {dateLabel}
            <span className="text-text-muted"> · </span>
            <span className="text-text-secondary">
              {dayName}
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
