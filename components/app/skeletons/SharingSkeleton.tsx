"use client";

import { motion } from "framer-motion";
import { Card, CardHeader } from "@/components/app/Card";

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
 * Skeleton for the calendar component (reused from ShiftsSkeleton)
 */
function CalendarSkeleton() {
  return (
    <Card className="rounded-3xl border-0 bg-transparent">
      {/* Calendar header: month picker + year + total */}
      <div className="flex flex-row items-center justify-between py-3">
        <div className="flex items-center gap-1 flex-1">
          {/* Month picker: prev button, month name, next button */}
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 bg-surface-secondary rounded animate-pulse" />
            <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
            <div className="h-9 w-9 bg-surface-secondary rounded animate-pulse" />
          </div>
          {/* Year */}
          <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse ml-1" />
        </div>
        {/* Total earnings for month */}
        <div className="h-6 w-20 bg-surface-secondary rounded animate-pulse" />
      </div>

      {/* Weekday headers (M T W T F S S) */}
      <div className="grid grid-cols-7 mb-2">
        {Array.from({ length: 7 }, (_, i) => (
          <div key={i} className="text-center py-2">
            <div className="h-3 w-6 bg-surface-secondary rounded animate-pulse mx-auto" />
          </div>
        ))}
      </div>

      {/* Calendar grid - 5 weeks x 7 days */}
      <div className="space-y-1 pb-6">
        {Array.from({ length: 5 }, (_, weekIdx) => (
          <div key={weekIdx} className="grid grid-cols-7 gap-1">
            {Array.from({ length: 7 }, (_, dayIdx) => {
              const cellIdx = weekIdx * 7 + dayIdx;
              // Simulate some days having shifts (every 2-3 days)
              const hasShift = cellIdx % 3 === 0;

              return (
                <div key={dayIdx} className="aspect-square p-0">
                  <div className="w-full h-full rounded-lg border border-border-subtle bg-surface-primary p-1 pb-1.5">
                    <div className="relative flex flex-col items-center justify-start gap-0.5 w-full h-full">
                      {/* Day number */}
                      <div className="w-full text-right pr-1">
                        <div className="h-3 w-4 bg-surface-secondary rounded animate-pulse ml-auto" />
                      </div>
                      {/* Earnings placeholder (only for days with "shifts") */}
                      {hasShift && (
                        <div className="h-3 w-10 bg-surface-secondary rounded animate-pulse mt-1" />
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* Toggle buttons for earnings/hours view */}
      <div className="flex justify-center pb-6">
        <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 w-2/3">
          <div className="h-9 flex-1 bg-surface-primary rounded-full animate-pulse" />
          <div className="h-9 flex-1 bg-surface-secondary rounded-full animate-pulse" />
        </div>
      </div>
    </Card>
  );
}

/**
 * Skeleton for a shift card in the list
 */
function ShiftCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          {/* Date + day (e.g., "15. januar · onsdag") */}
          <div className="h-7 w-44 bg-surface-secondary rounded animate-pulse" />
          {/* Clock icon + time range + arrow + hours */}
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1">
              <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
              <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="h-4 w-3 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-10 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
        <div className="text-right space-y-1">
          {/* Amount */}
          <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
          {/* Breakdown */}
          <div className="h-3 w-16 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}

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
 * Skeleton for the SharingDropdown component
 * Matches: rounded-xl border, px-4 py-3, w-full, avatar (h-8 w-8) + name + chevron
 */
function DropdownSkeleton() {
  return (
    <div className="flex w-full items-center gap-3 rounded-xl border border-border-subtle bg-surface-primary px-4 py-3">
      {/* Avatar circle */}
      <div className="h-8 w-8 rounded-full bg-surface-secondary animate-pulse shrink-0" />
      {/* Name text */}
      <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse flex-1" />
      {/* Chevron */}
      <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse shrink-0" />
    </div>
  );
}

/**
 * Skeleton for a shift preview inside a sharer card
 * Matches: SharedUserShiftPreview - date, time range, and status badge
 */
function ShiftPreviewSkeleton() {
  return (
    <div className="flex items-center gap-3 px-3 py-2 bg-surface-secondary/50 rounded-lg">
      {/* Shift info */}
      <div className="flex-1 min-w-0 space-y-1">
        <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
        <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse" />
      </div>
      {/* Status badge */}
      <div className="h-6 w-16 bg-surface-secondary rounded-full animate-pulse shrink-0" />
    </div>
  );
}

/**
 * Skeleton for a sharer card in the list
 * Matches: SharersList button with avatar, name, secondary info, chevron, and optional shift preview
 */
export function SharerCardSkeleton({ hasShiftPreview = false }: { hasShiftPreview?: boolean }) {
  return (
    <div className="w-full rounded-xl border border-border-subtle bg-surface-primary overflow-hidden">
      {/* User card header */}
      <div className="flex w-full items-center gap-3 px-4 py-3">
        {/* Avatar (h-10 w-10 for size="md") */}
        <div className="h-10 w-10 rounded-full bg-surface-secondary animate-pulse shrink-0" />
        <div className="flex flex-1 flex-col min-w-0 gap-1">
          {/* Name */}
          <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
          {/* Secondary info (phone/email) */}
          <div className="h-3 w-32 bg-surface-secondary rounded animate-pulse" />
        </div>
        {/* Chevron */}
        <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse shrink-0" />
      </div>
      {/* Shift preview */}
      {hasShiftPreview && (
        <div className="px-3 pb-3">
          <ShiftPreviewSkeleton />
        </div>
      )}
    </div>
  );
}

/**
 * Skeleton for the sharing view header with back button and dropdown
 * Used inside ShiftsView headerSlot
 */
function SharingHeaderSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      {/* Back button skeleton */}
      <div className="inline-flex items-center gap-2 w-fit">
        <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
        <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
      </div>
      {/* Dropdown skeleton - full width */}
      <DropdownSkeleton />
    </div>
  );
}

/**
 * SharingDefaultSkeleton - Loading skeleton for /sharing (default view, no sharer selected)
 * Matches ScrollablePageWrapper structure with centered container
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 * When the real content loads, it simply replaces the skeleton without additional animation.
 */
export function SharingDefaultSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      {/* Matches ScrollablePageWrapper container */}
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <motion.div
          className="flex flex-col gap-6 pt-4"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          {/* Header: Title "Deling" (text-2xl) + Manage button */}
          <motion.div className="flex items-center justify-between gap-4" variants={itemVariants}>
            <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
            <div className="h-9 w-40 bg-surface-secondary rounded-lg animate-pulse" />
          </motion.div>

          {/* Sharers list - cards with shift previews */}
          <motion.div className="flex flex-col gap-3" variants={itemVariants}>
            <SharerCardSkeleton hasShiftPreview={true} />
          </motion.div>
          <motion.div className="flex flex-col gap-3" variants={itemVariants}>
            <SharerCardSkeleton hasShiftPreview={true} />
          </motion.div>
          <motion.div className="flex flex-col gap-3" variants={itemVariants}>
            <SharerCardSkeleton hasShiftPreview={false} />
          </motion.div>
        </motion.div>
      </div>
    </div>
  );
}

/**
 * SharingViewSkeleton - Loading skeleton for /sharing?view=<id> (viewing a sharer's shifts)
 * Matches ShiftsView structure with headerSlot inside calendar container
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 * When the real content loads, it simply replaces the skeleton without additional animation.
 */
export function SharingViewSkeleton() {
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
            {/* Header slot - inside calendar container with pb-3 */}
            <div className="pb-3">
              <SharingHeaderSkeleton />
            </div>
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

/**
 * Skeleton for the sharers list while shift previews are loading
 * Shows sharer cards with preview skeleton placeholders
 */
export function SharersListSkeleton({ count = 3 }: { count?: number }) {
  return (
    <div className="flex flex-col gap-3">
      {Array.from({ length: count }, (_, i) => (
        <SharerCardSkeleton key={i} hasShiftPreview={i < 2} />
      ))}
    </div>
  );
}

/**
 * SharingSkeleton - Alias for backward compatibility
 * @deprecated Use SharingDefaultSkeleton or SharingViewSkeleton instead
 */
export const SharingSkeleton = SharingDefaultSkeleton;
