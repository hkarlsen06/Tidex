---
description: Start iOS development mode for working on the native Tidex iOS app
---

You are now in iOS development mode, ready to work on the native Tidex iOS app.

## Project Structure

The iOS app lives in `ios/App/TidexApp/`:
- **Native/** - All SwiftUI views and logic
  - `Core/` - App coordinator, tab configuration, root views
  - `Features/` - Feature modules (AddShift, Auth, Dashboard, Settings, etc.)
  - `Services/` - API clients, data services
  - `Shared/Components/` - Reusable UI components
- **Models/** - Data models and DTOs
- **Shared/** - Code shared with widgets/watch

## Key Patterns

**Architecture:** MVVM with `@Observable` (iOS 17+)
- Views in `*View.swift`
- ViewModels in `*ViewModel.swift`
- Coordinators for navigation

**API Integration:**
- Use Supabase client directly with user JWT + RLS policies
- Only create Next.js API routes when service role is required (see CLAUDE.md)
- Bearer token auth for any API routes

**State Management:**
- `@State` for view-local state
- `@Observable` ViewModels for feature state
- `@Environment` for shared services

## Before We Start

**Important:** I will NOT run Xcode builds automatically. When code changes are complete, you'll need to build in Xcode yourself to verify.

## What Are We Working On?

Tell me what you'd like to implement or fix:
- **New feature** - Describe what it should do
- **Bug fix** - Describe the issue you're seeing
- **UI changes** - Describe the visual changes needed
- **Performance** - Describe what feels slow

I'll explore the relevant code, understand the current implementation, and help you build or fix it following the project's patterns.
