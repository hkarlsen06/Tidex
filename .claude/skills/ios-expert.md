# iOS Development Expert

You are an iOS development expert specializing in the Tidex iOS app. You help implement features, fix bugs, and improve the native SwiftUI codebase.

## When to use this skill

- Starting work on iOS features or bug fixes
- Implementing new SwiftUI views and components
- Debugging iOS-specific issues
- Understanding how iOS integrates with the Supabase backend
- Working with the local-first sync system
- Optimizing iOS app performance

## Project Structure

```
ios/
├── TidexApp/                  # Main iOS application
│   ├── App/                   # App entry, coordinator, root views, tabs
│   ├── Features/              # Feature modules
│   │   ├── AddShift/          # Shift creation/editing
│   │   ├── Auth/              # Login, signup, MFA, Apple/Google sign-in
│   │   ├── Onboarding/        # Pre & post-auth onboarding flows
│   │   ├── Dashboard/         # Main view with month navigation, earnings
│   │   ├── Shifts/            # Shift list views with filtering/sorting
│   │   ├── Stats/             # Statistics & analytics
│   │   ├── Settings/          # User settings, pay config, appearance
│   │   ├── Sharing/           # Share shifts with friends
│   │   ├── Wagey/             # AI chat assistant
│   │   ├── Paywall/           # Premium subscription UI
│   │   └── Celebration/       # Achievement celebrations
│   ├── Services/              # API clients, payroll, auth, notifications
│   ├── Storage/               # SwiftData models, repositories, sync
│   │   ├── LocalStore.swift   # SwiftData container (primary storage)
│   │   ├── Models/            # Local* SwiftData model files
│   │   ├── Repositories/      # Data access (ShiftsRepository, etc.)
│   │   └── Sync/              # SyncCoordinator, conflict resolution
│   ├── Models/                # Data models and DTOs
│   └── Shared/                # Reusable components, extensions, design system
│       ├── Components/        # AvatarView, CalendarDayCell, PrimaryButton, etc.
│       ├── Extensions/        # Color+Tidex, Date+Tidex, View+Glass, etc.
│       ├── Managers/          # AppearanceManager, CelebrationManager, etc.
│       └── DesignSystem/      # Typography, Spacing
├── TidexShiftWidget/          # Home/lock screen widgets, live activities
├── TidexWatchApp/             # Apple Watch companion app
├── Shared/                    # Cross-target shared code (APIs, models)
├── Resources/Localization/    # Xcode String Catalogs (App, Widget, Watch)
├── Scripts/                   # Localization & build scripts
├── fastlane/                  # App Store deployment automation
└── docs/                      # Architecture documentation
```

## Key Patterns

### Architecture: Local-First with MVVM
- **Local-first**: All reads from SwiftData, writes mark records dirty for sync
- **SyncCoordinator**: Bidirectional sync (Pull → Conflict Detection → Push → Cleanup)
- **Repositories**: Data access layer over SwiftData (ShiftsRepository, SettingsRepository, etc.)
- **ViewModels**: `@MainActor`, `ObservableObject` with repository/service dependencies
- **AppCoordinator**: Singleton managing auth state and navigation flow
- **Services**: Network, payroll calculation, notifications, StoreKit

### State Management
- `@State` for view-local state
- `@StateObject` / `@ObservedObject` for view models
- `@Environment` for dependency injection
- SwiftData `@Model` for persistent local models with dirty tracking

### API Integration
- Supabase client with user JWT + RLS policies (preferred)
- Next.js API routes only when service role privileges required
- Bearer token authentication for API routes

### Storage Layer
- **LocalStore** (SwiftData actor): Primary persistent storage
- **Dirty tracking**: clean/dirty/pendingDelete states on all models
- **Repositories**: Thread-safe data access wrapping LocalStore
- **Sync triggers**: Manual refresh, app foreground (30s min interval), post-auth

## SwiftUI Best Practices

**View Identity:**
- Use explicit `.id()` modifiers for dynamic content
- Stable ForEach identifiers to prevent layout jumps

**Animations:**
- Use `withAnimation` for state-driven animations
- `.animation()` modifier for value-driven animations
- Spring animations for natural feel

**Async Data:**
- `.task(id:)` for cancellable async work
- Handle `CancellationError` gracefully
- Show loading states during fetches

**Performance:**
- Minimize `GeometryReader` usage
- Keep computed properties lightweight
- ViewModels cache data with 5-minute TTL
- Dashboard prefetches neighboring months

## Localization (Required)

All UI strings must be localized. Use the `add-strings` script:
```bash
add-strings --key "feature.context.description" --en "English text" --nb "Norwegian text"
```
Reference strings via generated `LocalizedStringResource` symbols (e.g., `.featureContextDescription`).

## Color System

Use semantic colors from `Color+Tidex.swift` (e.g., `Color.tidexSurfacePrimary`, `Color.tidexTextSecondary`). Never hardcode colors.

## Debugging Checklist

When diagnosing issues:

1. **View identity** - Unexpected identity changes?
2. **State placement** - State at correct hierarchy level?
3. **Sync state** - Dirty tracking correct? Conflict resolution working?
4. **Async handling** - Tasks cancelled properly?
5. **Geometry** - Stable frames during transitions?
6. **Animations** - Properly scoped with `withAnimation`?

## Important Rules

- **You may run xcodebuild** with simulator destination and reasonable timeout. Stop and report if it hangs.
- **Follow existing patterns** - Check similar features for consistency
- **API routes only when needed** - Use Supabase client directly when possible
- **Current iOS version: iOS 26** - Liquid Glass design language, use modern APIs
- **Always localize strings** - Never hardcode user-visible text
