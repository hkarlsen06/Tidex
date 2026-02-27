// Supabase Edge Function: Process Shift Reminders
// - Called by cron every 10 minutes
// - Queries shifts due for reminders using get_shifts_due_for_reminder()
// - Uses claim-before-send pattern to prevent duplicate sends
// - Sends push notifications via FCM HTTP v1 API

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

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
interface DueReminder {
  user_id: string;
  shift_instance_key: string;
  shift_date: string;
  start_time: string;
  end_time: string;
  reminder_minutes: number;
  minutes_until_shift: number;
  job_name?: string | null;
}

interface PushDevice {
  id: string;
  fcm_token: string;
  apns_token: string | null;
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

function formatTime(timeStr: string): string {
  // Handle both "HH:mm" and "HH:mm:ss" formats
  return timeStr.slice(0, 5);
}

/**
 * Get today and tomorrow date strings in Norway timezone
 */
function getNorwayDates(): { today: string; tomorrow: string } {
  const nowInNorway = new Date().toLocaleString("en-US", { timeZone: "Europe/Oslo" });
  const norwayDate = new Date(nowInNorway);
  const today = norwayDate.toISOString().split("T")[0];

  const tomorrowDate = new Date(norwayDate.getTime() + 86400000);
  const tomorrow = tomorrowDate.toISOString().split("T")[0];

  return { today, tomorrow };
}

/**
 * Build reminder notification message
 * - Title: "X timer til neste vakt" (calculated at send time)
 * - Body: "I dag/I morgen kl. {start}-{end}"
 */
function buildReminderMessage(
  minutesUntil: number,
  shiftDate: string,
  startTime: string,
  endTime: string,
  jobName?: string | null
): { title: string; body: string } {
  // Use CEIL consistently (matches SQL) to avoid "1 time" when there's 1h 29m left
  const hours = Math.ceil(minutesUntil / 60);

  // Title: "X timer til neste vakt"
  const title = hours === 1
    ? "1 time til neste vakt"
    : `${hours} timer til neste vakt`;

  // Body: "I dag/I morgen kl. {start}-{end}"
  const { today, tomorrow } = getNorwayDates();

  let dayText: string;
  if (shiftDate === today) {
    dayText = "I dag";
  } else if (shiftDate === tomorrow) {
    dayText = "I morgen";
  } else {
    // Edge case for shifts > 24hr out (24hr reminder for day after tomorrow)
    // Format as "onsdag 15. januar"
    const date = new Date(shiftDate);
    dayText = date.toLocaleDateString("nb-NO", {
      weekday: "long",
      day: "numeric",
      month: "long",
    });
    // Capitalize first letter
    dayText = dayText.charAt(0).toUpperCase() + dayText.slice(1);
  }

  const baseBody = `${dayText} kl. ${formatTime(startTime)}-${formatTime(endTime)}`;
  const safeJobName = jobName?.trim();
  const body = safeJobName ? `${baseBody} · ${safeJobName}` : baseBody;
  return { title, body };
}

// ---------- FCM Helpers ----------
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

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const jwt = await createJwt(payload, FCM_PRIVATE_KEY);

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

async function sendReminderToFcm(
  accessToken: string,
  fcmToken: string,
  reminder: DueReminder
): Promise<{ success: boolean; invalidToken?: boolean }> {
  const { title, body } = buildReminderMessage(
    reminder.minutes_until_shift,
    reminder.shift_date,
    reminder.start_time,
    reminder.end_time,
    reminder.job_name
  );

  // Extract shift_id from instance_key (format: "single:{id}:{date}:{start}")
  const parts = reminder.shift_instance_key.split(":");
  const shiftId = parts.length >= 2 ? parts[1] : "";

  const message = {
    message: {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: {
        type: "shift_reminder",
        shift_id: shiftId,
        shift_date: reminder.shift_date,
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "tidex_notification.caf",
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
 * Process a single reminder using claim-before-send pattern
 * Returns true if notification was sent, false if already claimed or failed
 */
async function processReminder(
  supabase: SupabaseClient,
  reminder: DueReminder,
  accessToken: string
): Promise<{ sent: boolean; invalidTokens: string[] }> {
  // Step 1: Try to claim the reminder by inserting into sent table
  // The unique constraint on (user_id, shift_instance_key, reminder_minutes) acts as a distributed lock
  const { error: claimError } = await supabase
    .from("shift_reminders_sent")
    .insert({
      user_id: reminder.user_id,
      shift_instance_key: reminder.shift_instance_key,
      reminder_minutes: reminder.reminder_minutes,
    });

  if (claimError) {
    // Unique constraint violation = already claimed by another worker
    if (claimError.code === "23505") {
      console.log(`Reminder already sent: ${reminder.shift_instance_key}`);
      return { sent: false, invalidTokens: [] };
    }
    throw claimError;
  }

  // Step 2: Claim succeeded, get user's devices and send notification
  const { data: devices } = await supabase
    .schema("internal").from("push_devices")
    .select("id, fcm_token, apns_token")
    .eq("user_id", reminder.user_id);

  if (!devices?.length) {
    console.log(`No devices for user ${reminder.user_id}`);
    return { sent: false, invalidTokens: [] };
  }

  // Skip if user has ANY device with APNs token - they handle reminders locally
  // This prevents double notifications for iOS users
  const hasApnsDevice = (devices as PushDevice[]).some((d) => d.apns_token != null);
  if (hasApnsDevice) {
    console.log(`User ${reminder.user_id} has APNs device, skipping server reminder`);
    return { sent: false, invalidTokens: [] };
  }

  // Send to each device
  const invalidTokens: string[] = [];
  let anySuccess = false;

  for (const device of devices as PushDevice[]) {
    try {
      const result = await sendReminderToFcm(accessToken, device.fcm_token, reminder);

      if (result.success) {
        anySuccess = true;
      } else if (result.invalidToken) {
        invalidTokens.push(device.id);
      }
    } catch (error) {
      console.error(`Failed to send to device ${device.id}:`, error);
    }
  }

  if (anySuccess) {
    console.log(`Sent reminder for ${reminder.shift_instance_key}`);
  } else {
    console.error(`Failed to send reminder for ${reminder.shift_instance_key} to any device`);
  }

  return { sent: anySuccess, invalidTokens };
}

// ---------- Server ----------
serve(async (req) => {
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

    // Get shifts due for reminders
    const { data: dueReminders, error: queryError } = await supabase.rpc(
      "get_shifts_due_for_reminder"
    );

    if (queryError) {
      console.error("Failed to get due reminders:", queryError);
      throw queryError;
    }

    if (!dueReminders?.length) {
      return json({ processed: 0, message: "No reminders due" });
    }

    console.log(`Found ${dueReminders.length} reminders due`);

    // Get FCM access token
    const accessToken = await getFcmAccessToken();

    let sent = 0;
    let skipped = 0;
    let failed = 0;
    const allInvalidTokens: string[] = [];

    for (const reminder of dueReminders as DueReminder[]) {
      try {
        const result = await processReminder(supabase, reminder, accessToken);

        if (result.sent) {
          sent++;
        } else {
          skipped++;
        }

        allInvalidTokens.push(...result.invalidTokens);
      } catch (error) {
        console.error(`Error processing reminder ${reminder.shift_instance_key}:`, error);
        failed++;
      }
    }

    // Clean up invalid tokens
    if (allInvalidTokens.length > 0) {
      await supabase.schema("internal").from("push_devices").delete().in("id", allInvalidTokens);
      console.log(`Deleted ${allInvalidTokens.length} invalid tokens`);
    }

    return json({
      total: dueReminders.length,
      sent,
      skipped,
      failed,
      invalidTokensRemoved: allInvalidTokens.length,
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      500
    );
  }
});
