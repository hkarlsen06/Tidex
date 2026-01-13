# Coding Conventions

**Analysis Date:** 2026-01-13

## Naming Patterns

**Files:**
- PascalCase: React components (`Button.tsx`, `Avatar.tsx`, `TimeInput.tsx`)
- kebab-case: Utilities, services (`date-utils.ts`, `cookie-config.ts`, `shift-validators.ts`)
- camelCase: Server actions (`createShift.ts`, `updateShift.ts`)
- `*.test.ts`: Test files alongside or in `tests/`

**Functions:**
- camelCase for all functions
- Prefixed with verb: `get*`, `set*`, `create*`, `compute*`, `validate*`
- Event handlers: `handle*` (`handleClick`, `handleSubmit`)
- No special prefix for async functions

**Variables:**
- camelCase for local variables
- UPPER_SNAKE_CASE for constants (`PRESET_WAGE_RATES`, `WEEKDAYS`, `ERRORS`)
- No underscore prefix for private members

**Types:**
- PascalCase for interfaces, no I prefix (`User`, `ShiftRow`, `WageSnapshot`)
- PascalCase for type aliases (`UserSettings`, `ComputedShift`)
- PascalCase for enums, UPPER_CASE for values

**Effect-TS:**
- Service suffix for services (`ShiftsService`, `SupabaseService`)
- Live suffix for implementations (`ShiftsServiceLive`, `AppConfigLive`)
- Error suffix for tagged errors (`DatabaseError`, `ValidationError`)

## Code Style

**Formatting:**
- ESLint flat config (`eslint.config.js`) - no Prettier
- 2 space indentation
- Double quotes for strings
- Semicolons required
- 100 character line length (soft limit)

**Linting:**
- ESLint with `@typescript-eslint/recommended`
- Next.js core-web-vitals rules
- React 19 best practices
- Unused vars prefixed with `_` to ignore
- Run: `pnpm lint`

## Import Organization

**Order:**
1. React, Next.js built-ins (`react`, `next/navigation`)
2. External packages (`effect`, `@supabase/ssr`)
3. Internal modules (`@/lib/`, `@/components/`)
4. Relative imports (`./utils`, `../types`)
5. Type imports (`import type { User }`)

**Grouping:**
- Blank line between groups
- Alphabetical within each group (by convention, not enforced)

**Path Aliases:**
- `@/*` - Project root
- `@components/*` - `components/`
- `@ui/*` - `components/ui/` (never use directly)
- `@dal/*` - `data-access/`

## Error Handling

**Patterns:**
- Services throw Effect tagged errors (`DatabaseError`, `ValidationError`)
- DAL catches with `Effect.catchTag` or `Effect.match`
- Server actions return `{ error: string }` for form errors
- API routes return JSON with appropriate status codes

**Error Types (`lib/errors/tagged.ts`):**
```typescript
export class DatabaseError extends Data.TaggedError("DatabaseError")<{...}> {}
export class ValidationError extends Data.TaggedError("ValidationError")<{...}> {}
export class NotFoundError extends Data.TaggedError("NotFoundError")<{...}> {}
export class AuthError extends Data.TaggedError("AuthError")<{...}> {}
```

**Error Messages:**
- User-facing: Norwegian in `lib/errors/messages.ts` (ERRORS constant)
- Internal: English in code/logs

## Logging

**Framework:**
- `lib/logger.ts` wrapper over console
- Levels: log, warn, error, debug

**Patterns:**
- Structured context: `logger.error({ err, userId }, 'Message')`
- Log at service boundaries
- No console.log in production code (use logger)

## Comments

**When to Comment:**
- Explain why, not what
- Document business rules and edge cases
- Complex algorithms and workarounds
- Avoid obvious comments

**JSDoc/TSDoc:**
- Required for public API functions
- Optional for internal if signature is self-explanatory
- Use `@param`, `@returns`, `@throws` tags

**TODO Comments:**
- Format: `// TODO: description`
- Link to issue if exists: `// TODO: Fix race condition (issue #123)`

## Function Design

**Size:**
- Keep under 50 lines when possible
- Extract helpers for complex logic
- One level of abstraction per function

**Parameters:**
- Max 3 parameters
- Use options object for 4+ parameters
- Destructure in parameter list: `({ id, name }: Params)`

**Return Values:**
- Explicit return statements
- Return early for guard clauses
- Effect for services, Promise for DAL

## Module Design

**Exports:**
- Named exports preferred
- Default exports for pages only
- Export public API from barrel files

**Barrel Files:**
- `index.ts` re-exports public API
- Keep internal helpers private
- Avoid circular dependencies

## Component Patterns

**Two-Tier System:**
- Raw components in `components/ui/` (shadcn/ui)
- Wrapped components in `components/app/`
- Always import from `components/app`

**Client Components:**
- Use `"use client"` directive at top
- Keep server data loading in parent
- Pass data as props

**Server Components:**
- Default for pages
- Call DAL functions directly
- Use `connection()` for prerender opt-out

**Skeleton Loading:**
- Dedicated skeleton components in `components/app/skeletons/`
- Match layout of actual component
- Use `Skeleton` primitive from shadcn

## Server Action Patterns

**Structure:**
```typescript
"use server";

import { verifySession } from "@/data-access/auth";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

export async function createShift(data: FormData) {
  const user = await verifySession();

  // Validate input
  // Call DAL function
  // Revalidate cache

  invalidateAndRevalidate(user.id);
  return { success: true };
}
```

**Cache Invalidation (Next.js 16):**
```typescript
import { revalidateTag } from "next/cache";

// ✅ CORRECT - Works everywhere, required second argument
revalidateTag(`user-${userId}`, "max");

// ❌ WRONG - Only works in Server Actions
import { updateTag } from "next/cache";
updateTag(`user-${userId}`);
```

## Effect-TS Patterns

**Service Definition:**
```typescript
export class MyService extends Context.Tag("MyService")<
  MyService,
  { readonly getData: (id: string) => Effect.Effect<Data, MyError> }
>() {}
```

**Layer Implementation:**
```typescript
export const MyServiceLive = Layer.effect(
  MyService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService;

    const getData = (id: string) =>
      Effect.gen(function* () {
        const result = yield* supabase.query(...);
        return result;
      });

    return { getData };
  })
);
```

**DAL Wrapper:**
```typescript
export async function getMyData(id: string) {
  return Effect.runPromise(
    Effect.gen(function* () {
      const service = yield* MyService;
      return yield* service.getData(id);
    }).pipe(Effect.provide(MyServiceLive))
  );
}
```

---

*Convention analysis: 2026-01-13*
*Update when patterns change*
