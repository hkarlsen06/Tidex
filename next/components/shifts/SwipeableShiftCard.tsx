"use client";

import React, { useEffect, useRef, useState } from "react";
import {
  animate,
  clamp,
  motion,
  MotionValue,
  useMotionValue,
  useSpring,
  useTransform,
} from "motion/react";
import { Trash2, Pencil } from "lucide-react";
import { cn } from "@/lib/cn";
import type { ShiftWithComputations } from "@/lib/payroll";
import { useTranslations } from "@/lib/i18n/client";

const SPRING_OPTIONS = {
  stiffness: 900,
  damping: 80,
};

type SwipeableShiftCardProps = {
  shift: ShiftWithComputations;
  children: React.ReactNode;
  onEdit: () => void;
  onDelete?: () => void; // undefined when readOnly
  disabled?: boolean;
};

export function SwipeableShiftCard({
  shift,
  children,
  onEdit,
  onDelete,
  disabled = false,
}: SwipeableShiftCardProps) {
  const { t } = useTranslations();
  const [isSwiping, setIsSwiping] = useState(false);
  const [isHorizontalSwipe, setIsHorizontalSwipe] = useState(false);
  const hasTriggeredHaptic = useRef(false);

  // Refs for swipe logic
  const swipeContainerRef = useRef<HTMLDivElement>(null);
  const swipeItemRef = useRef<HTMLDivElement>(null);
  const swipeItemWidth = useRef(0);
  const swipeStartX = useRef(0);
  const swipeStartY = useRef(0);
  const swipeStartOffset = useRef(0);
  const fullSwipeSnapPosition = useRef<"left" | "right" | null>(null);
  const isHorizontalSwipeRef = useRef<boolean | null>(null);

  // Motion values
  const swipeAmount = useMotionValue(0);
  const swipeAmountSpring = useSpring(swipeAmount, SPRING_OPTIONS);
  const swipeProgress = useTransform(swipeAmount, (value) => {
    const itemWidth = swipeItemWidth.current;
    if (!itemWidth) return 0;
    return value / itemWidth;
  });

  // Handle swipe events
  useEffect(() => {
    if (disabled) return;

    const handlePointerMove = (info: PointerEvent) => {
      if (isSwiping) {
        const itemWidth = swipeItemWidth.current;
        if (!itemWidth) return;

        // Determine if this is a horizontal or vertical swipe
        if (isHorizontalSwipeRef.current === null) {
          const deltaX = Math.abs(info.clientX - swipeStartX.current);
          const deltaY = Math.abs(info.clientY - swipeStartY.current);

          // Need at least 10px movement to determine direction
          if (deltaX > 10 || deltaY > 10) {
            const isHorizontal = deltaX > deltaY;
            isHorizontalSwipeRef.current = isHorizontal;
            setIsHorizontalSwipe(isHorizontal);

            // If vertical, cancel the swipe and let scroll happen
            if (!isHorizontal) {
              setIsSwiping(false);
              return;
            }
          } else {
            // Not enough movement yet to determine direction
            return;
          }
        }

        // If not horizontal swipe, don't process
        if (!isHorizontalSwipeRef.current) return;

        const swipeDelta =
          info.clientX - swipeStartX.current + swipeStartOffset.current;
        const fullSwipeThreshold = itemWidth * 0.5; // 50% of width triggers full swipe
        const isSwipingBeyondThreshold =
          Math.abs(swipeDelta) > fullSwipeThreshold;
        const isSwipingLeft = swipeDelta < 0;

        // Restrict swipe direction based on available actions
        // Left swipe (delete) only allowed if onDelete is provided
        // Right swipe (view) always allowed
        const canSwipeLeft = !!onDelete;
        const canSwipeRight = true;

        // Block swipe if direction not allowed
        if (isSwipingLeft && !canSwipeLeft && swipeDelta < 0) {
          swipeAmount.set(0);
          return;
        }
        if (!isSwipingLeft && !canSwipeRight && swipeDelta > 0) {
          swipeAmount.set(0);
          return;
        }

        // Haptic feedback when crossing threshold
        if (isSwipingBeyondThreshold && !hasTriggeredHaptic.current) {
          hasTriggeredHaptic.current = true;
        } else if (!isSwipingBeyondThreshold && hasTriggeredHaptic.current) {
          hasTriggeredHaptic.current = false;
        }

        // If already snapped to a side
        if (fullSwipeSnapPosition.current) {
          const isSwipingBackToCenter =
            Math.abs(swipeDelta) < fullSwipeThreshold;
          if (isSwipingBackToCenter) {
            fullSwipeSnapPosition.current = null;
            swipeAmount.set(swipeDelta);
          } else {
            // Keep at 50% max
            const snapPosition =
              fullSwipeSnapPosition.current === "left"
                ? -itemWidth * 0.5
                : itemWidth * 0.5;
            swipeAmount.set(snapPosition);
          }
          return;
        }

        // Not yet snapped to any side
        if (isSwipingBeyondThreshold) {
          const snapDirection = isSwipingLeft ? "left" : "right";
          // Snap to 50% position (max)
          const snapPosition = isSwipingLeft ? -itemWidth * 0.5 : itemWidth * 0.5;
          fullSwipeSnapPosition.current = snapDirection;
          swipeAmount.set(snapPosition);
        } else {
          // Clamp to 50% max in either direction
          const minClamp = canSwipeLeft ? -itemWidth * 0.5 : 0;
          const maxClamp = canSwipeRight ? itemWidth * 0.5 : 0;
          swipeAmount.set(clamp(minClamp, maxClamp, swipeDelta));
        }
      }
    };

    const handlePointerUp = () => {
      if (isSwiping) {
        const itemWidth = swipeItemWidth.current;
        if (!itemWidth) return;

        const isFullySwiped = fullSwipeSnapPosition.current;

        if (isFullySwiped) {
          // Trigger the action
          if (fullSwipeSnapPosition.current === "left" && onDelete) {
            // Full swipe left - delete
            onDelete();
          } else if (fullSwipeSnapPosition.current === "right") {
            // Full swipe right - view details
            onEdit();
          }

          // Animate the container for visual feedback
          if (swipeContainerRef.current) {
            animate([
              [
                swipeContainerRef.current,
                {
                  scaleY: 1.05,
                  scaleX: 0.95,
                  y: -24,
                  pointerEvents: "none",
                },
                {
                  duration: 0.1,
                  ease: "easeOut",
                },
              ],
              [
                swipeContainerRef.current,
                {
                  scaleY: 1,
                  scaleX: 1,
                  y: 0,
                  pointerEvents: "auto",
                },
                {
                  duration: 0.6,
                  type: "spring",
                },
              ],
            ]);
          }

          // Reset swipe amount to 0 with delay
          animate(swipeAmount, 0, {
            duration: 0.5,
            delay: 0.3,
          });
        } else {
          // Not fully swiped - spring back to center
          swipeAmount.set(0);
        }

        setIsSwiping(false);
        setIsHorizontalSwipe(false);
        fullSwipeSnapPosition.current = null;
        hasTriggeredHaptic.current = false;
        isHorizontalSwipeRef.current = null;
      }
    };

    document.addEventListener("pointermove", handlePointerMove);
    document.addEventListener("pointerup", handlePointerUp);

    return () => {
      document.removeEventListener("pointermove", handlePointerMove);
      document.removeEventListener("pointerup", handlePointerUp);
    };
  }, [swipeAmount, isSwiping, onDelete, onEdit, disabled]);

  // Resize listener
  useEffect(() => {
    const handleResize = () => {
      const newWidth = swipeItemRef.current?.getBoundingClientRect().width;
      if (!newWidth) return;

      swipeItemWidth.current = newWidth;

      const currentProgress = swipeProgress.get();
      const newOffset = currentProgress * newWidth;

      swipeAmount.jump(newOffset);
      swipeAmountSpring.jump(newOffset);
    };

    handleResize();

    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, [swipeAmount, swipeAmountSpring, swipeProgress]);

  // Reset swipe when shift changes
  useEffect(() => {
    swipeAmount.jump(0);
    swipeAmountSpring.jump(0);
    fullSwipeSnapPosition.current = null;
    hasTriggeredHaptic.current = false;
    isHorizontalSwipeRef.current = null;
    // Note: isHorizontalSwipe state is reset in handlePointerDown
  }, [shift.id, swipeAmount, swipeAmountSpring]);

  const handlePointerDown = (info: React.PointerEvent) => {
    if (disabled) return;
    setIsSwiping(true);
    setIsHorizontalSwipe(false);
    swipeStartX.current = info.clientX;
    swipeStartY.current = info.clientY;
    swipeStartOffset.current = swipeAmount.get();
    isHorizontalSwipeRef.current = null;
  };

  return (
    <motion.div
      ref={swipeContainerRef}
      className="relative overflow-hidden rounded-3xl"
      style={{ touchAction: isSwiping && isHorizontalSwipe ? "none" : "pan-y" }}
    >
      {/* Right side action (view details) - revealed on swipe right */}
      <ActionsGroup
        side="left"
        swipeAmount={swipeAmountSpring}
        action={
          <Action
            swipeProgress={swipeProgress}
            side="left"
            bgColor="bg-brand-highlight"
          >
            <ActionContent
              icon={Pencil}
              label={t.pages.shifts.swipeActions?.edit ?? "Edit"}
            />
          </Action>
        }
      />

      {/* Left side action (delete) - revealed on swipe left, only if onDelete provided */}
      {onDelete && (
        <ActionsGroup
          side="right"
          swipeAmount={swipeAmountSpring}
          action={
            <Action
              swipeProgress={swipeProgress}
              side="right"
              bgColor="bg-red-500 dark:bg-red-600"
            >
              <ActionContent
                icon={Trash2}
                label={t.pages.shifts.swipeActions?.delete ?? "Delete"}
              />
            </Action>
          }
        />
      )}

      {/* Main swipeable content */}
      <motion.div
        ref={swipeItemRef}
        className="relative z-10"
        style={{ x: swipeAmountSpring }}
        onPointerDown={handlePointerDown}
      >
        <SwipeItemContent swipeProgress={swipeProgress}>
          {children}
        </SwipeItemContent>
      </motion.div>
    </motion.div>
  );
}

// Actions container positioned on left or right
function ActionsGroup({
  swipeAmount,
  side,
  action,
}: {
  swipeAmount: MotionValue<number>;
  side: "left" | "right";
  action: React.ReactNode;
}) {
  return (
    <motion.div
      className={cn(
        "absolute inset-y-0 flex",
        side === "right" ? "left-full" : "right-full"
      )}
      style={{
        width: "100%",
        x: swipeAmount,
      }}
    >
      {action}
    </motion.div>
  );
}

// Individual action button
function Action({
  children,
  swipeProgress,
  side,
  bgColor,
}: {
  children: React.ReactNode;
  swipeProgress: MotionValue<number>;
  side: "left" | "right";
  bgColor: string;
}) {
  const ref = useRef<HTMLDivElement>(null);

  // Opacity: fade in as we swipe (max 50%)
  const opacity = useTransform(swipeProgress, (value) => {
    const absValue = Math.abs(value);
    const direction = value < 0 ? "left" : "right";

    // Only show when swiping to reveal this side's action
    // left side (view) shows when swiping right (positive progress)
    // right side (delete) shows when swiping left (negative progress)
    const isCorrectDirection =
      (side === "left" && direction === "right") ||
      (side === "right" && direction === "left");
    if (!isCorrectDirection) return 0;

    // Fade in from 0 to 0.5 (full visibility at 50% swipe)
    return Math.min(absValue * 2, 1);
  });

  // Scale: grow as we swipe (max 50%)
  const scale = useTransform(swipeProgress, (value) => {
    const absValue = Math.abs(value);
    const direction = value < 0 ? "left" : "right";

    const isCorrectDirection =
      (side === "left" && direction === "right") ||
      (side === "right" && direction === "left");
    if (!isCorrectDirection) return 0.8;

    // Scale up from 0.8 to 1 as we swipe to 50%
    return 0.8 + absValue * 0.4; // 0.8 at 0%, 1.0 at 50%
  });

  return (
    <motion.div
      ref={ref}
      className={cn(
        "absolute inset-y-0 flex items-center rounded-3xl",
        side === "right" ? "left-0" : "right-0",
        bgColor
      )}
      style={{
        width: "50%",
        justifyContent: side === "right" ? "flex-start" : "flex-end",
      }}
    >
      <motion.div
        className="flex h-full w-1/2 items-center justify-center"
        style={{
          opacity,
          scale,
          transformOrigin: side === "right" ? "left" : "right",
        }}
      >
        {children}
      </motion.div>
    </motion.div>
  );
}

// Action content (icon + label)
function ActionContent({
  icon: Icon,
  label,
}: {
  icon: React.ComponentType<{ size?: number; strokeWidth?: number; className?: string }>;
  label: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-1 text-white">
      <Icon size={24} strokeWidth={1.5} />
      <span className="text-xs font-medium">{label}</span>
    </div>
  );
}

// Wrapper for main content with opacity effect during swipe
function SwipeItemContent({
  swipeProgress,
  children,
}: {
  swipeProgress: MotionValue<number>;
  children: React.ReactNode;
}) {
  // Dim content slightly when swiped to either side - no spring needed, follows swipe directly
  const opacity = useTransform(swipeProgress, [-0.5, 0, 0.5], [0.7, 1, 0.7]);

  return (
    <motion.div style={{ opacity }}>
      {children}
    </motion.div>
  );
}
