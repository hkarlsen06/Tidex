"use client";

import { motion } from "motion/react";
import { Card } from "@/components/app/Card";

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
 * SettingsSkeleton - Loading skeleton for the /settings hub page
 * Matches the settings menu layout with 6 navigation cards
 *
 * Uses Framer Motion staggered animations for a polished loading experience.
 * When the real content loads, it simply replaces the skeleton without additional animation.
 */
export function SettingsSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <motion.div
          className="py-8"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          {/* Title and subtitle */}
          <motion.div variants={itemVariants}>
            <div className="h-9 w-36 bg-surface-secondary rounded animate-pulse mb-2" />
            <div className="h-5 w-64 bg-surface-secondary rounded animate-pulse mb-10" />
          </motion.div>

          {/* Settings menu cards */}
          <div className="flex flex-col gap-6">
            {Array.from({ length: 6 }, (_, i) => (
              <motion.div key={i} variants={itemVariants}>
                <Card className="p-5">
                  <div className="flex items-center gap-4">
                    {/* Icon placeholder */}
                    <div className="p-3 rounded-lg bg-surface-secondary">
                      <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
                    </div>
                    {/* Text content */}
                    <div className="flex-1">
                      <div className="h-5 w-28 bg-surface-secondary rounded animate-pulse mb-1.5" />
                      <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse" />
                    </div>
                    {/* Chevron */}
                    <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse shrink-0" />
                  </div>
                </Card>
              </motion.div>
            ))}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
