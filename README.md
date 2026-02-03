# Tidex

A monorepo for tracking work shifts and calculating wages, containing:

- **next/** - Next.js 16 web application
- **ios/** - Native iOS application

Both apps share a common Supabase backend for authentication, database, and edge functions.

## Tech Stack

### Web (next/)
- **Framework**: Next.js 16 with React 19
- **Styling**: Tailwind CSS v4 with semantic design tokens
- **Type Safety**: TypeScript with Effect-TS for services layer
- **Testing**: Vitest with React Testing Library + Playwright for E2E

### iOS (ios/)
- **Framework**: SwiftUI with iOS 26
- **Architecture**: MVVM with Swift concurrency

### Shared
- **Database & Auth**: Supabase
- **Payments**: Stripe (web) + Apple IAP (iOS)
- **Push Notifications**: Firebase Cloud Messaging

## Repository Structure

```
tidex/
├── next/               # Next.js web application
│   ├── app/            # App router pages and API routes
│   ├── components/     # React components
│   ├── data-access/    # Data Access Layer (DAL)
│   ├── lib/            # Utilities, services, payroll calculations
│   ├── public/         # Static assets
│   └── docs/           # Web-specific documentation
├── ios/                # Native iOS application
│   ├── TidexApp/       # iOS app target (Swift source)
│   ├── TidexShiftWidget/ # Widget extension
│   ├── TidexWatchApp/  # watchOS app
│   └── docs/           # iOS-specific documentation
├── supabase/           # Shared backend
│   ├── functions/      # Edge functions
│   ├── migrations/     # Database migrations
│   └── sql/            # SQL functions and cron jobs
└── docs/               # Shared documentation
```

## Getting Started

### Prerequisites

- Node.js 24.x
- pnpm
- Xcode 16+ (for iOS development)

### Web Development

```bash
cd next
pnpm install
pnpm dev            # Start HTTP dev server (http://localhost:3000)
pnpm dev:https      # Start HTTPS dev server (https://localhost:3000)
```

### iOS Development

Open `ios/Tidex.xcodeproj` in Xcode and build.

### Environment Variables

Create `next/.env.local` with:

```env
# Supabase
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your_supabase_anon_key

# Stripe
NEXT_PUBLIC_PRO_PRICE_ID=your_stripe_pro_price_id
NEXT_PUBLIC_MAX_PRICE_ID=your_stripe_max_price_id

# Security
NEXT_PUBLIC_TURNSTILE_SITE_KEY=your_turnstile_site_key

# AI (Wagey)
CLAUDE_API_KEY=your_claude_api_key
CLAUDE_MODEL=your_claude_model
```

## Documentation

- See `next/CLAUDE.md` for web development guidelines
- See `ios/CLAUDE.md` for iOS development guidelines
- See `docs/` for shared documentation (database, notifications, payroll spec)

## License

Private
