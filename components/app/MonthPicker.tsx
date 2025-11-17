"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslations } from "@/lib/i18n/client";

type MonthPickerProps = {
  month: Date;
  onPreviousMonth: () => void;
  onNextMonth: () => void;
  canNavigateToPreviousMonth?: boolean;
  canNavigateToNextMonth?: boolean;
};

function formatMonth(date: Date, monthsFull: readonly string[]): string {
  const monthIndex = date.getMonth();
  const monthName = monthsFull[monthIndex];
  // Capitalize first letter in JS to avoid CSS capitalize issues during animation
  return monthName.charAt(0).toUpperCase() + monthName.slice(1);
}

export function MonthPicker({
  month,
  onPreviousMonth,
  onNextMonth,
  canNavigateToPreviousMonth = true,
  canNavigateToNextMonth = true,
}: MonthPickerProps) {
  const { t } = useTranslations();
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [prevMonth, setPrevMonth] = useState(month);
  const [direction, setDirection] = useState<"forward" | "backward">("forward");

  // Track month changes for animation transitions
  useEffect(() => {
    if (month.getTime() !== prevMonth.getTime()) {
      // Determine direction based on month comparison
      const isForward = month > prevMonth;
      // Note: These setState calls are intentional to trigger animation state changes when month prop changes
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDirection(isForward ? "forward" : "backward");
      setIsTransitioning(true);
    }
  }, [month, prevMonth]);

  const handleExitAnimationEnd = () => {
    setPrevMonth(month);
  };

  const handleEnterAnimationEnd = () => {
    setIsTransitioning(false);
  };

  const handlePreviousMonth = () => {
    onPreviousMonth();
  };

  const handleNextMonth = () => {
    onNextMonth();
  };

  const exitAnimation = direction === "forward"
    ? "animate-[swipe-out-left_0.4s_ease-in-out]"
    : "animate-[swipe-out-right_0.4s_ease-in-out]";

  const enterAnimation = direction === "forward"
    ? "animate-[swipe-in-right_0.4s_ease-in-out]"
    : "animate-[swipe-in-left_0.4s_ease-in-out]";

  return (
    <div className="flex items-center gap-1">
      <button
        onClick={handlePreviousMonth}
        disabled={!canNavigateToPreviousMonth}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-hidden focus-visible:outline-hidden disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Forrige måned"
      >
        <ChevronLeft size={18} />
      </button>
      <div className="relative w-24 overflow-hidden" style={{ minHeight: '1.5rem' }}>
        {/* Current/Previous month - exits when transitioning */}
        <div
          className={`absolute inset-0 text-center font-medium text-text-primary ${
            isTransitioning ? exitAnimation : ''
          }`}
          style={{
            opacity: isTransitioning ? 0 : 1,
            pointerEvents: isTransitioning ? 'none' : 'auto',
          }}
          onAnimationEnd={handleExitAnimationEnd}
        >
          {formatMonth(prevMonth, t.dateTime.monthsFull)}
        </div>

        {/* Next month - enters when transitioning */}
        {isTransitioning && (
          <div
            className={`absolute inset-0 text-center font-medium text-text-primary ${enterAnimation}`}
            onAnimationEnd={handleEnterAnimationEnd}
          >
            {formatMonth(month, t.dateTime.monthsFull)}
          </div>
        )}
      </div>
      <button
        onClick={handleNextMonth}
        disabled={!canNavigateToNextMonth}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-hidden focus-visible:outline-hidden disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Neste måned"
      >
        <ChevronRight size={18} />
      </button>
    </div>
  );
}
