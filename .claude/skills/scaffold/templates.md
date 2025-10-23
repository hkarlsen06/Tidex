# Scaffolding Templates

## Component Wrapper Pattern

### shadcn/ui Base Component (components/ui/)
```typescript
// components/ui/[component-name].tsx
import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

const [component]Variants = cva(
  "base-classes-here",
  {
    variants: {
      variant: {
        default: "variant-classes",
      },
      size: {
        default: "size-classes",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export interface [Component]Props
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof [component]Variants> {
  asChild?: boolean
}

const [Component] = React.forwardRef<HTMLDivElement, [Component]Props>(
  ({ className, variant, size, ...props }, ref) => {
    return (
      <div
        className={cn([component]Variants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  }
)
[Component].displayName = "[Component]"

export { [Component], [component]Variants }
```

### App Wrapper Component (components/app/)
```typescript
// components/app/[Component].tsx
import * as React from "react";
import { [Component] as Base[Component] } from "@ui/[component-name]";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof Base[Component]> & {
  // Add app-specific props here
};

export function [Component]({ className, ...props }: Props) {
  return (
    <Base[Component]
      {...props}
      className={cn(
        // Add app-specific styling with semantic tokens here
        "bg-surface-primary text-text-primary",
        className
      )}
    />
  );
}
```

---

## Settings Page Pattern

### Settings Page (app/(app)/settings/[page-name]/page.tsx)
```typescript
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getUserSettings } from '../_data/getSettings';
import { [PageName]Form } from '@components/settings/[page-name]/[PageName]Form';

export default async function [PageName]Page() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Expected authenticated user in [page-name] settings page; middleware should handle redirects.');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">[Page Title]</h2>
          <p className="text-text-secondary mt-1">
            [Page description]
          </p>
        </div>

        <[PageName]Form initialData={settings} />
      </div>
    </div>
  );
}
```

### Settings Form Component (components/settings/[page-name]/[PageName]Form.tsx)
```typescript
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@appui/Button';
import type { UserSettings } from '@/lib/payroll';

type Props = {
  initialData: UserSettings;
};

export function [PageName]Form({ initialData }: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    // Initialize form state from initialData
  });

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    try {
      const response = await fetch('/api/settings/[endpoint]', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      if (!response.ok) throw new Error('Failed to save settings');

      router.refresh();
    } catch (error) {
      console.error('Error saving settings:', error);
      // Handle error (show toast, etc.)
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Form fields here using semantic tokens */}
      <div className="bg-surface-primary border border-border rounded-lg p-6">
        {/* Form content */}
      </div>

      <div className="flex justify-end gap-3">
        <Button type="submit" loading={loading}>
          Lagre
        </Button>
      </div>
    </form>
  );
}
```

---

## Authenticated Route Pattern

### Route Page (app/(app)/[route-name]/page.tsx)
```typescript
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { get[DataName] } from './_data/get[DataName]';
import { [RouteName]View } from '@components/[route-name]/[RouteName]View';

export default async function [RouteName]Page() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Expected authenticated user; middleware should handle redirects.');
  }

  const data = await get[DataName](user.id);

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold">[Page Title]</h1>
          <p className="text-text-secondary mt-2">
            [Page description]
          </p>
        </div>

        <[RouteName]View data={data} />
      </div>
    </div>
  );
}
```

### Data Loader (app/(app)/[route-name]/_data/get[DataName].ts)
```typescript
import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";

export type [DataName] = {
  // Define return type
};

export async function get[DataName](userId: string): Promise<[DataName]> {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("[table_name]")
    .select("*")
    .eq("user_id", userId);

  if (error) {
    logger.error("[DataName] fetch error:", error);
    throw new Error("Failed to load [data name]");
  }

  // Process data if needed
  return data ?? [];
}
```

### View Component (components/[route-name]/[RouteName]View.tsx)
```typescript
'use client';

import { useState } from 'react';
import type { [DataName] } from '@/app/(app)/[route-name]/_data/get[DataName]';

type Props = {
  data: [DataName];
};

export function [RouteName]View({ data }: Props) {
  return (
    <div className="space-y-4">
      {/* Render data using semantic tokens */}
      <div className="bg-surface-primary border border-border rounded-lg p-6">
        {/* Content */}
      </div>
    </div>
  );
}
```

---

## API Route Pattern

### API Route (app/api/[endpoint]/route.ts)
```typescript
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { NextResponse } from 'next/server';
import { logger } from '@/lib/logger';

export async function POST(request: Request) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    const body = await request.json();

    // Validate input
    // Process request
    // Update database

    const { data, error } = await supabase
      .from('[table_name]')
      .update(body)
      .eq('user_id', user.id)
      .select()
      .single();

    if (error) {
      logger.error('Database error:', error);
      return NextResponse.json(
        { error: 'Database error' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, data });
  } catch (error) {
    logger.error('API error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
```

---

## TypeScript Types Pattern

### Type Definitions (lib/types/[feature].ts)
```typescript
// Database row types
export type [Table]Row = {
  id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
  // ... other fields
};

// Computed/enriched types
export type [Feature]Data = [Table]Row & {
  computed: {
    // computed fields
  };
};

// Form/input types
export type [Feature]Input = {
  // input fields (subset of row)
};

// API response types
export type [Feature]Response = {
  success: boolean;
  data?: [Feature]Data;
  error?: string;
};
```

---

## Semantic Color Token Reference

Always use these instead of hardcoded colors:

**Backgrounds:**
- `bg-background` - Main page background
- `bg-background-secondary` - Subtle background
- `bg-surface-primary` - Card/panel background
- `bg-surface-secondary` - Nested surface
- `bg-surface-tertiary` - Deepest surface

**Text:**
- `text-text-primary` - Main text
- `text-text-secondary` - Secondary text
- `text-text-muted` - Muted/disabled text

**Borders:**
- `border-border` - Default border
- `border-border-subtle` - Subtle border

**Interactive:**
- `bg-primary text-primary-foreground` - Primary buttons
- `bg-destructive text-destructive-foreground` - Destructive actions
- `hover:bg-accent` - Hover states

**Brand:**
- `bg-brand-gradientStart` to `bg-brand-gradientEnd` - Brand gradients

---

## Import Patterns

```typescript
// Server components
import { createSupabaseServerClient } from '@/lib/supabase/server';

// Client components
import { supabase } from '@/lib/supabase/browser';

// Components (NEVER from @ui directly!)
import { Button } from '@appui/Button';
import { Card } from '@appui/Card';

// Utilities
import { cn } from '@/lib/cn';
import { logger } from '@/lib/logger';

// Types
import type { UserSettings, ShiftRow } from '@/lib/payroll';

// Data loaders
import { getShifts } from './_data/getShifts';
```

---

## File Naming Conventions

- **Components**: PascalCase (Button.tsx, ShiftCard.tsx)
- **Routes**: lowercase (page.tsx, layout.tsx)
- **Data loaders**: camelCase with get prefix (getShifts.ts, getUserSettings.ts)
- **Utils**: camelCase (formatCurrency.ts, dateHelpers.ts)
- **Types**: PascalCase for types, camelCase for files (lib/types/shifts.ts)

---

## Common Patterns to Follow

1. **Server-side data loading**: Always fetch in data loaders, not in page components
2. **Auth checks**: Every protected route checks user before data loading
3. **Error handling**: Use try/catch with logger, throw user-friendly errors
4. **Form state**: Client components with useState for forms
5. **Router refresh**: After mutations, call `router.refresh()` to update server data
6. **Type safety**: Export types from data loaders, import in components
7. **Semantic tokens**: Never use hardcoded colors, always use CSS variables
8. **Component wrapping**: All shadcn components get app wrappers
