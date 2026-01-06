// Supabase Edge Function: Send Push Notifications
// - Processes notifications from notifications_outbox table (pre-built messages)
// - Uses FCM HTTP v1 API with OAuth2 for iOS/Android push
// - Atomic queue claiming via claim_outbox_notifications RPC
// - Automatic invalid token cleanup
// - NO message building - titles/bodies are pre-computed by app

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
interface OutboxNotification {
  id: string;
  owner_id: string | null;
  recipient_id: string;
  broadcast_id: string | null;
  notification_type: string;
  due_at: string;
  status: string;
  title: string;
  body: string;
  data_payload: Record<string, unknown>;
  idempotency_key: string;
  created_at: string;
}

interface PushDevice {
  id: string;
  fcm_token: string;
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
 * Send a notification to FCM
 * Title and body are pre-computed and stored in the outbox
 */
async function sendToFcm(
  accessToken: string,
  fcmToken: string,
  notification: OutboxNotification
): Promise<{ success: boolean; invalidToken?: boolean }> {
  const { title, body, data_payload, notification_type } = notification;

  // Build data payload for deep linking
  // data_payload already contains type, owner_id, shift_dates, deeplink, etc.
  const dataPayload: Record<string, string> = {
    type: notification_type,
  };

  // Flatten data_payload to strings for FCM (FCM data values must be strings)
  for (const [key, value] of Object.entries(data_payload)) {
    if (value !== null && value !== undefined) {
      if (Array.isArray(value)) {
        // Convert arrays to comma-separated strings (e.g., shift_dates)
        dataPayload[key] = value.join(",");
      } else {
        dataPayload[key] = String(value);
      }
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

    // Claim notifications using the new RPC function
    // This atomically marks notifications as 'sending' and returns them
    // Note: Function is in internal schema, need to use schema() method
    const { data: notifications, error: claimError } = await supabase
      .schema("internal")
      .rpc("claim_outbox_notifications", { batch_size: 50 });

    if (claimError) {
      console.error("Failed to claim notifications:", claimError);
      throw claimError;
    }

    if (!notifications?.length) {
      return json({ processed: 0, message: "No pending notifications" });
    }

    // Get FCM access token
    const accessToken = await getFcmAccessToken();

    let processed = 0;
    let failed = 0;
    const invalidTokens: string[] = [];

    for (const notification of notifications as OutboxNotification[]) {
      try {
        // Get recipient's FCM tokens
        const { data: devices } = await supabase
          .schema("internal")
          .from("push_devices")
          .select("id, fcm_token")
          .eq("user_id", notification.recipient_id);

        if (!devices?.length) {
          // No devices registered, mark as skipped
          await supabase
            .schema("internal")
            .from("notifications_outbox")
            .update({
              status: "skipped",
              processed_at: new Date().toISOString(),
            })
            .eq("id", notification.id);
          continue;
        }

        // Send to each device
        let anySuccess = false;
        for (const device of devices as PushDevice[]) {
          const result = await sendToFcm(accessToken, device.fcm_token, notification);

          if (result.success) {
            anySuccess = true;
          } else if (result.invalidToken) {
            // Token is invalid, queue for deletion
            invalidTokens.push(device.id);
          }
        }

        // Mark notification status
        await supabase
          .schema("internal")
          .from("notifications_outbox")
          .update({
            status: anySuccess ? "sent" : "failed",
            error_message: anySuccess ? null : "All devices failed",
            processed_at: new Date().toISOString(),
          })
          .eq("id", notification.id);

        if (anySuccess) processed++;
        else failed++;
      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error);

        await supabase
          .schema("internal")
          .from("notifications_outbox")
          .update({
            status: "failed",
            error_message: error instanceof Error ? error.message : "Unknown error",
            processed_at: new Date().toISOString(),
          })
          .eq("id", notification.id);

        failed++;
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      await supabase.schema("internal").from("push_devices").delete().in("id", invalidTokens);
      console.log(`Deleted ${invalidTokens.length} invalid tokens`);
    }

    // Update broadcast status to 'complete' for finished admin broadcasts
    const processedBroadcastIds = new Set<string>();
    for (const notification of notifications as OutboxNotification[]) {
      if (notification.broadcast_id) {
        processedBroadcastIds.add(notification.broadcast_id);
      }
    }

    // For each broadcast, check if all notifications are processed
    for (const broadcastId of processedBroadcastIds) {
      // Count remaining pending notifications for this broadcast
      const { count: pendingCount } = await supabase
        .schema("internal")
        .from("notifications_outbox")
        .select("*", { count: "exact", head: true })
        .eq("broadcast_id", broadcastId)
        .in("status", ["pending", "sending"]);

      // If no pending notifications remain, mark broadcast as complete
      if (pendingCount === 0) {
        await supabase
          .schema("internal")
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
