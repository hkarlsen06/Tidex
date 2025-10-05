import { ShiftWithComputations } from "@/lib/payroll";
import { Card, CardHeader, CardContent } from "@/components/app/Card";

type ShiftCardProps = {
  shift: ShiftWithComputations;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const hoursFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const dayFormatter = new Intl.DateTimeFormat("nb-NO", {
  weekday: "long",
});

const dateFormatter = new Intl.DateTimeFormat("nb-NO", {
  day: "numeric",
  month: "long",
});

function formatDateParts(date: string) {
  const parsed = new Date(`${date}T00:00:00Z`);
  return {
    dayName: dayFormatter.format(parsed),
    dateLabel: dateFormatter.format(parsed),
  };
}

function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

function formatHours(value: number) {
  return `${hoursFormatter.format(value)}t`;
}

function formatCurrency(value: number) {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

function formatPlainAmount(value: number) {
  return numberFormatter.format(Math.round(value));
}

export function ShiftCard({ shift }: ShiftCardProps) {
  const { computed } = shift;
  const { dayName, dateLabel } = formatDateParts(shift.shift_date);
  const { basePay, bonusPay, gross, paidHours } = computed;

  const breakdown = `${formatPlainAmount(basePay)}${bonusPay > 0 ? ` + ${formatPlainAmount(bonusPay)}` : ""}`;
  const isWeekend = dayName === "lørdag" || dayName === "søndag";

  return (
    <Card className="rounded-[28px]">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 pb-3">
        <div className="space-y-1">
          <p className="text-lg font-medium capitalize text-text-primary">
            {dateLabel}
            <span className="text-text-muted"> · </span>
            <span className={`capitalize ${isWeekend ? "text-brand-highlight" : "text-text-secondary"}`}>
              {dayName}
            </span>
          </p>
          <div className="flex items-center gap-3 text-sm text-text-secondary">
            <span className="inline-flex items-center gap-1 rounded-full bg-surface-secondary/70 px-3 py-1 text-text-primary">
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
