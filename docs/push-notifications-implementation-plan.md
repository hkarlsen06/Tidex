# Push Notifications Implementation Plan

This document outlines the complete implementation plan for native push notifications in Tidex using Firebase Cloud Messaging (FCM) with Supabase backend.

## Overview

**Goal**: Notify users when someone who shares their shifts with them adds a new shift. Tapping the notification opens the app and navigates to that user's shared calendar with the new shift highlighted.

**Architecture**:
```
User A adds shift → Supabase DB trigger → Edge Function → FCM HTTP v1 → APNs → iOS notification
                                                              ↓
                                                    User B taps notification
                                                              ↓
                                                    Deep link to shared calendar
```

---

## Phase 1: Firebase & Apple Setup

### 1.1 Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" → Name it "Tidex" or "Tidex Push"
3. Disable Google Analytics (not needed for push)
4. Once created, go to Project Settings → General
5. Add an iOS app:
   - Bundle ID: `no.tidex.app`
   - Download `GoogleService-Info.plist` (needed later)

### 1.2 Configure APNs in Firebase

1. Go to [Apple Developer Console](https://developer.apple.com/account)
2. Navigate to: Certificates, Identifiers & Profiles → Keys
3. Create a new key:
   - Name: "Tidex Push Notifications"
   - Enable "Apple Push Notifications service (APNs)"
   - Download the `.p8` file (save securely, only downloadable once)
   - Note the **Key ID** shown after creation
4. Note your **Team ID** (top right of Apple Developer page, or in Membership)
5. In Firebase Console → Project Settings → Cloud Messaging:
   - Under "Apple app configuration", click the iOS app
   - Upload the APNs Authentication Key (`.p8` file)
   - Enter Key ID and Team ID

### 1.3 Create Google Service Account for FCM HTTP v1

> **Important**: We use FCM HTTP v1 API (not legacy) because it supports APNs-specific options and is the recommended approach.

1. In Firebase Console → Project Settings → Service Accounts
2. Click "Generate new private key"
3. Download the JSON file (contains credentials for OAuth2)
4. Store this securely - you'll add it to Supabase secrets

### 1.4 Enable Push Capability in Xcode

1. Open `ios/App/App.xcworkspace` in Xcode
2. Select the "App" target → Signing & Capabilities
3. Click "+ Capability" → Add "Push Notifications"
4. Also add "Background Modes" capability:
   - Check "Remote notifications"
5. Ensure signing is configured with your Apple Developer account

### 1.5 Add GoogleService-Info.plist

1. Copy `GoogleService-Info.plist` to `ios/App/App/`
2. In Xcode, right-click the App folder → "Add Files to App"
3. Select `GoogleService-Info.plist`
4. Ensure "Copy items if needed" is checked

---

## Phase 2: Database Schema

### 2.1 Push Device Tokens Table

```sql
-- Migration: create_push_devices_table
CREATE TABLE push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),

  -- Device identification for account switching
  device_id TEXT, -- iOS: identifierForVendor, allows token rotation
  device_model TEXT, -- e.g., "iPhone 14 Pro"
  app_version TEXT,  -- e.g., "1.2.0"

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Token is globally unique; when same device switches users, update user_id
  UNIQUE(fcm_token)
);

-- Index for looking up user's devices
CREATE INDEX idx_push_devices_user_id ON push_devices(user_id);

-- Index for device lookup (token rotation scenarios)
CREATE INDEX idx_push_devices_device_id ON push_devices(device_id) WHERE device_id IS NOT NULL;

-- Auto-update updated_at on row update
CREATE OR REPLACE FUNCTION update_push_devices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER push_devices_updated_at
  BEFORE UPDATE ON push_devices
  FOR EACH ROW
  EXECUTE FUNCTION update_push_devices_updated_at();

-- RLS: Users can only manage their own devices
ALTER TABLE push_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own devices"
  ON push_devices FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own devices"
  ON push_devices FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own devices"
  ON push_devices FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own devices"
  ON push_devices FOR DELETE
  USING (auth.uid() = user_id);

-- Note: Service role bypasses RLS automatically, no policy needed
```

### 2.2 Notification Queue Table

```sql
-- Migration: create_notification_queue_table
CREATE TABLE notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Notification type for routing/handling
  type TEXT NOT NULL CHECK (type IN (
    'shared_shift_created',
    'shared_shift_updated',
    'shared_shift_deleted',
    'share_request'  -- Future: when someone wants to share with you
  )),

  -- Who should receive this notification
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Who triggered the notification
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Notification content (minimal - client fetches details)
  payload JSONB NOT NULL DEFAULT '{}',

  -- Delivery tracking with atomic claiming support
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',     -- Waiting to be processed
    'processing',  -- Claimed by a worker
    'sent',        -- Successfully delivered
    'failed',      -- Delivery failed
    'skipped'      -- No devices registered
  )),
  error_message TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_at TIMESTAMPTZ,  -- When a worker claimed this row
  processed_at TIMESTAMPTZ,

  -- Prevent duplicate notifications for same event
  idempotency_key TEXT UNIQUE
);

-- Index for processing pending notifications with atomic claiming
CREATE INDEX idx_notification_queue_pending
  ON notification_queue(created_at)
  WHERE status = 'pending';

-- Index for finding stale "processing" rows (worker died)
CREATE INDEX idx_notification_queue_stale_processing
  ON notification_queue(claimed_at)
  WHERE status = 'processing';

CREATE INDEX idx_notification_queue_recipient ON notification_queue(recipient_id);

-- RLS: Only service role can access (Edge Functions bypass RLS automatically)
ALTER TABLE notification_queue ENABLE ROW LEVEL SECURITY;

-- No client policies - service role only
```

### 2.3 Notification Preferences Table

```sql
-- Migration: create_notification_preferences_table
CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Notification type toggles
  shared_shifts_enabled BOOLEAN NOT NULL DEFAULT true,

  -- Future notification types
  -- weekly_summary_enabled BOOLEAN NOT NULL DEFAULT false,
  -- shift_reminders_enabled BOOLEAN NOT NULL DEFAULT false,

  -- Quiet hours (optional, for future use)
  quiet_hours_start TIME,  -- e.g., '22:00'
  quiet_hours_end TIME,    -- e.g., '07:00'

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_notification_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notification_preferences_updated_at
  BEFORE UPDATE ON notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_notification_preferences_updated_at();

-- RLS: Users can only manage their own preferences
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own preferences"
  ON notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own preferences"
  ON notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own preferences"
  ON notification_preferences FOR UPDATE
  USING (auth.uid() = user_id);
```

### 2.4 Database Trigger for New Shifts

```sql
-- Migration: create_shift_notification_trigger

-- Function to queue notifications when a shift is created
-- Uses single INSERT...SELECT instead of loop for performance
CREATE OR REPLACE FUNCTION queue_shift_created_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  owner_name TEXT;
BEGIN
  -- Get the shift owner's display name with fallback
  SELECT COALESCE(display_name, email, 'Someone')
  INTO owner_name
  FROM profiles
  WHERE id = NEW.user_id;

  -- Fallback if profile doesn't exist (shouldn't happen, but be safe)
  IF owner_name IS NULL THEN
    owner_name := 'Someone';
  END IF;

  -- Single INSERT...SELECT instead of loop for better performance
  INSERT INTO notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'shared_shift_created',
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'shift_id', NEW.id,
      'shift_date', NEW.shift_date,
      'owner_id', NEW.user_id,
      'owner_name', owner_name
      -- Note: Minimal payload. Client fetches full details on open.
    ),
    'shift_created:' || NEW.id || ':' || ss.viewer_id
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND ss.blocked = false
    AND COALESCE(np.shared_shifts_enabled, true) = true
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on shift insert
CREATE TRIGGER on_shift_created_notify
  AFTER INSERT ON shifts
  FOR EACH ROW
  EXECUTE FUNCTION queue_shift_created_notification();
```

---

## Phase 3: Capacitor Plugin Setup

### 3.1 Install Dependencies

```bash
# Capacitor Firebase Messaging plugin (gives FCM tokens on iOS)
pnpm add @capacitor-firebase/messaging

# Device plugin for device ID
pnpm add @capacitor/device

# Sync native project
npx cap sync ios
```

> **Why @capacitor-firebase/messaging?**
>
> The standard `@capacitor/push-notifications` returns APNs tokens on iOS, not FCM tokens.
> Since we're sending via FCM HTTP v1, we need FCM tokens. The `@capacitor-firebase/messaging`
> plugin properly integrates with Firebase SDK and returns FCM tokens.

### 3.2 iOS Native Configuration

Update `ios/App/App/AppDelegate.swift`:

```swift
import UIKit
import Capacitor
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Firebase BEFORE creating the window
        FirebaseApp.configure()

        // Set messaging delegate
        Messaging.messaging().delegate = self

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Create window programmatically since Main.storyboard was removed
        window = UIWindow(frame: UIScreen.main.bounds)

        // Set window background to match splash screen and dark theme
        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        window?.backgroundColor = darkBackground

        let vc = CAPBridgeViewController()
        vc.view.backgroundColor = darkBackground

        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // MARK: - Remote Notification Registration
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass APNs token to Firebase - it will exchange for FCM token
        Messaging.messaging().apnsToken = deviceToken
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // FCM token received/refreshed
        // The @capacitor-firebase/messaging plugin handles forwarding this to JS
        print("[FCM] Token received: \(fcmToken ?? "nil")")
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner even when app is in foreground
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // The @capacitor-firebase/messaging plugin handles forwarding tap data to JS
        completionHandler()
    }
}
```

### 3.3 Add Firebase iOS SDK via Swift Package Manager

Since Capacitor 6+ uses Swift Package Manager by default:

1. Open `ios/App/App.xcworkspace` in Xcode
2. File → Add Package Dependencies
3. Enter: `https://github.com/firebase/firebase-ios-sdk`
4. Select version: 11.0.0 or later
5. Add these products to your App target:
   - FirebaseCore
   - FirebaseMessaging

Alternatively, if using CocoaPods, update `ios/App/Podfile`:

```ruby
target 'App' do
  capacitor_pods

  # Firebase
  pod 'FirebaseCore', '~> 11.0'
  pod 'FirebaseMessaging', '~> 11.0'
end
```

Then: `cd ios/App && pod install`

---

## Phase 4: Client-Side Implementation

### 4.1 Push Notification Service

Create `lib/notifications/push-service.ts`:

```typescript
import { Capacitor } from '@capacitor/core'
import { supabase } from '@/lib/supabase/browser'

export interface PushNotificationPayload {
  type: 'shared_shift_created' | 'shared_shift_updated' | 'shared_shift_deleted'
  shift_id: string
  owner_id: string
  owner_name: string
  shift_date: string
}

class PushNotificationService {
  private initialized = false
  private currentToken: string | null = null

  async initialize(): Promise<void> {
    if (this.initialized || !Capacitor.isNativePlatform()) {
      return
    }

    try {
      // Dynamic import to avoid loading on web
      const { FirebaseMessaging } = await import('@capacitor-firebase/messaging')
      const { Device } = await import('@capacitor/device')
      const { App } = await import('@capacitor/app')

      // Check/request permission
      const permResult = await FirebaseMessaging.requestPermissions()
      if (permResult.receive !== 'granted') {
        console.log('[Push] Permission denied')
        return
      }

      // Get FCM token
      const { token } = await FirebaseMessaging.getToken()
      if (token) {
        console.log('[Push] FCM token received')
        this.currentToken = token

        // Get device info for registration
        const deviceInfo = await Device.getInfo()
        const deviceId = await Device.getId()
        const appInfo = await App.getInfo()

        await this.saveTokenToServer(token, {
          deviceId: deviceId.identifier,
          deviceModel: deviceInfo.model,
          appVersion: appInfo.version,
        })
      }

      // Listen for token refresh
      FirebaseMessaging.addListener('tokenReceived', async ({ token }) => {
        console.log('[Push] Token refreshed')
        this.currentToken = token

        const deviceId = await Device.getId()
        await this.saveTokenToServer(token, {
          deviceId: deviceId.identifier,
        })
      })

      // Listen for notification tap (app was in background/killed)
      FirebaseMessaging.addListener('notificationActionPerformed', ({ notification }) => {
        console.log('[Push] Notification tapped:', notification)
        const data = notification.data as PushNotificationPayload
        if (data) {
          this.handleNotificationTap(data)
        }
      })

      // Listen for notification received while app is in foreground
      FirebaseMessaging.addListener('notificationReceived', ({ notification }) => {
        console.log('[Push] Notification received in foreground:', notification)
        // Could show in-app toast here
      })

      this.initialized = true
    } catch (error) {
      console.error('[Push] Initialization failed:', error)
    }
  }

  private async saveTokenToServer(
    fcmToken: string,
    metadata: {
      deviceId?: string
      deviceModel?: string
      appVersion?: string
    }
  ): Promise<void> {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      console.log('[Push] No user logged in, skipping token save')
      return
    }

    // Upsert with ON CONFLICT on fcm_token
    // This handles:
    // 1. New device registration
    // 2. Same device, same user (updates metadata)
    // 3. Same device, different user (updates user_id - account switch)
    const { error } = await supabase.from('push_devices').upsert(
      {
        user_id: user.id,
        fcm_token: fcmToken,
        platform: Capacitor.getPlatform() as 'ios' | 'android',
        device_id: metadata.deviceId,
        device_model: metadata.deviceModel,
        app_version: metadata.appVersion,
        last_seen_at: new Date().toISOString(),
      },
      {
        onConflict: 'fcm_token',
        // This ensures user_id gets updated on conflict (account switching)
      }
    )

    if (error) {
      console.error('[Push] Failed to save token:', error)
    } else {
      console.log('[Push] Token saved successfully')
    }
  }

  private handleNotificationTap(payload: PushNotificationPayload): void {
    // Build URL to shared calendar with highlight
    const url = `/${getLocale()}/sharing?user=${payload.owner_id}&highlight=${payload.shift_id}&date=${payload.shift_date}`

    // Navigate using the App URL listener pattern (consistent with OAuth flow)
    if (typeof window !== 'undefined') {
      window.location.href = url
    }
  }

  async removeTokenOnLogout(): Promise<void> {
    if (!this.currentToken) return

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    // Remove this specific token
    await supabase
      .from('push_devices')
      .delete()
      .eq('fcm_token', this.currentToken)

    this.currentToken = null
  }

  async updateLastSeen(): Promise<void> {
    if (!this.currentToken) return

    await supabase
      .from('push_devices')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('fcm_token', this.currentToken)
  }
}

// Helper to get current locale
function getLocale(): string {
  if (typeof window !== 'undefined') {
    // Extract from URL or cookie
    const match = window.location.pathname.match(/^\/(no|en)\//)
    return match?.[1] ?? 'no'
  }
  return 'no'
}

export const pushNotificationService = new PushNotificationService()
```

### 4.2 Initialize on App Load

Create `components/providers/PushNotificationProvider.tsx`:

```typescript
'use client'

import { useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { pushNotificationService } from '@/lib/notifications/push-service'

export function PushNotificationProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    if (Capacitor.isNativePlatform()) {
      pushNotificationService.initialize()

      // Update last_seen periodically when app is active
      const interval = setInterval(() => {
        pushNotificationService.updateLastSeen()
      }, 5 * 60 * 1000) // Every 5 minutes

      return () => clearInterval(interval)
    }
  }, [])

  return <>{children}</>
}
```

Add to app layout in `app/[locale]/(app)/layout.tsx`:

```typescript
import { PushNotificationProvider } from '@/components/providers/PushNotificationProvider'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <PushNotificationProvider>
      {/* existing layout content */}
      {children}
    </PushNotificationProvider>
  )
}
```

### 4.3 Handle Deep Link Navigation

Update `app/capacitor-url-listener.tsx` to also handle push notification deep links:

```typescript
// Add to existing CapacitorUrlListener component
// Inside the appUrlOpen listener:

if (url.startsWith('tidex://sharing')) {
  // Push notification deep link
  const customUrl = new URL(url)
  const httpsUrl = new URL(`https://app.tidex.no${customUrl.pathname}`)
  customUrl.searchParams.forEach((value, key) => {
    httpsUrl.searchParams.set(key, value)
  })

  setTimeout(() => {
    window.location.href = httpsUrl.toString()
  }, 100)
}
```

Update the sharing page to handle highlight params in `app/[locale]/(app)/sharing/page.tsx`:

```typescript
import { Suspense } from 'react'
import { SharingPageContent } from '@/components/sharing/SharingPageContent'

interface PageProps {
  searchParams: Promise<{
    user?: string
    highlight?: string
    date?: string
  }>
}

export default async function SharingPage({ searchParams }: PageProps) {
  const params = await searchParams

  return (
    <Suspense fallback={<SharingPageSkeleton />}>
      <SharingPageContent
        initialSelectedUserId={params.user}
        highlightShiftId={params.highlight}
        highlightDate={params.date}
      />
    </Suspense>
  )
}
```

Update shift display to highlight in `components/sharing/SharedUserShiftPreview.tsx`:

```typescript
interface Props {
  shift: SharedShift
  highlightShiftId?: string | null
}

export function SharedUserShiftPreview({ shift, highlightShiftId }: Props) {
  const isHighlighted = shift.id === highlightShiftId
  const highlightedRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to highlighted shift
  useEffect(() => {
    if (isHighlighted && highlightedRef.current) {
      // Small delay to ensure DOM is ready
      setTimeout(() => {
        highlightedRef.current?.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        })
      }, 300)
    }
  }, [isHighlighted])

  return (
    <div
      ref={isHighlighted ? highlightedRef : undefined}
      className={cn(
        "shift-card transition-all duration-300",
        isHighlighted && "ring-2 ring-brand-500 bg-brand-50 dark:bg-brand-950/20"
      )}
    >
      {/* shift content */}
    </div>
  )
}
```

---

## Phase 5: Supabase Edge Function

### 5.1 FCM HTTP v1 with Atomic Queue Processing

Create `supabase/functions/send-push-notifications/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// FCM HTTP v1 credentials (from Google service account JSON)
const FCM_PROJECT_ID = Deno.env.get('FCM_PROJECT_ID')!
const FCM_CLIENT_EMAIL = Deno.env.get('FCM_CLIENT_EMAIL')!
const FCM_PRIVATE_KEY = Deno.env.get('FCM_PRIVATE_KEY')!.replace(/\\n/g, '\n')

// Cache access token (valid for 1 hour)
let cachedAccessToken: { token: string; expiresAt: number } | null = null

interface NotificationPayload {
  shift_id: string
  shift_date: string
  owner_id: string
  owner_name: string
}

interface QueuedNotification {
  id: string
  type: string
  recipient_id: string
  sender_id: string
  payload: NotificationPayload
}

serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    // Atomic claim: SELECT ... FOR UPDATE SKIP LOCKED + UPDATE in one transaction
    // This prevents double-processing if function is invoked concurrently
    const { data: notifications, error: claimError } = await supabase.rpc(
      'claim_pending_notifications',
      { batch_size: 50 }
    )

    if (claimError) {
      console.error('Failed to claim notifications:', claimError)
      throw claimError
    }

    if (!notifications?.length) {
      return new Response(JSON.stringify({ processed: 0, message: 'No pending notifications' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get FCM access token
    const accessToken = await getFcmAccessToken()

    let processed = 0
    let failed = 0
    const invalidTokens: string[] = []

    for (const notification of notifications as QueuedNotification[]) {
      try {
        // Get recipient's FCM tokens
        const { data: devices } = await supabase
          .from('push_devices')
          .select('id, fcm_token')
          .eq('user_id', notification.recipient_id)

        if (!devices?.length) {
          // No devices registered, mark as skipped
          await supabase
            .from('notification_queue')
            .update({
              status: 'skipped',
              processed_at: new Date().toISOString(),
            })
            .eq('id', notification.id)
          continue
        }

        // Send to each device
        let anySuccess = false
        for (const device of devices) {
          const result = await sendToFcm(accessToken, device.fcm_token, notification)

          if (result.success) {
            anySuccess = true
          } else if (result.invalidToken) {
            // Token is invalid, queue for deletion
            invalidTokens.push(device.id)
          }
        }

        // Mark notification status
        await supabase
          .from('notification_queue')
          .update({
            status: anySuccess ? 'sent' : 'failed',
            error_message: anySuccess ? null : 'All devices failed',
            processed_at: new Date().toISOString(),
          })
          .eq('id', notification.id)

        if (anySuccess) processed++
        else failed++

      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error)

        await supabase
          .from('notification_queue')
          .update({
            status: 'failed',
            error_message: error instanceof Error ? error.message : 'Unknown error',
            processed_at: new Date().toISOString(),
          })
          .eq('id', notification.id)

        failed++
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      await supabase
        .from('push_devices')
        .delete()
        .in('id', invalidTokens)
      console.log(`Deleted ${invalidTokens.length} invalid tokens`)
    }

    return new Response(
      JSON.stringify({
        processed,
        failed,
        total: notifications.length,
        invalidTokensRemoved: invalidTokens.length,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

async function sendToFcm(
  accessToken: string,
  fcmToken: string,
  notification: QueuedNotification
): Promise<{ success: boolean; invalidToken?: boolean }> {
  const { payload } = notification

  // Localized message (Norwegian)
  const title = 'Ny vakt delt med deg'
  const body = `${payload.owner_name} la til en vakt ${formatDate(payload.shift_date)}`

  // FCM HTTP v1 message format
  const message = {
    message: {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: {
        type: notification.type,
        shift_id: payload.shift_id,
        owner_id: payload.owner_id,
        owner_name: payload.owner_name,
        shift_date: payload.shift_date,
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
            // Omit badge - we don't have unread count yet
            'mutable-content': 1,
          },
        },
      },
    },
  }

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    }
  )

  if (response.ok) {
    return { success: true }
  }

  const errorBody = await response.text()
  console.error(`FCM error for token ${fcmToken.substring(0, 20)}...:`, errorBody)

  // Check for invalid token errors
  if (
    errorBody.includes('UNREGISTERED') ||
    errorBody.includes('INVALID_ARGUMENT') ||
    errorBody.includes('NOT_FOUND')
  ) {
    return { success: false, invalidToken: true }
  }

  return { success: false }
}

async function getFcmAccessToken(): Promise<string> {
  // Return cached token if still valid
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60000) {
    return cachedAccessToken.token
  }

  // Generate JWT for Google OAuth2
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: FCM_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const jwt = await createJwt(payload, FCM_PRIVATE_KEY)

  // Exchange JWT for access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  if (!response.ok) {
    throw new Error(`Failed to get FCM access token: ${await response.text()}`)
  }

  const data = await response.json()
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in * 1000),
  }

  return data.access_token
}

async function createJwt(payload: object, privateKey: string): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const signingInput = `${encodedHeader}.${encodedPayload}`

  // Import private key and sign
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput)
  )

  return `${signingInput}.${base64UrlEncode(signature)}`
}

function base64UrlEncode(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input)

  const base64 = btoa(String.fromCharCode(...bytes))
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')

  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

function formatDate(dateStr: string): string {
  const date = new Date(dateStr)
  return date.toLocaleDateString('nb-NO', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })
}
```

### 5.2 Atomic Claim Function

Create this Postgres function for atomic claiming:

```sql
-- Migration: create_claim_notifications_function

CREATE OR REPLACE FUNCTION claim_pending_notifications(batch_size INTEGER DEFAULT 50)
RETURNS SETOF notification_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- First, reset any stale "processing" rows (worker died)
  -- Rows claimed more than 5 minutes ago are considered stale
  UPDATE notification_queue
  SET status = 'pending', claimed_at = NULL
  WHERE status = 'processing'
    AND claimed_at < NOW() - INTERVAL '5 minutes';

  -- Atomically claim and return rows
  RETURN QUERY
  WITH claimed AS (
    UPDATE notification_queue
    SET
      status = 'processing',
      claimed_at = NOW()
    WHERE id IN (
      SELECT id
      FROM notification_queue
      WHERE status = 'pending'
      ORDER BY created_at
      FOR UPDATE SKIP LOCKED
      LIMIT batch_size
    )
    RETURNING *
  )
  SELECT * FROM claimed;
END;
$$;
```

### 5.3 Deploy Edge Function

```bash
# Login to Supabase CLI
supabase login

# Link to your project
supabase link --project-ref your-project-ref

# Set secrets from Google service account JSON
supabase secrets set FCM_PROJECT_ID=your-firebase-project-id
supabase secrets set FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
supabase secrets set FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEv...your-key...\n-----END PRIVATE KEY-----"

# Deploy
supabase functions deploy send-push-notifications
```

### 5.4 Set Up Scheduled Invocation

Use pg_cron to trigger the Edge Function every minute:

```sql
-- Enable pg_cron extension (if not already)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Enable pg_net for HTTP requests
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule notification processing every minute
SELECT cron.schedule(
  'process-push-notifications',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/send-push-notifications',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

Note: Configure `app.settings.supabase_url` and `app.settings.service_role_key` in your Supabase project settings or use direct values.

---

## Phase 6: Settings UI

### 6.1 Notification Preferences Component

Create `components/settings/NotificationSettings.tsx`:

```typescript
'use client'

import { useState, useEffect, useCallback } from 'react'
import { Switch } from '@/components/app/Switch'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card'
import { Bell } from 'lucide-react'
import { supabase } from '@/lib/supabase/browser'
import { Capacitor } from '@capacitor/core'
import { Button } from '@/components/app/Button'

interface NotificationPreferences {
  shared_shifts_enabled: boolean
}

type PermissionStatus = 'granted' | 'denied' | 'prompt' | 'unknown'

export function NotificationSettings() {
  const [preferences, setPreferences] = useState<NotificationPreferences>({
    shared_shifts_enabled: true,
  })
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatus>('unknown')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const checkPermissionStatus = useCallback(async () => {
    if (!Capacitor.isNativePlatform()) {
      setPermissionStatus('granted') // Web shows as available
      return
    }

    try {
      const { FirebaseMessaging } = await import('@capacitor-firebase/messaging')
      const status = await FirebaseMessaging.checkPermissions()
      setPermissionStatus(status.receive as PermissionStatus)
    } catch {
      setPermissionStatus('unknown')
    }
  }, [])

  const loadPreferences = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data } = await supabase
      .from('notification_preferences')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (data) {
      setPreferences(data)
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    loadPreferences()
    checkPermissionStatus()
  }, [loadPreferences, checkPermissionStatus])

  async function updatePreference(key: keyof NotificationPreferences, value: boolean) {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    setSaving(true)
    setPreferences(prev => ({ ...prev, [key]: value }))

    const { error } = await supabase
      .from('notification_preferences')
      .upsert({
        user_id: user.id,
        [key]: value,
      })

    if (error) {
      // Revert on error
      setPreferences(prev => ({ ...prev, [key]: !value }))
      console.error('Failed to save preference:', error)
    }

    setSaving(false)
  }

  async function requestPermission() {
    if (!Capacitor.isNativePlatform()) return

    try {
      const { FirebaseMessaging } = await import('@capacitor-firebase/messaging')
      const result = await FirebaseMessaging.requestPermissions()
      setPermissionStatus(result.receive as PermissionStatus)

      if (result.receive === 'granted') {
        // Re-initialize to register token
        const { pushNotificationService } = await import('@/lib/notifications/push-service')
        await pushNotificationService.initialize()
      }
    } catch (error) {
      console.error('Failed to request permission:', error)
    }
  }

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <div className="h-6 w-32 bg-surface-secondary animate-pulse rounded" />
        </CardHeader>
        <CardContent>
          <div className="h-12 bg-surface-secondary animate-pulse rounded" />
        </CardContent>
      </Card>
    )
  }

  const isNative = Capacitor.isNativePlatform()

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Bell className="h-5 w-5" />
          Varslinger
        </CardTitle>
        <CardDescription>
          Velg hvilke varslinger du vil motta
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {isNative && permissionStatus === 'denied' && (
          <div className="p-4 bg-amber-50 dark:bg-amber-950/20 text-amber-800 dark:text-amber-200 rounded-lg">
            <p className="text-sm">
              Varslinger er deaktivert for denne appen. Gå til Innstillinger → Tidex for å aktivere.
            </p>
          </div>
        )}

        {isNative && permissionStatus === 'prompt' && (
          <Button
            onClick={requestPermission}
            className="w-full"
          >
            Aktiver varslinger
          </Button>
        )}

        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <p className="font-medium">Delte vakter</p>
            <p className="text-sm text-text-secondary">
              Få varsel når noen deler en ny vakt med deg
            </p>
          </div>
          <Switch
            checked={preferences.shared_shifts_enabled}
            onCheckedChange={(checked) => updatePreference('shared_shifts_enabled', checked)}
            disabled={saving || (isNative && permissionStatus === 'denied')}
          />
        </div>
      </CardContent>
    </Card>
  )
}
```

### 6.2 Add to Settings Page

Create `app/[locale]/(app)/settings/notifications/page.tsx`:

```typescript
import { connection } from 'next/server'
import { NotificationSettings } from '@/components/settings/NotificationSettings'
import { getDictionary } from '@/lib/i18n/dictionaries'

interface PageProps {
  params: Promise<{ locale: string }>
}

export default async function NotificationSettingsPage({ params }: PageProps) {
  await connection()
  const { locale } = await params
  const dict = await getDictionary(locale)

  return (
    <div className="container max-w-2xl py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Varslinger</h1>
        <p className="text-text-secondary">
          Administrer varslingsinnstillingene dine
        </p>
      </div>
      <NotificationSettings />
    </div>
  )
}
```

---

## Phase 7: Testing

### 7.1 Local Testing Checklist

**Database setup:**
- [ ] All migrations applied
- [ ] RLS policies working (test with anon key)
- [ ] Trigger fires on shift insert (check notification_queue)
- [ ] claim_pending_notifications function works

**iOS app:**
- [ ] Firebase SDK integrated (check Xcode build)
- [ ] Push capability enabled in Xcode
- [ ] GoogleService-Info.plist added
- [ ] App prompts for permission
- [ ] FCM token logged in console
- [ ] Token saved to push_devices table
- [ ] Token updates on refresh

**Edge Function:**
- [ ] Function deployed
- [ ] All secrets configured
- [ ] Can be invoked manually
- [ ] Atomic claiming works (no double-sends)
- [ ] Invalid tokens cleaned up

**End-to-end:**
- [ ] User A creates shift
- [ ] Notification appears in queue
- [ ] Edge Function claims and sends
- [ ] User B receives notification on device
- [ ] Tap opens app to shared calendar
- [ ] Correct shift is highlighted

### 7.2 Test Commands

```bash
# Test Edge Function locally
supabase functions serve send-push-notifications --env-file .env.local

# Manually trigger notification processing
curl -X POST https://your-project.supabase.co/functions/v1/send-push-notifications \
  -H "Authorization: Bearer your-service-role-key" \
  -H "Content-Type: application/json"

# Check notification queue
supabase db execute "SELECT id, type, status, created_at, processed_at FROM notification_queue ORDER BY created_at DESC LIMIT 10"

# Check registered devices
supabase db execute "SELECT user_id, platform, device_model, last_seen_at FROM push_devices"

# Test atomic claiming
supabase db execute "SELECT * FROM claim_pending_notifications(5)"
```

### 7.3 TestFlight Testing

1. Build and archive the iOS app in Xcode
2. Upload to App Store Connect
3. Add internal testers
4. Test scenarios:
   - Fresh install → permission prompt
   - Token registration
   - Receive notification (app backgrounded)
   - Receive notification (app killed)
   - Tap notification → deep link
   - Account switch → token moves to new user

---

## Phase 8: Monitoring & Maintenance

### 8.1 Monitoring Queries

```sql
-- Notification delivery stats (last 24h)
SELECT
  status,
  COUNT(*) as count
FROM notification_queue
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY status;

-- Failed notifications with error details
SELECT
  id,
  type,
  error_message,
  created_at,
  processed_at
FROM notification_queue
WHERE status = 'failed'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 20;

-- Stale processing (worker may have died)
SELECT *
FROM notification_queue
WHERE status = 'processing'
  AND claimed_at < NOW() - INTERVAL '5 minutes';

-- Devices per platform
SELECT
  platform,
  COUNT(*) as device_count,
  COUNT(DISTINCT user_id) as user_count
FROM push_devices
GROUP BY platform;

-- Stale devices (not seen in 30+ days)
SELECT
  user_id,
  platform,
  device_model,
  last_seen_at
FROM push_devices
WHERE last_seen_at < NOW() - INTERVAL '30 days'
ORDER BY last_seen_at;
```

### 8.2 Cleanup Jobs

```sql
-- Schedule via pg_cron

-- Delete old processed notifications (keep 30 days)
SELECT cron.schedule(
  'cleanup-old-notifications',
  '0 3 * * *', -- Daily at 3 AM
  $$
  DELETE FROM notification_queue
  WHERE processed_at < NOW() - INTERVAL '30 days';
  $$
);

-- Delete stale device tokens (not seen in 90 days)
SELECT cron.schedule(
  'cleanup-stale-devices',
  '0 4 * * 0', -- Weekly on Sunday at 4 AM
  $$
  DELETE FROM push_devices
  WHERE last_seen_at < NOW() - INTERVAL '90 days';
  $$
);
```

---

## Security Considerations

1. **FCM Credentials**: Service account credentials stored only in Supabase secrets
2. **RLS Policies**: Users can only manage their own devices and preferences
3. **Service Role**: Only Edge Functions access notification_queue (no RLS policies needed, service role bypasses)
4. **Atomic Processing**: FOR UPDATE SKIP LOCKED prevents double-sends
5. **Token Cleanup**: Invalid tokens automatically removed on send failure
6. **Minimal Payload**: Push contains only IDs; client fetches full data
7. **Idempotency**: Duplicate notifications prevented by unique constraint
8. **SECURITY DEFINER Functions**: All have explicit search_path set

---

## Files to Create/Modify

### New Files
- `lib/notifications/push-service.ts`
- `components/providers/PushNotificationProvider.tsx`
- `components/settings/NotificationSettings.tsx`
- `app/[locale]/(app)/settings/notifications/page.tsx`
- `supabase/functions/send-push-notifications/index.ts`
- `supabase/migrations/XXXXXX_create_push_devices_table.sql`
- `supabase/migrations/XXXXXX_create_notification_queue_table.sql`
- `supabase/migrations/XXXXXX_create_notification_preferences_table.sql`
- `supabase/migrations/XXXXXX_create_shift_notification_trigger.sql`
- `supabase/migrations/XXXXXX_create_claim_notifications_function.sql`

### Modified Files
- `ios/App/App/AppDelegate.swift` - Firebase initialization
- `ios/App/App.xcodeproj` - Push capability, Firebase SPM
- `app/[locale]/(app)/layout.tsx` - Add PushNotificationProvider
- `app/[locale]/(app)/sharing/page.tsx` - Handle deep link params
- `app/capacitor-url-listener.tsx` - Handle push deep links
- `components/sharing/SharedUserShiftPreview.tsx` - Highlight support
- `package.json` - New dependencies

---

## Dependencies to Add

```bash
pnpm add @capacitor-firebase/messaging @capacitor/device
```

---

## References

- [Capacitor Firebase Messaging](https://github.com/capawesome-team/capacitor-firebase/tree/main/packages/messaging)
- [FCM HTTP v1 API](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [APNs Documentation](https://developer.apple.com/documentation/usernotifications)
- [Google Service Account Auth](https://developers.google.com/identity/protocols/oauth2/service-account)
