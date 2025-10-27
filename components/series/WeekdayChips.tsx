"use client";

import type { SelectedDays } from "@/lib/series/types";
import { formatWeekdayShort } from "@/lib/series/utils";
import { cn } from "@/lib/utils";
import { useLocale } from "@/lib/i18n/client";

export type WeekdayChipsProps = {
  /** Selected anchor dates by weekday */
  selected: SelectedDays;
  /** Callback when user clicks to remove a weekday */
  onRemove: (weekday: '0' | '1' | '2' | '3' | '4' | '5' | '6') => void;
  /** Optional className for container */
  className?: string;
};

/**
 * WeekdayChips component
 *
 * Displays 7 chips (Mon-Sun) showing which weekdays are selected.
 * Active chips are clickable to remove the anchor.
 * Inactive chips are grayed out and not clickable.
 */
export function WeekdayChips({ selected, onRemove, className }: WeekdayChipsProps) {
  const locale = useLocale();

  // Weekdays in calendar order: Mon-Sun
  const weekdayKeys: Array<'0' | '1' | '2' | '3' | '4' | '5' | '6'> = ['1', '2', '3', '4', '5', '6', '0'];

  return (
    <div className={cn("flex items-center justify-between gap-2", className)}>
      {weekdayKeys.map((weekdayKey) => {
        const isSelected = selected[weekdayKey] !== undefined;
        const label = formatWeekdayShort(weekdayKey, locale);

        return (
          <button
            key={weekdayKey}
            type="button"
            onClick={() => isSelected && onRemove(weekdayKey)}
            disabled={!isSelected}
            className={cn(
              "flex h-9 flex-1 items-center justify-center rounded-xl px-3 text-sm font-semibold transition-all",
              "border focus:outline-none focus-visible:outline-none",
              isSelected
                ? "border-brand-highlight bg-brand-gradientStart text-text-inverse shadow-app hover:bg-brand-gradientMid cursor-pointer"
                : "border-border-subtle bg-surface-secondary/50 text-text-muted cursor-not-allowed opacity-60"
            )}
            title={
              isSelected
                ? `Click to remove ${formatWeekdayShort(weekdayKey, locale)}`
                : formatWeekdayShort(weekdayKey, locale)
            }
          >
            {label}
          </button>
        );
      })}
    </div>
  );
}
