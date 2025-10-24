# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Next.js 15 application for tracking work shifts and calculating wages with Supabase authentication. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

## Development Commands

```bash
npm run dev      # Start dev server with Turbo (http://localhost:3000)
npm run build    # Production build
npm start        # Run production server
npm run lint     # Run ESLint
```

## Architecture

### Route Structure

- `app/(app)/*` - Protected routes requiring authentication (home, shifts)
- `app/(auth)/*` - Public authentication routes (login, logout)
- `app/auth/callback/` - OAuth/magic link callback handler

Each route group has its own layout:

- `app/(app)/layout.tsx` - Renders TopHeader and wraps authenticated pages
- `app/(auth)/layout.tsx` - Minimal layout for auth pages
- `app/layout.tsx` - Root layout with theme initialization script

### Authentication Flow

Uses `@supabase/ssr` with cookie-based sessions:

1. **Server-side**: Use `createSupabaseServerClient()` from `lib/supabase/server.ts` in Server Components and data loaders
2. **Client-side**: Import the shared `supabase` instance from `lib/supabase/browser.ts` in Client Components
3. **Session sync**: `app/supabase-listener.tsx` subscribes to auth changes via the shared client and calls `router.refresh()` to update server components

Protected pages fetch user via `createSupabaseServerClient()` and redirect to `/login` if unauthenticated. See `docs/auth.md` for detailed flow.

### Component System

**Critical: Two-tier component architecture**

- `components/ui/*` - Raw shadcn/ui components (generated, do not import directly)
- `components/app/*` - Wrapped components with app-specific logic and styling

**Always import from `components/app`, never from `components/ui`**

To add new shadcn components:

```bash
npm dlx shadcn@latest add <component-name>
```

Then create a wrapper in `components/app/` (see `components/ui/shadcn_components.md` for patterns).

### Import Aliases

Defined in `tsconfig.json`:

- `@/*` - Project root
- `@components/*` - `components/`
- `@ui/*` - `components/ui/`
- `@appui/*` - `components/app/`

### Theming & Styling

**Dark mode is class-based**: The `dark` class on `<html>` toggles between themes.

Theme management:

- `ThemeToggle` component controls theme (in `components/app/ThemeToggle.tsx`)
- Theme state synced to localStorage
- Initial theme set via inline script in `app/layout.tsx` (prevents flash)
- Tailwind configured with `darkMode: ["class"]` in `tailwind.config.js`

**Color system**: CSS variables in `app/globals.css` define semantic tokens for light and dark modes:

- Surface: `bg-surface-primary`, `bg-surface-secondary`
- Text: `text-text-primary`, `text-text-secondary`, `text-text-muted`
- Background: `bg-background`, `bg-background-secondary`
- Borders: `border-border`, `border-border-subtle`
- Brand: `bg-brand-gradientStart`, etc.

**Never use hardcoded colors** (e.g., `bg-slate-900`, `text-gray-400`). Always use semantic tokens so components respond to theme changes.

The root `<body>` must have `bg-background text-foreground` classes for proper theming.

See `docs/THEME.md` for color token management.

### Payroll Calculation System

Pure, deterministic wage calculations live in `lib/payroll/`:

- **Entry point**: `computeShift(shift, settings, presetRules)` from `lib/payroll/calc.ts`
- **Zero I/O**: All inputs explicit, no dates from system clock
- **Server-side only**: Compute once per fetch in data loaders (e.g., `app/(app)/shifts/_data/getShifts.ts`)
- **Client receives precomputed data**: UI renders `gross`, `paidHours`, etc. without recalculation

Key concepts:

- Base rate resolved from snapshot, preset table, or custom wage
- Time split into wage periods with supplement overlays
- Break deductions applied via configurable policies (fixed, proportional, etc.)
- [Removed] No per-shift manual pause; policy-based only
- Cross-midnight shifts supported (when `end <= start`, treat as next day)

See `docs/calculations.md` for complete specification.

### Data Loading Pattern

Server Components fetch and compute data:

```tsx
// app/(app)/shifts/_data/getShifts.ts
export async function getComputedShifts(userId: string) {
  const supabase = await createSupabaseServerClient();
  // 1. Load user settings
  // 2. Load raw shifts
  // 3. Compute each shift with computeShift()
  // 4. Return enriched shifts with derived fields
}
```

Pages import and await these loaders, never calling Supabase directly.

## Configuration Files

Configuration files are in the project root:

- `tailwind.config.js` - Tailwind theme and semantic colors
- `postcss.config.cjs` - PostCSS with Tailwind plugin
- `tsconfig.json` - TypeScript configuration with path aliases
- `next.config.js` - Next.js configuration with PWA settings

## Environment Variables

Required in `.env.local`:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_SUPABASE_REDIRECT_URL` (optional; login flow constructs callback URLs dynamically)

Validated at module load in `lib/supabase/browser.ts` and accessed via `lib/env.ts`.

## Key Principles

1. **Never import from `components/ui` directly** - always wrap and import from `components/app`
2. **Use semantic color tokens** - avoid hardcoded Tailwind colors like `slate-*` or `gray-*`
3. **Centralize Supabase access** - use helpers in `lib/supabase`, never instantiate clients elsewhere
4. **Compute wages server-side** - `lib/payroll` functions are pure and called in data loaders
5. **Theme-aware components** - all UI must respond to light/dark mode via CSS variables
6. **Server-first auth checks** - redirect before render to avoid unauthenticated UI flashes
