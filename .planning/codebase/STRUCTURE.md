# Codebase Structure

**Analysis Date:** 2026-01-13

## Directory Layout

```
tidex/
├── app/                          # Next.js App Router
│   ├── [locale]/                # Locale-prefixed routes
│   │   ├── (app)/               # Protected app routes
│   │   └── (auth)/              # Public auth routes
│   ├── api/                     # REST API routes
│   ├── auth/                    # OAuth callback handler
│   └── .well-known/             # Apple App Site Association
├── components/                  # React components
│   ├── app/                    # App-specific wrapped components
│   ├── ui/                     # Raw shadcn/ui (never import directly)
│   ├── settings/               # Settings-specific components
│   ├── shifts/                 # Shift-specific components
│   └── providers/              # Context providers
├── data-access/                # Data Access Layer
├── lib/                        # Utilities & services
│   ├── services/              # Effect-based services
│   ├── payroll/               # Wage computation
│   ├── errors/                # Error handling
│   ├── validation/            # Input validation
│   ├── i18n/                  # Internationalization
│   ├── auth/                  # Authentication utilities
│   ├── supabase/              # Supabase clients
│   └── layers/                # Service composition
├── ios/                        # iOS Xcode project
├── supabase/                   # Database & edge functions
│   ├── functions/             # Edge functions
│   └── sql/                   # SQL functions & cron jobs
├── marketing/                  # Marketing website (monorepo)
├── dev-site/                   # Dev documentation site
├── tests/                      # Test files
├── public/                     # Static assets
├── docs/                       # Documentation
└── scripts/                    # Build & utility scripts
```

## Directory Purposes

**app/[locale]/(app)/:**
- Purpose: Protected routes requiring authentication
- Contains: Dashboard, shifts, stats, settings, wagey, sharing, onboarding
- Key files: Each route has `page.tsx`, some have `layout.tsx`, `_actions/`, `_components/`
- Subdirectories: Nested routes like `settings/security/`, `settings/subscription/`

**app/[locale]/(auth)/:**
- Purpose: Public authentication routes
- Contains: Login, signup, mfa-verify, reset-password, accept-terms, verify-email
- Key files: `page.tsx` with client components for forms

**app/api/:**
- Purpose: REST API endpoints
- Contains: shifts/, stats/, chat/, sharing/, admin/, locale/, error-report/
- Key files: `route.ts` files with GET/POST/PATCH/DELETE handlers

**components/app/:**
- Purpose: App-specific wrapped components (107 components)
- Contains: Button, Avatar, Card, Modal, Form components with app logic
- Key files: `Button.tsx`, `NavBar.tsx`, `HomeContent.tsx`, `ShiftsCalendar.tsx`
- Subdirectories: `skeletons/` for loading states

**components/ui/:**
- Purpose: Raw shadcn/ui components (never import directly)
- Contains: Radix-based primitives
- Key files: `button.tsx`, `dialog.tsx`, `input.tsx`, `select.tsx`

**data-access/:**
- Purpose: Centralized data loading with auth enforcement
- Contains: DAL functions for all data types
- Key files: `auth.ts`, `shifts.ts`, `settings.ts`, `stats.ts`, `subscription.ts`, `cache.ts`

**lib/services/:**
- Purpose: Effect-based services with type safety
- Contains: Business logic services
- Key files: `supabase.ts`, `shifts.ts`, `stats.ts`, `claude.ts`, `wagey.ts`, `sharing.ts`

**lib/payroll/:**
- Purpose: Pure wage calculation functions
- Contains: Computation logic, period splitting, break deduction
- Key files: `calc.ts`, `effect.ts`, `periods.ts`, `breaks.ts`, `presets.ts`, `types.ts`

**lib/errors/:**
- Purpose: Error handling utilities
- Contains: Tagged errors, message constants
- Key files: `tagged.ts`, `messages.ts`, `translate.ts`

**lib/i18n/:**
- Purpose: Internationalization
- Contains: Locale config, dictionary loading
- Key files: `config.ts`, `server.ts`, `client.ts`
- Subdirectories: `dictionaries/` with `en.ts`, `no.ts`

**supabase/functions/:**
- Purpose: Supabase Edge Functions
- Contains: Webhook handlers, cron job triggers
- Key files: `stripe_webhook/index.ts`, `apple-server-notifications/index.ts`, `send-push-notifications/index.ts`

**supabase/sql/:**
- Purpose: SQL function definitions and cron job documentation
- Contains: Function definitions by category
- Subdirectories: `functions/admin/`, `functions/auth/`, `functions/notification/`, `cron/`

## Key File Locations

**Entry Points:**
- `app/layout.tsx` - Root layout (theme, fonts, metadata)
- `proxy.ts` - Token refresh, locale routing
- `app/[locale]/layout.tsx` - i18n wrapper
- `app/supabase-listener.tsx` - Real-time auth sync

**Configuration:**
- `tsconfig.json` - TypeScript with path aliases
- `next.config.js` - Next.js with Turbopack, React Compiler
- `postcss.config.cjs` - Tailwind v4
- `vitest.config.ts` - Test runner configuration
- `capacitor.config.ts` - iOS app configuration

**Core Logic:**
- `data-access/*.ts` - All data loading functions
- `lib/services/*.ts` - Effect-based services
- `lib/payroll/calc.ts` - Wage computation entry point
- `lib/chat/executor.ts` - AI chat tool execution

**Testing:**
- `tests/integration/` - Integration tests (payroll, snapshots)
- `tests/e2e/` - Playwright E2E tests
- `tests/setup.ts` - Test configuration

**Documentation:**
- `CLAUDE.md` - Instructions for Claude Code
- `docs/*.md` - Feature documentation

## Naming Conventions

**Files:**
- PascalCase: React components (`Button.tsx`, `Avatar.tsx`)
- kebab-case: Utilities, services (`date-utils.ts`, `cookie-config.ts`)
- camelCase: Actions (`createShift.ts`, `deleteShift.ts`)
- UPPERCASE: Constants, documentation (`CLAUDE.md`, `ERRORS`)

**Directories:**
- kebab-case: All directories (`data-access`, `wage-snapshots`)
- Brackets: Dynamic segments (`[locale]`, `[id]`)
- Parentheses: Route groups (`(app)`, `(auth)`)
- Underscore: Private/co-located (`_actions`, `_components`)

**Special Patterns:**
- `page.tsx` - Route page component
- `layout.tsx` - Route layout component
- `route.ts` - API route handler
- `index.ts` - Barrel exports
- `*.test.ts` - Test files

## Where to Add New Code

**New Feature:**
- Primary code: `app/[locale]/(app)/{feature}/page.tsx`
- Server actions: `app/[locale]/(app)/{feature}/_actions/`
- Components: `components/{feature}/` or `app/[locale]/(app)/{feature}/_components/`
- Tests: `tests/integration/{feature}.test.ts`

**New Component:**
- App component: `components/app/{ComponentName}.tsx`
- Feature component: `components/{feature}/{ComponentName}.tsx`
- Skeleton: `components/app/skeletons/{ComponentName}Skeleton.tsx`

**New API Route:**
- Definition: `app/api/{resource}/route.ts`
- Nested: `app/api/{resource}/[id]/route.ts`

**New Service:**
- Service: `lib/services/{name}.ts`
- DAL function: `data-access/{name}.ts`
- Layer composition: Update `lib/layers/app.ts`

**Utilities:**
- Shared helpers: `lib/{name}.ts`
- Type definitions: `lib/types/{name}.ts`
- Validation: `lib/validation/{name}.ts`

## Special Directories

**ios/:**
- Purpose: iOS Xcode project (Capacitor-wrapped)
- Source: Generated by `npx cap add ios`
- Committed: Yes (with native customizations)

**.next/:**
- Purpose: Next.js build output
- Source: Auto-generated by build
- Committed: No (gitignored)

**node_modules/:**
- Purpose: Dependencies
- Source: pnpm install
- Committed: No (gitignored)

**public/:**
- Purpose: Static assets served at root
- Contains: `manifest.json`, icons, `.well-known/`
- Committed: Yes

---

*Structure analysis: 2026-01-13*
*Update when directory structure changes*
