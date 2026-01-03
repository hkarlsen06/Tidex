"use client";

import { motion } from "motion/react";

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
 * AddShiftSkeleton - Loading skeleton for /shifts/add
 * Matches: Header with mode toggle, MonthPicker, Calendar, Time inputs, Summary, Submit button
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 */
export function AddShiftSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <motion.div
          className="mx-auto flex w-full max-w-4xl flex-col gap-6 pt-8 pb-24"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          <motion.div className="flex flex-col gap-4" variants={itemVariants}>
            <div className="space-y-1">
              {/* Subtitle */}
              <div className="h-3 w-20 bg-brand-gradient-start/30 rounded animate-pulse" />
              <div className="flex items-center justify-between gap-3">
                {/* Heading */}
                <div className="h-8 w-32 sm:h-9 sm:w-40 bg-surface-secondary rounded animate-pulse" />
                {/* Mode toggle */}
                <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shrink-0">
                  <div className="h-9 w-20 bg-brand-gradient-mid rounded-full animate-pulse" />
                  <div className="h-9 w-24 bg-surface-secondary rounded-full animate-pulse" />
                </div>
              </div>
            </div>
            {/* Description */}
            <div className="h-4 w-72 bg-surface-secondary rounded animate-pulse" />
          </motion.div>

          <div className="space-y-6">
            {/* Month picker row */}
            <motion.div className="flex flex-wrap items-center justify-between gap-4" variants={itemVariants}>
              <div className="flex items-center gap-2">
                <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
                <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
                <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
              </div>
              <div className="h-6 w-12 bg-surface-secondary/80 rounded-full animate-pulse" />
            </motion.div>

            {/* Calendar skeleton */}
            <motion.div
              className="rounded-2xl border border-border-subtle bg-surface-secondary/30 p-4"
              variants={itemVariants}
            >
              {/* Weekday headers */}
              <div className="grid grid-cols-7 gap-1 mb-2">
                {[1, 2, 3, 4, 5, 6, 7].map((i) => (
                  <div key={i} className="h-4 bg-surface-secondary rounded animate-pulse mx-auto w-6" />
                ))}
              </div>
              {/* Calendar grid - 6 rows */}
              {[1, 2, 3, 4, 5, 6].map((row) => (
                <div key={row} className="grid grid-cols-7 gap-1 mb-1">
                  {[1, 2, 3, 4, 5, 6, 7].map((col) => (
                    <div
                      key={col}
                      className="aspect-square rounded-lg bg-surface-secondary animate-pulse"
                    />
                  ))}
                </div>
              ))}
            </motion.div>

            {/* Time inputs row */}
            <motion.div className="grid grid-cols-1 gap-4 sm:grid-cols-2" variants={itemVariants}>
              {/* Start time */}
              <div className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4">
                <div className="h-3 w-12 bg-surface-secondary rounded animate-pulse" />
                <div className="flex min-w-0 items-center gap-2">
                  <div className="h-14 flex-1 bg-surface-secondary rounded-xl animate-pulse" />
                  <div className="h-10 w-10 bg-surface-secondary rounded-xl animate-pulse shrink-0" />
                </div>
              </div>
              {/* End time */}
              <div className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4">
                <div className="h-3 w-12 bg-surface-secondary rounded animate-pulse" />
                <div className="flex min-w-0 items-center gap-2">
                  <div className="h-14 flex-1 bg-surface-secondary rounded-xl animate-pulse" />
                  <div className="h-10 w-10 bg-surface-secondary rounded-xl animate-pulse shrink-0" />
                </div>
              </div>
            </motion.div>

            {/* Summary box */}
            <motion.div
              className="rounded-2xl border border-border-subtle bg-surface-secondary/70 px-4 py-3"
              variants={itemVariants}
            >
              <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse" />
            </motion.div>

            {/* Submit button */}
            <motion.div className="flex justify-center" variants={itemVariants}>
              <div className="h-14 w-full max-w-md bg-brand-gradient-mid/50 rounded-2xl animate-pulse" />
            </motion.div>
          </div>
        </motion.div>
      </div>
    </div>
  );
}
