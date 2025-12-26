"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useTranslations } from "@/lib/i18n/client";

type MonthPickerProps = {
  month: Date;
  onPreviousMonth: () => void;
  onNextMonth: () => void;
  canNavigateToPreviousMonth?: boolean;
  canNavigateToNextMonth?: boolean;
  /** Animation direction - set by parent when month changes */
  direction?: "forward" | "backward";
  /** Whether initial hydration from sessionStorage is complete - skips animation if false */
  isHydrated?: boolean;
};

function formatMonth(date: Date, monthsFull: readonly string[]): string {
  const monthIndex = date.getMonth();
  const monthName = monthsFull[monthIndex];
  // Capitalize first letter in JS to avoid CSS capitalize issues during animation
  return monthName.charAt(0).toUpperCase() + monthName.slice(1);
}

// Framer Motion variants for vertical month name scrolling
const monthVariants = {
  enter: (direction: "forward" | "backward") => ({
    y: direction === "forward" ? 20 : -20,
    opacity: 0,
  }),
  center: {
    y: 0,
    opacity: 1,
  },
  exit: (direction: "forward" | "backward") => ({
    y: direction === "forward" ? -20 : 20,
    opacity: 0,
  }),
};

export function MonthPicker({
  month,
  onPreviousMonth,
  onNextMonth,
  canNavigateToPreviousMonth = true,
  canNavigateToNextMonth = true,
  direction: externalDirection,
  isHydrated = true,
}: MonthPickerProps) {
  const { t } = useTranslations();
  // Track direction locally when external direction is not provided
  const [internalDirection, setInternalDirection] = useState<"forward" | "backward">("forward");

  // Use external direction if provided, otherwise use internal tracking
  const direction = externalDirection ?? internalDirection;

  const handlePrevious = () => {
    setInternalDirection("backward");
    onPreviousMonth();
  };

  const handleNext = () => {
    setInternalDirection("forward");
    onNextMonth();
  };

  return (
    <div className="flex items-center gap-1">
      <button
        onClick={handlePrevious}
        disabled={!canNavigateToPreviousMonth}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Forrige måned"
      >
        <ChevronLeft size={18} />
      </button>
      <div className="relative w-24 overflow-hidden" style={{ minHeight: '1.5rem' }}>
        <AnimatePresence mode="popLayout" custom={direction} initial={false}>
          <motion.div
            key={`${month.getFullYear()}-${month.getMonth()}`}
            custom={direction}
            variants={monthVariants}
            // Skip animation if not hydrated yet (prevents flicker during sessionStorage restoration)
            initial={isHydrated ? "enter" : false}
            animate="center"
            exit="exit"
            transition={{
              y: { type: "spring", stiffness: 300, damping: 30 },
              opacity: { duration: 0.15 },
            }}
            className="absolute inset-0 text-center font-medium text-text-primary"
          >
            {formatMonth(month, t.dateTime.monthsFull)}
          </motion.div>
        </AnimatePresence>
      </div>
      <button
        onClick={handleNext}
        disabled={!canNavigateToNextMonth}
        className="flex h-10 w-10 items-center justify-center rounded-md text-text-primary transition-colors hover:bg-surface-secondary focus:outline-none focus-visible:outline-none disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        aria-label="Neste måned"
      >
        <ChevronRight size={18} />
      </button>
    </div>
  );
}
