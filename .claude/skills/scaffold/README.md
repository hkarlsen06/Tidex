# Component Scaffolder Skill for app.kkarlsen.dev

## Overview

This skill automates the creation of components, routes, and features following the established architecture patterns of the Next.js 15 shift tracking application. It ensures all generated code follows best practices, uses semantic color tokens, and adheres to the two-tier component system.

## What This Skill Does

The Component Scaffolder generates production-ready code for:

1. **UI Components** - shadcn/ui base components with app-specific wrappers
2. **Settings Pages** - Complete settings pages with forms, API routes, and data loaders
3. **Authenticated Routes** - Protected routes with server-side data loading
4. **Complete Features** - End-to-end features with all necessary files

## Key Features

- ✅ Follows two-tier component architecture (`components/ui` → `components/app`)
- ✅ Uses semantic color tokens (never hardcoded colors)
- ✅ Server-side data loading with Supabase
- ✅ Type-safe TypeScript throughout
- ✅ Auth checks for protected routes
- ✅ Proper client/server component separation
- ✅ Light/dark theme support built-in

## Files in This Skill

- **skill.md** - Main skill prompt and instructions
- **templates.md** - Code templates for all scaffold types
- **examples.md** - Real examples from the codebase
- **quick-reference.md** - Quick lookup guide for common patterns
- **README.md** - This file

## How to Use

### 1. Invoke the Skill

In Claude Code:
```
/scaffold
```

Or use the Skill tool to invoke it.

### 2. Describe What You Want

Use natural language to describe what you want to scaffold:

**Examples:**
- "Generate a Badge component with success, warning, and error variants"
- "Scaffold a notifications settings page with email and push notification toggles"
- "Create a reports route with monthly/yearly filters and export button"
- "Build a shift templates feature for saving recurring shift patterns"

### 3. Answer Clarifying Questions

The skill will ask questions to ensure it generates exactly what you need:
- What variants/options should be included?
- Where should the feature live in the route structure?
- What data needs to be displayed/managed?

### 4. Review and Confirm

The skill will show you what it will generate before creating files. You can:
- Confirm and proceed
- Request changes
- Cancel if it's not quite right

## Common Use Cases

### Adding a shadcn Component

**Scenario:** You need a new UI component from shadcn/ui

**Command:**
```
npm dlx shadcn@latest add [component-name]
```

**Then in Claude Code:**
```
/scaffold
"Create an app wrapper for the [component-name] component"
```

**What Gets Generated:**
- `components/app/[ComponentName].tsx` - App wrapper with semantic tokens

### Creating a Settings Page

**Scenario:** You need a new settings page for user preferences

**Command:**
```
/scaffold
"Scaffold a [setting-name] settings page"
```

**What Gets Generated:**
- `app/(app)/settings/[setting-name]/page.tsx` - Server component
- `components/settings/[setting-name]/[SettingName]Form.tsx` - Client form
- `app/api/settings/[endpoint]/route.ts` - API route (if needed)

### Building a New Route

**Scenario:** You need a new authenticated route with data

**Command:**
```
/scaffold
"Create a [route-name] route with data loader"
```

**What Gets Generated:**
- `app/(app)/[route-name]/page.tsx` - Server component with auth
- `app/(app)/[route-name]/_data/get[DataName].ts` - Data loader
- `components/[route-name]/[RouteName]View.tsx` - Client view component
- Type definitions

### Creating a Complete Feature

**Scenario:** You need a full feature with database, routes, and UI

**Command:**
```
/scaffold
"Build a [feature-name] feature"
```

**What Gets Generated:**
- Database migration template (for manual execution)
- Type definitions
- Data loaders
- Route structure
- Components (view, forms, sub-components)
- API routes (CRUD operations)

## Architecture Patterns

### Two-Tier Component System

**Never import from `components/ui` directly!**

```typescript
// ❌ Wrong
import { Button } from '@ui/button';

// ✅ Correct
import { Button } from '@appui/Button';
```

**Pattern:**
1. shadcn generates base component in `components/ui/`
2. Create app wrapper in `components/app/`
3. Import wrapper throughout the app

### Semantic Color Tokens

**Never use hardcoded Tailwind colors!**

```typescript
// ❌ Wrong
className="bg-slate-900 text-gray-400 border-zinc-700"

// ✅ Correct
className="bg-surface-primary text-text-secondary border-border"
```

### Server-Side Data Loading

**Pattern:**
1. Server component fetches data
2. Data loader does the heavy lifting
3. Precompute everything (especially wages)
4. Pass data to client components

```typescript
// Server Component (page.tsx)
export default async function Page() {
  const data = await getData(userId); // Fetch + compute
  return <View data={data} />;         // Pass to client
}

// Client Component
'use client';
export function View({ data }) {
  return <div>{data.computed.total}</div>; // Just render
}
```

### Auth Pattern

**All protected routes:**
1. Get Supabase server client
2. Check for authenticated user
3. Throw error if unauthenticated (middleware handles redirect)
4. Load data for that user

```typescript
export default async function ProtectedPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Expected authenticated user; middleware should handle redirects.');
  }

  const data = await getData(user.id);
  // ...
}
```

## Generated Code Checklist

All scaffolded code will:

- [ ] Use semantic color tokens exclusively
- [ ] Follow two-tier component architecture
- [ ] Include proper TypeScript types
- [ ] Have server/client separation
- [ ] Include auth checks (protected routes)
- [ ] Use createSupabaseServerClient() in server code
- [ ] Use shared supabase instance in client code
- [ ] Include error handling with logger
- [ ] Have loading states for async operations
- [ ] Call router.refresh() after mutations
- [ ] Support light/dark themes automatically

## Import Aliases

The project uses these aliases (defined in tsconfig.json):

```typescript
@/          // Project root
@components // components/
@ui         // components/ui/
@appui      // components/app/
```

**Usage:**
```typescript
import { Button } from '@appui/Button';
import { computeShift } from '@/lib/payroll/calc';
import { createSupabaseServerClient } from '@/lib/supabase/server';
```

## File Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Components | PascalCase.tsx | `Button.tsx`, `ShiftCard.tsx` |
| Data loaders | get[Name].ts | `getShifts.ts`, `getSettings.ts` |
| API routes | route.ts | `app/api/shifts/route.ts` |
| Types | PascalCase | `ShiftRow`, `UserSettings` |
| Utils | camelCase.ts | `formatCurrency.ts`, `dateHelpers.ts` |

## Examples from the Codebase

### Button Component (Two-Tier)

**Base** (`components/ui/button.tsx`):
- Generated by shadcn
- Generic variants
- Never imported directly

**Wrapper** (`components/app/Button.tsx`):
- Adds `loading` prop
- App-specific styling
- This is what gets imported

### Pay Settings Page

**Route** (`app/(app)/settings/pay/page.tsx`):
- Server component
- Auth check
- Loads settings
- Renders PayForm

**Form** (`components/settings/pay/PayForm.tsx`):
- Client component
- Form state
- POST to API
- router.refresh()

### Shifts Route

**Structure:**
```
app/(app)/shifts/
  ├── page.tsx               # Entry point
  └── _data/
      └── getShifts.ts       # Data loader (server-only)
components/shifts/
  ├── ShiftCard.tsx          # Individual shift
  └── ShiftStats.tsx         # Statistics
```

**Data Flow:**
1. `getShifts()` fetches + computes wages server-side
2. Page receives enriched data
3. Components just render (no computation)

## Troubleshooting

### "Cannot find module '@appui/Component'"

**Issue:** App wrapper wasn't created

**Fix:** Make sure to create `components/app/Component.tsx` after adding shadcn component

### "Hydration mismatch"

**Issue:** Client/server mismatch (dates, randomness, etc.)

**Fix:** Ensure all data is precomputed on server, client just renders

### "User not authenticated"

**Issue:** Missing auth check

**Fix:** Add auth check pattern to page component

### "Type error in data loader"

**Issue:** Types not exported/imported

**Fix:** Export types from data loader, import in components

## Tips for Best Results

1. **Be specific** - The more detail you provide, the better the output
2. **Reference existing patterns** - Say "like the PayForm but for notifications"
3. **Specify data structure** - Describe what fields/data the feature needs
4. **Mention special requirements** - Auth, validation, exports, etc.
5. **Review before proceeding** - Check the generated code preview

## Related Documentation

- [CLAUDE.md](../../../CLAUDE.md) - Project overview and architecture
- [docs/auth.md](../../../docs/auth.md) - Authentication flow details
- [docs/THEME.md](../../../docs/THEME.md) - Color token system
- [docs/calculations.md](../../../docs/calculations.md) - Payroll calculation spec

## Contributing to This Skill

To improve this skill:

1. **Add new templates** - Update `templates.md` with new patterns
2. **Document examples** - Add real examples to `examples.md`
3. **Update quick reference** - Keep `quick-reference.md` current
4. **Improve skill prompt** - Enhance `skill.md` instructions

## License

This skill is part of the app.kkarlsen.dev project and follows the same license.

---

**Ready to scaffold?** Invoke the skill and start building! 🚀
