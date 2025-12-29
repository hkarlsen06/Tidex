/**
 * Capacitor In-App Purchase Wrapper
 *
 * Provides a unified interface for iOS StoreKit 2 purchases via Capacitor.
 * Only loads the native plugin on iOS platform.
 *
 * This module handles:
 * - Product listing
 * - Purchase flow
 * - Restore purchases
 * - Server verification via Supabase Edge Function
 */

import { isNativePlatform, getPlatform } from "./platform";

// ---------- Types ----------

export interface IAPProduct {
  id: string;
  title: string;
  description: string;
  price: string;
  priceValue: number;
  currency: string;
  type: "subscription" | "consumable" | "non_consumable";
}

export interface IAPPurchaseResult {
  success: boolean;
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  error?: string;
  entitled?: boolean;
}

export interface IAPEntitlement {
  isEntitled: boolean;
  productId?: string;
  expiresAt?: string;
  provider?: "apple" | "stripe";
}

// ---------- Apple Product IDs ----------
// These must match the products configured in App Store Connect
// Matches existing tiers: Pro and Max, each with monthly/yearly
export const APPLE_PRODUCT_IDS = {
  PRO_MONTHLY: "no.tidex.pro.monthly",
  PRO_YEARLY: "no.tidex.pro.yearly",
  MAX_MONTHLY: "no.tidex.max.monthly",
  MAX_YEARLY: "no.tidex.max.yearly",
} as const;

export const ALL_APPLE_PRODUCT_IDS = Object.values(APPLE_PRODUCT_IDS);

// ---------- Lazy Plugin Import ----------
// Only import the native plugin on iOS to avoid errors on web
let NativePurchases: any = null;
let pluginModule: any = null;

/**
 * Check if the IAP plugin object exists at runtime
 */
export function checkPluginAvailability(): { available: boolean; details: string } {
  if (!isNativePlatform()) {
    return { available: false, details: "Not running on native platform" };
  }
  if (getPlatform() !== "ios") {
    return { available: false, details: `Platform is ${getPlatform()}, not iOS` };
  }
  if (pluginModule) {
    return { available: true, details: "Plugin module loaded" };
  }
  return { available: true, details: "Plugin not yet loaded (will be loaded on first use)" };
}

async function getNativePurchases() {
  console.log("[iap] getNativePurchases called");

  if (NativePurchases) {
    console.log("[iap] Returning cached NativePurchases");
    return NativePurchases;
  }

  if (!isNativePlatform() || getPlatform() !== "ios") {
    const error = new Error("Native purchases only available on iOS");
    console.error("[iap] Platform check failed:", {
      isNative: isNativePlatform(),
      platform: getPlatform()
    });
    throw error;
  }

  try {
    console.log("[iap] Attempting to import @capgo/native-purchases...");
    // Dynamic import to avoid loading on web
    pluginModule = await import("@capgo/native-purchases");
    console.log("[iap] Module imported successfully, keys:", Object.keys(pluginModule));

    NativePurchases = pluginModule.NativePurchases;

    if (!NativePurchases) {
      console.error("[iap] NativePurchases is undefined in module. Available exports:", Object.keys(pluginModule));
      throw new Error("NativePurchases not found in module exports");
    }

    console.log("[iap] NativePurchases object obtained, methods:",
      typeof NativePurchases === 'object' ? Object.keys(NativePurchases) : typeof NativePurchases
    );

    return NativePurchases;
  } catch (e: any) {
    console.error("[iap] Failed to import native-purchases:", {
      message: e.message,
      stack: e.stack,
      name: e.name
    });
    throw new Error(`Native purchases plugin not available: ${e.message}`);
  }
}

// ---------- IAP Functions ----------

/**
 * Check if IAP is available on the current platform
 */
export function isIAPAvailable(): boolean {
  return isNativePlatform() && getPlatform() === "ios";
}

/**
 * Initialize the IAP plugin
 * Should be called once at app startup on iOS
 */
export async function initializeIAP(): Promise<{ success: boolean; error?: string }> {
  console.log("[iap] initializeIAP called");

  if (!isIAPAvailable()) {
    console.log("[iap] Not available on this platform");
    return { success: false, error: "IAP not available on this platform" };
  }

  try {
    console.log("[iap] Getting plugin reference...");
    const plugin = await getNativePurchases();
    console.log("[iap] Plugin reference obtained, calling initialize()...");

    if (!plugin.initialize) {
      console.error("[iap] plugin.initialize is not a function. Plugin object:", plugin);
      return { success: false, error: "Plugin initialize method not found" };
    }

    const initResult = await plugin.initialize();
    console.log("[iap] plugin.initialize() completed with result:", initResult);
    console.log("[iap] Initialized successfully");
    return { success: true };
  } catch (e: any) {
    console.error("[iap] Initialization failed:", {
      message: e.message,
      stack: e.stack,
      name: e.name,
      code: e.code
    });
    return { success: false, error: e.message || "Unknown initialization error" };
  }
}

/**
 * Get available products from the App Store
 */
export async function getProducts(
  productIds: string[] = ALL_APPLE_PRODUCT_IDS
): Promise<{ products: IAPProduct[]; error?: string }> {
  console.log("[iap] getProducts called with product IDs:", productIds);

  if (!isIAPAvailable()) {
    console.log("[iap] getProducts: IAP not available");
    return { products: [], error: "IAP not available on this platform" };
  }

  try {
    console.log("[iap] Getting plugin reference for getProducts...");
    const plugin = await getNativePurchases();

    if (!plugin.getProducts) {
      console.error("[iap] plugin.getProducts is not a function");
      return { products: [], error: "Plugin getProducts method not found" };
    }

    console.log("[iap] Calling plugin.getProducts with IDs:", productIds);
    const result = await plugin.getProducts({ productIds });
    console.log("[iap] plugin.getProducts raw result:", JSON.stringify(result, null, 2));

    const rawProducts = result.products || [];
    console.log("[iap] Products count:", rawProducts.length);

    if (rawProducts.length === 0) {
      console.warn("[iap] No products returned from App Store. This could mean:");
      console.warn("[iap] - Products are not configured in App Store Connect");
      console.warn("[iap] - Product IDs do not match App Store Connect configuration");
      console.warn("[iap] - App is not in TestFlight or products not yet approved");
      console.warn("[iap] - Sandbox/production environment mismatch");
      return {
        products: [],
        error: "No products available. The app may not be fully configured in App Store Connect yet."
      };
    }

    rawProducts.forEach((p: any, i: number) => {
      console.log(`[iap] Product ${i + 1}:`, {
        id: p.id,
        title: p.title || p.displayName,
        price: p.priceString || p.displayPrice || p.price,
        type: p.type
      });
    });

    const mappedProducts = rawProducts.map((p: any) => ({
      id: p.id,
      title: p.title || p.displayName || p.id,
      description: p.description || "",
      price: p.priceString || p.displayPrice || `${p.price}`,
      priceValue: parseFloat(p.price) || 0,
      currency: p.currencyCode || "USD",
      type: p.type === 0 || p.type === "autoRenewable" ? "subscription" : "non_consumable",
    }));

    console.log("[iap] getProducts completed successfully with", mappedProducts.length, "products");
    return { products: mappedProducts };
  } catch (e: any) {
    console.error("[iap] Failed to get products:", {
      message: e.message,
      stack: e.stack,
      name: e.name,
      code: e.code
    });
    return { products: [], error: e.message || "Failed to fetch products" };
  }
}

/**
 * Purchase a product
 *
 * @param productId - The Apple product ID
 * @param appAccountToken - UUID linking purchase to Tidex user (required)
 * @param supabaseAccessToken - Supabase auth token for server verification
 */
export async function purchaseProduct(
  productId: string,
  appAccountToken: string,
  supabaseAccessToken: string
): Promise<IAPPurchaseResult> {
  if (!isIAPAvailable()) {
    return { success: false, error: "IAP not available on this platform" };
  }

  if (!appAccountToken) {
    return { success: false, error: "appAccountToken is required" };
  }

  try {
    const plugin = await getNativePurchases();

    // Start purchase with appAccountToken
    const purchaseResult = await plugin.purchaseProduct({
      productId,
      appAccountToken, // Links purchase to Tidex user
    });

    if (!purchaseResult.transactionId) {
      return {
        success: false,
        error: purchaseResult.error || "Purchase failed - no transaction",
      };
    }

    // Verify with our server
    const verifyResult = await verifyPurchaseWithServer(
      purchaseResult.transactionId,
      purchaseResult.originalTransactionId || purchaseResult.transactionId,
      productId,
      appAccountToken,
      supabaseAccessToken
    );

    if (!verifyResult.success) {
      // Purchase succeeded but verification failed
      // Transaction is still valid - user should retry verification
      return {
        success: true, // Purchase itself succeeded
        transactionId: purchaseResult.transactionId,
        originalTransactionId: purchaseResult.originalTransactionId,
        productId,
        error: `Verification failed: ${verifyResult.error}. Please try "Restore Purchases".`,
        entitled: false,
      };
    }

    return {
      success: true,
      transactionId: purchaseResult.transactionId,
      originalTransactionId: purchaseResult.originalTransactionId,
      productId,
      entitled: verifyResult.entitled,
    };
  } catch (e: any) {
    console.error("[iap] Purchase failed:", e);

    // Handle specific StoreKit errors
    if (e.code === "E_USER_CANCELLED" || e.message?.includes("cancelled")) {
      return { success: false, error: "Purchase cancelled" };
    }

    return { success: false, error: e.message || "Purchase failed" };
  }
}

/**
 * Restore previous purchases
 * Call this when user taps "Restore Purchases" or on new device
 *
 * @param appAccountToken - UUID linking purchase to Tidex user
 * @param supabaseAccessToken - Supabase auth token for server verification
 */
export async function restorePurchases(
  appAccountToken: string,
  supabaseAccessToken: string
): Promise<IAPPurchaseResult> {
  if (!isIAPAvailable()) {
    return { success: false, error: "IAP not available on this platform" };
  }

  try {
    const plugin = await getNativePurchases();
    const result = await plugin.restorePurchases();

    // Find active subscription transactions
    const activeTransactions = (result.transactions || []).filter(
      (t: any) => t.productId && ALL_APPLE_PRODUCT_IDS.includes(t.productId)
    );

    if (activeTransactions.length === 0) {
      return { success: true, error: "No purchases to restore" };
    }

    // Verify each transaction with our server
    let lastEntitled = false;
    let lastProductId: string | undefined;

    for (const txn of activeTransactions) {
      const verifyResult = await verifyPurchaseWithServer(
        txn.transactionId,
        txn.originalTransactionId || txn.transactionId,
        txn.productId,
        appAccountToken,
        supabaseAccessToken
      );

      if (verifyResult.entitled) {
        lastEntitled = true;
        lastProductId = txn.productId;
      }
    }

    return {
      success: true,
      productId: lastProductId,
      entitled: lastEntitled,
    };
  } catch (e: any) {
    console.error("[iap] Restore failed:", e);
    return { success: false, error: e.message || "Restore failed" };
  }
}

/**
 * Get current entitlement status
 * Checks both local transactions and server state
 */
export async function getEntitlementStatus(
  supabaseAccessToken: string
): Promise<IAPEntitlement> {
  // Always check server state for entitlements
  // Server is source of truth (handles both Stripe and Apple)
  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/get_user_entitlement_status`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseAccessToken}`,
          apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "",
        },
        body: JSON.stringify({}),
      }
    );

    if (!response.ok) {
      console.error("[iap] Entitlement check failed:", response.status);
      return { isEntitled: false };
    }

    const data = await response.json();
    return {
      isEntitled: data?.is_entitled ?? false,
      productId: data?.active_product_id,
      expiresAt: data?.subscription_ends_at,
      provider: data?.active_provider,
    };
  } catch (e) {
    console.error("[iap] Failed to check entitlement:", e);
    return { isEntitled: false };
  }
}

// ---------- Server Verification ----------

async function verifyPurchaseWithServer(
  transactionId: string,
  originalTransactionId: string,
  productId: string,
  appAccountToken: string,
  supabaseAccessToken: string
): Promise<{ success: boolean; entitled?: boolean; error?: string }> {
  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/apple-verify-purchase`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseAccessToken}`,
        },
        body: JSON.stringify({
          transactionId,
          originalTransactionId,
          productId,
          appAccountToken,
        }),
      }
    );

    const data = await response.json();

    if (!response.ok) {
      return {
        success: false,
        error: data.error || `Verification failed (${response.status})`,
      };
    }

    return {
      success: true,
      entitled: data.entitled ?? false,
    };
  } catch (e: any) {
    console.error("[iap] Server verification failed:", e);
    return { success: false, error: e.message || "Network error" };
  }
}

/**
 * Open the iOS subscription management page
 */
export async function openSubscriptionManagement(): Promise<void> {
  // iOS deep link to subscription management
  const iosDeepLink = "https://apps.apple.com/account/subscriptions";

  if (!isIAPAvailable()) {
    // On web, open in new tab
    window.open(iosDeepLink, "_blank");
    return;
  }

  try {
    const plugin = await getNativePurchases();
    await plugin.openManagement();
  } catch (e) {
    console.log("[iap] openManagement failed, trying Browser plugin:", e);

    // Fallback: use Capacitor Browser plugin which properly handles external URLs
    try {
      const { Browser } = await import("@capacitor/browser");
      await Browser.open({ url: iosDeepLink });
    } catch (browserError) {
      console.log("[iap] Browser plugin failed, using location.href:", browserError);
      // Last resort fallback
      window.location.href = iosDeepLink;
    }
  }
}
