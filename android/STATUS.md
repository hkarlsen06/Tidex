# Android App Status

## Overview

Android version of Tidex, built with Capacitor 8.0.0 and Kotlin. Mirrors the iOS app's functionality with native tab bar, splash screen, shift notifications, and offline mode.

## What Works

### Core Functionality
- [x] App builds and runs
- [x] WebView loads content from `https://app.tidex.no`
- [x] Login/authentication flow
- [x] Edge-to-edge display
- [x] Dark theme background (`#020817`) - no white flash

### Splash Screen
- [x] Android 12+ SplashScreen API integration
- [x] Custom app icon in splash
- [x] Auto-dismiss fallback (2 seconds) if JS plugin call fails

### Network & Offline
- [x] Network connectivity monitoring (`NetworkMonitor.kt`)
- [x] Offline screen with Jetpack Compose UI
- [x] Cached shift data display when offline
- [x] Auto-reconnect when network restored
- [x] Retry button functionality

### Configuration
- [x] Firebase configured (`google-services.json`)
- [x] Deep links: `tidex://` custom scheme
- [x] App Links: `https://app.tidex.no`
- [x] FileProvider for document sharing

## Custom Capacitor Plugins

All plugins are registered in `MainActivity.onCreate()` before `super.onCreate()`.

| Plugin | Status | Notes |
|--------|--------|-------|
| `NativeTabBarPlugin` | Needs testing | Controls BottomNavigationView |
| `NativeSplashPlugin` | Needs testing | Splash screen control |
| `ShiftActivityPlugin` | Needs testing | Ongoing notifications for active shifts |
| `DocumentSharePlugin` | Needs testing | Share PDF/CSV via Android share sheet |

### Plugin Methods

**NativeTabBar**
- `setSelectedTab(index)` - Highlight tab
- `clearSelection()` - Deselect all tabs
- `setTabBadge(index, value)` - Show badge
- `setTabTitles(titles)` - Update labels
- `hide()` / `show()` - Toggle visibility
- `isAvailable()` - Check availability
- `getTabBarHeight()` - Get height in pixels

**NativeSplash**
- `hide(fadeOutDuration)` - Dismiss with animation
- `show()` - Re-show (rare)
- `isVisible()` - Check state

**ShiftActivity**
- `startActivity(data)` - Start ongoing notification
- `updateActivity(data)` - Update progress/earnings
- `endActivity()` / `endAllActivities()` - Dismiss
- `getActiveActivity()` - Check running
- `isAvailable()` - Always true on Android
- `saveShiftsToSharedStorage(shifts)` - Save to SharedPreferences

**DocumentShare**
- `shareDocument(data, filename, mimeType)` - Open share sheet

## What Needs Work

### Testing Required
- [ ] Tab bar show/hide based on route
- [ ] Tab selection sync with web navigation
- [ ] Tab re-tap for scroll-to-top (`tabReselected` event)
- [ ] Badge display on tabs
- [ ] Shift notification appearance and updates
- [ ] Document sharing (PDF/CSV export)
- [ ] Push notifications via Firebase

### Not Yet Implemented
- [ ] In-App Purchases (Google Play Billing)
- [ ] Widget (skipped for v1)
- [ ] Digital Asset Links verification (`/.well-known/assetlinks.json`)

### Known Issues
- Swipe-back gesture from left edge may need tuning (50px threshold)

## Project Structure

```
android/app/src/main/java/no/tidex/app/
├── MainActivity.kt              # Main activity, plugin registration
├── plugins/
│   ├── NativeTabBarPlugin.kt    # Bottom navigation control
│   ├── NativeSplashPlugin.kt    # Splash screen control
│   ├── ShiftActivityPlugin.kt   # Ongoing notifications
│   └── DocumentSharePlugin.kt   # Share sheet integration
├── features/
│   ├── OfflineScreen.kt         # Compose offline UI
│   └── OfflineShiftStorage.kt   # SharedPreferences access
└── utilities/
    ├── NetworkMonitor.kt        # Connectivity detection
    └── TidexColors.kt           # Brand colors
```

## Build Requirements

- Java 21 (required for SDK 36)
- Kotlin 1.9.24 with JVM target 21
- Android SDK 36 (compile) / 23 (min)
- Jetpack Compose BOM 2024

## Commands

```bash
# Sync Capacitor
pnpm exec cap sync android

# Open in Android Studio
pnpm exec cap open android

# Build debug APK (from android directory)
./gradlew assembleDebug
```

## Testing Checklist

When testing, verify:

1. **App Launch**
   - Splash appears briefly then dismisses
   - Content loads without white flash
   - Login works

2. **Tab Bar**
   - Appears on dashboard/shifts/stats/sharing routes
   - Hidden on login/settings routes
   - Correct tab highlighted when navigating
   - Re-tapping tab scrolls to top

3. **Offline Mode**
   - Turn off WiFi/data
   - Offline screen appears with cached data
   - "Retry" reloads app
   - Reconnects automatically when online

4. **Notifications** (if shift active)
   - Ongoing notification appears
   - Progress bar updates
   - Earnings display correctly
   - Dismisses when shift ends

5. **Sharing**
   - Export PDF from stats
   - Android share sheet opens
   - File can be shared to other apps
