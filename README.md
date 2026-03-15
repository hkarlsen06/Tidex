# Tidex

A monorepo for tracking work shifts and calculating wages, containing:

- **marketing/** - Next.js 16 public website for `tidex.no`
- **app-compat/** - Static Cloudflare Pages compatibility site for `app.tidex.no`
- **dev-site/** - Developer portfolio site for `kkarlsen.dev`
- **ios/** - Native iOS application

The public web surfaces and the iOS app share a common Supabase backend for authentication, database, and edge functions.

## Tech Stack

### Web (marketing/)
- **Framework**: Next.js 16 with React 19
- **Styling**: Tailwind CSS v4 with semantic design tokens
- **Hosting**: Static export for Cloudflare Pages

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

- Node.js 24.x
- pnpm
- Xcode 16+ (for iOS development)

### Web Development

```bash
cd marketing
pnpm install
pnpm dev            # Start the Tidex public site locally (http://localhost:3001)
```

### iOS Development

Open `ios/Tidex.xcodeproj` in Xcode and build.

### Environment Variables

Create `.env.local` in the repository root when running the iOS localization scripts:

```env
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5.4
```

## Documentation

- See `ios/AGENTS.md` for iOS development guidelines
- See `docs/` for shared documentation (database, notifications, payroll spec)

## License

Private
