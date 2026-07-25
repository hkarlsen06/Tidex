// Supabase Edge Function: Before User Created Hook
// - Triggered by Supabase Auth before a new user is created
// - Verifies webhook signature using standardwebhooks
// - Inserts a notification to notify admin of new signups
// - Always returns 204 to allow signup to proceed

import { createAdminClient } from "@supabase/server/core";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

// ---------- Env ----------
const HOOK_SECRET = Deno.env.get("BEFORE_USER_CREATED_HOOK_SECRET")?.replace(
  "v1,whsec_",
  "",
) ?? "";

// ---------- Types ----------
interface BeforeUserCreatedPayload {
  metadata: {
    uuid: string;
    time: string;
    ip_address: string;
    name: "before-user-created";
  };
  user: {
    id: string;
    aud: string;
    role: string;
    email: string;
    phone: string;
    app_metadata: {
      provider: string;
      providers: string[];
    };
    user_metadata: Record<string, unknown>;
    identities: unknown[];
    created_at: string;
    updated_at: string;
    is_anonymous: boolean;
  };
}

interface SignupNotification {
  recipient_id: string;
  notification_type: "admin_new_signup";
  title: string;
  body: string;
  data_payload: {
    new_user_id: string;
    new_user_name: string | null;
    new_user_email: string | null;
    new_user_phone: string | null;
    provider: string;
    signup_ip: string;
  };
  status: "pending";
  due_at: string;
  idempotency_key: string;
}

// ---------- Helpers ----------
export function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function extractName(
  user: BeforeUserCreatedPayload["user"],
): string | null {
  const metadata = user.user_metadata ?? {};
  const metadataPartsName = [
    asNonEmptyString(metadata.given_name),
    asNonEmptyString(metadata.family_name),
  ].filter(Boolean).join(" ").trim();

  const metadataName = asNonEmptyString(metadata.full_name) ??
    asNonEmptyString(metadata.name) ??
    (metadataPartsName || null);
  if (metadataName) return metadataName;

  for (const identity of user.identities ?? []) {
    if (!identity || typeof identity !== "object") continue;
    const identityRecord = identity as Record<string, unknown>;

    const identityData = identityRecord.identity_data &&
        typeof identityRecord.identity_data === "object"
      ? (identityRecord.identity_data as Record<string, unknown>)
      : null;
    if (!identityData) continue;
    const identityPartsName = [
      asNonEmptyString(identityData.given_name),
      asNonEmptyString(identityData.family_name),
    ].filter(Boolean).join(" ").trim();

    const identityName = asNonEmptyString(identityData.full_name) ??
      asNonEmptyString(identityData.name) ??
      (identityPartsName || null);
    if (identityName) return identityName;
  }

  return null;
}

export function buildNotificationBody(
  user: BeforeUserCreatedPayload["user"],
): string {
  const lines: string[] = [];

  // Add name if available from user_metadata
  const fullName = extractName(user);
  if (fullName) {
    lines.push(fullName);
  }

  // Add email or phone
  if (user.email) {
    lines.push(user.email);
  } else if (user.phone) {
    lines.push(user.phone);
  }

  // Add OAuth provider info if not email/phone signup
  const provider = user.app_metadata.provider;
  if (provider && provider !== "email" && provider !== "phone") {
    lines.push(`via ${provider}`);
  }

  // Add anonymous user indicator
  if (user.is_anonymous) {
    lines.push("(anonymous)");
  }

  return lines.join("\n") || "No contact info provided";
}

export function buildSignupNotifications(
  adminUserIds: string[],
  payload: BeforeUserCreatedPayload,
  dueAt: string,
): SignupNotification[] {
  const title = "New user signed up";
  const body = buildNotificationBody(payload.user);
  const fullName = extractName(payload.user);

  return adminUserIds.map((adminUserId) => ({
    recipient_id: adminUserId,
    notification_type: "admin_new_signup",
    title,
    body,
    data_payload: {
      new_user_id: payload.user.id,
      new_user_name: fullName,
      new_user_email: payload.user.email || null,
      new_user_phone: payload.user.phone || null,
      provider: payload.user.app_metadata.provider,
      signup_ip: payload.metadata.ip_address,
    },
    status: "pending",
    due_at: dueAt,
    idempotency_key: `new-signup-${payload.user.id}-${adminUserId}`,
  }));
}

// ---------- Server ----------
async function handleRequest(req: Request): Promise<Response> {
  // Always return 204 to allow signup - we don't want notification failures to block signups
  const allowSignup = () => new Response(null, { status: 204 });

  try {
    // Only accept POST requests
    if (req.method !== "POST") {
      return allowSignup();
    }

    if (!HOOK_SECRET) {
      console.error("BEFORE_USER_CREATED_HOOK_SECRET not configured");
      return allowSignup();
    }

    // Get raw payload for signature verification
    const payloadText = await req.text();
    const headers = Object.fromEntries(req.headers);

    // Verify webhook signature
    let payload: BeforeUserCreatedPayload;
    try {
      const wh = new Webhook(HOOK_SECRET);
      payload = wh.verify(payloadText, headers) as BeforeUserCreatedPayload;
    } catch (error) {
      console.error("Webhook signature verification failed:", error);
      return allowSignup();
    }

    // Validate hook name
    if (payload.metadata?.name !== "before-user-created") {
      console.error("Invalid hook name:", payload.metadata?.name);
      return allowSignup();
    }

    const supabase = createAdminClient<any>();

    const { data: adminUserIds, error: adminLookupError } = await supabase.rpc(
      "get_admin_user_ids",
    );

    if (adminLookupError) {
      console.error(
        "Failed to look up admin notification recipients:",
        adminLookupError,
      );
      return allowSignup();
    }

    if (!adminUserIds?.length) {
      console.error("No admin notification recipients configured");
      return allowSignup();
    }

    const notifications = buildSignupNotifications(
      adminUserIds,
      payload,
      new Date().toISOString(),
    );

    const { error } = await supabase.schema("internal").from(
      "notifications_outbox",
    ).upsert(notifications, {
      onConflict: "idempotency_key",
      ignoreDuplicates: true,
    });

    if (error) {
      // Log but don't fail - we still want signup to proceed
      console.error("Failed to insert notification:", error);
    }

    return allowSignup();
  } catch (error) {
    console.error("Edge function error:", error);
    // Always allow signup even if notification fails
    return allowSignup();
  }
}

export default { fetch: handleRequest };
