# Tidex

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is now an iOS-only product. This repository still contains the supporting public/legal website, the legacy compatibility host for old `app.tidex.no` links, the developer site, and the shared Supabase backend.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **app-compat/** - Static Cloudflare Pages compatibility site for `app.tidex.no`
- **dev-site/** - Developer portfolio site for `kkarlsen.dev`
- **ios/** - Native iOS application

The iOS app and its supporting web infrastructure share a common Supabase backend for authentication, database, and edge functions.

## Tech Stack

### Supporting Web Surfaces
- **Framework**: Next.js 16 with React 19
- **Purpose**: Public marketing/legal pages plus legacy compatibility redirects
- **Hosting**: Cloudflare Pages

### iOS (ios/)
- **Framework**: SwiftUI with iOS 26
- **Architecture**: MVVM with Swift concurrency

### Shared
- **Database & Auth**: Supabase
- **Payments**: Apple IAP (iOS) + legacy Stripe subscriptions handled manually via support
- **Push Notifications**: Firebase Cloud Messaging

## Repository Structure

```
tidex/
├── marketing/          # Public Tidex site (tidex.no)
├── app-compat/         # Static compatibility host (app.tidex.no)
├── dev-site/           # Developer portfolio (kkarlsen.dev)
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

- Bun 1.3.14+
- Xcode 16+ (for iOS development)

### Supporting Website Development

```bash
cd marketing
bun install
bun run dev         # Start the Tidex public/legal site locally (http://localhost:3001)
```

### Cloudflare Pages

The marketing Pages project builds from `marketing/` with `bun run build` and publishes `out/`. The compatibility project publishes `app-compat/` directly.

```bash
bun run pages:deploy:marketing
bun run pages:deploy:app-compat
```

Set `CLOUDFLARE_API_TOKEN` or authenticate with `bunx wrangler login` before deploying. These scripts target the existing `tidex` and `app-compat` Pages projects.

### iOS Development

Open `ios/Tidex.xcodeproj` in Xcode and build.

### Environment Variables

Create `.env.local` in the repository root when running the iOS localization scripts:

```env
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5.6-luna
OPENAI_REASONING_EFFORT=max
```

## Documentation

- See `ios/AGENTS.md` for iOS development guidelines
- See `docs/` for shared documentation (database, notifications, payroll spec)

## License

Private
