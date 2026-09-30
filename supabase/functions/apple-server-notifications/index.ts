// Supabase Edge Function: Apple App Store Server Notifications V2
// - Receives and verifies Apple server-to-server notifications
// - Updates subscription state in unified subscriptions table
// - Handles renewals, cancellations, refunds, grace periods, expirations
// - Does NOT require Supabase auth (Apple sends notifications directly)
// - Verifies notification signature using Apple's public keys
import { Buffer } from "node:buffer";
import { DenoSignedDataVerifier } from "../_shared/deno-signed-data-verifier.ts";
import { createAdminClient } from "@supabase/server/core";
import {
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

// ---------- Environment ----------
const APPLE_APP_BUNDLE_ID = Deno.env.get("APPLE_APP_BUNDLE_ID") ??
  "no.tidex.app";
const APPLE_APP_APPLE_ID_RAW = Deno.env.get("APPLE_APP_APPLE_ID") ??
  Deno.env.get("APPLE_APP_ID") ??
  "6757129790";
const APPLE_APP_APPLE_ID = Number(APPLE_APP_APPLE_ID_RAW);

// Apple's public key URLs for verification
const APPLE_ROOT_CA_G2_URL =
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer";
const APPLE_ROOT_CA_G3_URL =
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";
const APPLE_ROOT_CA_URLS = [APPLE_ROOT_CA_G2_URL, APPLE_ROOT_CA_G3_URL];
const EXTERNAL_FETCH_TIMEOUT_MS = 15_000;

// ---------- Apple Product ID Mapping ----------
// Matches existing tiers: Pro and Max, each with monthly/yearly
const APPLE_PRODUCT_TO_INTERNAL: Record<string, string> = {
  "no.tidex.pro": "pro_monthly",
  "no.tidex.pro.year": "pro_yearly",
  "no.tidex.max": "max_monthly",
  "no.tidex.max.year": "max_yearly",
};

function mapAppleProductToInternal(appleProductId: string): string {
  return APPLE_PRODUCT_TO_INTERNAL[appleProductId] ?? appleProductId;
}

// ---------- Supabase Client ----------
let supabaseAdmin: any = null;

// ---------- Apple Notification Types ----------
// https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
type NotificationType =
  | "CONSUMPTION_REQUEST"
  | "DID_CHANGE_RENEWAL_PREF"
  | "DID_CHANGE_RENEWAL_STATUS"
  | "DID_FAIL_TO_RENEW"
  | "DID_RENEW"
  | "EXPIRED"
  | "EXTERNAL_PURCHASE_TOKEN"
  | "GRACE_PERIOD_EXPIRED"
  | "OFFER_REDEEMED"
  | "PRICE_INCREASE"
  | "REFUND"
  | "REFUND_DECLINED"
  | "REFUND_REVERSED"
  | "RENEWAL_EXTENDED"
  | "RENEWAL_EXTENSION"
  | "REVOKE"
  | "SUBSCRIBED"
  | "TEST";

type NotificationSubtype =
  | "ACCEPTED"
  | "AUTO_RENEW_DISABLED"
  | "AUTO_RENEW_ENABLED"
  | "BILLING_RECOVERY"
  | "BILLING_RETRY"
  | "DOWNGRADE"
  | "FAILURE"
  | "GRACE_PERIOD"
  | "INITIAL_BUY"
  | "PENDING"
  | "PRICE_INCREASE"
  | "PRODUCT_NOT_FOR_SALE"
  | "RESUBSCRIBE"
  | "SUMMARY"
  | "UPGRADE"
  | "VOLUNTARY"
  | null;

interface AppleNotificationPayload {
  notificationType: NotificationType;
  subtype: NotificationSubtype;
  notificationUUID: string;
  data: {
    appAppleId?: number;
    bundleId: string;
    bundleVersion?: string;
    environment: "Production" | "Sandbox";
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
  version: string;
  signedDate: number;
}

interface AppleTransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  environment: "Production" | "Sandbox";
  appAccountToken?: string;
  offerType?: number;
  type: string;
}

interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId: string;
  autoRenewStatus: number;
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

type AppleVerificationResult = {
  notification: AppleNotificationPayload;
  verifier: SignedDataVerifier;
};

let appleRootCertificatesPromise: Promise<Buffer[]> | null = null;

async function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit = {},
  timeoutMs = EXTERNAL_FETCH_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  const upstreamSignal = init.signal;
  const abortFromUpstream = () => controller.abort();

  if (upstreamSignal?.aborted) {
    controller.abort();
  } else {
    upstreamSignal?.addEventListener("abort", abortFromUpstream, {
      once: true,
    });
  }

  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
    upstreamSignal?.removeEventListener("abort", abortFromUpstream);
  }
}

async function appleRootCertificates(): Promise<Buffer[]> {
  appleRootCertificatesPromise ??= Promise.all(
    APPLE_ROOT_CA_URLS.map(async (url) => {
      const response = await fetchWithTimeout(url);
      if (!response.ok) {
        throw new Error(`Failed to fetch Apple root certificate: ${url}`);
      }
      return Buffer.from(await response.arrayBuffer());
    }),
  ).catch((error) => {
    appleRootCertificatesPromise = null;
    throw error;
  });

  return appleRootCertificatesPromise;
}

function decodeAppleJWSPayload(jws: string): Record<string, any> | null {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) return null;
    return JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    return null;
  }
}

function appleNotificationEnvironmentHint(
  signedPayload: string,
): "Production" | "Sandbox" | null {
  const payload = decodeAppleJWSPayload(signedPayload);
  const environment = payload?.data?.environment ??
    payload?.summary?.environment ??
    payload?.appData?.environment;
  return environment === "Production" || environment === "Sandbox"
    ? environment
    : null;
}

function productionAppleAppId(): number {
  if (!Number.isFinite(APPLE_APP_APPLE_ID) || APPLE_APP_APPLE_ID <= 0) {
    throw new Error(
      "APPLE_APP_APPLE_ID or APPLE_APP_ID must be set for Production Apple notifications",
    );
  }
  return APPLE_APP_APPLE_ID;
}

function appleVerifiers(
  rootCertificates: Buffer[],
  signedPayload: string,
): SignedDataVerifier[] {
  const environment = appleNotificationEnvironmentHint(signedPayload);
  if (environment === "Sandbox") {
    return [
      new DenoSignedDataVerifier(
        rootCertificates,
        false,
        Environment.SANDBOX,
        APPLE_APP_BUNDLE_ID,
      ),
    ];
  }

  if (environment === "Production") {
    return [
      new DenoSignedDataVerifier(
        rootCertificates,
        false,
        Environment.PRODUCTION,
        APPLE_APP_BUNDLE_ID,
        productionAppleAppId(),
      ),
    ];
  }

  const verifiers = [
    new DenoSignedDataVerifier(
      rootCertificates,
      false,
      Environment.SANDBOX,
      APPLE_APP_BUNDLE_ID,
    ),
  ];

  if (APPLE_APP_APPLE_ID_RAW) {
    verifiers.unshift(
      new DenoSignedDataVerifier(
        rootCertificates,
        false,
        Environment.PRODUCTION,
        APPLE_APP_BUNDLE_ID,
        productionAppleAppId(),
      ),
    );
  }

  return verifiers;
}

// ---------- Signature Verification ----------
async function verifyAppleNotification(
  signedPayload: string,
): Promise<AppleVerificationResult | null> {
  try {
    const rootCertificates = await appleRootCertificates();

    for (const verifier of appleVerifiers(rootCertificates, signedPayload)) {
      try {
        const notification = await verifier.verifyAndDecodeNotification(
          signedPayload,
        ) as AppleNotificationPayload;
        return { notification, verifier };
      } catch (e) {
        console.warn(
          "[apple-notifications] Signed payload verification attempt failed:",
          e instanceof Error ? e.message : e,
        );
      }
    }

    console.error("[apple-notifications] Signed payload verification failed");
    return null;
  } catch (e) {
    console.error(
      "[apple-notifications] Verification failed:",
      e instanceof Error ? e.message : e,
    );
    return null;
  }
}

// ---------- Status Determination ----------
function determineStatusFromNotification(
  notificationType: NotificationType,
  subtype: NotificationSubtype,
  transactionInfo: AppleTransactionInfo | null,
  renewalInfo: AppleRenewalInfo | null,
): { status: string; cancelAtPeriodEnd: boolean } {
  const activeStatus = (cancelAtPeriodEnd = false) => ({
    status: transactionInfo?.offerType === 1 &&
        !!transactionInfo.expiresDate &&
        transactionInfo.expiresDate > Date.now()
      ? "trialing"
      : "active",
    cancelAtPeriodEnd,
  });

  // Handle based on notification type
  switch (notificationType) {
    case "SUBSCRIBED":
      if (subtype === "INITIAL_BUY" || subtype === "RESUBSCRIBE") {
        return activeStatus(false);
      }
      return activeStatus(false);

    case "DID_RENEW":
      if (subtype === "BILLING_RECOVERY") {
        return activeStatus(false);
      }
      return activeStatus(false);

    case "DID_FAIL_TO_RENEW":
      if (subtype === "GRACE_PERIOD") {
        return { status: "grace", cancelAtPeriodEnd: false };
      }
      return { status: "past_due", cancelAtPeriodEnd: false };

    case "DID_CHANGE_RENEWAL_STATUS":
      if (subtype === "AUTO_RENEW_DISABLED") {
        return activeStatus(true);
      }
      if (subtype === "AUTO_RENEW_ENABLED") {
        return activeStatus(false);
      }
      return activeStatus(renewalInfo?.autoRenewStatus === 0);

    case "EXPIRED":
      if (subtype === "VOLUNTARY") {
        return { status: "canceled", cancelAtPeriodEnd: true };
      }
      if (subtype === "BILLING_RETRY" || subtype === "PRICE_INCREASE") {
        return { status: "expired", cancelAtPeriodEnd: false };
      }
      return { status: "expired", cancelAtPeriodEnd: true };

    case "GRACE_PERIOD_EXPIRED":
      return { status: "expired", cancelAtPeriodEnd: false };

    case "REFUND":
    case "REVOKE":
      return { status: "refunded", cancelAtPeriodEnd: false };

    case "REFUND_REVERSED":
      // Refund was reversed - restore active status
      return activeStatus(false);

    case "RENEWAL_EXTENDED":
    case "RENEWAL_EXTENSION":
      return activeStatus(false);

    case "DID_CHANGE_RENEWAL_PREF":
      // User changed product (upgrade/downgrade) - still active
      return activeStatus(renewalInfo?.autoRenewStatus === 0);

    case "OFFER_REDEEMED":
      return activeStatus(false);

    case "TEST":
      // Test notification - don't change anything
      return { status: "active", cancelAtPeriodEnd: false };

    default:
      // For unknown types, infer from transaction/renewal info
      if (transactionInfo?.revocationDate) {
        return { status: "refunded", cancelAtPeriodEnd: false };
      }
      if (
        transactionInfo?.expiresDate && transactionInfo.expiresDate < Date.now()
      ) {
        return { status: "expired", cancelAtPeriodEnd: true };
      }
      return activeStatus(renewalInfo?.autoRenewStatus === 0);
  }
}

// ---------- Database Operations ----------
async function markNotificationSeen(
  notificationUUID: string,
  notificationType: string,
  subtype: string | null,
  originalTransactionId: string | null,
  transactionId: string | null,
  rawPayload: any,
): Promise<{ ok: boolean; isDuplicate: boolean }> {
  if (!supabaseAdmin) {
    return { ok: false, isDuplicate: false };
  }

  try {
    const { error } = await supabaseAdmin.schema("internal").from(
      "apple_notifications",
    ).insert({
      id: notificationUUID,
      notification_type: notificationType,
      subtype,
      original_transaction_id: originalTransactionId,
      transaction_id: transactionId,
      raw_payload: rawPayload,
    });

    if (error) {
      if (error.code === "23505") {
        // Seen before. Only skip it if an earlier delivery finished processing;
        // otherwise this is Apple retrying after a failure.
        const { data: seen, error: seenError } = await supabaseAdmin
          .schema("internal").from("apple_notifications")
          .select("processed_at")
          .eq("id", notificationUUID)
          .maybeSingle();
        if (seenError) {
          console.error(
            "[apple-notifications] processed_at lookup failed:",
            seenError.message,
          );
          return { ok: false, isDuplicate: false };
        }
        return { ok: true, isDuplicate: !!seen?.processed_at };
      }
      console.error(
        "[apple-notifications] markNotificationSeen failed:",
        error.message,
      );
      return { ok: false, isDuplicate: false };
    }

    return { ok: true, isDuplicate: false };
  } catch (e) {
    console.error("[apple-notifications] markNotificationSeen exception:", e);
    return { ok: false, isDuplicate: false };
  }
}

async function markNotificationProcessed(
  notificationUUID: string,
): Promise<void> {
  if (!supabaseAdmin) return;

  await supabaseAdmin
    .schema("internal").from("apple_notifications")
    .update({ processed_at: new Date().toISOString() })
    .eq("id", notificationUUID);
}

async function markNotificationError(
  notificationUUID: string,
  error: string,
): Promise<void> {
  if (!supabaseAdmin) return;

  const { data } = await supabaseAdmin
    .schema("internal").from("apple_notifications")
    .select("attempts")
    .eq("id", notificationUUID)
    .single();

  await supabaseAdmin
    .schema("internal").from("apple_notifications")
    .update({
      last_error: error,
      attempts: (data?.attempts ?? 0) + 1,
    })
    .eq("id", notificationUUID);
}

async function lookupUserIdByAppAccountToken(
  appAccountToken: string,
): Promise<string | null> {
  if (!supabaseAdmin) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .schema("internal").from("app_account_tokens")
    .select("user_id")
    .eq("token", appAccountToken)
    .maybeSingle();

  if (error) {
    console.error(
      "[apple-notifications] app_account_token lookup failed:",
      error.message,
    );
    return null;
  }

  return data?.user_id ?? null;
}

async function upsertSubscriptionFromNotification(
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | null,
  notificationType: NotificationType,
  subtype: NotificationSubtype,
): Promise<{ success: boolean; error?: string }> {
  if (!supabaseAdmin) {
    return { success: false, error: "Database not configured" };
  }

  const originalTransactionId = transactionInfo.originalTransactionId;
  const { status, cancelAtPeriodEnd } = determineStatusFromNotification(
    notificationType,
    subtype,
    transactionInfo,
    renewalInfo,
  );

  const internalProductId = mapAppleProductToInternal(
    transactionInfo.productId,
  );
  const appAccountToken = transactionInfo.appAccountToken ?? null;

  // First, try to find existing subscription by original_transaction_id
  const { data: existing } = await supabaseAdmin
    .from("subscriptions")
    .select("id, user_id, app_account_token")
    .eq("apple_original_transaction_id", originalTransactionId)
    .maybeSingle();

  const tokenUserId = appAccountToken
    ? await lookupUserIdByAppAccountToken(appAccountToken)
    : null;

  if (existing?.user_id && tokenUserId && tokenUserId !== existing.user_id) {
    console.warn(
      `[apple-notifications] appAccountToken owner mismatch: existing=${existing.user_id}, tokenUser=${tokenUserId}`,
    );
    return {
      success: false,
      error: "Apple transaction belongs to a different user",
    };
  }

  let userId: string | null = existing?.user_id ?? tokenUserId;

  // If still no user, store as orphan notification
  if (!userId) {
    console.warn(
      `[apple-notifications] Cannot find user for transaction ${originalTransactionId}`,
    );
    await storeOrphanNotification(
      transactionInfo,
      renewalInfo,
      notificationType,
      subtype,
      appAccountToken,
    );
    return { success: true }; // Don't fail - orphan is expected for some cases
  }

  const payload = {
    user_id: userId,
    provider: "apple",
    provider_subscription_id: originalTransactionId,
    status,
    product_id: internalProductId,
    current_period_start: transactionInfo.purchaseDate
      ? new Date(transactionInfo.purchaseDate).toISOString()
      : null,
    current_period_end: transactionInfo.expiresDate
      ? new Date(transactionInfo.expiresDate).toISOString()
      : null,
    apple_original_transaction_id: originalTransactionId,
    apple_last_transaction_id: transactionInfo.transactionId,
    apple_environment: transactionInfo.environment,
    app_account_token: appAccountToken,
    cancel_at_period_end: cancelAtPeriodEnd,
    canceled_at: cancelAtPeriodEnd ? new Date().toISOString() : null,
    raw_provider_payload: {
      lastNotification: notificationType,
      lastSubtype: subtype,
      transactionInfo,
      renewalInfo,
      processedAt: new Date().toISOString(),
    },
  };

  if (existing) {
    // Update existing subscription
    const { error } = await supabaseAdmin
      .from("subscriptions")
      .update(payload)
      .eq("id", existing.id);

    if (error) {
      console.error("[apple-notifications] Update failed:", error.message);
      return { success: false, error: error.message };
    }
  } else {
    // Insert new subscription
    const { error } = await supabaseAdmin
      .from("subscriptions")
      .insert(payload);

    if (error) {
      // Handle unique constraint violation
      if (error.code === "23505") {
        // subscriptions has one row per user. Only refresh a row that is
        // already Apple's. A Stripe or admin-granted row stays untouched.
        const { data: updatedRows, error: updateError } = await supabaseAdmin
          .from("subscriptions")
          .update(payload)
          .eq("user_id", userId)
          .eq("provider", "apple")
          .select("id");

        if (updateError) {
          console.error(
            "[apple-notifications] Insert/Update fallback failed:",
            updateError.message,
          );
          return { success: false, error: updateError.message };
        }

        if (!updatedRows?.length) {
          // Acknowledge so Apple does not retry a write that can never apply.
          console.warn(
            `[apple-notifications] User ${userId} has a non-Apple subscription row, not overwriting`,
          );
          return { success: true };
        }
      } else {
        console.error("[apple-notifications] Insert failed:", error.message);
        return { success: false, error: error.message };
      }
    }
  }

  console.log(
    `[apple-notifications] Updated subscription: user=${userId}, status=${status}`,
  );
  return { success: true };
}

async function storeOrphanNotification(
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | null,
  notificationType: NotificationType,
  subtype: NotificationSubtype,
  appAccountToken: string | null,
): Promise<void> {
  if (!supabaseAdmin) return;

  try {
    await supabaseAdmin.schema("internal").from("apple_orphan_notifications")
      .insert({
        id: `${transactionInfo.transactionId}_${Date.now()}`,
        notification_type: notificationType,
        subtype,
        original_transaction_id: transactionInfo.originalTransactionId,
        app_account_token: appAccountToken,
        raw_payload: {
          transactionInfo,
          renewalInfo,
          receivedAt: new Date().toISOString(),
        },
      });
  } catch (e) {
    console.error("[apple-notifications] Failed to store orphan:", e);
  }
}

// ---------- Request Handler ----------
async function handleRequest(req: Request): Promise<Response> {
  // Apple doesn't send OPTIONS, but handle it anyway
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    supabaseAdmin ??= createAdminClient<any>();
  } catch (error) {
    console.error("[apple-notifications] Supabase not configured:", error);
    return new Response("Service not configured", { status: 503 });
  }

  try {
    // Parse request body
    const body = await req.json();
    const signedPayload = body.signedPayload;

    if (!signedPayload) {
      console.error("[apple-notifications] Missing signedPayload");
      return new Response("Missing signedPayload", { status: 400 });
    }

    // Verify and decode the notification
    const verification = await verifyAppleNotification(signedPayload);
    if (!verification) {
      return new Response("Invalid notification", { status: 400 });
    }

    const { notification, verifier } = verification;
    const { notificationType, subtype, notificationUUID, data } = notification;

    console.log(
      `[apple-notifications] Received: type=${notificationType}, subtype=${subtype}, uuid=${notificationUUID}`,
    );

    // Parse transaction and renewal info from notification data
    let transactionInfo: AppleTransactionInfo | null = null;
    let renewalInfo: AppleRenewalInfo | null = null;

    if (data.signedTransactionInfo) {
      try {
        transactionInfo = await verifier.verifyAndDecodeTransaction(
          data.signedTransactionInfo,
        ) as AppleTransactionInfo;
      } catch (e) {
        console.error(
          "[apple-notifications] Failed to decode signedTransactionInfo:",
          e,
        );
      }
    }

    if (data.signedRenewalInfo) {
      try {
        renewalInfo = await verifier.verifyAndDecodeRenewalInfo(
          data.signedRenewalInfo,
        ) as AppleRenewalInfo;
      } catch (e) {
        console.error(
          "[apple-notifications] Failed to decode signedRenewalInfo:",
          e,
        );
      }
    }

    // Mark notification as seen (idempotency)
    const markResult = await markNotificationSeen(
      notificationUUID,
      notificationType,
      subtype,
      transactionInfo?.originalTransactionId ?? null,
      transactionInfo?.transactionId ?? null,
      { notification, signedPayload: "[redacted]" },
    );

    if (markResult.isDuplicate) {
      console.log(
        `[apple-notifications] Duplicate notification ignored: ${notificationUUID}`,
      );
      return new Response(JSON.stringify({ received: true, duplicate: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Handle TEST notifications
    if (notificationType === "TEST") {
      console.log("[apple-notifications] Test notification received");
      await markNotificationProcessed(notificationUUID);
      return new Response(JSON.stringify({ received: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Process the notification
    if (!transactionInfo) {
      console.warn(
        `[apple-notifications] No transaction info for ${notificationType}`,
      );
      await markNotificationError(notificationUUID, "No transaction info");
      return new Response(
        JSON.stringify({ received: true, warning: "No transaction info" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Sandbox and TestFlight purchases must not write production rows.
    // Acknowledge them so Apple does not retry.
    if (
      data.environment !== "Production" ||
      transactionInfo.environment !== "Production"
    ) {
      console.log(
        `[apple-notifications] Ignoring ${notificationType} from non-production environment=${transactionInfo.environment}`,
      );
      await markNotificationProcessed(notificationUUID);
      return new Response(
        JSON.stringify({ received: true, ignored: "non-production" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Only subscriptions are tracked.
    if (transactionInfo.type !== "Auto-Renewable Subscription") {
      console.log(
        `[apple-notifications] Ignoring ${notificationType} for non-subscription transaction type=${transactionInfo.type}, product=${transactionInfo.productId}`,
      );
      await markNotificationProcessed(notificationUUID);
      return new Response(
        JSON.stringify({ received: true, ignored: "not a subscription" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Update subscription
    const result = await upsertSubscriptionFromNotification(
      transactionInfo,
      renewalInfo,
      notificationType,
      subtype,
    );

    if (result.success) {
      await markNotificationProcessed(notificationUUID);
    } else {
      await markNotificationError(
        notificationUUID,
        result.error ?? "Unknown error",
      );
    }

    // Apple retries non-200 responses, which is what we want after a failure.
    return new Response(
      JSON.stringify({ received: true, processed: result.success }),
      {
        status: result.success ? 200 : 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    console.error(
      "[apple-notifications] Exception:",
      e instanceof Error ? e.message : e,
    );
    // Apple retries with backoff for a limited period, so a 500 is safe.
    return new Response(
      JSON.stringify({ received: true, error: "Processing error" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
}

export default { fetch: handleRequest };
