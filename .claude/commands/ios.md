---
description: Start iOS development mode for working on the native Tidex iOS app
---

You are now in iOS development mode, ready to work on the native Tidex iOS app.

## Project Structure

The iOS app and extensions are inside `ios/`.

**Main App** (`ios/TidexApp/`):
- `App/` - App entry point, AppCoordinator, RootView, MainTabView, push notifications
- `Features/` - Feature modules (AddShift, Auth, Onboarding, Dashboard, Shifts, Stats, Settings, Sharing, Wagey, Paywall, Celebration)
- `Services/` - AuthService, PayrollCalculator, PayrollEngine, NotificationService, StoreKitManager, WageyService, etc.
- `Storage/` - LocalStore (SwiftData), Local* models, Repositories, SyncCoordinator
- `Models/` - Data models and DTOs (Shift, WageSnapshot, Currency, Friend, etc.)
- `Shared/` - Reusable components, Color+Tidex extensions, Typography, Spacing

**Widgets** (`ios/TidexShiftWidget/`) - Home screen, lock screen widgets, live activities

**Shared** (`ios/Shared/`) - Cross-target shared APIs and models

**Resources** (`ios/Resources/Localization/`) - Xcode String Catalogs for the app, widgets, and share extension

## Key Patterns

**Architecture:** Local-first MVVM with bidirectional sync
- **All reads** come from SwiftData (offline-capable, instant)
- **All writes** mark records dirty, SyncCoordinator pushes to Supabase
- **Repositories** wrap LocalStore for thread-safe data access
- **ViewModels** are `@MainActor ObservableObject` with repository/service dependencies
- **AppCoordinator** manages auth state flow: loading → unauthenticated → mfaRequired → termsRequired → authenticated

**State Management:**
- `@State` for view-local state
- `@StateObject` / `@ObservedObject` for view models
- `@Environment` for dependency injection
- SwiftData `@Model` with dirty tracking (clean/dirty/pendingDelete)

**API Integration:**
- Use Supabase client directly with user JWT + RLS policies (preferred)
- Only create Next.js API routes when service role is required (see CLAUDE.md)
- Bearer token auth for any API routes

**Localization (Required):**
- Never hardcode user-visible strings
- Add strings: `add-strings --key "feature.context.description" --en "English text" --nb "Norwegian text"`
- Use generated `LocalizedStringResource` symbols in code (e.g., `.featureContextDescription`)

**Color System:**
- Always use semantic colors from `Color+Tidex.swift` (e.g., `Color.tidexSurfacePrimary`)
- Never hardcode color values

## Build

You may run xcodebuild with simulator destination and reasonable timeout:
```bash
cd /Users/hjalmarsamuelkarlsen/Lokalt/Cloned-Repos/tidex/ios && xcodebuild -project Tidex.xcodeproj -scheme App -destination 'generic/platform=iOS Simulator' build
```
If a build hangs or takes too long, stop and report.

**Current iOS version: iOS 26** (Liquid Glass design language)

## What Are We Working On?

Tell me what you'd like to implement or fix:
- **New feature** - Describe what it should do
- **Bug fix** - Describe the issue you're seeing
- **UI changes** - Describe the visual changes needed
- **Performance** - Describe what feels slow

I'll explore the relevant code, understand the current implementation, and help you build or fix it following the project's patterns.
