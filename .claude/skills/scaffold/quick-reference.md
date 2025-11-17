# Component Scaffolder - Quick Reference

## 🚀 Quick Start Commands

```bash
# In Claude Code, invoke the skill:
/scaffold

# Then use natural language:
"Generate a Badge component"
"Scaffold a notifications settings page"
"Create a reports route with data loader"
"Build a shift templates feature"
```

---

## 📋 What Can Be Scaffolded

### 1. UI Components
- shadcn/ui base component + app wrapper
- Follows two-tier architecture
- Uses semantic color tokens
- Type-safe props

**Example:** `"Generate a Badge component with variants for success/warning/error"`

### 2. Settings Pages
- Server component with auth check
- Client form component
- API route for updates
- Proper data loading pattern

**Example:** `"Scaffold a notifications settings page with email/push toggles"`

### 3. Authenticated Routes
- Protected route with auth
- Data loader (server-only)
- View component (client)
- Type definitions

**Example:** `"Create a reports route with monthly filters"`

### 4. Complete Features
- All of the above
- Database migration template
- API CRUD routes
- Sub-components

**Example:** `"Build a shift templates feature for saving recurring patterns"`

---

## 🎨 Semantic Color Tokens (Always Use These!)

### Backgrounds
```typescript
bg-background              // Main page bg
bg-background-secondary    // Subtle bg
bg-surface-primary         // Cards/panels
bg-surface-secondary       // Nested surfaces
bg-surface-tertiary        // Deepest surface
```

### Text
```typescript
text-text-primary      // Main text
text-text-secondary    // Secondary text
text-text-muted        // Muted/disabled
```

### Borders
```typescript
border-border         // Default border
border-border-subtle  // Subtle border
```

### Interactive
```typescript
bg-primary text-primary-foreground        // Primary buttons
bg-destructive text-destructive-foreground // Delete/danger
hover:bg-accent                            // Hover states
```

### Brand
```typescript
bg-brand-gradient-start
bg-brand-gradient-end
// ... gradient tokens
```

---

## 📁 File Structure Reference

```
app/
  (app)/                          # Protected routes
    [feature]/
      page.tsx                    # Server component
      _data/
        get[Data].ts              # Data loader (server-only)
      _components/                # Feature-specific components
  (auth)/                         # Public auth routes
  api/
    [endpoint]/
      route.ts                    # API handlers

components/
  ui/                             # shadcn base (don't import!)
    button.tsx
  app/                            # App wrappers (import these!)
    Button.tsx
  settings/
    [page-name]/
      [Page]Form.tsx              # Settings forms
  [feature]/
    [Feature]View.tsx             # Feature components

lib/
  supabase/
    server.ts                     # createSupabaseServerClient()
    browser.ts                    # Shared client instance
  payroll/
    calc.ts                       # Pure calculation logic
  types/
    [feature].ts                  # Type definitions
```

---

## ✅ Import Patterns (Copy These!)

### Server Components
```typescript
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { get[Data] } from './_data/get[Data]';

export default async function Page() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  // ...
}
```

### Client Components
```typescript
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@appui/Button';
import { supabase } from '@/lib/supabase/browser';

export function Component() {
  const router = useRouter();
  // ... form logic
  router.refresh(); // After mutations
}
```

### Data Loaders
```typescript
import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";

export async function get[Data](userId: string) {
  const supabase = await createSupabaseServerClient();
  // ... fetch logic
}
```

---

## 🚫 Common Mistakes (Avoid These!)

### ❌ Wrong
```typescript
// Don't import from ui directly
import { Button } from '@ui/button';

// Don't use hardcoded colors
className="bg-slate-900 text-gray-400"

// Don't instantiate Supabase directly
const supabase = createClient(url, key);

// Don't compute wages client-side
const gross = calculateGross(shift);

// Don't fetch in client components
useEffect(() => { fetch('/api/data')... }, []);
```

### ✅ Correct
```typescript
// Import from app wrappers
import { Button } from '@appui/Button';

// Use semantic tokens
className="bg-surface-primary text-text-secondary"

// Use helpers
const supabase = await createSupabaseServerClient();

// Use precomputed data
<div>{shift.computed.gross}</div>

// Fetch in server components
const data = await getData(userId);
```

---

## 🔧 Project-Specific Rules

1. **Two-tier components**: shadcn base → app wrapper → import wrapper
2. **Server-side calculation**: Wages computed in data loaders, never client
3. **Auth pattern**: Check user before data loading in protected routes
4. **Theme support**: All UI responds to light/dark via CSS variables
5. **Type safety**: Export types from data loaders, import in components
6. **Error handling**: Use logger, throw user-friendly messages
7. **Router refresh**: Call after mutations to update server state

---

## 📊 Scaffolding Decision Tree

```
Need UI element?
  ├─ Exists in shadcn?
  │   ├─ Yes → Add with: npm dlx shadcn@latest add [name]
  │   │        Then scaffold app wrapper
  │   └─ No → Scaffold custom component with semantic tokens
  │
  └─ New page/feature?
      ├─ Settings page?
      │   └─ Scaffold: route + form + API + types
      │
      ├─ New route?
      │   └─ Scaffold: page + data loader + view + types
      │
      └─ Complete feature?
          └─ Scaffold: all above + migration template + sub-components
```

---

## 🎯 Best Practices Checklist

When scaffolding, ensure:

- [ ] Server code uses `await createSupabaseServerClient()`
- [ ] Client code uses shared `supabase` instance
- [ ] No direct imports from `components/ui`
- [ ] All colors are semantic tokens
- [ ] Server-only files have `import "server-only"`
- [ ] Client components have `'use client'`
- [ ] Data loaders in `_data/` folders
- [ ] Auth checks before data fetching
- [ ] TypeScript types exported/imported
- [ ] Error handling with logger
- [ ] Loading states for async ops
- [ ] `router.refresh()` after mutations

---

## 📚 More Details

For comprehensive examples and patterns, see:
- [skill.md](./skill.md) - Skill overview and usage
- [templates.md](./templates.md) - Code templates
- [examples.md](./examples.md) - Real examples from codebase

---

## 🆘 Troubleshooting

**"Import not found"**
→ Make sure you created the app wrapper in `components/app/`

**"Hydration error"**
→ Check for client/server mismatches (dates, randomness, localStorage)

**"Auth error"**
→ Verify auth check pattern in page component

**"Type error"**
→ Ensure data loader exports types and component imports them

**"Theme not working"**
→ Check that semantic tokens are used (not hardcoded colors)

---

**Ready to scaffold? Invoke the skill and start building!** 🎨
