"use client";

import { motion } from "framer-motion";
import { ReactNode } from "react";

// Consistent spring animation settings used across the app
export const springTransition = {
  type: "spring" as const,
  stiffness: 300,
  damping: 30,
};

// Stagger configuration for list items
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05,
      delayChildren: 0.1,
    },
  },
};

const itemVariants = {
  hidden: {
    opacity: 0,
    y: 20,
  },
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

type AnimatedShiftListProps = {
  children: ReactNode;
  className?: string;
};

/**
 * Wrapper component that animates list items with a staggered entrance effect.
 * Use this to wrap a list of ShiftCards for a polished cascade animation.
 */
export function AnimatedShiftList({ children, className }: AnimatedShiftListProps) {
  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className={className}
    >
      {children}
    </motion.div>
  );
}

type AnimatedShiftItemProps = {
  children: ReactNode;
  className?: string;
};

/**
 * Individual animated item within an AnimatedShiftList.
 * Each item fades in and slides up with a staggered delay.
 */
export function AnimatedShiftItem({ children, className }: AnimatedShiftItemProps) {
  return (
    <motion.div variants={itemVariants} className={className}>
      {children}
    </motion.div>
  );
}
