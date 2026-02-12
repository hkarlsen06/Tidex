"use client";

import type { ReactNode } from "react";
import type { CustomSupplementsData } from "@/lib/payroll/types";
import { useTranslations } from "@/lib/i18n/client";
import { formatHours } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";

const MINUTES_PER_DAY = 24 * 60;

function timeToMinutes(time: string): number | null {
  if (!time) return null;
  const [hh, mm] = time.split(":").map((part) => Number.parseInt(part, 10));
  if (Number.isNaN(hh) || Number.isNaN(mm)) return null;
  if (hh === 24 && mm === 0) return MINUTES_PER_DAY;
  if (hh < 0 || mm < 0 || mm >= 60 || hh > 24) return null;
  return hh * 60 + mm;
}

function minutesToDisplay(minutes: number): string {
  const offset = minutes >= 0 ? Math.floor(minutes / MINUTES_PER_DAY) : Math.ceil((minutes - MINUTES_PER_DAY + 1) / MINUTES_PER_DAY);
  const remainder = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;

  const isFullDay = remainder === 0 && minutes !== 0;
  const hours = isFullDay ? 24 : Math.floor(remainder / 60);
  const mins = isFullDay ? 0 : remainder % 60;
  const base = `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
  if (offset > 0) return `${base} (+${offset})`;
  if (offset < 0) return `${base} (${offset})`;
  return base;
}

export type SupplementSegmentInput = {
  from: string;
  to: string;
  dayOffset?: number;
  rate?: number | null;
  percent?: number | null;
  actualHours?: number; // Pre-computed paid hours (after break deduction)
  note?: ReactNode;
};

type SupplementBreakdownProps = {
  baseWage: number;
  segments: SupplementSegmentInput[];
  customSupplements?: CustomSupplementsData | null;
};

type SupplementRow = {
  period: string;
  hours: number;
  rate: number;
  amount: number;
  note?: ReactNode;
};

function computeRows({ baseWage, segments }: SupplementBreakdownProps) {
  const rows: SupplementRow[] = [];

  for (const segment of segments) {
    const segStartRaw = timeToMinutes(segment.from);
    const segEndRaw = timeToMinutes(segment.to);
    if (segStartRaw == null || segEndRaw == null) continue;

    const offsetMinutes = (segment.dayOffset ?? 0) * MINUTES_PER_DAY;
    const segStart = segStartRaw + offsetMinutes;
    let segEnd = segEndRaw + offsetMinutes;
    if (segEnd <= segStart) {
      segEnd += MINUTES_PER_DAY;
    }

    const rate = segment.rate ?? ((segment.percent ?? 0) / 100) * baseWage;
    if (rate <= 0) continue;

    // Use pre-computed actualHours if available (accounts for break deductions)
    // Otherwise fall back to calculating from segment boundaries
    const hours = segment.actualHours ?? 0;
    if (hours <= 0) continue;

    const amount = hours * rate;

    rows.push({
      period: `${minutesToDisplay(segStart)} – ${minutesToDisplay(segEnd)}`,
      hours,
      rate,
      amount,
      note: segment.note,
    });
  }

  return rows;
}

export function SupplementBreakdown(props: SupplementBreakdownProps) {
  const { t } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const rows = computeRows(props);
  if (rows.length === 0) return null;

  const total = rows.reduce((sum, row) => sum + row.amount, 0);
  const hasCustomSupplements = props.customSupplements != null;

  return (
    <>
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <div className="text-sm text-text-secondary">{t.pages.shifts.details.totalSupplement}</div>
          {hasCustomSupplements && (
            <span className="inline-flex items-center rounded-full bg-blue-100 dark:bg-blue-900/30 px-2 py-0.5 text-xs font-medium text-blue-800 dark:text-blue-300">
              {t.pages.shifts.details.customized}
            </span>
          )}
        </div>
        <div className="text-base font-medium text-text-primary">
          {formatCurrency(total)}
        </div>
      </div>
      <div className="space-y-2">
        {rows.map((row, index) => (
          <div
            key={`${row.period}-${index}`}
            className="space-y-1 rounded-xl bg-surface-secondary/40 p-3"
          >
            <div className="flex items-center justify-between text-sm text-text-primary">
              <span>{row.period.replace("23:59", "24:00")}</span>
              <span>
                {formatHours(row.hours)} × {formatCurrency(row.rate)}
              </span>
            </div>
            <div className="flex items-center justify-between text-sm font-semibold text-text-primary">
              <span>{t.pages.shifts.details.supplement}</span>
              <span>{formatCurrency(row.amount)}</span>
            </div>
            {row.note ? (
              <div className="text-xs text-text-secondary">{row.note}</div>
            ) : null}
          </div>
        ))}
      </div>
    </>
  );
}

export default SupplementBreakdown;
