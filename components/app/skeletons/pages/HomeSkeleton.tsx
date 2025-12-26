"use client";

import { motion } from "framer-motion";
import { NextPayrollCardSkeleton } from "../cards/NextPayrollCardSkeleton";
import { TotalCardSkeleton } from "../cards/TotalCardSkeleton";
import { ShiftCardSkeleton } from "../cards/ShiftCardSkeleton";

// Animation variants for staggered skeleton sections
const containerVariants = {
  hidden: { opacity: 1 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1,
      delayChildren: 0.05,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

/**
 * Skeleton for MonthPicker
 * Matches: prev button, month name, next button, year on right
 */
function MonthPickerSkeleton() {
  return (
    <div className="flex items-center justify-between -mt-3 -mb-3">
      <div className="flex items-center gap-4">
        {/* Previous month button */}
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
        {/* Month name */}
        <div className="h-8 w-28 bg-surface-secondary rounded animate-pulse" />
        {/* Next month button */}
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
      </div>
      {/* Year */}
      <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse mr-3" />
    </div>
  );
}

/**
 * HomeSkeleton - Loading skeleton for the dashboard/home page
 * Matches the actual HomeContent layout inside CenteredPageWrapper
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 * When the real content loads, it simply replaces the skeleton without additional animation.
 */
export function HomeSkeleton() {
  return (
    <div className="h-full px-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8 overflow-y-auto">
      <div className="w-full max-w-md md:max-w-lg mx-auto my-auto min-h-full flex flex-col justify-center pt-2 pb-6">
        <div className="flex items-center">
          <motion.div
            className="flex flex-col gap-6 w-full"
            variants={containerVariants}
            initial="hidden"
            animate="visible"
          >
            {/* Payroll countdown text */}
            <motion.div className="flex flex-col gap-2" variants={itemVariants}>
              <div className="h-3 w-32 bg-surface-secondary rounded animate-pulse mx-auto" />
              <NextPayrollCardSkeleton />
            </motion.div>

            {/* Total earnings card */}
            <motion.div variants={itemVariants}>
              <TotalCardSkeleton />
            </motion.div>

            {/* Month picker */}
            <motion.div variants={itemVariants}>
              <MonthPickerSkeleton />
            </motion.div>

            {/* Display shift with relative time */}
            <motion.div className="flex flex-col gap-2" variants={itemVariants}>
              <ShiftCardSkeleton />
              {/* Relative time text (e.g., "om 2 dager") */}
              <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse mx-auto" />
            </motion.div>
          </motion.div>
        </div>
      </div>
    </div>
  );
}
