# Push Notifications System (Native)

This document explains how push notifications work for native iOS and Android users in Tidex.

## Overview

The notifications system supports two types of notifications:

1. **Shared Shift Notifications** - Instant delivery when someone shares a shift
2. **Shift Reminder Notifications** - Scheduled reminders before shifts start

Both use Firebase Cloud Messaging (FCM) HTTP v1 API for delivery to iOS (via APNS) and Android devices.

---

## Architecture Flow Diagram

```
                                    PUSH NOTIFICATION SYSTEM
    ═══════════════════════════════════════════════════════════════════════════════

    ┌─────────────────────────────────────────────────────────────────────────────┐
    │                           CLIENT-SIDE (Native App)                          │
    └─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
    │   App Launches   │────>│  Request FCM     │────>│  Save Token to Server    │
    │                  │     │  Permission      │     │  (push_devices table)    │
    └──────────────────┘     └──────────────────┘     └──────────────────────────┘
                                                                   │
                                                                   ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │                                                                              │
    │   push_devices table                                                         │
    │   ┌────────────────────────────────────────────────────────────────────┐    │
    │   │ id | user_id | fcm_token | platform | device_id | last_seen_at    │    │
    │   │ ─────────────────────────────────────────────────────────────────── │    │
    │   │ ... | abc-123 | dX9f...  | ios      | vendor-id | 2025-01-15 10:00│    │
    │   └────────────────────────────────────────────────────────────────────┘    │
    │                                                                              │
    └──────────────────────────────────────────────────────────────────────────────┘


    ═══════════════════════════════════════════════════════════════════════════════
                              SHARED SHIFT NOTIFICATIONS
                                  (Instant Delivery)
    ═══════════════════════════════════════════════════════════════════════════════

    User A creates shift
           │
           ▼
    ┌──────────────────┐
    │  INSERT INTO     │
    │  user_shifts     │
    └──────────────────┘
           │
           │ Row-level trigger (AFTER INSERT)
           ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  queue_shift_created_notification()                                          │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ - Finds all viewers who share with User A                               │ │
    │  │ - Checks notification_preferences (shared_shifts_enabled = true)        │ │
    │  │ - Inserts into notification_queue with idempotency_key                  │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
           │
           │ Statement-level trigger (AFTER INSERT, fires ONCE)
           ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  trigger_push_notifications_after_insert()                                   │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ - Checks if pending notifications exist                                 │ │
    │  │ - Calls send-push-notifications Edge Function via pg_net               │ │
    │  │ - Consolidates multiple shifts from same sender                         │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
           │
           │ HTTP POST (instant)
           ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  send-push-notifications (Edge Function)                                     │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ 1. claim_pending_notifications() - atomic claim with FOR UPDATE SKIP   │ │
    │  │ 2. Consolidate notifications from same sender                          │ │
    │  │ 3. Get FCM access token (OAuth2 with service account)                  │ │
    │  │ 4. Send to all recipient devices                                       │ │
    │  │ 5. Update notification_queue status (sent/failed/skipped)              │ │
    │  │ 6. Delete invalid FCM tokens                                           │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
    ┌──────────────────┐     ┌──────────────────┐
    │  FCM HTTP v1     │────>│  APNS / Android  │────> User's Device
    │  API             │     │  Push Service    │
    └──────────────────┘     └──────────────────┘


    ═══════════════════════════════════════════════════════════════════════════════
                             SHIFT REMINDER NOTIFICATIONS
                              (Cron-based, every 10 min)
    ═══════════════════════════════════════════════════════════════════════════════

                                 ┌────────────────────┐
                                 │  pg_cron job       │
                                 │  */10 * * * *      │
                                 └────────────────────┘
                                          │
                                          │ Every 10 minutes
                                          ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  process-shift-reminders (Edge Function)                                     │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ 1. get_shifts_due_for_reminder() - SQL function                        │ │
    │  │    ┌────────────────────────────────────────────────────────────────┐  │ │
    │  │    │ - Query user_shifts where shift_date >= today                  │  │ │
    │  │    │ - Join with notification_preferences (shift_reminders_enabled) │  │ │
    │  │    │ - Calculate minutes_until_shift in Europe/Oslo timezone        │  │ │
    │  │    │ - Narrow window: reminder_minutes-10 <= minutes <= reminder    │  │ │
    │  │    └────────────────────────────────────────────────────────────────┘  │ │
    │  │                                                                         │ │
    │  │ 2. For each due reminder:                                               │ │
    │  │    ┌────────────────────────────────────────────────────────────────┐  │ │
    │  │    │ CLAIM: INSERT INTO shift_reminders_sent                        │  │ │
    │  │    │        (unique constraint acts as distributed lock)            │  │ │
    │  │    │        - Success: Send notification                            │  │ │
    │  │    │        - Conflict (23505): Skip (already sent)                 │  │ │
    │  │    └────────────────────────────────────────────────────────────────┘  │ │
    │  │                                                                         │ │
    │  │ 3. Send via FCM HTTP v1 API to user's devices                          │ │
    │  │ 4. Clean up invalid tokens                                             │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
    ┌──────────────────┐     ┌──────────────────┐
    │  FCM HTTP v1     │────>│  APNS / Android  │────> User's Device
    │  API             │     │  Push Service    │
    └──────────────────┘     └──────────────────┘


    ═══════════════════════════════════════════════════════════════════════════════
                              NOTIFICATION TAP HANDLING
    ═══════════════════════════════════════════════════════════════════════════════

    User taps notification
           │
           ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  notificationActionPerformed listener                                        │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ payload = { type, shift_id, owner_id, shift_date }                     │ │
    │  │                                                                         │ │
    │  │ if type === "shift_reminder":                                           │ │
    │  │   navigate to /{locale}/shifts?date={shift_date}                       │ │
    │  │                                                                         │ │
    │  │ if type === "shared_shift_*":                                           │ │
    │  │   navigate to /{locale}/sharing?user={owner_id}&highlight={shift_id}   │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### `push_devices` - FCM Token Storage

```sql
CREATE TABLE push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL UNIQUE,  -- Globally unique token
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  device_id TEXT,        -- iOS identifierForVendor for token rotation
  device_model TEXT,     -- e.g., "iPhone 14 Pro"
  app_version TEXT,      -- e.g., "1.2.0"
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**RLS Policies:** Users can only manage their own devices.

### `notification_preferences` - User Settings

```sql
CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  shared_shifts_enabled BOOLEAN NOT NULL DEFAULT true,
  shift_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  shift_reminder_minutes INTEGER NOT NULL DEFAULT 300
    CHECK (shift_reminder_minutes IN (60, 120, 300, 1440)),
  quiet_hours_start TIME,
  quiet_hours_end TIME,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Reminder options:**
- `60` = 1 hour before
- `120` = 2 hours before
- `300` = 5 hours before (default)
- `1440` = 24 hours before

### `notification_queue` - Delivery Queue (Shared Shifts)

```sql
CREATE TABLE notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN (
    'shared_shift_created',
    'shared_shift_updated',
    'shared_shift_deleted',
    'share_request'
  )),
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'processing', 'sent', 'failed', 'skipped'
  )),
  claimed_at TIMESTAMPTZ,      -- For atomic claiming
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  idempotency_key TEXT UNIQUE  -- Prevent duplicate notifications
);
```

**Status flow:** `pending` -> `processing` -> `sent`/`failed`/`skipped`

### `shift_reminders_sent` - Duplicate Prevention

```sql
CREATE TABLE shift_reminders_sent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shift_instance_key TEXT NOT NULL,  -- "single:{id}:{date}:{start}"
  reminder_minutes INTEGER NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, shift_instance_key, reminder_minutes)  -- Distributed lock
);
```

The unique constraint acts as a **distributed lock** - if two workers try to send the same reminder simultaneously, only one succeeds (the other gets constraint violation 23505).

---

## Client-Side Code

### Push Service (`lib/notifications/push-service.ts`)

```typescript
class PushNotificationService {
  private initialized = false
  private currentToken: string | null = null

  async initialize(): Promise<void> {
    if (this.initialized || !Capacitor.isNativePlatform()) return

    const { FirebaseMessaging } = await import("@capacitor-firebase/messaging")
    const { Device } = await import("@capacitor/device")

    // Request permission
    const permResult = await FirebaseMessaging.requestPermissions()
    if (permResult.receive !== "granted") return

    // Get FCM token and save to server
    const { token } = await FirebaseMessaging.getToken()
    if (token) {
      this.currentToken = token
      await this.saveTokenToServer(token, { ... })
    }

    // Listen for token refresh
    FirebaseMessaging.addListener("tokenReceived", async ({ token }) => {
      await this.saveTokenToServer(token, { ... })
    })

    // Handle notification tap
    FirebaseMessaging.addListener("notificationActionPerformed", ({ notification }) => {
      const data = notification.data as PushNotificationPayload
      this.handleNotificationTap(data)
    })
  }

  private handleNotificationTap(payload: PushNotificationPayload): void {
    const locale = this.getLocale()

    if (payload.type === "shift_reminder") {
      window.location.href = `/${locale}/shifts?date=${payload.shift_date}`
    } else {
      // Shared shift - navigate to sharing view
      window.location.href = `/${locale}/sharing?user=${payload.owner_id}&highlight=${payload.shift_id}`
    }
  }
}

export const pushNotificationService = new PushNotificationService()
```

### Token Registration

```typescript
private async saveTokenToServer(fcmToken: string, metadata: {...}): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return

  // Upsert with ON CONFLICT on fcm_token handles:
  // 1. New device registration
  // 2. Same device, same user (updates metadata)
  // 3. Same device, different user (account switch)
  await supabase.from("push_devices").upsert({
    user_id: user.id,
    fcm_token: fcmToken,
    platform: Capacitor.getPlatform(),
    device_id: metadata.deviceId,
    device_model: metadata.deviceModel,
    app_version: metadata.appVersion,
  }, { onConflict: "fcm_token" })
}
```

---

## Edge Functions

### `send-push-notifications` (Instant Delivery)

Triggered immediately when shifts are created via statement-level trigger.

**Flow:**
1. `claim_pending_notifications(50)` - Atomic claim with `FOR UPDATE SKIP LOCKED`
2. Consolidate notifications from same sender to same recipient
3. Get OAuth2 access token from Google
4. Send to FCM HTTP v1 API
5. Update queue status, delete invalid tokens

**Consolidation example:**
- User A creates 6 shifts that User B receives
- Instead of 6 notifications, User B gets: "User A la til 6 vakter"

### `process-shift-reminders` (Cron-based)

Runs every 10 minutes via `pg_cron`.

**Flow:**
1. `get_shifts_due_for_reminder()` - Find shifts in the narrow window
2. For each: try INSERT into `shift_reminders_sent` (claim)
   - Success: send notification
   - Constraint violation: skip (already sent)
3. Send to user's devices via FCM
4. Clean up invalid tokens

**Narrow window logic:**
```sql
-- Only send when within [reminder_minutes - 10, reminder_minutes]
WHERE mins_until <= reminder_mins
  AND mins_until >= (reminder_mins - 10)
```

This prevents early sends while ensuring 10-minute polling catches all reminders.

---

## FCM Integration

Both edge functions use FCM HTTP v1 API (not legacy API):

```typescript
// OAuth2 authentication
const accessToken = await getFcmAccessToken() // Cached for 1 hour

// Send notification
await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    message: {
      token: fcmToken,
      notification: { title, body },
      data: { type, shift_id, shift_date, owner_id },
      apns: { payload: { aps: { sound: "default", "mutable-content": 1 } } },
      android: { notification: { sound: "default" } },
    },
  }),
})
```

**Invalid token handling:**
- `UNREGISTERED`, `INVALID_ARGUMENT`, `NOT_FOUND` errors trigger token deletion
- Automatic cleanup keeps `push_devices` table clean

---

## Settings UI

Users configure notifications at `/{locale}/settings/notifications`:

**Components:**
- `NotificationSettingsForm.tsx` - Client component with auto-save

**Features:**
- Shared shifts toggle (on/off)
- Shift reminders toggle (on/off)
- Reminder timing selector (1hr, 2hr, 5hr, 24hr options)
- Permission status check (shows warning if denied on iOS)
- Request permission button (when permission is "prompt")

**Auto-save:** Changes are saved immediately via server actions:
- `updateNotificationSettings()` - Shared shifts preference
- `updateShiftReminderSettings()` - Reminder preferences

---

## Cron Jobs

```sql
-- Process shift reminders every 10 minutes
SELECT cron.schedule(
  'process-shift-reminders',
  '*/10 * * * *',
  $$ SELECT net.http_post(...) $$
);

-- Cleanup old sent records daily at 3 AM
SELECT cron.schedule(
  'cleanup-shift-reminders-sent',
  '0 3 * * *',
  $$ DELETE FROM shift_reminders_sent WHERE sent_at < NOW() - INTERVAL '7 days' $$
);
```

---

## Key Design Decisions

### 1. Instant vs Polling

| Type | Delivery | Reason |
|------|----------|--------|
| Shared Shifts | Instant (trigger) | Users expect immediate notification when someone shares |
| Shift Reminders | Polling (10 min) | Time-based, slight delay acceptable |

### 2. Claim-Before-Send Pattern

Both systems use claim-before-send to prevent duplicate notifications:

- **Shared shifts:** `claim_pending_notifications()` with `FOR UPDATE SKIP LOCKED`
- **Reminders:** Unique constraint on `shift_reminders_sent` acts as distributed lock

### 3. Consolidation

Multiple shifts from same sender are consolidated into one notification:
- Single shift: "Ola la til en vakt - Fredag 15. januar kl. 08:00-16:00"
- Multiple shifts: "Ola la til 6 vakter - Trykk for å se vaktene"

### 4. Timezone Handling

All shift times are processed in Europe/Oslo timezone for Norwegian users:
```sql
((shift_date::TEXT || ' ' || start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo')
```

---

## File References

| File | Purpose |
|------|---------|
| [lib/notifications/push-service.ts](lib/notifications/push-service.ts) | Client-side FCM registration & tap handling |
| [components/settings/notifications/NotificationSettingsForm.tsx](components/settings/notifications/NotificationSettingsForm.tsx) | Settings UI component |
| [supabase/functions/send-push-notifications/index.ts](supabase/functions/send-push-notifications/index.ts) | Shared shift delivery |
| [supabase/functions/process-shift-reminders/index.ts](supabase/functions/process-shift-reminders/index.ts) | Reminder processing |
| [supabase/migrations/20251230174738_*.sql](supabase/migrations/) | Database schema migrations |

---

## Environment Variables Required

```env
# Supabase (in Edge Functions)
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# FCM HTTP v1 (from Google service account)
FCM_PROJECT_ID=your-firebase-project
FCM_CLIENT_EMAIL=firebase-adminsdk@...iam.gserviceaccount.com
FCM_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...
```

**Vault secrets** (for pg_cron/pg_net):
- `supabase_url` - Used by triggers to call edge functions
- `service_role_key` - Authorization for edge function calls
