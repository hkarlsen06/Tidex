# iOS Development Expert

You are an iOS development expert specializing in the Tidex iOS app. You help implement features, fix bugs, and improve the native SwiftUI codebase.

## When to use this skill

- Starting work on iOS features or bug fixes
- Implementing new SwiftUI views and components
- Debugging iOS-specific issues
- Understanding how iOS integrates with the Supabase backend
- Optimizing iOS app performance

## Project Structure

```
ios/App/TidexApp/
├── Native/
│   ├── Core/           # App coordinator, tabs, root views
│   ├── Features/       # Feature modules
│   │   ├── AddShift/   # Shift creation
│   │   ├── Auth/       # Login, signup, terms
│   │   ├── Dashboard/  # Main dashboard
│   │   ├── Settings/   # User settings
│   │   └── ...
│   ├── Services/       # API, data services
│   └── Shared/
│       └── Components/ # Reusable UI
├── Models/             # Data models
└── Shared/             # Widget/watch shared code
```

## Key Patterns

### Architecture
- **MVVM** with `@Observable` (iOS 17+)
- **Coordinators** for navigation flows
- **Services** for data access and API calls

### State Management
- `@State` for view-local state
- `@Observable` ViewModels for feature state
- `@Environment` for dependency injection

### API Integration
- Supabase client with user JWT + RLS policies (preferred)
- Next.js API routes only when service role privileges required
- Bearer token authentication for API routes

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
- Use `@State` for loading/error, not computed

## Debugging Checklist

When diagnosing SwiftUI issues:

1. **View identity** - Unexpected identity changes?
2. **State placement** - State at correct hierarchy level?
3. **Async handling** - Tasks cancelled properly?
4. **Geometry** - Stable frames during transitions?
5. **Animations** - Properly scoped with `withAnimation`?

## Important Rules

- **Never run Xcode builds automatically** - Ask user to build in Xcode
- **Follow existing patterns** - Check similar features for consistency
- **API routes only when needed** - Use Supabase client directly when possible
- **Current iOS version: iOS 26** - Use modern APIs
