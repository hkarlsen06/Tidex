# Animation Specification

This document outlines the animation patterns and guidelines for Tidex.
Consistent animations create a polished, professional feel and improve perceived
performance.

## Core Principles

1. **Consistency** - Use the same spring physics across all animations
2. **Subtlety** - Animations enhance UX without being distracting
3. **Performance** - Prefer `transform` and `opacity` for 60fps animations
4. **Accessibility** - Respect `prefers-reduced-motion` user preference

## Spring Physics

All spring-based animations use these consistent values:

```typescript
const springTransition = {
  type: "spring" as const,
  stiffness: 300,
  damping: 30,
};
```

This creates a snappy, responsive feel without being jarring.

## Animation Patterns

### 1. Skeleton-First Page Loading (Recommended)

**The preferred pattern for page entrance animations.** Staggered animations
should be applied to loading skeletons, not the final content. When the real
content loads, it simply replaces the skeleton without additional animation.

**Why this approach:**

- Skeleton animates in immediately (no waiting for data)
- Creates perception of faster loading
- Avoids double-animation (skeleton + content)
- Smoother transition from loading to loaded state

**Implementation:** Used in `AddShiftSkeleton.tsx`

```tsx
// In the skeleton component (e.g., components/app/skeletons/pages/AddShiftSkeleton.tsx)
"use client";

import { motion } from "framer-motion";

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

export function PageSkeleton() {
  return (
    <motion.div variants={containerVariants} initial="hidden" animate="visible">
      <motion.div variants={itemVariants}>
        {/* Skeleton placeholder */}
        <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
      </motion.div>
      <motion.div variants={itemVariants}>
        {/* More skeleton placeholders */}
      </motion.div>
    </motion.div>
  );
}

// The actual page content component uses regular divs - NO animation
export function PageContent() {
  return (
    <div>
      <div>Section 1</div>
      <div>Section 2</div>
    </div>
  );
}
```

**Key points:**

- Skeleton is a `"use client"` component with Framer Motion
- Real content uses plain `<div>` elements (no motion)
- Page wrapper should NOT add entrance animations around the content

### 2. Page Section Staggering (Legacy)

For pages without skeletons, sections can animate in with a staggered cascade
effect.

**Implementation:** Used in `HomeContent.tsx`

```typescript
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1, // 100ms between each child
      delayChildren: 0.05, // 50ms initial delay
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
```

**Usage:**

```tsx
<motion.div variants={containerVariants} initial="hidden" animate="visible">
  <motion.div variants={itemVariants}>Section 1</motion.div>
  <motion.div variants={itemVariants}>Section 2</motion.div>
  <motion.div variants={itemVariants}>Section 3</motion.div>
</motion.div>;
```

### 3. List Item Staggering

Shift cards and list items cascade in with shorter delays for snappier lists.

**Implementation:** Used in `ShiftsView.tsx`

```typescript
const listContainerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05, // 50ms for faster cascade
      delayChildren: 0.1,
    },
  },
};

const listItemVariants = {
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
```

### 4. Button Press Feedback

Buttons provide tactile feedback on hover and press.

**Implementation:** `Button.tsx`

```typescript
const tapScale = { scale: 0.98 };    // Slightly shrink on press
const hoverScale = { scale: 1.02 };  // Slightly grow on hover

<motion.button
  whileTap={tapScale}
  whileHover={hoverScale}
  transition={{ type: "spring", stiffness: 400, damping: 25 }}
>
```

### 5. Dialog Animations

Dialogs use CSS animations for smooth enter/exit with Radix primitives.

**Implementation:** `Dialog.tsx`

```tsx
<DialogPrimitive.Content
  className={cn(
    // Enter animations
    "data-[state=open]:animate-in",
    "data-[state=open]:fade-in-0",
    "data-[state=open]:zoom-in-95",
    "data-[state=open]:slide-in-from-left-1/2",
    "data-[state=open]:slide-in-from-top-[48%]",
    // Exit animations
    "data-[state=closed]:animate-out",
    "data-[state=closed]:fade-out-0",
    "data-[state=closed]:zoom-out-95",
    "data-[state=closed]:slide-out-to-left-1/2",
    "data-[state=closed]:slide-out-to-top-[48%]",
    "duration-200",
  )}
/>;
```

### 6. Tab Content Transitions

Tab content fades and slides when switching tabs.

**Implementation:** `Tabs.tsx`

```typescript
const tabContentVariants = {
  hidden: { opacity: 0, y: 10 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
  exit: {
    opacity: 0,
    y: -10,
    transition: { duration: 0.15 },
  },
};
```

### 7. Month Navigation

Month picker uses vertical slide animations matching navigation direction.

**Implementation:** `MonthPicker.tsx`

```typescript
const monthVariants = {
  enter: (direction: "forward" | "backward") => ({
    y: direction === "forward" ? 20 : -20,
    opacity: 0,
  }),
  center: { y: 0, opacity: 1 },
  exit: (direction: "forward" | "backward") => ({
    y: direction === "forward" ? -20 : 20,
    opacity: 0,
  }),
};
```

**Exception:** MonthPicker uses tween animations instead of spring physics:

```typescript
transition={{
  y: { type: "tween", duration: 0.2, ease: "easeOut" },
  opacity: { duration: 0.15 },
}}
```

This is intentional because spring animations with `AnimatePresence` can leave elements
partially visible during exit. Tween with fixed duration ensures the exit animation
completes reliably before the element unmounts.

## Reusable Components

### AnimatedShiftList / AnimatedShiftItem

Wrapper for staggered list animations:

```tsx
import {
  AnimatedShiftItem,
  AnimatedShiftList,
} from "@/components/app/AnimatedShiftList";

<AnimatedShiftList>
  {shifts.map((shift) => (
    <AnimatedShiftItem key={shift.id}>
      <ShiftCard shift={shift} />
    </AnimatedShiftItem>
  ))}
</AnimatedShiftList>;
```

### AnimatedCard

Card with hover/tap feedback:

```tsx
import { AnimatedCard } from "@/components/app/AnimatedCard";

<AnimatedCard
  enableHover={true}
  enableTap={true}
  animateEntrance={true}
  entranceDelay={0.1}
>
  Card content
</AnimatedCard>;
```

### StaggeredContainer / AnimatedStaggerItem

For general staggered layouts:

```tsx
import {
  AnimatedStaggerItem,
  StaggeredContainer,
} from "@/components/app/AnimatedCard";

<StaggeredContainer staggerDelay={0.1}>
  <AnimatedStaggerItem>Item 1</AnimatedStaggerItem>
  <AnimatedStaggerItem>Item 2</AnimatedStaggerItem>
</StaggeredContainer>;
```

## Animation Timing Reference

| Context       | Stagger Delay | Entrance Duration |
| ------------- | ------------- | ----------------- |
| Page sections | 100ms         | Spring (300/30)   |
| List items    | 50ms          | Spring (300/30)   |
| Dialogs       | N/A           | 200ms CSS         |
| Tabs          | N/A           | Spring (300/30)   |
| Buttons       | N/A           | Spring (400/25)   |

## Accessibility

Always respect user preferences for reduced motion:

```typescript
// In components that use Framer Motion
import { useReducedMotion } from "framer-motion";

const shouldReduceMotion = useReducedMotion();

<motion.div
  animate={{ opacity: 1, y: shouldReduceMotion ? 0 : 20 }}
/>;
```

For CSS animations, use:

```css
@media (prefers-reduced-motion: reduce) {
  .animated-element {
    animation: none;
    transition: none;
  }
}
```

## Best Practices

1. **Don't animate on every render** - Use `initial={false}` for components that
   shouldn't animate on mount
2. **Keep durations short** - Most animations should complete in under 300ms
3. **Use layout animations sparingly** - They can cause performance issues with
   large lists
4. **Test on low-end devices** - Ensure animations stay smooth on older phones
5. **Exit animations** - Always include exit animations for elements that
   unmount
