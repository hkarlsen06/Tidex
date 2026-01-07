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
// Native users only have access to Pro monthly subscription
export const APPLE_PRODUCT_IDS = {
  PRO_MONTHLY: "no.tidex.pro",
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
  if (NativePurchases) {
    return NativePurchases;
  }

  if (!isNativePlatform() || getPlatform() !== "ios") {
    throw new Error("Native purchases only available on iOS");
  }

  try {
    // Dynamic import to avoid loading on web
    pluginModule = await import("@capgo/native-purchases");
    NativePurchases = pluginModule.NativePurchases;

    if (!NativePurchases) {
      throw new Error("NativePurchases not found in module exports");
    }

    return NativePurchases;
  } catch (e: any) {
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
 * Note: @capgo/native-purchases doesn't require explicit initialization,
 * but we check if billing is supported as a validation step.
 */
export async function initializeIAP(): Promise<{ success: boolean; error?: string }> {
  if (!isIAPAvailable()) {
    return { success: false, error: "IAP not available on this platform" };
  }

  try {
    console.log("[IAP] initializeIAP called");
    const plugin = await getNativePurchases();
    console.log("[IAP] Plugin loaded for init");

    // Check if billing is supported instead of calling initialize()
    // The @capgo/native-purchases plugin doesn't have an initialize method
    console.log("[IAP] Checking if billing is supported...");
    const { isBillingSupported } = await plugin.isBillingSupported();
    console.log("[IAP] isBillingSupported:", isBillingSupported);

    if (!isBillingSupported) {
      return { success: false, error: "Billing is not supported on this device" };
    }

    return { success: true };
  } catch (e: any) {
    console.error("[IAP] initializeIAP error:", e);
    return { success: false, error: e.message || "Unknown initialization error" };
  }
}

/**
 * Get available products from the App Store
 */
export async function getProducts(
  productIds: string[] = ALL_APPLE_PRODUCT_IDS
): Promise<{ products: IAPProduct[]; error?: string }> {
  if (!isIAPAvailable()) {
    return { products: [], error: "IAP not available on this platform" };
  }

  try {
    console.log("[IAP] getProducts called with productIds:", productIds);
    const plugin = await getNativePurchases();
    console.log("[IAP] Plugin loaded, calling getProducts...");

    if (!plugin.getProducts) {
      return { products: [], error: "Plugin getProducts method not found" };
    }

    // Note: Plugin uses productIdentifiers (not productIds) and productType for subscriptions
    const result = await plugin.getProducts({
      productIdentifiers: productIds,
      productType: "subs" // Subscriptions
    });
    console.log("[IAP] getProducts result:", JSON.stringify(result));
    const rawProducts = result.products || [];

    if (rawProducts.length === 0) {
      return {
        products: [],
        error: "No products available. The app may not be fully configured in App Store Connect yet."
      };
    }

    // Map plugin's Product interface to our IAPProduct interface
    // Plugin returns: identifier, title, description, price, priceString, currencyCode
    const mappedProducts = rawProducts.map((p: any) => ({
      id: p.identifier,
      title: p.title || p.identifier,
      description: p.description || "",
      price: p.priceString || `${p.price}`,
      priceValue: typeof p.price === "number" ? p.price : parseFloat(p.price) || 0,
      currency: p.currencyCode || "NOK",
      type: "subscription" as const,
    }));
    console.log("[IAP] Mapped products:", JSON.stringify(mappedProducts));

    return { products: mappedProducts };
  } catch (e: any) {
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

    console.log("[IAP] Starting purchase for product:", productId);
    // Start purchase with appAccountToken
    // Plugin uses productIdentifier (not productId) and productType for subscriptions
    const purchaseResult = await plugin.purchaseProduct({
      productIdentifier: productId,
      productType: "subs", // Subscription
      appAccountToken, // Links purchase to Tidex user (must be UUID format)
    });
    console.log("[IAP] Purchase result:", JSON.stringify(purchaseResult));

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

    console.log("[IAP] Restoring purchases...");
    // First call restorePurchases to sync with App Store
    await plugin.restorePurchases();

    // Then get the current purchases/transactions
    console.log("[IAP] Getting purchases...");
    const result = await plugin.getPurchases({ productType: "subs" });
    console.log("[IAP] getPurchases result:", JSON.stringify(result));

    // Find active subscription transactions
    // Plugin uses productIdentifier not productId
    const activeTransactions = (result.transactions || []).filter(
      (t: any) => t.productIdentifier && ALL_APPLE_PRODUCT_IDS.includes(t.productIdentifier)
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
        txn.productIdentifier,
        appAccountToken,
        supabaseAccessToken
      );

      if (verifyResult.entitled) {
        lastEntitled = true;
        lastProductId = txn.productIdentifier;
      }
    }

    return {
      success: true,
      productId: lastProductId,
      entitled: lastEntitled,
    };
  } catch (e: any) {
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
      return { isEntitled: false };
    }

    const data = await response.json();
    return {
      isEntitled: data?.is_entitled ?? false,
      productId: data?.active_product_id,
      expiresAt: data?.subscription_ends_at,
      provider: data?.active_provider,
    };
  } catch {
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
  } catch {
    // Fallback: use Capacitor Browser plugin which properly handles external URLs
    try {
      const { Browser } = await import("@capacitor/browser");
      await Browser.open({ url: iosDeepLink });
    } catch {
      // Last resort fallback
      window.location.href = iosDeepLink;
    }
  }
}
