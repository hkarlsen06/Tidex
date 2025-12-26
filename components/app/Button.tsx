// components/app/Button.tsx
"use client";

import * as React from "react";
import { motion, HTMLMotionProps } from "framer-motion";
import { Button as BaseButton, buttonVariants } from "@ui/button";
import { cn } from "@/lib/cn";
import type { VariantProps } from "class-variance-authority";

type Props = VariantProps<typeof buttonVariants> & {
  loading?: boolean;
  /** Disable the press animation (useful for disabled states) */
  disableAnimation?: boolean;
  asChild?: boolean;
  children?: React.ReactNode;
  className?: string;
  disabled?: boolean;
  onClick?: React.MouseEventHandler<HTMLButtonElement>;
  type?: "button" | "submit" | "reset";
  title?: string;
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
  onClick,
  type,
  title,
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
      type={type}
      title={title}
      disabled={isDisabled}
      onClick={onClick}
      whileTap={!isDisabled && !disableAnimation ? tapScale : undefined}
      whileHover={!isDisabled && !disableAnimation ? hoverScale : undefined}
      transition={{ type: "spring", stiffness: 400, damping: 25 }}
      className={cn(buttonVariants({ variant, size }), "font-medium", className)}
    >
      {loading ? "…" : children}
    </motion.button>
  );
}
