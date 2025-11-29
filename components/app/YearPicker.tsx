"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useEffect, useState } from "react";

type YearPickerProps = {
  year: number;
  onPreviousYear: () => void;
  onNextYear: () => void;
  canNavigateToPreviousYear?: boolean;
  canNavigateToNextYear?: boolean;
  suffix?: string;
};

export function YearPicker({
  year,
  onPreviousYear,
  onNextYear,
  canNavigateToPreviousYear = true,
  canNavigateToNextYear = true,
  suffix,
}: YearPickerProps) {
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [prevYear, setPrevYear] = useState(year);
  const [direction, setDirection] = useState<"forward" | "backward">("forward");

  // Track year changes for animation transitions
  useEffect(() => {
    if (year !== prevYear) {
      // Determine direction based on year comparison
      const isForward = year > prevYear;
      // Note: These setState calls are intentional to trigger animation state changes when year prop changes
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDirection(isForward ? "forward" : "backward");
      setIsTransitioning(true);
    }
  }, [year, prevYear]);

  const handleExitAnimationEnd = () => {
    setPrevYear(year);
  };

  const handleEnterAnimationEnd = () => {
    setIsTransitioning(false);
  };

  const handlePreviousYear = () => {
    onPreviousYear();
  };

  const handleNextYear = () => {
    onNextYear();
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
        onClick={handlePreviousYear}
        disabled={!canNavigateToPreviousYear}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Previous year"
      >
        <ChevronLeft size={18} />
      </button>
      <div className="relative w-16 overflow-hidden" style={{ minHeight: '1.5rem' }}>
        {/* Current/Previous year - exits when transitioning */}
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
          {prevYear}
        </div>

        {/* Next year - enters when transitioning */}
        {isTransitioning && (
          <div
            className={`absolute inset-0 text-center font-medium text-text-primary ${enterAnimation}`}
            onAnimationEnd={handleEnterAnimationEnd}
          >
            {year}
          </div>
        )}
      </div>
      <button
        onClick={handleNextYear}
        disabled={!canNavigateToNextYear}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Next year"
      >
        <ChevronRight size={18} />
      </button>
      {suffix && (
        <span className="text-text-muted text-sm ml-1">{suffix}</span>
      )}
    </div>
  );
}
