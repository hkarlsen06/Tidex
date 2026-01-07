// Supabase Edge Function: Apple IAP Purchase Verification
// - Verifies purchase/transaction with Apple App Store Server API
// - Upserts subscription state into unified subscriptions table
// - Returns entitlement status
// - Requires authenticated Supabase user
// - Uses StoreKit 2 / App Store Server API (not legacy verifyReceipt)
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";

// ---------- Environment ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Apple App Store Server API credentials
const APPLE_APP_BUNDLE_ID = Deno.env.get("APPLE_APP_BUNDLE_ID") ?? "no.tidex.app";
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID") ?? "";
const APPLE_ISSUER_ID = Deno.env.get("APPLE_ISSUER_ID") ?? "";
const APPLE_PRIVATE_KEY_RAW = Deno.env.get("APPLE_PRIVATE_KEY");
const APPLE_PRIVATE_KEY = APPLE_PRIVATE_KEY_RAW ?? "";
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID") ?? "48ZSLD4RMP";

// Debug: Log environment state at startup
console.log("[apple-verify] Environment check at startup:");
console.log(`[apple-verify] APPLE_KEY_ID defined: ${APPLE_KEY_ID !== ""}`);
console.log(`[apple-verify] APPLE_ISSUER_ID defined: ${APPLE_ISSUER_ID !== ""}`);
console.log(`[apple-verify] APPLE_PRIVATE_KEY_RAW is undefined: ${APPLE_PRIVATE_KEY_RAW === undefined}`);
console.log(`[apple-verify] APPLE_PRIVATE_KEY_RAW is null: ${APPLE_PRIVATE_KEY_RAW === null}`);
console.log(`[apple-verify] APPLE_PRIVATE_KEY_RAW is empty string: ${APPLE_PRIVATE_KEY_RAW === ""}`);
console.log(`[apple-verify] APPLE_PRIVATE_KEY length: ${APPLE_PRIVATE_KEY.length}`);

// Apple App Store Server API endpoints
const APPLE_PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
const APPLE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";

// ---------- Apple Product ID Mapping ----------
// Maps Apple product IDs to internal product IDs
// Native users only have access to Pro monthly subscription
const APPLE_PRODUCT_TO_INTERNAL: Record<string, string> = {
  "no.tidex.pro": "pro_monthly",
};

// Allowed Apple product IDs (for validation)
const ALLOWED_APPLE_PRODUCTS = Object.keys(APPLE_PRODUCT_TO_INTERNAL);

function mapAppleProductToInternal(appleProductId: string): string {
  return APPLE_PRODUCT_TO_INTERNAL[appleProductId] ?? appleProductId;
}

// ---------- Supabase Client ----------
const supabaseAdmin = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false }
    })
  : null;

// ---------- Apple JWT Generation ----------
async function generateAppleJWT(): Promise<string> {
  console.log("[apple-verify] generateAppleJWT called");
  console.log(`[apple-verify] APPLE_KEY_ID: ${APPLE_KEY_ID}`);
  console.log(`[apple-verify] APPLE_ISSUER_ID: ${APPLE_ISSUER_ID}`);
  console.log(`[apple-verify] APPLE_PRIVATE_KEY length: ${APPLE_PRIVATE_KEY.length}`);

  if (!APPLE_KEY_ID || !APPLE_ISSUER_ID || !APPLE_PRIVATE_KEY) {
    throw new Error("Apple credentials not configured");
  }

  try {
    // Parse the private key (p8 format)
    // Handle escaped newlines from env vars - they come as literal \n (backslash + n)
    let keyPem = APPLE_PRIVATE_KEY;

    // Debug: Check what we're dealing with
    console.log(`[apple-verify] Raw key has literal backslash-n: ${keyPem.includes('\\n')}`);
    console.log(`[apple-verify] Raw key has actual newlines: ${keyPem.includes('\n')}`);

    // Replace literal \n (backslash followed by n) with actual newlines
    // In a string, we need to escape the backslash, so \\n matches literal \n
    keyPem = keyPem.replace(/\\n/g, '\n');

    console.log(`[apple-verify] After replacement, key has newlines: ${keyPem.includes('\n')}`);
    console.log(`[apple-verify] Key line count: ${keyPem.split('\n').length}`);
    console.log(`[apple-verify] Key starts with: ${keyPem.substring(0, 30)}`);
    console.log(`[apple-verify] Key ends with: ${keyPem.substring(keyPem.length - 30)}`);

    const privateKey = await jose.importPKCS8(keyPem, "ES256");
    console.log("[apple-verify] Private key imported successfully");

    // App Store Server API requires 'bid' (bundle ID) and 'nonce' (unique UUID) in payload
    const jwt = await new jose.SignJWT({
        bid: APPLE_APP_BUNDLE_ID,
        nonce: crypto.randomUUID()
      })
      .setProtectedHeader({
        alg: "ES256",
        kid: APPLE_KEY_ID,
        typ: "JWT"
      })
      .setIssuer(APPLE_ISSUER_ID)
      .setAudience("appstoreconnect-v1")
      .setIssuedAt()
      .setExpirationTime("20m")
      .sign(privateKey);

    console.log(`[apple-verify] JWT bundle ID: ${APPLE_APP_BUNDLE_ID}`);

    console.log("[apple-verify] JWT generated successfully");
    return jwt;
  } catch (e) {
    console.error("[apple-verify] JWT generation failed:", e instanceof Error ? e.message : e);
    throw e;
  }
}

// ---------- Apple Server API Calls ----------
interface AppleTransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number; // milliseconds
  expiresDate?: number; // milliseconds, for subscriptions
  revocationDate?: number; // milliseconds, if refunded
  revocationReason?: number;
  environment: "Production" | "Sandbox";
  appAccountToken?: string; // UUID if set during purchase
  offerType?: number;
  type: "Auto-Renewable Subscription" | "Non-Consumable" | "Consumable" | "Non-Renewing Subscription";
}

interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId: string;
  autoRenewStatus: number; // 1 = on, 0 = off
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

async function verifyTransactionWithApple(
  transactionId: string,
  environment: "Production" | "Sandbox" = "Sandbox" // Default to Sandbox for testing
): Promise<{ transactionInfo: AppleTransactionInfo; renewalInfo?: AppleRenewalInfo } | null> {
  const jwt = await generateAppleJWT();
  const baseUrl = environment === "Sandbox" ? APPLE_SANDBOX_URL : APPLE_PRODUCTION_URL;

  console.log(`[apple-verify] Calling Apple API: ${baseUrl}/inApps/v1/transactions/${transactionId}`);

  // Get transaction info
  const response = await fetch(
    `${baseUrl}/inApps/v1/transactions/${transactionId}`,
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    }
  );

  if (!response.ok) {
    // Log full error details
    let errorBody = "";
    try {
      errorBody = await response.text();
    } catch {
      errorBody = "(could not read error body)";
    }
    console.error(`[apple-verify] Apple API error: ${response.status} - ${errorBody}`);

    // If sandbox fails with 404, try production (for restored purchases from production)
    if (response.status === 404 && environment === "Sandbox") {
      console.log("[apple-verify] Transaction not found in Sandbox, trying Production");
      return verifyTransactionWithApple(transactionId, "Production");
    }

    // If 401, log additional debug info
    if (response.status === 401) {
      console.error("[apple-verify] 401 Unauthorized - possible causes:");
      console.error("  - API key not yet propagated (can take up to 24 hours for new keys)");
      console.error("  - Key ID mismatch");
      console.error("  - Issuer ID mismatch");
      console.error("  - Private key doesn't match the Key ID");
    }

    return null;
  }

  const data = await response.json();
  const signedTransactionInfo = data.signedTransactionInfo;

  if (!signedTransactionInfo) {
    console.error("[apple-verify] No signed transaction info in response");
    return null;
  }

  // Decode the JWS (without verification for now - Apple's response is trusted)
  const transactionInfo = decodeAppleJWS(signedTransactionInfo) as AppleTransactionInfo;

  // For subscriptions, also get renewal info
  let renewalInfo: AppleRenewalInfo | undefined;
  if (transactionInfo.type === "Auto-Renewable Subscription") {
    const subResponse = await fetch(
      `${baseUrl}/inApps/v1/subscriptions/${transactionInfo.originalTransactionId}`,
      {
        headers: {
          Authorization: `Bearer ${jwt}`,
        },
      }
    );

    if (subResponse.ok) {
      const subData = await subResponse.json();
      const lastTransaction = subData.data?.[0]?.lastTransactions?.[0];
      if (lastTransaction?.signedRenewalInfo) {
        renewalInfo = decodeAppleJWS(lastTransaction.signedRenewalInfo) as AppleRenewalInfo;
      }
    }
  }

  return { transactionInfo, renewalInfo };
}

function decodeAppleJWS(jws: string): Record<string, any> {
  // JWS format: header.payload.signature
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid JWS format");
  }
  const payload = parts[1];
  const decoded = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
  return JSON.parse(decoded);
}

// ---------- Subscription Status Determination ----------
function determineSubscriptionStatus(
  transactionInfo: AppleTransactionInfo,
  renewalInfo?: AppleRenewalInfo
): { status: string; isEntitled: boolean } {
  const now = Date.now();

  // Check for refund/revocation
  if (transactionInfo.revocationDate) {
    return { status: "refunded", isEntitled: false };
  }

  // Check expiration
  if (transactionInfo.expiresDate) {
    if (transactionInfo.expiresDate > now) {
      // Still within subscription period
      // Check for grace period
      if (renewalInfo?.gracePeriodExpiresDate && renewalInfo.gracePeriodExpiresDate > now) {
        return { status: "grace", isEntitled: true };
      }
      // Check for billing retry
      if (renewalInfo?.isInBillingRetryPeriod) {
        return { status: "past_due", isEntitled: true };
      }
      return { status: "active", isEntitled: true };
    } else {
      // Subscription has expired
      if (renewalInfo?.gracePeriodExpiresDate && renewalInfo.gracePeriodExpiresDate > now) {
        return { status: "grace", isEntitled: true };
      }
      return { status: "expired", isEntitled: false };
    }
  }

  // For non-subscription purchases (one-time)
  return { status: "active", isEntitled: true };
}

// ---------- Database Operations ----------
async function upsertAppleSubscription(
  userId: string,
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | undefined,
  clientAppAccountToken: string | null
): Promise<{ success: boolean; error?: string }> {
  if (!supabaseAdmin) {
    return { success: false, error: "Database not configured" };
  }

  const { status, isEntitled } = determineSubscriptionStatus(transactionInfo, renewalInfo);
  const internalProductId = mapAppleProductToInternal(transactionInfo.productId);

  // Prefer Apple-provided appAccountToken, fall back to client-provided
  const appAccountToken = transactionInfo.appAccountToken ?? clientAppAccountToken ?? null;

  const payload = {
    user_id: userId,
    provider: "apple",
    provider_subscription_id: transactionInfo.originalTransactionId,
    status,
    product_id: internalProductId,
    current_period_start: transactionInfo.purchaseDate
      ? new Date(transactionInfo.purchaseDate).toISOString()
      : null,
    current_period_end: transactionInfo.expiresDate
      ? new Date(transactionInfo.expiresDate).toISOString()
      : null,
    // Apple-specific fields
    apple_original_transaction_id: transactionInfo.originalTransactionId,
    apple_last_transaction_id: transactionInfo.transactionId,
    apple_environment: transactionInfo.environment,
    app_account_token: appAccountToken ? appAccountToken : null,
    // Cancellation handling
    cancel_at_period_end: renewalInfo?.autoRenewStatus === 0,
    // Store raw payload for debugging
    raw_provider_payload: {
      transactionInfo,
      renewalInfo,
      verifiedAt: new Date().toISOString(),
    },
  };

  // First try to find existing row by apple_original_transaction_id
  const { data: existing } = await supabaseAdmin
    .from("subscriptions")
    .select("id, user_id")
    .eq("apple_original_transaction_id", transactionInfo.originalTransactionId)
    .maybeSingle();

  if (existing) {
    // Update existing subscription
    // Security: Verify user_id matches (unless this is first verification)
    if (existing.user_id && existing.user_id !== userId) {
      console.error(`[apple-verify] User ID mismatch: ${existing.user_id} vs ${userId}`);
      return { success: false, error: "Subscription belongs to different user" };
    }

    const { error } = await supabaseAdmin
      .from("subscriptions")
      .update(payload)
      .eq("id", existing.id);

    if (error) {
      console.error("[apple-verify] Update failed:", error.message);
      return { success: false, error: error.message };
    }
  } else {
    // Check if user already has a subscription row (from Stripe or previous Apple)
    const { data: userSub } = await supabaseAdmin
      .from("subscriptions")
      .select("id, provider")
      .eq("user_id", userId)
      .maybeSingle();

    if (userSub) {
      // User has existing subscription - update it with Apple info if provider is apple
      // or create a new row if it's from a different provider (support multiple subs)
      if (userSub.provider === "apple") {
        const { error } = await supabaseAdmin
          .from("subscriptions")
          .update(payload)
          .eq("id", userSub.id);

        if (error) {
          console.error("[apple-verify] Update existing Apple sub failed:", error.message);
          return { success: false, error: error.message };
        }
      } else {
        // User has Stripe sub, create new Apple sub
        // Remove user_id conflict constraint by using apple_original_transaction_id as identifier
        const { error } = await supabaseAdmin
          .from("subscriptions")
          .insert(payload);

        if (error) {
          // If unique constraint on user_id fails, update instead
          if (error.code === "23505") {
            const { error: updateError } = await supabaseAdmin
              .from("subscriptions")
              .update(payload)
              .eq("user_id", userId)
              .eq("provider", "apple");

            if (updateError) {
              console.error("[apple-verify] Insert/Update fallback failed:", updateError.message);
              return { success: false, error: updateError.message };
            }
          } else {
            console.error("[apple-verify] Insert failed:", error.message);
            return { success: false, error: error.message };
          }
        }
      }
    } else {
      // No existing subscription - insert new
      const { error } = await supabaseAdmin
        .from("subscriptions")
        .insert(payload);

      if (error) {
        console.error("[apple-verify] Insert failed:", error.message);
        return { success: false, error: error.message };
      }
    }
  }

  return { success: true };
}

// ---------- Request Handlers ----------
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    if (!supabaseAdmin) {
      return json({ error: "Service not configured" }, 503);
    }

    // Verify Supabase auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return json({ error: "Invalid or expired token" }, 401);
    }

    // Parse request body
    const body = await req.json();
    const {
      transactionId,
      originalTransactionId,
      productId,
      appAccountToken,
      environment = "Sandbox" // Default to Sandbox for TestFlight testing
    } = body;

    // Validate required fields
    if (!transactionId && !originalTransactionId) {
      return json({ error: "transactionId or originalTransactionId required" }, 400);
    }

    if (productId && !ALLOWED_APPLE_PRODUCTS.includes(productId)) {
      return json({ error: "Invalid product ID" }, 400);
    }

    // Use transactionId or originalTransactionId for verification
    const txnToVerify = transactionId ?? originalTransactionId;

    // Verify with Apple
    console.log(`[apple-verify] Verifying transaction ${txnToVerify} for user ${user.id}`);
    const result = await verifyTransactionWithApple(txnToVerify, environment);

    if (!result) {
      return json({ error: "Transaction verification failed" }, 400);
    }

    const { transactionInfo, renewalInfo } = result;

    // Validate bundle ID
    if (transactionInfo.bundleId !== APPLE_APP_BUNDLE_ID) {
      console.error(`[apple-verify] Bundle ID mismatch: ${transactionInfo.bundleId}`);
      return json({ error: "Invalid bundle ID" }, 400);
    }

    // Validate product ID if provided
    if (productId && transactionInfo.productId !== productId) {
      console.warn(`[apple-verify] Product ID mismatch: expected ${productId}, got ${transactionInfo.productId}`);
    }

    // Validate product is allowed
    if (!ALLOWED_APPLE_PRODUCTS.includes(transactionInfo.productId)) {
      console.error(`[apple-verify] Unknown product ID: ${transactionInfo.productId}`);
      return json({ error: "Unknown product ID" }, 400);
    }

    // Upsert subscription
    const upsertResult = await upsertAppleSubscription(
      user.id,
      transactionInfo,
      renewalInfo,
      appAccountToken ?? null
    );

    if (!upsertResult.success) {
      return json({ error: upsertResult.error ?? "Failed to save subscription" }, 500);
    }

    // Determine entitlement status
    const { status, isEntitled } = determineSubscriptionStatus(transactionInfo, renewalInfo);

    console.log(`[apple-verify] Success: user=${user.id}, status=${status}, entitled=${isEntitled}`);

    return json({
      success: true,
      entitled: isEntitled,
      subscription: {
        status,
        productId: transactionInfo.productId,
        internalProductId: mapAppleProductToInternal(transactionInfo.productId),
        expiresAt: transactionInfo.expiresDate
          ? new Date(transactionInfo.expiresDate).toISOString()
          : null,
        environment: transactionInfo.environment,
        autoRenewEnabled: renewalInfo?.autoRenewStatus === 1,
      },
    });
  } catch (e) {
    console.error("[apple-verify] Exception:", e instanceof Error ? e.message : e);
    console.error("[apple-verify] Stack:", e instanceof Error ? e.stack : "no stack");
    return json({ error: "Internal server error" }, 500);
  }
});

// ---------- Response Helpers ----------
function json(obj: Record<string, any>, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
