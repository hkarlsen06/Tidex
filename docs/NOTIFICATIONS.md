# Push Notification System

This guide explains how to add new notification types with proper localization in both Norwegian and English.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Locale Detection](#locale-detection)
3. [Adding New Notification Types](#adding-new-notification-types)
4. [Localization Helpers](#localization-helpers)
5. [notifications_outbox Schema](#notifications_outbox-schema)
6. [Data Payload Structure](#data-payload-structure)
7. [Notification Type Reference](#notification-type-reference)
8. [Edge Functions](#edge-functions)
9. [Testing & Troubleshooting](#testing--troubleshooting)

---

## Architecture Overview

The notification system uses a **single pathway**:

### Immediate Notifications (via `notifications_outbox`)

Used for: `share_started`, `feedback_responded`, `feedback_submitted`, `admin_broadcast`, `error_report`

```
DB trigger / Edge function → Build localized message → Insert to notifications_outbox → Edge function sends
```

### Key Design Principle

**Messages are pre-built with localization at queue time, not send time.**

The edge function (`send-push-notifications`) does NOT build messages - it just sends what's already in `notifications_outbox`. This means:

1. Each recipient gets a separate row with their localized message
2. No translation logic in the edge function
3. Messages can be audited/logged before sending

---

## Locale Detection

User locale is stored in: `auth.users.raw_user_meta_data->>'locale'`

| Value | Language |
|-------|----------|
| `'en'` | English (default if not set) |
| `'no'` | Norwegian (generic) |
| `'nb'` | Norwegian Bokmål |
| `'nn'` | Norwegian Nynorsk |

**Always use:** `COALESCE(raw_user_meta_data->>'locale', 'en')` when fetching locale.

**Important:** When checking for Norwegian, always check for all three codes: `'no'`, `'nb'`, and `'nn'`.

---

## Adding New Notification Types

### Step 1: Define the Notification Type

Choose a descriptive `snake_case` name following the pattern `feature_action`:

Examples: `friend_request_received`, `subscription_expired`, `goal_achieved`

### Step 2: Create Trigger Function

Create `supabase/sql/functions/trigger/queue_friend_request_notification.sql`:

```sql
-- Function: queue_friend_request_notification
-- Description: Queues notifications when a friend request is sent
-- Used by: AFTER INSERT trigger on friend_requests

CREATE OR REPLACE FUNCTION public.queue_friend_request_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $$
DECLARE
  v_sender_name TEXT;
  v_recipient RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Get the sender's display name
  SELECT COALESCE(
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'name',
    email,
    'Someone'
  ) INTO v_sender_name
  FROM auth.users
  WHERE id = NEW.sender_id;

  -- Get recipient's locale
  SELECT
    u.id as user_id,
    COALESCE(u.raw_user_meta_data->>'locale', 'en') as locale
  INTO v_recipient
  FROM auth.users u
  WHERE u.id = NEW.recipient_id;

  -- Build localized message inline
  IF v_recipient.locale = 'no' THEN
    v_title := 'Venneforespørsel';
    v_body := v_sender_name || ' vil dele vakter med deg';
  ELSE
    v_title := 'Friend Request';
    v_body := v_sender_name || ' wants to share shifts with you';
  END IF;

  -- Insert into notifications_outbox with pre-built message
  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    title,
    body,
    data_payload,
    idempotency_key,
    due_at,
    status
  ) VALUES (
    NEW.sender_id,                          -- who triggered it
    NEW.recipient_id,                       -- who receives it
    'friend_request_received',              -- notification_type
    v_title,                                -- localized title
    v_body,                                 -- localized body
    jsonb_build_object(
      'type', 'friend_request_received',
      'sender_id', NEW.sender_id,
      'sender_name', v_sender_name,
      'deeplink', '/friends/requests'       -- where to navigate on tap
    ),
    'friend_request:' || NEW.id,            -- idempotency_key (prevents duplicates)
    NOW(),                                  -- due_at (send immediately)
    'pending'
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;
```

### Step 4: Create Database Triggers

```sql
-- Row-level trigger to queue notification
CREATE TRIGGER on_friend_request_inserted_notify
  AFTER INSERT ON friend_requests
  FOR EACH ROW
  EXECUTE FUNCTION queue_friend_request_notification();

-- Statement-level trigger to fire edge function
-- Use 'z_' prefix to ensure it runs LAST (alphabetical order)
CREATE TRIGGER z_on_friend_request_send_notifications
  AFTER INSERT ON friend_requests
  FOR EACH STATEMENT
  EXECUTE FUNCTION trigger_push_notifications_after_outbox_insert();
```

### Step 5: Handle in iOS App (if needed)

Update `PushNotificationManager.swift` for custom tap handling:

```swift
private func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
    guard let type = userInfo["type"] as? String else { return }

    switch type {
    case "friend_request_received":
        if let deeplink = userInfo["deeplink"] as? String {
            coordinator.navigate(to: deeplink)
        }
    // ... other cases
    default:
        break
    }
}
```

### Step 6: Handle in Web App (if needed)

Update `lib/notifications/push-service.ts`:

```typescript
private handleNotificationTap(payload: PushNotificationPayload): void {
  const locale = this.getLocale();

  switch (payload.type) {
    case "friend_request_received":
      window.location.href = `/${locale}${payload.deeplink || '/friends'}`;
      break;
    // ... other cases
  }
}
```

---

## Localization Helpers

### Creating New Helpers

Follow this pattern for new localization functions:

```sql
CREATE OR REPLACE FUNCTION internal.build_[notification_type]_message(
  p_param1 TEXT,
  p_param2 TEXT,
  p_locale TEXT
)
RETURNS TABLE(title TEXT, body TEXT)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_locale = 'no' THEN
    -- Norwegian
    RETURN QUERY SELECT
      'Norwegian title'::TEXT,
      'Norwegian body with ' || p_param1::TEXT;
  ELSE
    -- English (default)
    RETURN QUERY SELECT
      'English title'::TEXT,
      'English body with ' || p_param1::TEXT;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION internal.build_[notification_type]_message TO service_role;
```

---

## notifications_outbox Schema

```sql
CREATE TABLE internal.notifications_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID,                    -- Who triggered the notification (NULL for admin broadcasts)
  recipient_id UUID NOT NULL,       -- Who receives it
  broadcast_id UUID,                -- For admin broadcasts
  notification_type TEXT NOT NULL,  -- e.g., 'share_started', 'feedback_responded'
  due_at TIMESTAMPTZ DEFAULT NOW(), -- When to send (for delayed delivery)
  status TEXT DEFAULT 'pending',    -- pending, sending, sent, failed, skipped
  claimed_at TIMESTAMPTZ,           -- When edge function claimed it
  processed_at TIMESTAMPTZ,         -- When edge function finished
  error_message TEXT,               -- If failed
  attempts INT DEFAULT 0,           -- Retry counter (max 10)
  title TEXT NOT NULL,              -- Pre-built localized title
  body TEXT NOT NULL,               -- Pre-built localized body
  data_payload JSONB,               -- Deep link data, shift dates, etc.
  idempotency_key TEXT UNIQUE,      -- Prevents duplicate notifications
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Status Flow

```
pending → sending → sent
                  → failed (retried up to 10 times)
                  → skipped (no devices registered)
```

---

## Data Payload Structure

The `data_payload` JSONB field is sent to the device for:
1. Deep linking (where to navigate on tap)
2. Display enrichment (calendar highlighting, etc.)

### Required Fields

```jsonb
{
  "type": "notification_type"    // REQUIRED: matches notification_type column
}
```

### Recommended Fields

```jsonb
{
  "type": "friend_request_received",
  "deeplink": "/friends/requests",     // URL path for navigation
  "owner_id": "uuid",                  // Who triggered the action
  "owner_name": "Display Name",        // For display purposes
  "shift_dates": ["2025-01-25"],       // For calendar highlighting
  "additional_data": "value"           // Any other relevant data
}
```

---

## Notification Type Reference

### Current Notification Types

| Type | Localized | Trigger Source | Notes |
|------|-----------|----------------|-------|
| `share_started` | Yes (SQL) | DB trigger on `shift_shares` INSERT | Localized in trigger function |
| `feedback_submitted` | No (admin-only) | DB trigger on `feedback` INSERT | Norwegian OK for admins |
| `feedback_responded` | Yes (SQL) | DB trigger on `feedback` UPDATE | Localized in trigger function |
| `admin_broadcast` | No | Admin API | Pre-written messages |
| `error_report` | No | API route | Dev-only notification |

---

## Edge Functions

### `send-push-notifications`

Location: `supabase/functions/send-push-notifications/index.ts`

**Purpose:** Processes `notifications_outbox` and sends via APNs/FCM.

**Key Points:**
- Claims up to 50 notifications atomically via `claim_outbox_notifications()`
- Does NOT build messages - uses pre-built `title` and `body` from outbox
- Tries APNs first (native iOS), falls back to FCM (hybrid/Android)
- Automatically cleans up invalid tokens
- Retries failed notifications up to 10 times

**Flow:**
```
1. Claim notifications (atomic, prevents duplicates)
2. For each notification:
   a. Get recipient's devices from push_devices
   b. If apns_token exists → send via APNs
   c. Else if fcm_token exists → send via FCM
   d. Mark as sent/failed/skipped
3. Clean up invalid tokens
```

## Testing & Troubleshooting

### Check Outbox Queue

```sql
SELECT id, recipient_id, notification_type, title, body, status, created_at
FROM internal.notifications_outbox
WHERE recipient_id = 'your-user-id'
ORDER BY created_at DESC
LIMIT 10;
```

### Check User's Locale

```sql
SELECT
  id,
  email,
  raw_user_meta_data->>'locale' as locale,
  COALESCE(raw_user_meta_data->>'locale', 'en') as effective_locale
FROM auth.users
WHERE id = 'user-id';
```

### Check Push Devices

```sql
SELECT
  id,
  user_id,
  platform,
  apns_token IS NOT NULL as has_apns,
  fcm_token IS NOT NULL as has_fcm,
  last_seen_at
FROM internal.push_devices
WHERE user_id = 'your-user-id';
```

### Manually Trigger Edge Function

```bash
curl -X POST "https://[project-ref].supabase.co/functions/v1/send-push-notifications" \
  -H "Authorization: Bearer [service-role-key]" \
  -H "Content-Type: application/json"
```

### Common Issues

#### Notification Not Sending

1. Check `notifications_outbox` for the row and its status
2. Verify user has `push_devices` entry with valid tokens
3. Check edge function logs for errors
4. Verify APNs/FCM credentials are configured

#### Wrong Language

1. Check user's locale: `SELECT raw_user_meta_data->>'locale' FROM auth.users`
2. Verify localization function uses `COALESCE(..., 'en')` for default
3. Ensure the correct locale is passed to the helper function

#### Duplicate Notifications

1. Check `idempotency_key` is unique and deterministic
2. Verify `ON CONFLICT (idempotency_key) DO NOTHING` in INSERT

---

## Checklist for New Notification Types

- [ ] Define notification type name (`snake_case`)
- [ ] Create trigger function in `supabase/sql/functions/trigger/` (with inline localized messages)
- [ ] Create row-level database trigger on source table
- [ ] Create statement-level trigger to fire edge function (use `z_` prefix)
- [ ] Test with both English and Norwegian users
- [ ] Update iOS app if custom tap handling needed
- [ ] Update iOS or other active clients if custom tap handling is needed
- [ ] Document in this file

---

## Database Tables Reference

| Table | Schema | Purpose |
|-------|--------|---------|
| `notifications_outbox` | `internal` | Primary delivery queue with pre-built messages |
| `push_devices` | `internal` | User device tokens (APNs + FCM) |
| `notification_preferences` | `public` | User notification settings |

---

## Cron Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `cleanup-shift-notification-events` | `0 4 * * *` | Clean sent outbox entries |

---

## File References

| File | Purpose |
|------|---------|
| `supabase/sql/functions/trigger/queue_feedback_responded_notification.sql` | Feedback response trigger + notification |
| `supabase/sql/functions/trigger/queue_share_started_notification.sql` | Share started trigger + notification |
| `supabase/sql/functions/notification/claim_outbox_notifications.sql` | Atomic queue claiming |
| `supabase/functions/send-push-notifications/index.ts` | Main delivery edge function |
| `supabase/sql/functions/trigger/queue_abuse_report_notification.sql` | Admin abuse-report notification enqueueing |
| `app-compat/_redirects` | Legacy `app.tidex.no` redirect behavior after web app retirement |
| `ios/TidexApp/Services/Notification/NotificationService.swift` | iOS push handling |
