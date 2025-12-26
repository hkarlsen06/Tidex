"use client";

import { motion } from "framer-motion";
import { CalendarSkeleton } from "../calendar/CalendarSkeleton";
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
 * Skeleton for a week group in the shifts list
 */
function WeekGroupSkeleton({ shiftCount }: { shiftCount: number }) {
  return (
    <section className="space-y-4">
      {/* Week header: "Uke X" + chevron + total */}
      <div className="flex flex-row items-center justify-between bg-transparent">
        <div className="flex items-center gap-2">
          <div className="h-5 w-16 bg-surface-secondary rounded animate-pulse" />
          <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
        </div>
        <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
      </div>
      {/* Shift cards */}
      <div className="space-y-4">
        {Array.from({ length: shiftCount }, (_, i) => (
          <ShiftCardSkeleton key={i} />
        ))}
      </div>
    </section>
  );
}

/**
 * ShiftsSkeleton - Loading skeleton for the /shifts page
 * Matches the actual ShiftsView layout with ScrollablePageWrapper
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 * When the real content loads, it simply replaces the skeleton without additional animation.
 */
export function ShiftsSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      {/* Mobile/Tablet: vertical stack. Desktop: side-by-side */}
      <motion.div
        className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {/* Calendar Section */}
        <motion.div
          className="h-[calc(100dvh-3.5rem-5rem-env(safe-area-inset-top)-env(safe-area-inset-bottom))] flex flex-col justify-center px-4 shrink-0 lg:h-auto lg:w-1/2 lg:sticky lg:top-6 lg:justify-start lg:items-center lg:px-0"
          variants={itemVariants}
        >
          <div className="w-full max-w-md md:max-w-lg lg:max-w-none lg:w-[480px]">
            <CalendarSkeleton />
          </div>
        </motion.div>

        {/* Shifts List Section */}
        <motion.div
          className="px-4 lg:w-1/2 lg:flex lg:justify-center lg:px-0"
          variants={itemVariants}
        >
          <div className="pb-10 w-full max-w-md md:max-w-lg lg:max-w-lg lg:overflow-y-auto lg:max-h-[calc(100vh-8rem)] lg:px-4">
            <div className="flex flex-col gap-12">
              {/* Week groups with varying shift counts */}
              <WeekGroupSkeleton shiftCount={2} />
              <WeekGroupSkeleton shiftCount={3} />
              <WeekGroupSkeleton shiftCount={1} />
            </div>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
