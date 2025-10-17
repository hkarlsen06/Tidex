# Skeleton Loading States

This directory contains skeleton components for improving perceived performance during data loading.

## Available Skeleton Components

### ShiftCardSkeleton
Skeleton placeholder for individual shift cards.

```tsx
import { ShiftCardSkeleton } from "@/components/app/ShiftCardSkeleton";

<ShiftCardSkeleton />
```

### ShiftListSkeleton
Skeleton placeholder for the entire shifts list view (includes week headers and multiple shift cards).

```tsx
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

<ShiftListSkeleton />
```

### CalendarSkeleton
Skeleton placeholder for calendar views.

```tsx
import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";

<CalendarSkeleton />
```

### TotalCardSkeleton
Skeleton placeholder for the monthly totals card on the home page.

```tsx
import { TotalCardSkeleton } from "@/components/app/TotalCardSkeleton";

<TotalCardSkeleton />
```

### NextPayrollCardSkeleton
Skeleton placeholder for the next payroll card on the home page.

```tsx
import { NextPayrollCardSkeleton } from "@/components/app/NextPayrollCardSkeleton";

<NextPayrollCardSkeleton />
```

## Usage Examples

### Implemented in This Project

The skeleton components are already integrated into Next.js route loading states:

**Home Page** (`app/(app)/loading.tsx`):
```tsx
import { NextPayrollCardSkeleton } from "@/components/app/NextPayrollCardSkeleton";
import { TotalCardSkeleton } from "@/components/app/TotalCardSkeleton";
import { ShiftCardSkeleton } from "@/components/app/ShiftCardSkeleton";

export default function HomeLoading() {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="flex flex-col gap-6 w-full max-w-md">
        <NextPayrollCardSkeleton />
        <TotalCardSkeleton />
        {/* Month picker and shift card skeletons */}
      </div>
    </div>
  );
}
```

**Shifts Page** (`app/(app)/shifts/loading.tsx`):
```tsx
import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

export default function ShiftsLoading() {
  return (
    <div className="flex w-full flex-col">
      <CalendarSkeleton />
      <ShiftListSkeleton />
    </div>
  );
}
```

## Additional Usage Examples

### With React Suspense

```tsx
import { Suspense } from "react";
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

export default function ShiftsPage() {
  return (
    <Suspense fallback={<ShiftListSkeleton />}>
      <ShiftsList />
    </Suspense>
  );
}
```

### With Next.js Dynamic Import

```tsx
import dynamic from "next/dynamic";
import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";

const MonthlyEarningsCalendar = dynamic(
  () => import("./MonthlyEarningsCalendar"),
  { loading: () => <CalendarSkeleton /> }
);
```

### With Loading States

```tsx
import { ShiftCardSkeleton } from "@/components/app/ShiftCardSkeleton";

function ShiftsList({ isLoading, shifts }) {
  if (isLoading) {
    return (
      <div className="space-y-4">
        <ShiftCardSkeleton />
        <ShiftCardSkeleton />
        <ShiftCardSkeleton />
      </div>
    );
  }

  return shifts.map(shift => <ShiftCard key={shift.id} shift={shift} />);
}
```

## Design Principles

1. **Match the actual component structure**: Skeleton components should closely match the layout and sizing of the real components they replace.

2. **Use semantic color tokens**: All skeleton components use `bg-surface-secondary` to ensure they adapt to theme changes.

3. **Subtle animation**: The `animate-pulse` utility provides a subtle pulsing effect to indicate loading.

4. **Appropriate detail level**: Skeletons show the general structure without overwhelming detail.

## Performance Benefits

- **Improved perceived performance**: Users see immediate feedback instead of blank screens
- **Reduced layout shift**: Skeletons reserve space, preventing content jumps when data loads
- **Better UX during navigation**: Route transitions feel more responsive
