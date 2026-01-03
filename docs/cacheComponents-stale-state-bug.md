# cacheComponents Stale State Bug

## Symptoms

When using Next.js `cacheComponents: true`, you may observe:

1. **Component shows wrong data after navigation** - e.g., calendar shows previous month instead of current
2. **Data refetches on every route transition** - shifts/data reload even when already fetched
3. **Brief flash of stale/zero values** - e.g., "0 kr" appears before correct amount
4. **Animations play incorrectly** - wrong direction or unexpected transitions

## Root Cause

`cacheComponents` keeps components in the DOM when navigating away (hidden via React Activity API) rather than unmounting them. This means:

- **State persists** across hide/reveal cycles
- **Effects re-run** on reveal (but may have stale closure values)
- **Refs persist** (which is actually useful for tracking)
- **Props from SSR remain the same** (the component isn't re-rendered by the server)

When shared context (like MonthContext) changes while a component is hidden, the revealed component has stale internal state that doesn't match the new context values.

## Common Patterns That Break

### 1. Controlled Components with Internal State

Libraries like `react-day-picker` maintain internal state that can desync from controlled props.

**Fix:** Add a `key` prop based on the controlled value to force remount:
```tsx
<DayPicker
  key={`${month.getFullYear()}-${month.getMonth()}`}
  month={month}
  ...
/>
```

### 2. useState for Tracking Loaded Data

Using `useState` for tracking which data has been loaded causes issues because:
- State updates trigger re-renders and callback recreation
- Effects re-run with new callback references
- This can cause unnecessary refetches

**Fix:** Use `useRef` for tracking sets that don't need to trigger re-renders:
```tsx
// Bad
const [loadedMonths, setLoadedMonths] = useState<Set<string>>(new Set());

// Good
const loadedMonthsRef = useRef<Set<string>>(new Set());
```

### 3. Effects That Clear State on Mount

Effects that reset state based on props will run on every reveal:

```tsx
// Bad - runs on every reveal, clearing dynamically fetched data
useEffect(() => {
  setAdditionalData([]);
  loadedRef.current.clear();
  // ... repopulate from initialData
}, [initialData]);
```

**Fix:** Track the previous prop reference to detect actual changes:
```tsx
const prevPropsRef = useRef(initialData);

useEffect(() => {
  // Skip if same reference (cacheComponents reveal, not actual data change)
  if (prevPropsRef.current === initialData) {
    return;
  }
  prevPropsRef.current = initialData;

  // Only clear on actual data change
  setAdditionalData([]);
  loadedRef.current.clear();
}, [initialData]);
```

### 4. Lazy Initialization in Effects vs Synchronous

Effect-based initialization runs after render, causing race conditions:

```tsx
// Bad - effect runs after other effects that might need this data
useEffect(() => {
  loadedMonthsRef.current.add(currentMonth);
}, []);
```

**Fix:** Initialize synchronously during render:
```tsx
const hasInitializedRef = useRef(false);

// Runs synchronously before any effects
if (!hasInitializedRef.current) {
  hasInitializedRef.current = true;
  for (const item of initialData) {
    loadedRef.current.add(item.key);
  }
}
```

## Solutions Summary

### For Third-Party Components with Internal State
Add `key` props based on controlled values to force remount when values change.

### For Data Tracking (loaded/loading sets)
1. Use `useRef` instead of `useState`
2. Initialize synchronously, not in effects
3. Check reference equality before clearing in effects

### For Loading States
Show loading skeleton with minimum display time (e.g., 250ms) to prevent flash:
```tsx
if (needsLoading) {
  setIsLoading(true);
  loadingStartTime = Date.now();
}

// After fetch completes
const elapsed = Date.now() - loadingStartTime;
const remaining = Math.max(0, 250 - elapsed);
if (remaining > 0) {
  setTimeout(() => setIsLoading(false), remaining);
} else {
  setIsLoading(false);
}
```

### For Wrapper Components
Create wrapper components that add keys based on shared context:
```tsx
function ContentWrapper(props) {
  const { selectedMonth } = useSharedContext();
  const key = `${selectedMonth.getFullYear()}-${selectedMonth.getMonth()}`;

  return <Content key={`content-${key}`} {...props} />;
}
```

## Files Modified in Original Fix

- `components/app/ShiftsCalendar.tsx` - Added key to DayPicker
- `components/app/HomeContent.tsx` - Added loading state, key to MonthPicker
- `components/app/HomeContentWrapper.tsx` - New wrapper for key-based remounting
- `components/app/StatsContent.tsx` - Added key to MonthPicker
- `components/shifts/ShiftsView.tsx` - Changed to useRef, added reference check
- `components/shifts/MonthlyEarningsCalendar.tsx` - Added key to MonthPicker

## Testing Checklist

When working with cacheComponents, test these scenarios:

1. Navigate away and back without changing shared context - state should persist
2. Navigate away, change shared context, return - should show updated data
3. Navigate to data outside SSR window, return to original route - should not refetch
4. Quick navigation back and forth - no duplicate fetches or race conditions
5. Loading states - no flash of stale/zero values
