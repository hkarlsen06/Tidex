# Technology Stack

**Analysis Date:** 2026-01-13

## Languages

**Primary:**
- TypeScript 5.9.3 - All application code (`package.json`)

**Secondary:**
- JavaScript - Build scripts, config files
- Swift - iOS native code (`ios/App/`)
- SQL - Database migrations, functions (`supabase/sql/`)

## Runtime

**Environment:**
- Node.js 24+ - `.nvmrc` specifies Node 24
- React 19 - Client-side rendering

**Package Manager:**
- pnpm 10.28.0 - `package.json` packageManager field
- Lockfile: `pnpm-lock.yaml` present

## Frameworks

**Core:**
- Next.js 16.1.1 - App Router with locale-based routing (`next.config.js`)
- React 19 - UI framework (default with Next.js 16)
- SwiftUI - Native iOS app (`ios/App/TidexApp/`)

**Testing:**
- Vitest 4.0.17 - Unit and integration tests (`vitest.config.ts`)
- Playwright 1.57.0 - E2E tests (`playwright.config.ts`)
- fast-check 0.2.4 - Property-based testing (`@fast-check/vitest`)

**Build/Dev:**
- Turbopack - Default bundler in Next.js 16 (`next.config.js`)
- Tailwind CSS 4.1.18 - Styling framework (`postcss.config.cjs`)
- PostCSS 8.5.6 - CSS processing

## Key Dependencies

**Critical:**
- Effect 3.19.14 - Type-safe services and error handling (`lib/services/`)
- Supabase 2.90.1 - Database and authentication (`@supabase/supabase-js`, `@supabase/ssr`)
- Stripe 19.3.1 - Payment processing
- Motion 12.26.1 - React animations (`motion/react`)

**UI:**
- Radix UI - Component primitives (via shadcn/ui pattern)
- Lucide React 0.562.0 - Icon library
- Recharts 3.6.0 - Charts and analytics
- React Day Picker 9.13.0 - Date selection

**Infrastructure:**
- Zod 4.3.5 - Runtime validation
- date-fns 4.1.0 - Date utilities
- clsx 2.1.1, tailwind-merge 3.4.0 - Classname utilities

**iOS Native:**
- SwiftUI - Native UI framework
- Supabase Swift SDK - Database and authentication
- Firebase iOS SDK - Push notifications (FCM)
- StoreKit 2 - In-app purchases

## Configuration

**Environment:**
- `.env.local` - Local development (gitignored)
- `.env.local.example` - Template with required variables
- Key variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`

**Build:**
- `tsconfig.json` - TypeScript strict mode, path aliases (`@/*`, `@components/*`, `@ui/*`, `@dal/*`)
- `next.config.js` - Bundle analyzer, React Compiler, compression, Turbopack
- `postcss.config.cjs` - Tailwind v4 plugin (`@tailwindcss/postcss`)
- `vitest.config.ts` - Test runner with jsdom, coverage via v8

## Platform Requirements

**Development:**
- macOS/Linux/Windows with Node.js 24+
- pnpm 10.28+ for package management
- Xcode (for iOS development only)

**Production:**
- Vercel - Web hosting with Turbopack builds
- Supabase - PostgreSQL database, Edge Functions, Auth
- Apple App Store - iOS distribution

---

*Stack analysis: 2026-01-13*
*Update after major dependency changes*
