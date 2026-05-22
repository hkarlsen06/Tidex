// Supabase Edge Function: Apple IAP Purchase Verification
// - Verifies purchase/transaction with Apple App Store Server API
// - Upserts subscription state into unified subscriptions table
// - Returns entitlement status
// - Requires authenticated Supabase user
// - Uses StoreKit 2 / App Store Server API (not legacy verifyReceipt)
import { withSupabase } from "npm:@supabase/server@1.0.0";
import { corsHeaders } from "../_shared/cors.ts";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";

// ---------- Environment ----------
// Apple App Store Server API credentials
const APPLE_APP_BUNDLE_ID =
  Deno.env.get("APPLE_APP_BUNDLE_ID") ?? "no.tidex.app";
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID") ?? "";
const APPLE_ISSUER_ID = Deno.env.get("APPLE_ISSUER_ID") ?? "";
const APPLE_PRIVATE_KEY_RAW = Deno.env.get("APPLE_PRIVATE_KEY");
const APPLE_PRIVATE_KEY = APPLE_PRIVATE_KEY_RAW ?? "";
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID") ?? "48ZSLD4RMP";

// Debug: Log environment state at startup
console.log("[apple-verify] Environment check at startup:");
console.log(`[apple-verify] APPLE_KEY_ID defined: ${APPLE_KEY_ID !== ""}`);
console.log(
  `[apple-verify] APPLE_ISSUER_ID defined: ${APPLE_ISSUER_ID !== ""}`,
);
console.log(
  `[apple-verify] APPLE_PRIVATE_KEY_RAW is undefined: ${
    APPLE_PRIVATE_KEY_RAW === undefined
  }`,
);
console.log(
  `[apple-verify] APPLE_PRIVATE_KEY_RAW is null: ${
    APPLE_PRIVATE_KEY_RAW === null
  }`,
);
console.log(
  `[apple-verify] APPLE_PRIVATE_KEY_RAW is empty string: ${
    APPLE_PRIVATE_KEY_RAW === ""
  }`,
);
console.log(
  `[apple-verify] APPLE_PRIVATE_KEY length: ${APPLE_PRIVATE_KEY.length}`,
);

// Apple App Store Server API endpoints
const APPLE_PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
const APPLE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";
const EXTERNAL_FETCH_TIMEOUT_MS = 15_000;

// ---------- Apple Product ID Mapping ----------
// Maps Apple product IDs to internal product IDs
const APPLE_PRODUCT_TO_INTERNAL: Record<string, string> = {
  "no.tidex.pro": "pro_monthly",
  "no.tidex.pro.year": "pro_yearly",
  "no.tidex.max": "max_monthly",
  "no.tidex.max.year": "max_yearly",
};

// ---------- Consumable Product Mapping ----------
// Maps consumable Apple product IDs to the number of bonus credits granted
const CONSUMABLE_CREDITS: Record<string, number> = {
  "no.tidex.wagey.20": 20,
};

// Allowed Apple product IDs (for validation)
const ALLOWED_APPLE_PRODUCTS = [
  ...Object.keys(APPLE_PRODUCT_TO_INTERNAL),
  ...Object.keys(CONSUMABLE_CREDITS),
];

function mapAppleProductToInternal(appleProductId: string): string {
  return APPLE_PRODUCT_TO_INTERNAL[appleProductId] ?? appleProductId;
}

// ---------- Supabase Client ----------
let supabaseAdmin: any = null;

// ---------- Apple JWT Generation ----------
async function generateAppleJWT(): Promise<string> {
  console.log("[apple-verify] generateAppleJWT called");
  console.log(`[apple-verify] APPLE_KEY_ID: ${APPLE_KEY_ID}`);
  console.log(`[apple-verify] APPLE_ISSUER_ID: ${APPLE_ISSUER_ID}`);
  console.log(
    `[apple-verify] APPLE_PRIVATE_KEY length: ${APPLE_PRIVATE_KEY.length}`,
  );

  if (!APPLE_KEY_ID || !APPLE_ISSUER_ID || !APPLE_PRIVATE_KEY) {
    throw new Error("Apple credentials not configured");
  }

  try {
    // Parse the private key (p8 format)
    // Handle escaped newlines from env vars - they come as literal \n (backslash + n)
    let keyPem = APPLE_PRIVATE_KEY;

    // Debug: Check what we're dealing with
    console.log(
      `[apple-verify] Raw key has literal backslash-n: ${keyPem.includes(
        "\\n",
      )}`,
    );
    console.log(
      `[apple-verify] Raw key has actual newlines: ${keyPem.includes("\n")}`,
    );

    // Replace literal \n (backslash followed by n) with actual newlines
    // In a string, we need to escape the backslash, so \\n matches literal \n
    keyPem = keyPem.replace(/\\n/g, "\n");

    console.log(
      `[apple-verify] After replacement, key has newlines: ${keyPem.includes(
        "\n",
      )}`,
    );
    console.log(`[apple-verify] Key line count: ${keyPem.split("\n").length}`);
    console.log(`[apple-verify] Key starts with: ${keyPem.substring(0, 30)}`);
    console.log(
      `[apple-verify] Key ends with: ${keyPem.substring(keyPem.length - 30)}`,
    );

    const privateKey = await jose.importPKCS8(keyPem, "ES256");
    console.log("[apple-verify] Private key imported successfully");

    // App Store Server API requires 'bid' (bundle ID) and 'nonce' (unique UUID) in payload
    const jwt = await new jose.SignJWT({
      bid: APPLE_APP_BUNDLE_ID,
      nonce: crypto.randomUUID(),
    })
      .setProtectedHeader({
        alg: "ES256",
        kid: APPLE_KEY_ID,
        typ: "JWT",
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
    console.error(
      "[apple-verify] JWT generation failed:",
      e instanceof Error ? e.message : e,
    );
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
  type:
    | "Auto-Renewable Subscription"
    | "Non-Consumable"
    | "Consumable"
    | "Non-Renewing Subscription";
}

interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId: string;
  autoRenewStatus: number; // 1 = on, 0 = off
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

function normalizeAppleEnvironment(value: unknown): "Production" | "Sandbox" {
  return value === "Production" ? "Production" : "Sandbox";
}

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

async function verifyTransactionWithApple(
  transactionId: string,
  environment: "Production" | "Sandbox" = "Sandbox", // Default to Sandbox for testing
): Promise<{
  transactionInfo: AppleTransactionInfo;
  renewalInfo?: AppleRenewalInfo;
} | null> {
  const jwt = await generateAppleJWT();
  const baseUrl =
    environment === "Sandbox" ? APPLE_SANDBOX_URL : APPLE_PRODUCTION_URL;

  console.log(
    `[apple-verify] Calling Apple API: ${baseUrl}/inApps/v1/transactions/${transactionId}`,
  );

  // Get transaction info
  const response = await fetchWithTimeout(
    `${baseUrl}/inApps/v1/transactions/${transactionId}`,
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    },
  );

  if (!response.ok) {
    // Log full error details
    let errorBody = "";
    try {
      errorBody = await response.text();
    } catch {
      errorBody = "(could not read error body)";
    }
    console.error(
      `[apple-verify] Apple API error: ${response.status} - ${errorBody}`,
    );

    // If sandbox fails with 404, try production (for restored purchases from production)
    if (response.status === 404 && environment === "Sandbox") {
      console.log(
        "[apple-verify] Transaction not found in Sandbox, trying Production",
      );
      return verifyTransactionWithApple(transactionId, "Production");
    }

    // If 401, log additional debug info
    if (response.status === 401) {
      console.error("[apple-verify] 401 Unauthorized - possible causes:");
      console.error(
        "  - API key not yet propagated (can take up to 24 hours for new keys)",
      );
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
  const transactionInfo = decodeAppleJWS(
    signedTransactionInfo,
  ) as AppleTransactionInfo;

  // For subscriptions, also get renewal info
  let renewalInfo: AppleRenewalInfo | undefined;
  if (transactionInfo.type === "Auto-Renewable Subscription") {
    const subResponse = await fetchWithTimeout(
      `${baseUrl}/inApps/v1/subscriptions/${transactionInfo.originalTransactionId}`,
      {
        headers: {
          Authorization: `Bearer ${jwt}`,
        },
      },
    );

    if (subResponse.ok) {
      const subData = await subResponse.json();
      const lastTransaction = subData.data?.[0]?.lastTransactions?.[0];
      if (lastTransaction?.signedRenewalInfo) {
        renewalInfo = decodeAppleJWS(
          lastTransaction.signedRenewalInfo,
        ) as AppleRenewalInfo;
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

function assertUploadedJWSMatchesApple(
  uploadedTransactionInfo: Partial<AppleTransactionInfo> | null,
  transactionInfo: AppleTransactionInfo,
): { ok: boolean; error?: string } {
  if (!uploadedTransactionInfo) {
    return { ok: true };
  }

  const fieldsToCompare: Array<keyof AppleTransactionInfo> = [
    "transactionId",
    "originalTransactionId",
    "bundleId",
    "productId",
    "environment",
  ];

  for (const field of fieldsToCompare) {
    const uploadedValue = uploadedTransactionInfo[field];
    if (
      uploadedValue !== undefined &&
      uploadedValue !== transactionInfo[field]
    ) {
      console.error(
        `[apple-verify] Uploaded JWS mismatch for ${field}: uploaded=${uploadedValue}, apple=${
          transactionInfo[field]
        }`,
      );
      return {
        ok: false,
        error: "Uploaded transaction does not match Apple verification",
      };
    }
  }

  return { ok: true };
}

async function lookupUserIdByAppAccountToken(
  appAccountToken: string,
): Promise<string | null> {
  if (!supabaseAdmin) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .schema("internal")
    .from("app_account_tokens")
    .select("user_id")
    .eq("token", appAccountToken)
    .maybeSingle();

  if (error) {
    console.error(
      "[apple-verify] app_account_token lookup failed:",
      error.message,
    );
    return null;
  }

  return data?.user_id ?? null;
}

async function lookupExistingOwnerForLegacyTransaction(
  transactionInfo: AppleTransactionInfo,
): Promise<string | null> {
  if (!supabaseAdmin) {
    return null;
  }

  if (transactionInfo.type === "Consumable") {
    const { data, error } = await supabaseAdmin
      .from("consumable_transactions")
      .select("user_id")
      .eq("apple_transaction_id", transactionInfo.transactionId)
      .maybeSingle();

    if (error) {
      console.error(
        "[apple-verify] Legacy consumable lookup failed:",
        error.message,
      );
      return null;
    }

    return data?.user_id ?? null;
  }

  const { data: providerData, error: providerError } = await supabaseAdmin
    .from("subscriptions")
    .select("user_id")
    .eq("provider", "apple")
    .eq("provider_subscription_id", transactionInfo.originalTransactionId)
    .maybeSingle();

  if (providerError) {
    console.error(
      "[apple-verify] Legacy subscription provider lookup failed:",
      providerError.message,
    );
    return null;
  }

  if (providerData?.user_id) {
    return providerData.user_id;
  }

  const { data: appleTxnData, error: appleTxnError } = await supabaseAdmin
    .from("subscriptions")
    .select("user_id")
    .eq("provider", "apple")
    .eq("apple_original_transaction_id", transactionInfo.originalTransactionId)
    .maybeSingle();

  if (appleTxnError) {
    console.error(
      "[apple-verify] Legacy subscription original transaction lookup failed:",
      appleTxnError.message,
    );
    return null;
  }

  return appleTxnData?.user_id ?? null;
}

async function assertTransactionBelongsToUser(
  userId: string,
  transactionInfo: AppleTransactionInfo,
): Promise<{ ok: boolean; error?: string; status?: number }> {
  const appAccountToken = transactionInfo.appAccountToken ?? null;
  if (!appAccountToken) {
    const existingOwner =
      await lookupExistingOwnerForLegacyTransaction(transactionInfo);
    if (existingOwner === userId) {
      return { ok: true };
    }

    if (existingOwner && existingOwner !== userId) {
      console.warn(
        `[apple-verify] Legacy transaction owner mismatch: existing=${existingOwner}, authUser=${userId}`,
      );
      return {
        ok: false,
        error: "Apple transaction belongs to a different user",
        status: 403,
      };
    }

    return {
      ok: false,
      error: "Apple transaction is missing appAccountToken",
      status: 403,
    };
  }

  const tokenUserId = await lookupUserIdByAppAccountToken(appAccountToken);
  if (!tokenUserId) {
    return {
      ok: false,
      error: "Apple appAccountToken is not registered",
      status: 403,
    };
  }

  if (tokenUserId !== userId) {
    console.warn(
      `[apple-verify] appAccountToken owner mismatch: tokenUser=${tokenUserId}, authUser=${userId}`,
    );
    return {
      ok: false,
      error: "Apple transaction belongs to a different user",
      status: 403,
    };
  }

  return { ok: true };
}

// ---------- Subscription Status Determination ----------
function determineSubscriptionStatus(
  transactionInfo: AppleTransactionInfo,
  renewalInfo?: AppleRenewalInfo,
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
      if (
        renewalInfo?.gracePeriodExpiresDate &&
        renewalInfo.gracePeriodExpiresDate > now
      ) {
        return { status: "grace", isEntitled: true };
      }
      // Check for billing retry
      if (renewalInfo?.isInBillingRetryPeriod) {
        return { status: "past_due", isEntitled: true };
      }
      return { status: "active", isEntitled: true };
    } else {
      // Subscription has expired
      if (
        renewalInfo?.gracePeriodExpiresDate &&
        renewalInfo.gracePeriodExpiresDate > now
      ) {
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
  priceDisplay: string | null,
): Promise<{ success: boolean; error?: string; status?: number }> {
  if (!supabaseAdmin) {
    return { success: false, error: "Database not configured" };
  }

  const { status, isEntitled } = determineSubscriptionStatus(
    transactionInfo,
    renewalInfo,
  );
  const internalProductId = mapAppleProductToInternal(
    transactionInfo.productId,
  );

  // Only Apple's signed appAccountToken is trusted. Never fall back to a client-supplied token.
  const appAccountToken = transactionInfo.appAccountToken ?? null;

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
    // Store localized price from App Store (only if provided)
    ...(priceDisplay ? { price_display: priceDisplay } : {}),
  };

  // First try to find existing row by unique constraint columns (provider + provider_subscription_id)
  // This matches the idx_subscriptions_unique_provider_sub constraint
  const { data: existingByProviderSub } = await supabaseAdmin
    .from("subscriptions")
    .select("id, user_id, price_display")
    .eq("provider", "apple")
    .eq("provider_subscription_id", transactionInfo.originalTransactionId)
    .maybeSingle();

  if (existingByProviderSub) {
    // Found by unique constraint - update it
    if (
      existingByProviderSub.user_id &&
      existingByProviderSub.user_id !== userId
    ) {
      console.warn(
        `[apple-verify] Subscription ownership mismatch by provider_subscription_id: existing=${existingByProviderSub.user_id}, auth=${userId}`,
      );
      return {
        success: false,
        error: "Subscription belongs to a different user",
        status: 403,
      };
    }

    // Don't overwrite price_display if it already exists (preserve original purchase price)
    const updatePayload = { ...payload };
    if (
      existingByProviderSub.price_display &&
      "price_display" in updatePayload
    ) {
      delete (updatePayload as any).price_display;
    }

    const { error } = await supabaseAdmin
      .from("subscriptions")
      .update(updatePayload)
      .eq("id", existingByProviderSub.id);

    if (error) {
      console.error(
        "[apple-verify] Update by provider_sub failed:",
        error.message,
      );
      return { success: false, error: error.message };
    }

    console.log(
      `[apple-verify] Updated existing subscription by provider_subscription_id`,
    );
    return { success: true };
  }

  // Also check by apple_original_transaction_id for backwards compatibility
  const { data: existingByAppleTxn } = await supabaseAdmin
    .from("subscriptions")
    .select("id, user_id, price_display")
    .eq("apple_original_transaction_id", transactionInfo.originalTransactionId)
    .maybeSingle();

  if (existingByAppleTxn) {
    // Found by apple_original_transaction_id - update it
    if (existingByAppleTxn.user_id && existingByAppleTxn.user_id !== userId) {
      console.warn(
        `[apple-verify] Subscription ownership mismatch by apple_original_transaction_id: existing=${existingByAppleTxn.user_id}, auth=${userId}`,
      );
      return {
        success: false,
        error: "Subscription belongs to a different user",
        status: 403,
      };
    }

    const updatePayload = { ...payload };
    if (existingByAppleTxn.price_display && "price_display" in updatePayload) {
      delete (updatePayload as any).price_display;
    }

    const { error } = await supabaseAdmin
      .from("subscriptions")
      .update(updatePayload)
      .eq("id", existingByAppleTxn.id);

    if (error) {
      console.error(
        "[apple-verify] Update by apple_original_transaction_id failed:",
        error.message,
      );
      return { success: false, error: error.message };
    }

    console.log(
      `[apple-verify] Updated existing subscription by apple_original_transaction_id`,
    );
    return { success: true };
  }

  // Check if user already has a subscription row (from Stripe or previous Apple)
  const { data: userSub } = await supabaseAdmin
    .from("subscriptions")
    .select("id, provider, price_display")
    .eq("user_id", userId)
    .maybeSingle();

  if (userSub) {
    // User has existing subscription - update it with Apple info
    const userSubUpdatePayload = { ...payload };
    if (userSub.price_display && "price_display" in userSubUpdatePayload) {
      delete (userSubUpdatePayload as any).price_display;
    }

    const { error } = await supabaseAdmin
      .from("subscriptions")
      .update(userSubUpdatePayload)
      .eq("id", userSub.id);

    if (error) {
      console.error(
        "[apple-verify] Update existing user sub failed:",
        error.message,
      );
      return { success: false, error: error.message };
    }

    console.log(
      `[apple-verify] Updated existing user subscription (was ${userSub.provider})`,
    );
    return { success: true };
  }

  // No existing subscription - insert new
  const { error } = await supabaseAdmin.from("subscriptions").insert(payload);

  if (error) {
    console.error("[apple-verify] Insert failed:", error.message);
    return { success: false, error: error.message };
  }

  console.log(`[apple-verify] Inserted new subscription`);
  return { success: true };
}

// ---------- Consumable Credit (Idempotent) ----------
async function creditConsumable(
  userId: string,
  transactionInfo: AppleTransactionInfo,
  credits: number,
): Promise<{ success: boolean; alreadyCredited: boolean; error?: string }> {
  if (!supabaseAdmin) {
    return {
      success: false,
      alreadyCredited: false,
      error: "Database not configured",
    };
  }

  // Insert into consumable_transactions (unique on apple_transaction_id)
  const { error: insertError } = await supabaseAdmin
    .from("consumable_transactions")
    .insert({
      user_id: userId,
      apple_transaction_id: transactionInfo.transactionId,
      apple_original_transaction_id: transactionInfo.originalTransactionId,
      apple_product_id: transactionInfo.productId,
      credits_granted: credits,
      environment: transactionInfo.environment,
    });

  if (insertError) {
    // Postgres unique violation = already credited
    if (insertError.code === "23505") {
      console.log(
        `[apple-verify] Consumable already credited: txn ${transactionInfo.transactionId}`,
      );
      return { success: true, alreadyCredited: true };
    }
    console.error(
      "[apple-verify] Consumable insert failed:",
      insertError.message,
    );
    return {
      success: false,
      alreadyCredited: false,
      error: insertError.message,
    };
  }

  // Atomically increment bonus on profiles.wagey_invocations
  const { error: rpcError } = await supabaseAdmin.rpc("increment_wagey_bonus", {
    p_user_id: userId,
    p_credits: credits,
  });

  if (rpcError) {
    console.error("[apple-verify] Bonus increment failed:", rpcError.message);
    return { success: false, alreadyCredited: false, error: rpcError.message };
  }

  console.log(`[apple-verify] Credited ${credits} bonus to user ${userId}`);
  return { success: true, alreadyCredited: false };
}

// ---------- Request Handlers ----------
export default {
  fetch: withSupabase<any>(
    { auth: "user", cors: corsHeaders },
    async (req, ctx) => {
      supabaseAdmin = ctx.supabaseAdmin;

      // VERY FIRST THING: Log that we received the request
      console.log("[apple-verify] ========== REQUEST RECEIVED ==========");
      console.log(`[apple-verify] Method: ${req.method}`);
      console.log(`[apple-verify] URL: ${req.url}`);

      // Log all headers for debugging
      const headersObj: Record<string, string> = {};
      req.headers.forEach((value, key) => {
        // Mask sensitive values but show they exist
        if (key.toLowerCase() === "authorization") {
          headersObj[key] = value
            ? `Bearer ${value.substring(7, 20)}...`
            : "(empty)";
        } else if (key.toLowerCase() === "apikey") {
          headersObj[key] = value ? `${value.substring(0, 15)}...` : "(empty)";
        } else {
          headersObj[key] = value;
        }
      });
      console.log(
        "[apple-verify] Headers:",
        JSON.stringify(headersObj, null, 2),
      );

      try {
        if (req.method !== "POST") {
          console.log("[apple-verify] Rejecting non-POST method");
          return json({ error: "Method not allowed" }, 405);
        }

        if (!supabaseAdmin) {
          console.log("[apple-verify] supabaseAdmin not configured");
          return json({ error: "Service not configured" }, 503);
        }

        const {
          data: { user },
          error: authError,
        } = await ctx.supabase.auth.getUser();
        console.log(
          `[apple-verify] getUser result - user: ${user?.id ?? "null"}, error: ${
            authError?.message ?? "none"
          }`,
        );

        if (authError || !user) {
          return json({ error: "Invalid or expired token" }, 401);
        }

        // Parse request body
        const body = await req.json();
        const {
          jws,
          transactionId,
          originalTransactionId,
          productId,
          priceDisplay, // Localized price string from StoreKit (e.g., "29,00 kr")
          environment = "Sandbox", // Default to Sandbox for TestFlight testing
        } = body;

        let uploadedTransactionInfo: Partial<AppleTransactionInfo> | null =
          null;
        if (typeof jws === "string" && jws.trim().length > 0) {
          try {
            uploadedTransactionInfo = decodeAppleJWS(
              jws,
            ) as Partial<AppleTransactionInfo>;
          } catch (e) {
            console.error(
              "[apple-verify] Uploaded JWS decode failed:",
              e instanceof Error ? e.message : e,
            );
            return json({ error: "Invalid transaction JWS" }, 400);
          }
        }

        const signedTransactionId = uploadedTransactionInfo?.transactionId;
        if (uploadedTransactionInfo && !signedTransactionId) {
          return json(
            {
              error: "Uploaded transaction JWS is missing transactionId",
            },
            400,
          );
        }

        // Validate required fields. Prefer the StoreKit JWS transaction ID when present.
        if (!signedTransactionId && !transactionId && !originalTransactionId) {
          return json(
            {
              error: "jws, transactionId, or originalTransactionId required",
            },
            400,
          );
        }

        if (productId && !ALLOWED_APPLE_PRODUCTS.includes(productId)) {
          return json({ error: "Invalid product ID" }, 400);
        }

        // Use Apple's signed StoreKit JWS transaction ID when present; client transaction IDs are
        // only a legacy fallback and must still pass appAccountToken ownership binding below.
        const txnToVerify =
          signedTransactionId ?? transactionId ?? originalTransactionId;
        const environmentToVerify = normalizeAppleEnvironment(
          uploadedTransactionInfo?.environment ?? environment,
        );

        // Verify with Apple
        console.log(
          `[apple-verify] Verifying transaction ${txnToVerify} for user ${user.id}`,
        );
        const result = await verifyTransactionWithApple(
          txnToVerify,
          environmentToVerify,
        );

        if (!result) {
          return json({ error: "Transaction verification failed" }, 400);
        }

        const { transactionInfo, renewalInfo } = result;

        const jwsMatch = assertUploadedJWSMatchesApple(
          uploadedTransactionInfo,
          transactionInfo,
        );
        if (!jwsMatch.ok) {
          return json(
            { error: jwsMatch.error ?? "Uploaded transaction mismatch" },
            400,
          );
        }

        const ownership = await assertTransactionBelongsToUser(
          user.id,
          transactionInfo,
        );
        if (!ownership.ok) {
          return json(
            {
              error: ownership.error ?? "Apple transaction ownership mismatch",
            },
            ownership.status ?? 403,
          );
        }

        // Validate bundle ID
        if (transactionInfo.bundleId !== APPLE_APP_BUNDLE_ID) {
          console.error(
            `[apple-verify] Bundle ID mismatch: ${transactionInfo.bundleId}`,
          );
          return json({ error: "Invalid bundle ID" }, 400);
        }

        // Validate product ID if provided
        if (productId && transactionInfo.productId !== productId) {
          console.warn(
            `[apple-verify] Product ID mismatch: expected ${productId}, got ${transactionInfo.productId}`,
          );
        }

        // Validate product is allowed
        if (!ALLOWED_APPLE_PRODUCTS.includes(transactionInfo.productId)) {
          console.error(
            `[apple-verify] Unknown product ID: ${transactionInfo.productId}`,
          );
          return json({ error: "Unknown product ID" }, 400);
        }

        // ---------- Consumable handling ----------
        const consumableCredits = CONSUMABLE_CREDITS[transactionInfo.productId];
        if (consumableCredits !== undefined) {
          const creditResult = await creditConsumable(
            user.id,
            transactionInfo,
            consumableCredits,
          );
          if (!creditResult.success) {
            return json(
              {
                error: creditResult.error ?? "Failed to credit consumable",
              },
              500,
            );
          }
          console.log(
            `[apple-verify] Consumable processed: user=${user.id}, credits=${consumableCredits}, alreadyCredited=${creditResult.alreadyCredited}`,
          );
          return json({
            ok: true,
            type: "consumable",
            credits: consumableCredits,
            alreadyCredited: creditResult.alreadyCredited,
          });
        }

        // ---------- Subscription handling ----------
        // Upsert subscription
        const upsertResult = await upsertAppleSubscription(
          user.id,
          transactionInfo,
          renewalInfo,
          priceDisplay ?? null,
        );

        if (!upsertResult.success) {
          return json(
            {
              error: upsertResult.error ?? "Failed to save subscription",
            },
            upsertResult.status ?? 500,
          );
        }

        // Determine entitlement status
        const { status, isEntitled } = determineSubscriptionStatus(
          transactionInfo,
          renewalInfo,
        );

        console.log(
          `[apple-verify] Success: user=${user.id}, status=${status}, entitled=${isEntitled}`,
        );

        return json({
          ok: true,
          entitled: isEntitled,
          subscription: {
            status,
            productId: transactionInfo.productId,
            internalProductId: mapAppleProductToInternal(
              transactionInfo.productId,
            ),
            expiresAt: transactionInfo.expiresDate
              ? new Date(transactionInfo.expiresDate).toISOString()
              : null,
            environment: transactionInfo.environment,
            autoRenewEnabled: renewalInfo?.autoRenewStatus === 1,
          },
        });
      } catch (e) {
        console.error(
          "[apple-verify] Exception:",
          e instanceof Error ? e.message : e,
        );
        console.error(
          "[apple-verify] Stack:",
          e instanceof Error ? e.stack : "no stack",
        );
        return json({ error: "Internal server error" }, 500);
      }
    },
  ),
};

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
