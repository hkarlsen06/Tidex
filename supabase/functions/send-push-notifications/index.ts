// Supabase Edge Function: Send Push Notifications
// - Processes notifications from notifications_outbox table (pre-built messages)
// - Uses APNs HTTP/2 API for iOS native app (preferred)
// - Uses FCM HTTP v1 API with OAuth2 for hybrid app (fallback)
// - Atomic queue claiming via claim_outbox_notifications RPC
// - Automatic invalid token cleanup
// - NO message building - titles/bodies are pre-computed by app

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

// ---------- Env ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

// FCM HTTP v1 credentials (from Google service account JSON)
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID") ?? "";
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(
  /\\n/g,
  "\n",
);

// APNs credentials (from Apple Developer Portal)
// Production credentials (for App Store builds)
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_PRIVATE_KEY = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(
  /\\n/g,
  "\n",
);
// Sandbox credentials (for TestFlight/debug builds) - falls back to production if not set
const APNS_SANDBOX_KEY_ID = Deno.env.get("APNS_SANDBOX_KEY_ID") ?? "";
const APNS_SANDBOX_PRIVATE_KEY =
  (Deno.env.get("APNS_SANDBOX_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "no.tidex.app";

// Cache access tokens (valid for 1 hour)
let cachedFcmAccessToken: { token: string; expiresAt: number } | null = null;
let cachedApnsTokenProd: { token: string; expiresAt: number } | null = null;
let cachedApnsTokenSandbox: { token: string; expiresAt: number } | null = null;

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
  fcm_token: string | null;
  apns_token: string | null;
}

interface NotificationDeliveryJob {
  notifications: OutboxNotification[];
  notification: OutboxNotification;
}

// ---------- Helpers ----------
function res(body: string, status: number) {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/plain" },
  });
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function notificationDataString(
  notification: OutboxNotification,
  key: string,
): string | null {
  return asNonEmptyString(notification.data_payload[key]);
}

function notificationMessageCount(notification: OutboxNotification): number {
  const rawCount = notification.data_payload.message_count;
  const count = typeof rawCount === "number"
    ? rawCount
    : typeof rawCount === "string"
    ? Number.parseInt(rawCount, 10)
    : Number.NaN;

  return Number.isFinite(count) && count > 0 ? Math.floor(count) : 1;
}

function notificationThreadId(notification: OutboxNotification): string | null {
  return notification.notification_type === "thread_message"
    ? notificationDataString(notification, "thread_id")
    : null;
}

function notificationCollapseId(
  notification: OutboxNotification,
): string | null {
  const threadId = notificationThreadId(notification);
  if (!threadId) return null;
  if (notificationMessageCount(notification) < 4) return null;
  return `thread-message:${threadId}`;
}

function isNewerNotification(
  lhs: OutboxNotification,
  rhs: OutboxNotification,
): boolean {
  return lhs.created_at > rhs.created_at ||
    (lhs.created_at === rhs.created_at && lhs.id > rhs.id);
}

function coalesceNotifications(
  notifications: OutboxNotification[],
): NotificationDeliveryJob[] {
  const jobsByKey = new Map<string, NotificationDeliveryJob>();

  for (const notification of notifications) {
    const threadId = notificationThreadId(notification);
    const key = threadId
      ? `thread_message:${notification.recipient_id}:${threadId}`
      : notification.id;

    const existing = jobsByKey.get(key);
    if (!existing) {
      jobsByKey.set(key, {
        notifications: [notification],
        notification,
      });
      continue;
    }

    existing.notifications.push(notification);
    if (isNewerNotification(notification, existing.notification)) {
      existing.notification = notification;
    }
  }

  return Array.from(jobsByKey.values()).map((job) => {
    if (job.notifications.length == 1) {
      return job;
    }

    const latestMessageCount = job.notifications.reduce(
      (maxCount, notification) =>
        Math.max(maxCount, notificationMessageCount(notification)),
      0,
    );

    return {
      notifications: job.notifications,
      notification: {
        ...job.notification,
        data_payload: {
          ...job.notification.data_payload,
          message_count: latestMessageCount,
        },
      },
    };
  });
}

function buildApsPayload(
  notification: OutboxNotification,
  badgeCount: number,
): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: { title: notification.title, body: notification.body },
    sound: "tidex_notification.caf",
    badge: Math.max(0, badgeCount),
    "mutable-content": 1,
  };

  const threadId = notificationThreadId(notification);
  if (threadId) {
    aps["category"] = "THREAD_MESSAGE";
    aps["thread-id"] = threadId;
    aps["target-content-id"] = `friend-chat:${threadId}`;
    aps["interruption-level"] = "active";
    aps["relevance-score"] = notificationMessageCount(notification) > 1
      ? 0.95
      : 0.9;
    return aps;
  }

  switch (notification.notification_type) {
    case "share_started":
      aps["thread-id"] = "sharing";
      aps["target-content-id"] = "sharing";
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.65;
      break;
    case "feedback_responded":
      aps["thread-id"] = "feedback";
      aps["target-content-id"] = "feedback";
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.55;
      break;
    case "feedback_submitted":
      aps["thread-id"] = "admin-feedback";
      aps["target-content-id"] = "admin-feedback";
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.55;
      break;
    case "abuse_report_submitted":
      aps["thread-id"] = "admin-reports";
      aps["target-content-id"] = "admin-reports";
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.7;
      break;
    default:
      aps["thread-id"] = notification.notification_type;
      aps["target-content-id"] = notification.notification_type;
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.5;
      break;
  }

  return aps;
}

function buildApnsHeaders(
  notification: OutboxNotification,
): Record<string, string> {
  const headers: Record<string, string> = {
    "apns-push-type": "alert",
    "apns-priority": "10",
  };

  const collapseId = notificationCollapseId(notification);
  if (collapseId) {
    headers["apns-collapse-id"] = collapseId;
  }

  return headers;
}

async function getUnreadBadgeCount(
  supabase: ReturnType<typeof createClient>,
  recipientId: string,
  cache: Map<string, number>,
): Promise<number> {
  const cached = cache.get(recipientId);
  if (cached !== undefined) {
    return cached;
  }

  const { data, error } = await supabase.rpc(
    "get_unread_direct_message_count",
    {
      p_user_id: recipientId,
    },
  );

  if (error) {
    console.error(
      `Failed to fetch unread badge count for ${recipientId}:`,
      error,
    );
    cache.set(recipientId, 0);
    return 0;
  }

  const badgeCount = typeof data === "number"
    ? data
    : Number.parseInt(String(data ?? 0), 10) || 0;
  cache.set(recipientId, Math.max(0, badgeCount));
  return Math.max(0, badgeCount);
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

/**
 * Create JWT with RS256 algorithm (for FCM/Google OAuth)
 */
async function createJwtRs256(
  payload: object,
  privateKey: string,
): Promise<string> {
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
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(signature)}`;
}

/**
 * Create JWT with ES256 algorithm (for APNs)
 * APNs requires ECDSA with P-256 curve
 */
async function createJwtEs256(
  payload: object,
  privateKey: string,
  keyId: string,
): Promise<string> {
  const header = { alg: "ES256", typ: "JWT", kid: keyId };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  // Import EC private key (P-256 curve)
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  // Convert signature to raw r||s format (APNs expects raw format)
  // Web Crypto may return DER or raw format depending on runtime
  const rawSignature = signatureToRaw(new Uint8Array(signature));

  return `${signingInput}.${base64UrlEncode(rawSignature)}`;
}

/**
 * Convert ECDSA signature to raw r||s format for APNs
 * Handles both DER-encoded and raw format signatures
 * - Deno/Web Crypto may return either format depending on version
 * - DER format: 0x30 [total-length] 0x02 [r-length] [r] 0x02 [s-length] [s]
 * - Raw format: [r (32 bytes)] [s (32 bytes)] = 64 bytes total
 */
function signatureToRaw(sig: Uint8Array): Uint8Array {
  // If already 64 bytes, it's already in raw format
  if (sig.length === 64) {
    return sig;
  }

  // Otherwise, parse as DER format
  // DER format starts with 0x30 (SEQUENCE tag)
  if (sig[0] !== 0x30) {
    throw new Error(
      `Unexpected signature format: first byte is ${
        sig[0]
      }, length is ${sig.length}`,
    );
  }

  let offset = 2; // Skip 0x30 and total length

  // Read r
  if (sig[offset] !== 0x02) {
    throw new Error(
      `Invalid DER signature: expected 0x02 at offset ${offset}, got ${
        sig[offset]
      }`,
    );
  }
  offset++;
  const rLength = sig[offset];
  offset++;
  let r = sig.slice(offset, offset + rLength);
  offset += rLength;

  // Read s
  if (sig[offset] !== 0x02) {
    throw new Error(
      `Invalid DER signature: expected 0x02 at offset ${offset}, got ${
        sig[offset]
      }`,
    );
  }
  offset++;
  const sLength = sig[offset];
  offset++;
  let s = sig.slice(offset, offset + sLength);

  // Normalize to 32 bytes each (remove leading zeros or pad)
  r = normalizeToLength(r, 32);
  s = normalizeToLength(s, 32);

  // Concatenate r and s
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);

  return raw;
}

/**
 * Normalize byte array to specific length
 */
function normalizeToLength(bytes: Uint8Array, length: number): Uint8Array {
  if (bytes.length === length) return bytes;

  if (bytes.length > length) {
    // Remove leading zeros
    return bytes.slice(bytes.length - length);
  }

  // Pad with leading zeros
  const padded = new Uint8Array(length);
  padded.set(bytes, length - bytes.length);
  return padded;
}

async function getFcmAccessToken(): Promise<string> {
  // Return cached token if still valid (with 1 minute buffer)
  if (
    cachedFcmAccessToken && Date.now() < cachedFcmAccessToken.expiresAt - 60000
  ) {
    return cachedFcmAccessToken.token;
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

  const jwt = await createJwtRs256(payload, FCM_PRIVATE_KEY);

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
  cachedFcmAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };

  return data.access_token;
}

/**
 * Get APNs JWT token for authentication
 * APNs uses ES256 algorithm (ECDSA with P-256 curve)
 * @param sandbox - If true, use sandbox credentials; otherwise use production
 */
async function getApnsToken(sandbox: boolean): Promise<string> {
  const cache = sandbox ? cachedApnsTokenSandbox : cachedApnsTokenProd;

  // Return cached token if still valid (with 5 minute buffer)
  // APNs tokens are valid for 1 hour
  if (cache && Date.now() < cache.expiresAt - 300000) {
    return cache.token;
  }

  // Select credentials based on environment
  const keyId = sandbox ? (APNS_SANDBOX_KEY_ID || APNS_KEY_ID) : APNS_KEY_ID;
  const privateKey = sandbox
    ? (APNS_SANDBOX_PRIVATE_KEY || APNS_PRIVATE_KEY)
    : APNS_PRIVATE_KEY;

  const now = Math.floor(Date.now() / 1000);
  const token = await createJwtEs256(
    { iss: APNS_TEAM_ID, iat: now },
    privateKey,
    keyId,
  );

  const cacheEntry = {
    token,
    expiresAt: Date.now() + 3600000, // 1 hour
  };

  if (sandbox) {
    cachedApnsTokenSandbox = cacheEntry;
  } else {
    cachedApnsTokenProd = cacheEntry;
  }

  return token;
}

/**
 * Send a notification to FCM
 * Title and body are pre-computed and stored in the outbox
 */
async function sendToFcm(
  accessToken: string,
  fcmToken: string,
  notification: OutboxNotification,
  badgeCount: number,
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

  const aps = buildApsPayload(notification, badgeCount);
  const apnsHeaders = buildApnsHeaders(notification);

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
        headers: apnsHeaders,
        payload: {
          aps,
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
    },
  );

  if (response.ok) {
    return { success: true };
  }

  const errorBody = await response.text();
  console.error(
    `FCM error for token ${fcmToken.substring(0, 20)}...:`,
    errorBody,
  );

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
 * Send a notification to APNs (Apple Push Notification service)
 * Uses HTTP/2 API with JWT authentication
 * Tries production first, falls back to sandbox if BadDeviceToken
 */
async function sendToApns(
  apnsToken: string,
  notification: OutboxNotification,
  badgeCount: number,
): Promise<{ success: boolean; invalidToken?: boolean }> {
  const { title, body, data_payload, notification_type } = notification;

  // Build custom data payload
  const customData: Record<string, unknown> = {
    type: notification_type,
    ...data_payload,
  };

  const aps = buildApsPayload(notification, badgeCount);
  const apnsHeaders = buildApnsHeaders(notification);

  // APNs payload format
  const payload = {
    aps,
    ...customData,
  };

  // Try production first, then sandbox
  // This handles mixed environments (App Store + TestFlight users)
  const environments: Array<{ sandbox: boolean; host: string }> = [
    { sandbox: false, host: "api.push.apple.com" },
    { sandbox: true, host: "api.sandbox.push.apple.com" },
  ];

  // Check if sandbox credentials are configured
  const sandboxConfigured = !!(APNS_SANDBOX_KEY_ID && APNS_SANDBOX_PRIVATE_KEY);

  for (const env of environments) {
    // Skip sandbox if not configured
    if (env.sandbox && !sandboxConfigured) {
      continue;
    }

    const jwtToken = await getApnsToken(env.sandbox);
    const apnsUrl = `https://${env.host}/3/device/${apnsToken}`;

    console.log(`[APNs] Trying ${env.host}...`);

    const response = await fetch(apnsUrl, {
      method: "POST",
      headers: {
        Authorization: `bearer ${jwtToken}`,
        "apns-topic": APNS_BUNDLE_ID,
        ...apnsHeaders,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (response.ok) {
      console.log(`[APNs] Success via ${env.host}`);
      return { success: true };
    }

    const status = response.status;
    const errorBody = await response.text();
    console.error(
      `APNs error (${status}) via ${env.host} for token ${
        apnsToken.substring(0, 20)
      }...:`,
      errorBody,
    );

    // If BadDeviceToken on production, try sandbox (device might be from TestFlight)
    if (
      status === 400 && errorBody.includes("BadDeviceToken") && !env.sandbox
    ) {
      console.log("[APNs] BadDeviceToken on production, trying sandbox...");
      continue;
    }

    // 410 Unregistered means token is truly invalid (user uninstalled app)
    if (status === 410) {
      return { success: false, invalidToken: true };
    }

    // Other 400 errors (BadDeviceToken after both attempts) mean invalid token
    if (status === 400) {
      // Only mark as invalid if this is the last attempt
      if (env.sandbox || !sandboxConfigured) {
        return { success: false, invalidToken: true };
      }
    }
  }

  // All attempts failed
  return { success: false, invalidToken: true };
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

    // Check if at least one push provider is configured
    const fcmConfigured =
      !!(FCM_PROJECT_ID && FCM_CLIENT_EMAIL && FCM_PRIVATE_KEY);
    const apnsConfigured = !!(APNS_KEY_ID && APNS_TEAM_ID && APNS_PRIVATE_KEY);

    if (!fcmConfigured && !apnsConfigured) {
      return res("No push provider configured (FCM or APNs required)", 503);
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

    // Get FCM access token only if FCM is configured
    let fcmAccessToken: string | null = null;
    if (fcmConfigured) {
      fcmAccessToken = await getFcmAccessToken();
    }

    let processed = 0;
    let failed = 0;
    const invalidTokens: string[] = [];
    const unreadBadgeCountByRecipient = new Map<string, number>();
    const deliveryJobs = coalesceNotifications(
      notifications as OutboxNotification[],
    );

    for (const job of deliveryJobs) {
      const notification = job.notification;
      const notificationIds = job.notifications.map((entry) => entry.id);
      try {
        // Get recipient's push tokens (both APNs and FCM)
        const { data: devices } = await supabase
          .schema("internal")
          .from("push_devices")
          .select("id, fcm_token, apns_token")
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
            .in("id", notificationIds);
          continue;
        }

        const badgeCount = await getUnreadBadgeCount(
          supabase,
          notification.recipient_id,
          unreadBadgeCountByRecipient,
        );

        // Send to each device
        // Priority: APNs (native iOS) > FCM (hybrid/Android)
        let anySuccess = false;
        for (const device of devices as PushDevice[]) {
          let result: { success: boolean; invalidToken?: boolean };

          // Prefer APNs if token exists and APNs is configured
          if (device.apns_token && apnsConfigured) {
            result = await sendToApns(
              device.apns_token,
              notification,
              badgeCount,
            );
            if (result.invalidToken) {
              // Clear invalid APNs token but don't delete device (may have FCM)
              await supabase
                .schema("internal")
                .from("push_devices")
                .update({ apns_token: null })
                .eq("id", device.id);
            }
          } // Fall back to FCM if APNs not available/failed
          else if (device.fcm_token && fcmAccessToken) {
            result = await sendToFcm(
              fcmAccessToken,
              device.fcm_token,
              notification,
              badgeCount,
            );
            if (result.invalidToken) {
              // Token is invalid, queue device for deletion
              invalidTokens.push(device.id);
            }
          } else {
            // No valid token for this device
            result = { success: false };
          }

          if (result.success) {
            anySuccess = true;
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
          .in("id", notificationIds);

        if (anySuccess) processed += notificationIds.length;
        else failed += notificationIds.length;
      } catch (error) {
        console.error(
          `Error processing notification ${notification.id}:`,
          error,
        );

        await supabase
          .schema("internal")
          .from("notifications_outbox")
          .update({
            status: "failed",
            error_message: error instanceof Error
              ? error.message
              : "Unknown error",
            processed_at: new Date().toISOString(),
          })
          .in("id", notificationIds);

        failed += notificationIds.length;
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      await supabase.schema("internal").from("push_devices").delete().in(
        "id",
        invalidTokens,
      );
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
      500,
    );
  }
});
