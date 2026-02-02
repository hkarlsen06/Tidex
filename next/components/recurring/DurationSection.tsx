"use client";

import { useState } from "react";
import type { EndCondition } from "@/lib/recurring/types";
import { Input } from "@/components/app/Input";
import { cn } from "@/lib/utils";
import { useTranslations } from "@/lib/i18n/client";
import { getTodayAsDateString } from "@/lib/date-utils";

export type DurationSectionProps = {
  /** Current end condition value */
  value: EndCondition;
  /** Callback when end condition changes */
  onChange: (value: EndCondition) => void;
  /** Optional className for container */
  className?: string;
};

/**
 * DurationSection component
 *
 * Allows users to select the end condition for a recurring shift:
 * - No End (null)
 * - X Months
 * - X Years
 * - Specific End Date
 */
export function DurationSection({ value, onChange, className }: DurationSectionProps) {
  const { t } = useTranslations();

  // Local state for input values
  const [monthsValue, setMonthsValue] = useState(
    value?.type === 'months' ? String(value.value) : '6'
  );
  const [yearsValue, setYearsValue] = useState(
    value?.type === 'years' ? String(value.value) : '1'
  );
  const [endDateValue, setEndDateValue] = useState(() => {
    // Handle both newer 'date' format and legacy 'value' format
    if (value?.type === 'end_date') {
      return 'date' in value ? value.date : value.value;
    }
    // Default to 6 months from now
    const sixMonthsAhead = new Date();
    sixMonthsAhead.setMonth(sixMonthsAhead.getMonth() + 6);
    return getTodayAsDateString();
  });

  const activeType = value?.type ?? 'no_end';

  const handleSelectNoEnd = () => {
    onChange(null);
  };

  const handleSelectMonths = () => {
    onChange({ type: 'months', value: parseInt(monthsValue, 10) || 6 });
  };

  const handleSelectYears = () => {
    onChange({ type: 'years', value: parseInt(yearsValue, 10) || 1 });
  };

  const handleSelectEndDate = () => {
    onChange({
      type: 'end_date',
      date: endDateValue,
      end_time: '23:59', // Default to end of day
    });
  };

  const handleMonthsChange = (val: string) => {
    setMonthsValue(val);
    if (activeType === 'months' && /^\d+$/.test(val)) {
      const num = parseInt(val, 10);
      if (num >= 1 && num <= 120) {
        onChange({ type: 'months', value: num });
      }
    }
  };

  const handleYearsChange = (val: string) => {
    setYearsValue(val);
    if (activeType === 'years' && /^\d+$/.test(val)) {
      const num = parseInt(val, 10);
      if (num >= 1 && num <= 10) {
        onChange({ type: 'years', value: num });
      }
    }
  };

  const handleEndDateChange = (val: string) => {
    setEndDateValue(val);
    if (activeType === 'end_date') {
      onChange({ type: 'end_date', date: val, end_time: '23:59' });
    }
  };

  const fieldWrapperClass = (isActive: boolean) =>
    cn(
      "rounded-xl border px-4 py-3 transition-all",
      isActive
        ? "border-brand-gradient-mid bg-brand-gradient-mid/10"
        : "border-border-subtle bg-surface-secondary/70 hover:border-border"
    );

  return (
    <div className={cn("space-y-3", className)}>
      <span className="text-xs font-semibold uppercase tracking-widest text-text-muted">
        {t.pages.shifts.add.recurring.duration}
      </span>

      {/* Top: No End */}
      <button
        type="button"
        onClick={handleSelectNoEnd}
        className={cn(
          "flex w-full items-center justify-center rounded-xl border px-4 py-3 text-center transition-all",
          activeType === 'no_end'
            ? "border-brand-gradient-mid bg-brand-gradient-mid/10 text-text-primary"
            : "border-border-subtle bg-surface-secondary/70 text-text-secondary hover:border-border hover:text-text-primary"
        )}
      >
        <span className="text-base font-medium">{t.pages.shifts.add.recurring.noEnd}</span>
      </button>

      {/* Middle: Months and Years */}
      <div className="flex gap-3">
        {/* Months */}
        <button
          type="button"
          onClick={handleSelectMonths}
          className={cn(
            "flex flex-1 items-center justify-center gap-2 rounded-xl border px-4 py-3 text-center transition-all",
            activeType === 'months'
              ? "border-brand-gradient-mid bg-brand-gradient-mid/10 text-text-primary"
              : "border-border-subtle bg-surface-secondary/70 text-text-secondary hover:border-border hover:text-text-primary"
          )}
        >
          <Input
            type="number"
            min={1}
            max={120}
            value={monthsValue}
            onChange={(e) => handleMonthsChange(e.target.value)}
            onBlur={() => {
              if (monthsValue === '' || parseInt(monthsValue, 10) < 1) {
                setMonthsValue('6');
                if (activeType === 'months') onChange({ type: 'months', value: 6 });
              }
            }}
            onClick={(e) => {
              e.stopPropagation();
              handleSelectMonths();
            }}
            className="h-9 w-16 rounded-lg border-border-subtle bg-surface-primary text-center text-base text-text-primary"
          />
          <span className="text-base font-medium">{t.pages.shifts.add.recurring.months}</span>
        </button>

        {/* Years */}
        <button
          type="button"
          onClick={handleSelectYears}
          className={cn(
            "flex flex-1 items-center justify-center gap-2 rounded-xl border px-4 py-3 text-center transition-all",
            activeType === 'years'
              ? "border-brand-gradient-mid bg-brand-gradient-mid/10 text-text-primary"
              : "border-border-subtle bg-surface-secondary/70 text-text-secondary hover:border-border hover:text-text-primary"
          )}
        >
          <Input
            type="number"
            min={1}
            max={10}
            value={yearsValue}
            onChange={(e) => handleYearsChange(e.target.value)}
            onBlur={() => {
              if (yearsValue === '' || parseInt(yearsValue, 10) < 1) {
                setYearsValue('1');
                if (activeType === 'years') onChange({ type: 'years', value: 1 });
              }
            }}
            onClick={(e) => {
              e.stopPropagation();
              handleSelectYears();
            }}
            className="h-9 w-16 rounded-lg border-border-subtle bg-surface-primary text-center text-base text-text-primary"
          />
          <span className="text-base font-medium">{t.pages.shifts.add.recurring.years}</span>
        </button>
      </div>

      {/* Bottom: End Date */}
      <div className={fieldWrapperClass(activeType === 'end_date')}>
        <div className="mb-2">
          <span
            className={cn(
              "text-base font-medium",
              activeType === 'end_date' ? "text-text-primary" : "text-text-secondary"
            )}
          >
            {t.pages.shifts.add.recurring.endDate}
          </span>
        </div>
        <Input
          type="date"
          value={endDateValue}
          onChange={(e) => handleEndDateChange(e.target.value)}
          onFocus={handleSelectEndDate}
          className="h-10 rounded-xl border-border-subtle bg-surface-primary text-base text-text-primary"
        />
      </div>
    </div>
  );
}
