# Tidex

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is an iOS-only product. This repository contains the supporting public/legal website and the shared backend. The `app.tidex.no` compatibility host was retired on 2026-11-08.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **ios/** - Native iOS application

The iOS app uses Convex on `one-s` and Clerk authentication. The retained Supabase database and GoTrue service support source data and legacy session refresh.

## Tech Stack

### Supporting Web Surfaces
- **Framework**: Next.js 16 with React 19
- **Purpose**: Public marketing and legal pages
- **Hosting**: Cloudflare Pages

### iOS (ios/)
- **Framework**: SwiftUI with iOS 26
- **Architecture**: MVVM with Swift concurrency

### Shared
- **Database**: Self-hosted Convex on `one-s`
- **Authentication**: Clerk
- **Payments**: None. Tidex is free since 2026-09-28; earlier purchases are handled manually via support
- **Push Notifications**: APNs through Convex

## Repository Structure

```
tidex/
├── marketing/          # Public Tidex site (tidex.no)
├── ios/                # Native iOS application
│   ├── TidexApp/       # iOS app target (Swift source)
│   ├── TidexShiftWidget/ # Widget extension
│   └── docs/           # iOS-specific documentation
├── backend/            # Production Convex backend
├── supabase/           # Retained source data and legacy GoTrue refresh
│   ├── functions/      # Retired edge-function source
│   ├── migrations/     # Database migrations
│   └── sql/            # SQL functions and cron jobs
└── docs/               # Shared documentation
```

## Getting Started

### Prerequisites

- Bun 1.4.4
- Xcode 27.2+ (for iOS development)

### Supporting Website Development

```bash
cd marketing
bun install
bun run dev         # Start the Tidex public/legal site locally (http://localhost:3001)
```

### Cloudflare Pages

The `tidex` Pages project builds from `marketing/` with `bun run build` and publishes `out/`. Pushing `main` deploys the public website.

```bash
bun run pages:deploy:marketing
```

Set `CLOUDFLARE_API_TOKEN` or authenticate with `bunx wrangler login` before deploying directly to the `tidex` Pages project.

### iOS Development

Open `ios/Tidex.xcodeproj` in Xcode and build.

### Environment Variables

The iOS string translator (`bun run localize`) calls Claude through the `ant` CLI. Install it with `brew install anthropics/tap/ant` and sign in with `ant auth login`.

The App Store metadata generator (`ios/Scripts/generate-appstore-metadata.mjs`) uses OpenAI. Create `.env.local` in the repository root before running it:

```env
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5.6-luna
```

## Documentation

- See `ios/AGENTS.md` for iOS development guidelines
- See `docs/` for shared documentation (database, notifications, payroll spec)

## License

Private
