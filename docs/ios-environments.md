# Run Tidex from Xcode

Use the normal checkout at `/Users/hkarlsen06/repo/Tidex`. Open `ios/Tidex.xcodeproj`, select the App scheme, choose your iPhone or a shared simulator, and run with Debug.

Debug and Release use the same app identity, production Clerk instance, and production Convex backend. The URLs and Clerk key live in `ios/production-backend.xcconfig`, which both configurations include. Xcode installs update the same Tidex app as TestFlight. They use the existing keychain and local database. Changes made in a Debug build affect your real account and data.

The app does not need a local backend, Tailscale, a separate development account, or another checkout. The local Convex deployment remains available for explicit backend experiments. Deploy backend changes only after approval under the production deployment rule.

The production Clerk instance is on the Pro plan since 2026-11-14. Its Sessions page has no maximum lifetime, a one-year inactivity timeout, and native sessions follow the web settings, so a session's `expire_at` reads as the year 2094. On the Hobby plan every session ended 7 days after sign-in, and 26 users were signed out that way between 5 and 13 November. Sessions created before the change keep their 7-day expiry, so those users sign in once more. The Xcode build configuration does not affect session lifetime.
