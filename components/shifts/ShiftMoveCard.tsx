"use client";

import { KeyboardEvent, useMemo } from "react";
import { ShiftWithComputations, UserSettings, SupplementRule, computeShift } from "@/lib/payroll";
import { cn } from "@/lib/cn";
import {
  formatCurrency as baseFormatCurrency,
  formatPlainAmount as baseFormatPlainAmount,
  formatTimeRange as baseFormatTimeRange,
  formatHours as baseFormatHours,
} from "@/components/app/ShiftCard";
import { Card, CardHeader } from "@/components/app/Card";

const dayNumberFormatter = new Intl.DateTimeFormat("nb-NO", { day: "numeric" });
const monthFormatter = new Intl.DateTimeFormat("nb-NO", { month: "long" });
const dayFormatter = new Intl.DateTimeFormat("nb-NO", { weekday: "short" });

// Parse ISO date string consistently as UTC to avoid timezone issues
function parseISODate(isoDate: string): Date {
  return new Date(`${isoDate}T00:00:00Z`);
}

// Epsilon comparison for float values
function floatEquals(a: number, b: number, epsilon = 0.01): boolean {
  return Math.abs(a - b) <= epsilon;
}

type ShiftMoveCardProps = {
  shift: ShiftWithComputations;
  targetDate: string | null;
  selected: boolean;
  onToggle: (id: string) => void;
  userSettings: UserSettings;
  presetRules: SupplementRule[];
};

export function ShiftMoveCard({ shift, targetDate, selected, onToggle, userSettings, presetRules }: ShiftMoveCardProps) {
  const sourceDate = parseISODate(shift.shift_date);
  const target = targetDate ? parseISODate(targetDate) : null;

  // Format date parts
  const sourceDayNumber = dayNumberFormatter.format(sourceDate);
  const sourceMonth = monthFormatter.format(sourceDate);
  const sourceDayName = dayFormatter.format(sourceDate);

  const targetDayNumber = target ? dayNumberFormatter.format(target) : null;
  const targetMonth = target ? monthFormatter.format(target) : null;
  const targetDayName = target ? dayFormatter.format(target) : null;

  const sameMonth = target
    ? sourceDate.getUTCFullYear() === target.getUTCFullYear() &&
      sourceDate.getUTCMonth() === target.getUTCMonth()
    : true;

  const isDifferentWeekday = targetDayName && sourceDayName !== targetDayName;

  // Calculate what the wage would be on the target date - memoized for performance
  const { computed: originalComputed } = shift;
  const { basePay, supplementPay, gross: originalGross, paidHours } = originalComputed;

  const { newGross, wageChanged, grossDifference } = useMemo(() => {
    if (!target || !targetDate) {
      return {
        newGross: originalGross,
        wageChanged: false,
        grossDifference: 0,
      };
    }

    // Create a temporary shift with the target date to recalculate wages
    const tempShift = {
      ...shift,
      shift_date: targetDate,
    };
    const newComputed = computeShift(tempShift, userSettings, presetRules);
    const gross = newComputed.gross;
    const changed = !floatEquals(gross, originalGross);

    return {
      newGross: gross,
      wageChanged: changed,
      grossDifference: gross - originalGross,
    };
  }, [target, targetDate, shift, userSettings, presetRules, originalGross]);

  const normalBreakdown = `${baseFormatPlainAmount(basePay)}${supplementPay > 0 ? ` + ${baseFormatPlainAmount(supplementPay)}` : ""}`;

  const handleToggle = () => onToggle(shift.id);
  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === " " || event.key === "Spacebar" || event.key === "Enter") {
      event.preventDefault();
      handleToggle();
    }
  };

  return (
    <Card
      role="switch"
      aria-checked={selected}
      tabIndex={0}
      onClick={handleToggle}
      onKeyDown={handleKeyDown}
      className={cn(
        "rounded-3xl cursor-pointer transition-colors",
        selected
          ? "border-border-strong bg-surface-primary shadow-app-sm"
          : "hover:bg-surface-secondary"
      )}
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          <p className="text-lg font-medium text-text-primary">
            <span className="line-through">{sourceDayNumber}</span>
            {targetDayNumber && (
              <span className="text-brand-highlight"> {targetDayNumber}</span>
            )}
            {" "}
            <span className={!sameMonth ? "text-brand-highlight" : ""}>
              {sameMonth ? sourceMonth : targetMonth}
            </span>
            <span className="text-text-muted"> · </span>
            <span className={isDifferentWeekday ? "text-brand-highlight" : "text-text-secondary"}>
              {targetDayName || sourceDayName}
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
              {baseFormatTimeRange(shift.start_time, shift.end_time)}
            </span>
            <span className="text-text-muted">→</span>
            <span className="font-medium text-text-primary">{baseFormatHours(paidHours)}</span>
          </div>
        </div>
        <div className="text-right">
          <p className={cn(
            "text-2xl font-semibold tracking-tight",
            wageChanged ? "text-brand-highlight" : "text-text-primary"
          )}>
            {baseFormatCurrency(wageChanged ? newGross : originalGross)}
          </p>
          {wageChanged ? (
            <p className="text-xs text-text-secondary">
              {baseFormatPlainAmount(originalGross)}{" "}
              <span className="text-brand-highlight">
                {grossDifference >= 0 ? '+' : ''}{baseFormatPlainAmount(grossDifference)}
              </span>
            </p>
          ) : (
            <p className="text-xs text-text-secondary">
              {normalBreakdown}
            </p>
          )}
        </div>
      </CardHeader>
    </Card>
  );
}

export default ShiftMoveCard;
