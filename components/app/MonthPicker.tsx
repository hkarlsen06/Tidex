"use client";

import { IconChevronLeft, IconChevronRight } from "@tabler/icons-react";
import { useEffect, useState } from "react";

type MonthPickerProps = {
  month: Date;
  onPreviousMonth: () => void;
  onNextMonth: () => void;
};

function formatMonth(date: Date): string {
  const month = new Intl.DateTimeFormat("nb-NO", {
    month: "long",
  }).format(date);
  // Capitalize first letter in JS to avoid CSS capitalize issues during animation
  return month.charAt(0).toUpperCase() + month.slice(1);
}

export function MonthPicker({ month, onPreviousMonth, onNextMonth }: MonthPickerProps) {
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [prevMonth, setPrevMonth] = useState(month);
  const [direction, setDirection] = useState<"forward" | "backward">("forward");

  useEffect(() => {
    if (month.getTime() !== prevMonth.getTime()) {
      // Determine direction based on month comparison
      const isForward = month > prevMonth;
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
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none"
        aria-label="Forrige måned"
      >
        <IconChevronLeft size={18} />
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
          {formatMonth(prevMonth)}
        </div>

        {/* Next month - enters when transitioning */}
        {isTransitioning && (
          <div
            className={`absolute inset-0 text-center font-medium text-text-primary ${enterAnimation}`}
            onAnimationEnd={handleEnterAnimationEnd}
          >
            {formatMonth(month)}
          </div>
        )}
      </div>
      <button
        onClick={handleNextMonth}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none"
        aria-label="Neste måned"
      >
        <IconChevronRight size={18} />
      </button>
    </div>
  );
}
