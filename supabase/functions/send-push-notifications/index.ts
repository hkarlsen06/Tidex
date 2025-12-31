// Supabase Edge Function: Send Push Notifications
// - Processes queued notifications from notification_queue table
// - Uses FCM HTTP v1 API with OAuth2 for iOS/Android push
// - Atomic queue claiming with FOR UPDATE SKIP LOCKED
// - Automatic invalid token cleanup
// - Consolidates bulk notifications from same sender
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

// ---------- Env ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// FCM HTTP v1 credentials (from Google service account JSON)
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID") ?? "";
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");

// Cache access token (valid for 1 hour)
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

// ---------- Types ----------
interface ShiftNotificationPayload {
  shift_id: string;
  shift_date: string;
  start_time?: string;
  end_time?: string;
  owner_id: string;
  owner_name: string;
}

interface RecurringNotificationPayload {
  recurring_id: string;
  owner_id: string;
  owner_name: string;
}

interface AdminBroadcastPayload {
  title: string;
  body: string;
  deeplink?: string | null;
}

/** Payload for share_started notifications (when someone starts sharing with you) */
interface ShareStartedPayload {
  owner_id: string;
  owner_name: string;
  is_mutual?: boolean; // true if recipient already shares with the sender
}

/** Payload for batched shift changes (from cron processor) */
interface ShiftChangesPayload {
  updated_shifts: Array<{
    shift_id: string;
    shift_date: string;
    start_time: string;
    end_time: string;
  }>;
  deleted_shifts: Array<{
    shift_id: string;
    shift_date: string;
    start_time: string;
    end_time: string;
  }>;
  updated_count: number;
  deleted_count: number;
  owner_id: string;
  owner_name: string;
}

type NotificationPayload = ShiftNotificationPayload | RecurringNotificationPayload | AdminBroadcastPayload | ShiftChangesPayload | ShareStartedPayload;

interface QueuedNotification {
  id: string;
  type: string;
  recipient_id: string;
  sender_id: string;
  payload: NotificationPayload;
  created_at: string;
  broadcast_id?: string; // For admin broadcasts
}

interface PushDevice {
  id: string;
  fcm_token: string;
}

/** Consolidated notification for bulk sends */
interface ConsolidatedNotification {
  notifications: QueuedNotification[];
  recipient_id: string;
  sender_id: string;
  owner_name: string;
  type: "single_shift" | "multiple_shifts" | "recurring" | "admin_broadcast" | "shift_changes" | "share_started";
  notificationType: string; // Original notification type (shared_shift_created, shared_shift_updated, shared_shift_deleted, shared_shift_changes, share_started)
  // For single shift
  shift?: { date: string; start_time: string; end_time: string };
  // For multiple shifts
  shift_count?: number;
  shift_dates?: string[]; // All dates for multiple shifts (for deep link highlighting)
  // For admin broadcasts
  broadcast?: AdminBroadcastPayload;
  // For batched shift changes (from cron processor)
  shift_changes?: ShiftChangesPayload;
}

// ---------- Helpers ----------
function res(body: string, status: number) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain" } });
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function capitalizeFirst(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  return capitalizeFirst(
    date.toLocaleDateString("nb-NO", {
      weekday: "long",
      day: "numeric",
      month: "long",
    })
  );
}

function formatTime(timeStr: string): string {
  // Handle both "HH:mm" and "HH:mm:ss+TZ" formats
  return timeStr.slice(0, 5);
}

function base64UrlEncode(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);

  const base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function createJwt(payload: object, privateKey: string): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  // Import private key and sign
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput)
  );

  return `${signingInput}.${base64UrlEncode(signature)}`;
}

async function getFcmAccessToken(): Promise<string> {
  // Return cached token if still valid (with 1 minute buffer)
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60000) {
    return cachedAccessToken.token;
  }

  // Generate JWT for Google OAuth2
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const jwt = await createJwt(payload, FCM_PRIVATE_KEY);

  // Exchange JWT for access token
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to get FCM access token: ${await response.text()}`);
  }

  const data = await response.json();
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };

  return data.access_token;
}

/**
 * Build notification message based on consolidated notification type
 */
function buildNotificationMessage(consolidated: ConsolidatedNotification): {
  title: string;
  body: string;
} {
  const { owner_name, type, notificationType } = consolidated;

  switch (type) {
    case "admin_broadcast": {
      const broadcast = consolidated.broadcast!;
      return { title: broadcast.title, body: broadcast.body };
    }
    case "single_shift": {
      const shift = consolidated.shift!;
      const timeRange = `${formatDate(shift.date)} kl. ${formatTime(shift.start_time)}-${formatTime(shift.end_time)}`;

      // Handle updated and deleted notifications
      if (notificationType === "shared_shift_updated") {
        return {
          title: `${owner_name} endret en vakt`,
          body: timeRange,
        };
      }

      if (notificationType === "shared_shift_deleted") {
        return {
          title: `${owner_name} slettet en vakt`,
          body: timeRange,
        };
      }

      // Default: shared_shift_created
      const title = `${owner_name} la til en vakt`;
      const body = timeRange;
      return { title, body };
    }
    case "multiple_shifts": {
      const count = consolidated.shift_count!;

      // Handle updated and deleted notifications for multiple shifts
      if (notificationType === "shared_shift_updated") {
        return {
          title: `${owner_name} endret ${count} vakter`,
          body: "Trykk for å se vaktene",
        };
      }

      if (notificationType === "shared_shift_deleted") {
        return {
          title: `${owner_name} slettet ${count} vakter`,
          body: "Trykk for å se vaktene",
        };
      }

      // Default: shared_shift_created
      const title = `${owner_name} la til ${count} vakter`;
      const body = "Trykk for å se vaktene";
      return { title, body };
    }
    case "recurring": {
      const title = `${owner_name} la til en gjentakende vakt`;
      const body = "Trykk for å se vaktene";
      return { title, body };
    }
    case "shift_changes": {
      // New batched notification type from cron processor
      const changes = consolidated.shift_changes!;
      const { updated_count, deleted_count, updated_shifts, deleted_shifts } = changes;

      // Build message parts
      const parts: string[] = [];

      if (updated_count > 0) {
        parts.push(`endret ${updated_count} ${updated_count === 1 ? "vakt" : "vakter"}`);
      }

      if (deleted_count > 0) {
        parts.push(`slettet ${deleted_count} ${deleted_count === 1 ? "vakt" : "vakter"}`);
      }

      const title = `${owner_name} ${parts.join(" og ")}`;

      // Body: show details for single shift, generic for multiple
      let body: string;
      const totalCount = updated_count + deleted_count;

      if (totalCount === 1) {
        // Single shift - show details
        const shift = updated_count === 1 ? updated_shifts[0] : deleted_shifts[0];
        body = `${formatDate(shift.shift_date)} kl. ${formatTime(shift.start_time)}-${formatTime(shift.end_time)}`;
      } else {
        body = "Trykk for å se endringene";
      }

      return { title, body };
    }
    case "share_started": {
      // Someone started sharing their shifts with the recipient
      // Check if this is now mutual sharing
      const firstPayload = consolidated.notifications[0].payload as ShareStartedPayload;
      if (firstPayload.is_mutual) {
        // Already sharing with each other - celebrate mutual sharing
        return {
          title: "Dere kan nå se hverandres vakter!",
          body: `Du og ${owner_name} deler nå vakter med hverandre`,
        };
      }
      // Not mutual yet - prompt to share back
      return {
        title: `${owner_name} deler vaktene sine med deg`,
        body: "Trykk for å dele tilbake",
      };
    }
  }
}

async function sendConsolidatedToFcm(
  accessToken: string,
  fcmToken: string,
  consolidated: ConsolidatedNotification
): Promise<{ success: boolean; invalidToken?: boolean }> {
  const { title, body } = buildNotificationMessage(consolidated);

  // Use first notification's data for deep linking
  const firstNotification = consolidated.notifications[0];

  // Build data payload based on notification type
  const dataPayload: Record<string, string> = {
    type: firstNotification.type,
  };

  if (firstNotification.type === "admin_broadcast") {
    // Admin broadcast - include deeplink if present
    const adminPayload = firstNotification.payload as AdminBroadcastPayload;
    if (adminPayload.deeplink) {
      dataPayload.deeplink = adminPayload.deeplink;
    }
  } else if (firstNotification.type === "share_started") {
    // Share started - include owner_id and appropriate deep link
    const sharePayload = firstNotification.payload as ShareStartedPayload;
    dataPayload.owner_id = sharePayload.owner_id;
    if (sharePayload.is_mutual) {
      // Mutual sharing - just go to sharing page to see their shifts
      dataPayload.deeplink = `/sharing?user=${sharePayload.owner_id}`;
    } else {
      // Not mutual - open manage modal with highlight to prompt share back
      dataPayload.deeplink = `/sharing?manage=true&highlight=${sharePayload.owner_id}`;
    }
  } else if (firstNotification.type === "shared_shift_changes") {
    // Batched shift changes - collect all dates from updated + deleted shifts
    const changesPayload = firstNotification.payload as ShiftChangesPayload;
    dataPayload.owner_id = changesPayload.owner_id;

    // Collect all dates (updated + deleted) for deep link highlighting
    const allDates = [
      ...changesPayload.updated_shifts.map((s) => s.shift_date),
      ...changesPayload.deleted_shifts.map((s) => s.shift_date),
    ];
    const uniqueDates = [...new Set(allDates)].sort();
    if (uniqueDates.length > 0) {
      dataPayload.shift_dates = uniqueDates.join(",");
    }
  } else {
    // Regular shift notifications - include owner_id and shift info
    const shiftPayload = firstNotification.payload as ShiftNotificationPayload;
    dataPayload.owner_id = consolidated.sender_id;

    // For multiple shifts, send comma-separated dates for highlighting
    // For single shifts, send the single date
    if (consolidated.shift_dates && consolidated.shift_dates.length > 0) {
      dataPayload.shift_dates = consolidated.shift_dates.join(",");
    } else if (shiftPayload.shift_date) {
      dataPayload.shift_dates = shiftPayload.shift_date;
    }
  }

  // FCM HTTP v1 message format
  const message = {
    message: {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: dataPayload,
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            "mutable-content": 1,
          },
        },
      },
      android: {
        notification: {
          sound: "default",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
    },
  };

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    }
  );

  if (response.ok) {
    return { success: true };
  }

  const errorBody = await response.text();
  console.error(`FCM error for token ${fcmToken.substring(0, 20)}...:`, errorBody);

  // Check for invalid token errors
  if (
    errorBody.includes("UNREGISTERED") ||
    errorBody.includes("INVALID_ARGUMENT") ||
    errorBody.includes("NOT_FOUND")
  ) {
    return { success: false, invalidToken: true };
  }

  return { success: false };
}

/**
 * Consolidate notifications from the same sender to the same recipient
 * Groups by (type, sender_id, recipient_id, broadcast_id) and creates appropriate message
 *
 * Admin broadcasts use broadcast_id to ensure each broadcast is a separate message
 * Shift notifications group by type to prevent mixing created/updated/deleted
 */
function consolidateNotifications(
  notifications: QueuedNotification[]
): ConsolidatedNotification[] {
  // Group by type + sender_id + recipient_id (+ broadcast_id for admin_broadcast)
  // IMPORTANT: type is included to prevent mixing created/updated/deleted notifications
  const groups = new Map<string, QueuedNotification[]>();

  for (const notification of notifications) {
    let key: string;

    if (notification.type === "admin_broadcast") {
      // Validate broadcast_id is set (should always be due to DB constraint)
      if (!notification.broadcast_id) {
        console.error(`admin_broadcast ${notification.id} missing broadcast_id, skipping`);
        continue;
      }
      // Each broadcast_id is treated as a separate message (no consolidation across broadcasts)
      key = `${notification.type}:${notification.sender_id}:${notification.recipient_id}:${notification.broadcast_id}`;
    } else {
      // Shift notifications - include type to prevent mixing created/updated/deleted
      key = `${notification.type}:${notification.sender_id}:${notification.recipient_id}`;
    }

    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key)!.push(notification);
  }

  const consolidated: ConsolidatedNotification[] = [];

  for (const [, group] of groups) {
    const first = group[0];
    const payload = first.payload;

    // Handle admin broadcast
    if (first.type === "admin_broadcast") {
      const adminPayload = payload as AdminBroadcastPayload;
      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name: "Admin", // Not shown in message
        type: "admin_broadcast",
        notificationType: first.type,
        broadcast: adminPayload,
      });
      continue;
    }

    const owner_name = (payload as ShiftNotificationPayload).owner_name || "Noen";

    // Check if this is a recurring shift notification
    if (first.type === "recurring_shift_created") {
      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name,
        type: "recurring",
        notificationType: first.type,
      });
      continue;
    }

    // Handle share_started notification (someone started sharing with recipient)
    if (first.type === "share_started") {
      const sharePayload = payload as ShareStartedPayload;
      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name: sharePayload.owner_name,
        type: "share_started",
        notificationType: first.type,
      });
      continue;
    }

    // Handle batched shift changes (from cron processor - already consolidated)
    if (first.type === "shared_shift_changes") {
      const changesPayload = payload as ShiftChangesPayload;
      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name: changesPayload.owner_name,
        type: "shift_changes",
        notificationType: first.type,
        shift_changes: changesPayload,
      });
      continue;
    }

    // Regular shift notifications (created, updated, deleted)
    if (group.length === 1) {
      // Single shift - show full details
      const shiftPayload = payload as ShiftNotificationPayload;
      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name,
        type: "single_shift",
        notificationType: first.type, // Preserve original type for message building
        shift: {
          date: shiftPayload.shift_date,
          start_time: shiftPayload.start_time || "00:00",
          end_time: shiftPayload.end_time || "00:00",
        },
      });
    } else {
      // Multiple shifts - consolidate into one message
      // Collect all unique shift dates for deep link highlighting
      const shiftDates = [...new Set(
        group.map(n => (n.payload as ShiftNotificationPayload).shift_date)
      )].sort();

      consolidated.push({
        notifications: group,
        recipient_id: first.recipient_id,
        sender_id: first.sender_id,
        owner_name,
        type: "multiple_shifts",
        notificationType: first.type, // Preserve original type for message building
        shift_count: group.length,
        shift_dates: shiftDates,
      });
    }
  }

  return consolidated;
}

// ---------- Server ----------
serve(async (req: Request) => {
  try {
    // Only allow POST requests (or GET for cron health checks)
    if (req.method !== "POST" && req.method !== "GET") {
      return res("Method Not Allowed", 405);
    }

    // Check configuration
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return res("Supabase not configured", 503);
    }
    if (!FCM_PROJECT_ID || !FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
      return res("FCM not configured", 503);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    // Atomic claim: SELECT ... FOR UPDATE SKIP LOCKED + UPDATE in one transaction
    // This prevents double-processing if function is invoked concurrently
    const { data: notifications, error: claimError } = await supabase.rpc(
      "claim_pending_notifications",
      { batch_size: 50 }
    );

    if (claimError) {
      console.error("Failed to claim notifications:", claimError);
      throw claimError;
    }

    if (!notifications?.length) {
      return json({ processed: 0, message: "No pending notifications" });
    }

    // Get FCM access token
    const accessToken = await getFcmAccessToken();

    // Consolidate notifications from same sender to same recipient
    const consolidated = consolidateNotifications(notifications as QueuedNotification[]);

    let processed = 0;
    let failed = 0;
    const invalidTokens: string[] = [];

    for (const group of consolidated) {
      try {
        // Get recipient's FCM tokens
        const { data: devices } = await supabase
          .from("push_devices")
          .select("id, fcm_token")
          .eq("user_id", group.recipient_id);

        if (!devices?.length) {
          // No devices registered, mark all as skipped
          for (const notification of group.notifications) {
            await supabase
              .from("notification_queue")
              .update({
                status: "skipped",
                processed_at: new Date().toISOString(),
              })
              .eq("id", notification.id);
          }
          continue;
        }

        // Send to each device
        let anySuccess = false;
        for (const device of devices as PushDevice[]) {
          const result = await sendConsolidatedToFcm(accessToken, device.fcm_token, group);

          if (result.success) {
            anySuccess = true;
          } else if (result.invalidToken) {
            // Token is invalid, queue for deletion
            invalidTokens.push(device.id);
          }
        }

        // Mark all notifications in group
        for (const notification of group.notifications) {
          await supabase
            .from("notification_queue")
            .update({
              status: anySuccess ? "sent" : "failed",
              error_message: anySuccess ? null : "All devices failed",
              processed_at: new Date().toISOString(),
            })
            .eq("id", notification.id);
        }

        if (anySuccess) processed += group.notifications.length;
        else failed += group.notifications.length;
      } catch (error) {
        console.error(`Error processing consolidated notification:`, error);

        for (const notification of group.notifications) {
          await supabase
            .from("notification_queue")
            .update({
              status: "failed",
              error_message: error instanceof Error ? error.message : "Unknown error",
              processed_at: new Date().toISOString(),
            })
            .eq("id", notification.id);
        }

        failed += group.notifications.length;
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      await supabase.from("push_devices").delete().in("id", invalidTokens);
      console.log(`Deleted ${invalidTokens.length} invalid tokens`);
    }

    // Update broadcast status to 'complete' for finished admin broadcasts
    // Collect unique broadcast_ids from this batch
    const processedBroadcastIds = new Set<string>();
    for (const notification of notifications as QueuedNotification[]) {
      if (notification.broadcast_id) {
        processedBroadcastIds.add(notification.broadcast_id);
      }
    }

    // For each broadcast, check if all notifications are processed
    for (const broadcastId of processedBroadcastIds) {
      // Count remaining pending notifications for this broadcast
      const { count: pendingCount } = await supabase
        .from("notification_queue")
        .select("*", { count: "exact", head: true })
        .eq("broadcast_id", broadcastId)
        .in("status", ["pending", "processing"]);

      // If no pending notifications remain, mark broadcast as complete
      if (pendingCount === 0) {
        await supabase
          .from("admin_broadcasts")
          .update({ status: "complete" })
          .eq("id", broadcastId)
          .eq("status", "queued"); // Only update if currently queued (not partial_failure)
      }
    }

    return json({
      processed,
      failed,
      total: notifications.length,
      consolidated: consolidated.length,
      invalidTokensRemoved: invalidTokens.length,
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      500
    );
  }
});
