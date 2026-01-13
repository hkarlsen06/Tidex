# Tidex

A Next.js 16 application for tracking work shifts and calculating wages with Supabase authentication. Supports internationalization (i18n) with Norwegian and English locales. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

## Tech Stack

- **Framework**: Next.js 16 with React 19
- **Database & Auth**: Supabase
- **Styling**: Tailwind CSS v4 with semantic design tokens
- **Type Safety**: TypeScript with Effect-TS for services layer
- **Testing**: Vitest with React Testing Library + Playwright for E2E
- **Payments**: Stripe

## Getting Started

### Prerequisites

- Node.js 24.x
- pnpm

### Installation

```bash
pnpm install
```

### Environment Variables

Create a `.env.local` file with:

```env
# Supabase
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your_supabase_anon_key

# Stripe
NEXT_PUBLIC_PRO_PRICE_ID=your_stripe_pro_price_id
NEXT_PUBLIC_MAX_PRICE_ID=your_stripe_max_price_id
NEXT_PUBLIC_PRO_YEARLY_ID=your_stripe_pro_yearly_price_id
NEXT_PUBLIC_MAX_YEARLY_ID=your_stripe_max_yearly_price_id

# Security
NEXT_PUBLIC_TURNSTILE_SITE_KEY=your_turnstile_site_key

# AI (Wagey)
CLAUDE_API_KEY=your_claude_api_key
CLAUDE_MODEL=your_claude_model
```

### Development

```bash
pnpm dev            # Start HTTP dev server (http://localhost:3000)
pnpm dev:https      # Start HTTPS dev server (https://localhost:3000)
```

### Build & Production

```bash
pnpm build          # Production build
pnpm start          # Run production server
```

### Testing

```bash
pnpm test           # Run tests
pnpm test:watch     # Run tests in watch mode
pnpm test:ui        # Run tests with UI
pnpm test:coverage  # Run tests with coverage
```

## Project Structure

```
app/
├── [locale]/(app)/     # Protected routes (dashboard, shifts, stats, settings, wagey, sharing, onboarding)
├── [locale]/(auth)/    # Auth routes (login, signup, verify-email, reset-password, mfa-verify, accept-terms, logout)
├── auth/callback/      # OAuth/magic link callback handler
components/
├── app/                # App-specific wrapped components (import from here)
├── ui/                 # Raw shadcn/ui components (never import directly)
data-access/            # Data Access Layer - all database queries
lib/
├── auth/               # Authentication utilities
├── errors/             # Effect-based tagged errors
├── hooks/              # React hooks
├── i18n/               # Internationalization config and dictionaries
├── layers/             # Effect Layer composition
├── payroll/            # Pure wage calculation functions
├── revalidation/       # Cache invalidation utilities
├── services/           # Effect-based service layer
├── supabase/           # Supabase client utilities
├── validation/         # Schema validation with Effect
```

## Key Conventions

- **Component imports**: Always use `@/components/app/*`, never import from `@ui/*` directly
- **Data access**: All database queries go through the Data Access Layer (`data-access/`)
- **Styling**: Use semantic color tokens (`bg-surface-primary`, `text-text-secondary`), never hardcoded colors
- **i18n**: All user-facing routes include `[locale]` parameter; translations in `lib/i18n/dictionaries/`
- **Server-side computation**: Payroll calculations happen server-side in the DAL
- **Effect-TS**: All DAL functions and services use Effect internally with Promise wrappers at boundaries

## License

Private
