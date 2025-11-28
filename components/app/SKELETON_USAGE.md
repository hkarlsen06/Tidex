# Skeleton Loading States

Skeleton components for improving perceived performance during data loading. All skeletons are organized in `components/app/skeletons/` and exported from a single index.

## Import Pattern

All skeletons are exported from `@/components/app/skeletons`:

```tsx
import {
  // Page skeletons
  HomeSkeleton,
  ShiftsSkeleton,
  StatsSkeleton,
  // Card skeletons
  ShiftCardSkeleton,
  NextPayrollCardSkeleton,
  TotalCardSkeleton,
  // Calendar skeletons
  CalendarSkeleton,
  AddCalendarSkeleton,
} from "@/components/app/skeletons";
```

## Directory Structure

```
components/app/skeletons/
├── index.ts                    # Re-exports all skeletons
├── pages/
│   ├── HomeSkeleton.tsx        # Full home page skeleton
│   ├── ShiftsSkeleton.tsx      # Full shifts page skeleton (calendar + list)
│   └── StatsSkeleton.tsx       # Full stats page skeleton
├── cards/
│   ├── ShiftCardSkeleton.tsx   # Individual shift card
│   ├── NextPayrollCardSkeleton.tsx
│   └── TotalCardSkeleton.tsx
└── calendar/
    ├── CalendarSkeleton.tsx    # Main calendar with month picker
    └── AddCalendarSkeleton.tsx # Simplified calendar for add shift
```

## Usage in Next.js Route Loading

Page skeletons are used in `loading.tsx` files:

**Home Page** (`app/[locale]/(app)/loading.tsx`):
```tsx
import { HomeSkeleton } from "@/components/app/skeletons";

export default function HomeLoading() {
  return <HomeSkeleton />;
}
```

**Shifts Page** (`app/[locale]/(app)/shifts/loading.tsx`):
```tsx
import { ShiftsSkeleton } from "@/components/app/skeletons";

export default function ShiftsLoading() {
  return <ShiftsSkeleton />;
}
```

**Add Shift Page** (`app/[locale]/(app)/shifts/add/loading.tsx`):
```tsx
import { AddCalendarSkeleton } from "@/components/app/skeletons";

export default function AddShiftLoading() {
  return (
    <div className="...">
      <AddCalendarSkeleton />
    </div>
  );
}
```

## Usage with React Suspense

```tsx
import { Suspense } from "react";
import { ShiftCardSkeleton } from "@/components/app/skeletons";

export default function ShiftsPage() {
  return (
    <Suspense fallback={<ShiftCardSkeleton />}>
      <ShiftCard />
    </Suspense>
  );
}
```

## Usage with Next.js Dynamic Import

```tsx
import dynamic from "next/dynamic";
import { CalendarSkeleton } from "@/components/app/skeletons";

const MonthlyEarningsCalendar = dynamic(
  () => import("./MonthlyEarningsCalendar"),
  { loading: () => <CalendarSkeleton /> }
);
```

## Design Principles

1. **Match the actual component structure**: Skeleton components closely match the layout and sizing of the real components they replace.

2. **Use semantic color tokens**: All skeletons use `bg-surface-secondary` to adapt to theme changes.

3. **Subtle animation**: The `animate-pulse` utility provides a subtle pulsing effect.

4. **Page skeletons are self-contained**: `HomeSkeleton`, `ShiftsSkeleton`, etc. include all layout wrappers - just render them directly.
