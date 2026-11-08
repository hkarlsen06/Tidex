# Run Tidex from Xcode

Use the normal checkout at `/Users/hkarlsen06/repo/Tidex`. Open `ios/Tidex.xcodeproj`, select the App scheme, choose your iPhone or a shared simulator, and run with Debug.

Debug and Release use the same app identity, production Clerk instance, and production Convex backend. The URLs and Clerk key live in `ios/production-backend.xcconfig`, which both configurations include. Xcode installs update the same Tidex app as TestFlight. They use the existing keychain and local database. Changes made in a Debug build affect your real account and data.

The app does not need a local backend, Tailscale, a separate development account, or another checkout. The local Convex deployment remains available for explicit backend experiments. Deploy backend changes only after approval under the production deployment rule.

Clerk's fixed seven-day session lifetime is separate from the Xcode build configuration. A one-year native lifetime still needs an authenticated Clerk dashboard session and a suitable production plan. Existing sessions retain their old expiry after that setting changes.
