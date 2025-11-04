# Create Server Action

Complete guide for implementing server actions in tidex with proper validation, error handling, and cache revalidation.

## When to use this skill

- Creating a new form submission handler
- Implementing data mutations (create, update, delete)
- Building API endpoints for client components
- Any server-side data modification

## Important Context

Server actions in tidex follow a standardized pattern using centralized utilities from `lib/` and `data-access/`:
- **Validation**: Use validators from `lib/validation/shift-validators.ts`
- **Error messages**: Use constants from `lib/errors/messages.ts`
- **Revalidation**: Use helpers from `lib/revalidation/paths.ts`
- **Snapshots**: Use `getCurrentSnapshots()` from `data-access/snapshots.ts`
- **Authentication**: Use `verifySession()` from `data-access/auth.ts`

## Standard Server Action Pattern

### Template Structure

```tsx
'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { isISODate, isHHMM } from '@/lib/validation/shift-validators';
import { getCurrentSnapshots } from '@/data-access/snapshots';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { ERRORS } from '@/lib/errors/messages';

export async function myServerAction(data: MyDataType) {
  // 1. Verify authentication
  const user = await verifySession();

  // 2. Initialize Supabase client
  const supabase = await createSupabaseServerClient();

  // 3. Validate input
  if (!isISODate(data.date)) return { error: ERRORS.INVALID_DATE };
  if (!isHHMM(data.start)) return { error: ERRORS.INVALID_TIME };

  // 4. Get snapshots (if creating/updating shifts)
  const snapshots = await getCurrentSnapshots();

  // 5. Perform database operation
  const { error } = await supabase.from('my_table').insert({
    ...data,
    ...snapshots,
    user_id: user.id
  });

  if (error) return { error: ERRORS.DB_ERROR };

  // 6. Invalidate cache and revalidate
  invalidateAndRevalidate(user.id);

  return { success: true };
}
```

## Step-by-Step Implementation

### Step 1: Create file with 'use server' directive

```tsx
'use server';

// All imports here
```

**File location:** Typically in `app/[locale]/(app)/[route]/actions.ts` or a dedicated `actions/` directory

### Step 2: Import required utilities

```tsx
// Authentication
import { verifySession } from '@/data-access/auth';

// Database client
import { createSupabaseServerClient } from '@/lib/supabase/server';

// Validation (choose what you need)
import { isISODate, isHHMM } from '@/lib/validation/shift-validators';

// Error messages
import { ERRORS } from '@/lib/errors/messages';

// Revalidation
import { invalidateAndRevalidate, revalidateShiftData } from '@/lib/revalidation/paths';

// Snapshots (if working with shifts)
import { getCurrentSnapshots } from '@/data-access/snapshots';
```

### Step 3: Verify authentication

**Always first step:**

```tsx
const user = await verifySession();
```

This returns the authenticated user or redirects to login. No need for additional auth checks.

### Step 4: Initialize Supabase client

```tsx
const supabase = await createSupabaseServerClient();
```

**Important:** In Next.js 16, `cookies()` is async, so `createSupabaseServerClient()` must be awaited.

### Step 5: Validate input

Use the validation utilities:

```tsx
// Date validation
if (!isISODate(data.date)) {
  return { error: ERRORS.INVALID_DATE };
}

// Time validation (HH:MM format)
if (!isHHMM(data.start) || !isHHMM(data.end)) {
  return { error: ERRORS.INVALID_TIME };
}

// Custom validation
if (!data.name || data.name.length < 3) {
  return { error: "Name must be at least 3 characters" };
}
```

**Available validators:**
- `isISODate(date)` - Validates YYYY-MM-DD format
- `isHHMM(time)` - Validates HH:MM format (24-hour)

### Step 6: Get snapshots (if applicable)

For shift creation/updates, capture current wage settings:

```tsx
const snapshots = await getCurrentSnapshots();
// Returns: { hourly_wage_snapshot, supplement_rules_snapshot }
```

This ensures shifts preserve wage settings even if user changes them later.

### Step 7: Perform database operation

```tsx
const { data: result, error } = await supabase
  .from('my_table')
  .insert({
    ...inputData,
    ...snapshots, // If applicable
    user_id: user.id
  })
  .select()
  .single();

if (error) {
  console.error('Database error:', error);
  return { error: ERRORS.DB_ERROR };
}
```

**Pattern variations:**

```tsx
// Update
const { error } = await supabase
  .from('shifts')
  .update(updates)
  .eq('id', shiftId)
  .eq('user_id', user.id); // Important: verify ownership

// Delete
const { error } = await supabase
  .from('shifts')
  .delete()
  .eq('id', shiftId)
  .eq('user_id', user.id); // Important: verify ownership
```

### Step 8: Revalidate cache and pages

Choose the appropriate revalidation strategy:

**Option A: Full cache invalidation + revalidation** (recommended for mutations):
```tsx
invalidateAndRevalidate(user.id);
```

This clears Next.js cache for the user AND revalidates `/shifts`, `/`, and `/stats` pages.

**Option B: Page revalidation only** (lighter, no cache clearing):
```tsx
revalidateShiftData();
```

This only revalidates pages, doesn't clear cache.

### Step 9: Return success/error

```tsx
// Success
return { success: true, data: result };

// Error
return { error: ERRORS.INVALID_DATE };
return { error: "Custom error message" };
```

## Available Error Constants

From `lib/errors/messages.ts`:

```tsx
ERRORS.INVALID_DATE     // "Ugyldig dato"
ERRORS.INVALID_TIME     // "Ugyldig tid"
ERRORS.SHIFT_NOT_FOUND  // "Fant ikke vakten"
ERRORS.UNAUTHORIZED     // "Ikke autorisert"
ERRORS.DB_ERROR         // "Noe gikk galt"
```

## Available Revalidation Functions

From `lib/revalidation/paths.ts`:

```tsx
// Revalidate shift-related pages only
revalidateShiftData(); // Revalidates /shifts, /, /stats

// Full cache clear + revalidation (recommended for mutations)
invalidateAndRevalidate(userId); // Clears cache + revalidates pages
```

## Complete Example: Create Shift Action

```tsx
'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { isISODate, isHHMM } from '@/lib/validation/shift-validators';
import { getCurrentSnapshots } from '@/data-access/snapshots';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { ERRORS } from '@/lib/errors/messages';

type CreateShiftData = {
  date: string;
  start: string;
  end: string;
  description?: string;
};

export async function createShift(data: CreateShiftData) {
  // 1. Verify authentication
  const user = await verifySession();

  // 2. Initialize Supabase client
  const supabase = await createSupabaseServerClient();

  // 3. Validate input
  if (!isISODate(data.date)) {
    return { error: ERRORS.INVALID_DATE };
  }

  if (!isHHMM(data.start) || !isHHMM(data.end)) {
    return { error: ERRORS.INVALID_TIME };
  }

  // 4. Get current snapshots
  const snapshots = await getCurrentSnapshots();

  // 5. Perform database operation
  const { data: shift, error } = await supabase
    .from('shifts')
    .insert({
      date: data.date,
      start: data.start,
      end: data.end,
      description: data.description,
      ...snapshots,
      user_id: user.id,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating shift:', error);
    return { error: ERRORS.DB_ERROR };
  }

  // 6. Invalidate cache and revalidate
  invalidateAndRevalidate(user.id);

  return { success: true, data: shift };
}
```

## Verification

- [ ] File has `'use server'` directive at the top
- [ ] Authentication verified with `verifySession()`
- [ ] Input validated with validators from `lib/validation/`
- [ ] Errors use constants from `lib/errors/messages.ts`
- [ ] Database operations include `user_id` check for ownership
- [ ] Cache invalidated and pages revalidated after mutation
- [ ] Returns consistent `{ error }` or `{ success, data }` format

## Common Patterns

### Update with ownership check

```tsx
const { error } = await supabase
  .from('shifts')
  .update(updates)
  .eq('id', shiftId)
  .eq('user_id', user.id); // Prevent updating other users' data

if (error?.code === 'PGRST116') {
  return { error: ERRORS.SHIFT_NOT_FOUND };
}
```

### Batch operations

```tsx
const { error } = await supabase
  .from('shifts')
  .insert(shiftsArray.map(shift => ({
    ...shift,
    ...snapshots,
    user_id: user.id
  })));
```

### Conditional snapshot capture

```tsx
// Only get snapshots if actually creating/updating wage-related data
const snapshots = isWageRelated
  ? await getCurrentSnapshots()
  : {};
```
