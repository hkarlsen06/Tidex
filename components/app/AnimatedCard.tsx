"use client";

import { motion, HTMLMotionProps } from "framer-motion";
import { ReactNode, forwardRef } from "react";

// Consistent spring animation settings
const springTransition = {
  type: "spring" as const,
  stiffness: 300,
  damping: 30,
};

// Subtle hover/tap feedback
const hoverScale = { scale: 1.02 };
const tapScale = { scale: 0.98 };

interface AnimatedCardProps extends Omit<HTMLMotionProps<"div">, "children"> {
  children: ReactNode;
  /** Enable hover scale effect */
  enableHover?: boolean;
  /** Enable tap/press scale effect */
  enableTap?: boolean;
  /** Custom entrance animation - fade in and slide up */
  animateEntrance?: boolean;
  /** Delay for entrance animation (useful for staggering) */
  entranceDelay?: number;
}

/**
 * A wrapper component that adds subtle motion effects to cards.
 * Use this for interactive cards that benefit from tactile feedback.
 */
export const AnimatedCard = forwardRef<HTMLDivElement, AnimatedCardProps>(
  (
    {
      children,
      enableHover = true,
      enableTap = true,
      animateEntrance = false,
      entranceDelay = 0,
      ...props
    },
    ref
  ) => {
    return (
      <motion.div
        ref={ref}
        initial={animateEntrance ? { opacity: 0, y: 20 } : undefined}
        animate={animateEntrance ? { opacity: 1, y: 0 } : undefined}
        transition={
          animateEntrance
            ? { ...springTransition, delay: entranceDelay }
            : springTransition
        }
        whileHover={enableHover ? hoverScale : undefined}
        whileTap={enableTap ? tapScale : undefined}
        {...props}
      >
        {children}
      </motion.div>
    );
  }
);

AnimatedCard.displayName = "AnimatedCard";

// Staggered container for multiple animated cards
interface StaggeredContainerProps {
  children: ReactNode;
  className?: string;
  /** Delay between each child animation */
  staggerDelay?: number;
}

const containerVariants = {
  hidden: { opacity: 0 },
  visible: (staggerDelay: number) => ({
    opacity: 1,
    transition: {
      staggerChildren: staggerDelay,
      delayChildren: 0.1,
    },
  }),
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
 * Container that orchestrates staggered entrance animations for its children.
 * Wrap multiple AnimatedStaggerItem components to get cascading entrances.
 */
export function StaggeredContainer({
  children,
  className,
  staggerDelay = 0.1,
}: StaggeredContainerProps) {
  return (
    <motion.div
      className={className}
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      custom={staggerDelay}
    >
      {children}
    </motion.div>
  );
}

interface AnimatedStaggerItemProps {
  children: ReactNode;
  className?: string;
}

/**
 * Individual item within a StaggeredContainer.
 * Automatically animates with the parent's stagger timing.
 */
export function AnimatedStaggerItem({
  children,
  className,
}: AnimatedStaggerItemProps) {
  return (
    <motion.div variants={itemVariants} className={className}>
      {children}
    </motion.div>
  );
}
