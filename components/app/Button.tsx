// components/app/Button.tsx
"use client";

import * as React from "react";
import { motion, type HTMLMotionProps } from "framer-motion";
import { Button as BaseButton, buttonVariants } from "@ui/button";
import { cn } from "@/lib/cn";
import type { VariantProps } from "class-variance-authority";

// Use React's button attributes as the base, which includes all standard props
// like aria-label, form, name, etc.
type Props = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "ref"> &
  VariantProps<typeof buttonVariants> & {
    loading?: boolean;
    /** Disable the press animation (useful for disabled states) */
    disableAnimation?: boolean;
    asChild?: boolean;
  };

// Subtle scale animation on press
const tapScale = { scale: 0.98 };
const hoverScale = { scale: 1.02 };

export function Button({
  className,
  loading,
  children,
  disableAnimation,
  disabled,
  variant,
  size,
  asChild,
  // Extract the props that might conflict with motion
  _onDrag,
  _onDragEnd,
  _onDragStart,
  ...rest
}: Props) {
  const isDisabled = loading || disabled;

  // When asChild is used, we can't wrap with motion
  if (asChild) {
    return (
      <BaseButton
        variant={variant}
        size={size}
        disabled={isDisabled}
        asChild={asChild}
        className={cn("font-medium", className)}
      >
        {loading ? "…" : children}
      </BaseButton>
    );
  }

  return (
    <motion.button
      // Spread compatible button attributes (type, title, aria-*, etc.)
      {...(rest as HTMLMotionProps<"button">)}
      disabled={isDisabled}
      whileTap={!isDisabled && !disableAnimation ? tapScale : undefined}
      whileHover={!isDisabled && !disableAnimation ? hoverScale : undefined}
      transition={{ type: "spring", stiffness: 400, damping: 25 }}
      className={cn(buttonVariants({ variant, size }), "font-medium", className)}
    >
      {loading ? "…" : children}
    </motion.button>
  );
}
