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
import { NativePurchases, PURCHASE_TYPE } from "@capgo/native-purchases";
import { reportIAPNoProducts, reportIAPPurchaseFailed, reportIAPVerificationFailed } from "@/lib/error-reporting";

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
  /** True when purchase detected existing subscription and auto-restored */
  restoredFromExisting?: boolean;
}

export interface IAPEntitlement {
  isEntitled: boolean;
  productId?: string;
  expiresAt?: string;
  provider?: "apple" | "stripe";
}

// ---------- Apple Product IDs ----------
// These must match the products configured in App Store Connect
export const APPLE_PRODUCT_IDS = {
  PRO_MONTHLY: "no.tidex.pro",
  PRO_YEARLY: "no.tidex.pro.year",
  MAX_MONTHLY: "no.tidex.max",
  MAX_YEARLY: "no.tidex.max.year",
} as const;

export const ALL_APPLE_PRODUCT_IDS = Object.values(APPLE_PRODUCT_IDS);

// ---------- Product Cache ----------
// Cache products after fetching so we can look up prices during purchase/restore
let cachedProducts: IAPProduct[] = [];

export function getCachedProductPrice(productId: string): string | null {
  const product = cachedProducts.find((p) => p.id === productId);
  return product?.price ?? null;
}

// ---------- Plugin Helper ----------

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
  if (NativePurchases) {
    return { available: true, details: "Plugin available" };
  }
  return { available: false, details: "Plugin not available" };
}

function getPlugin() {
  if (!isNativePlatform() || getPlatform() !== "ios") {
    throw new Error("Native purchases only available on iOS");
  }
  return NativePurchases;
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
    const plugin = getPlugin();
    console.log("[IAP] Plugin obtained");

    // Check if billing is supported
    console.log("[IAP] Checking if billing is supported...");
    const result = await plugin.isBillingSupported();
    console.log("[IAP] isBillingSupported result:", JSON.stringify(result));

    if (!result.isBillingSupported) {
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
    const plugin = getPlugin();
    console.log("[IAP] Plugin obtained, calling getProducts...");

    // Note: Plugin uses productIdentifiers (not productIds) and productType for subscriptions
    console.log("[IAP] Calling plugin.getProducts with:", {
      productIdentifiers: productIds,
      productType: PURCHASE_TYPE.SUBS
    });

    const result = await plugin.getProducts({
      productIdentifiers: productIds,
      productType: PURCHASE_TYPE.SUBS
    });

    console.log("[IAP] getProducts raw result:", JSON.stringify(result));
    console.log("[IAP] getProducts result type:", typeof result);
    console.log("[IAP] getProducts result.products:", result.products);
    console.log("[IAP] getProducts result.products length:", result.products?.length);

    const rawProducts = result.products || [];

    if (rawProducts.length === 0) {
      console.warn("[IAP] No products returned from App Store!", {
        requestedProductIds: productIds,
        rawResult: result,
        resultKeys: Object.keys(result || {}),
      });
      // Report to developer
      reportIAPNoProducts({
        requestedProductIds: productIds,
        rawResult: result,
        platform: getPlatform(),
      });
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

    // Cache products for price lookup during purchase/restore
    cachedProducts = mappedProducts;

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
    const plugin = getPlugin();

    console.log("[IAP] Starting purchase for product:", productId);
    // Start purchase with appAccountToken
    // Plugin uses productIdentifier (not productId) and productType for subscriptions
    const purchaseResult = await plugin.purchaseProduct({
      productIdentifier: productId,
      productType: PURCHASE_TYPE.SUBS,
      appAccountToken, // Links purchase to Tidex user (must be UUID format)
    });
    console.log("[IAP] Purchase result:", JSON.stringify(purchaseResult));

    if (!purchaseResult.transactionId) {
      return {
        success: false,
        error: "Purchase failed - no transaction",
      };
    }

    // The plugin's Transaction type uses transactionId as the primary identifier
    // For original transaction ID, we use transactionId as fallback
    const txnId = purchaseResult.transactionId;

    // Get the localized price from cache to store in database
    const priceDisplay = getCachedProductPrice(productId);

    // Verify with our server
    const verifyResult = await verifyPurchaseWithServer(
      txnId,
      txnId, // Use same ID for original - server will handle via Apple API
      productId,
      appAccountToken,
      supabaseAccessToken,
      priceDisplay
    );

    if (!verifyResult.success) {
      // Purchase succeeded but verification failed
      // Transaction is still valid - user should retry verification
      reportIAPVerificationFailed(verifyResult.error || "Unknown verification error", {
        transactionId: txnId,
        productId,
      });
      return {
        success: true, // Purchase itself succeeded
        transactionId: txnId,
        originalTransactionId: txnId,
        productId,
        error: `Verification failed: ${verifyResult.error}. Please try "Restore Purchases".`,
        entitled: false,
      };
    }

    return {
      success: true,
      transactionId: txnId,
      originalTransactionId: txnId,
      productId,
      entitled: verifyResult.entitled,
    };
  } catch (e: any) {
    // Log full error details for debugging
    console.error("[IAP] Purchase error:", {
      message: e.message,
      code: e.code,
      name: e.name,
      fullError: JSON.stringify(e),
    });

    // Handle specific StoreKit errors
    if (e.code === "E_USER_CANCELLED" || e.message?.includes("cancelled")) {
      return { success: false, error: "Purchase cancelled" };
    }

    // Handle "already subscribed" - StoreKit shows dialog, user taps OK, we get an error
    // This can manifest as various error codes/messages depending on StoreKit version
    const errorMessage = (e.message || "").toLowerCase();
    const isAlreadySubscribed =
      errorMessage.includes("already") ||
      errorMessage.includes("subscribed") ||
      errorMessage.includes("purchased") ||
      e.code === "E_ALREADY_OWNED" ||
      e.code === "6778003"; // StoreKit "already purchased" code

    if (isAlreadySubscribed) {
      console.log("[IAP] User already subscribed, attempting restore...");
      // Automatically restore to sync the existing subscription
      const restoreResult = await restorePurchases(appAccountToken, supabaseAccessToken);

      // Add context about what happened
      if (restoreResult.entitled) {
        return {
          ...restoreResult,
          restoredFromExisting: true, // Flag for UI to show appropriate message
        };
      } else {
        return {
          ...restoreResult,
          error: restoreResult.error || "You have an existing subscription on a different account. Please restore from that account.",
          restoredFromExisting: true,
        };
      }
    }

    // Report non-cancellation errors
    reportIAPPurchaseFailed(e.message || "Unknown purchase error", {
      productId,
      errorCode: e.code,
    });
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
    const plugin = getPlugin();

    console.log("[IAP] Restoring purchases...");
    // First call restorePurchases to sync with App Store
    await plugin.restorePurchases();

    // Then get the current purchases/transactions
    console.log("[IAP] Getting purchases...");
    const result = await plugin.getPurchases({ productType: PURCHASE_TYPE.SUBS });
    console.log("[IAP] getPurchases result:", JSON.stringify(result));

    // Find active subscription transactions
    // Plugin returns { purchases: Transaction[] }
    // Transaction uses productIdentifier field
    const activePurchases = (result.purchases || []).filter(
      (t) => t.productIdentifier && (ALL_APPLE_PRODUCT_IDS as readonly string[]).includes(t.productIdentifier)
    );

    if (activePurchases.length === 0) {
      return { success: true, error: "No purchases to restore" };
    }

    // Verify each transaction with our server
    let lastEntitled = false;
    let lastProductId: string | undefined;

    for (const txn of activePurchases) {
      // Get the localized price from cache to store in database
      const priceDisplay = getCachedProductPrice(txn.productIdentifier);

      const verifyResult = await verifyPurchaseWithServer(
        txn.transactionId,
        txn.transactionId, // Use same ID - server handles original via Apple API
        txn.productIdentifier,
        appAccountToken,
        supabaseAccessToken,
        priceDisplay
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
  _supabaseAccessToken: string, // Kept for backward compatibility but we'll get fresh token
  priceDisplay?: string | null // Localized price from App Store
): Promise<{ success: boolean; entitled?: boolean; error?: string }> {
  try {
    // Dynamic import to avoid bundling Supabase in non-browser environments
    const { supabase } = await import("@/lib/supabase/browser");

    // Refresh session to ensure we have a valid token
    // This is important for native iOS where the app may have been in background
    console.log("[IAP] Refreshing session before edge function call...");
    const { data: refreshData, error: refreshError } = await supabase.auth.refreshSession();

    if (refreshError) {
      console.error("[IAP] Session refresh failed:", refreshError.message);
      return { success: false, error: "Failed to refresh authentication" };
    }

    const accessToken = refreshData.session?.access_token;
    if (!accessToken) {
      console.error("[IAP] No access token after refresh");
      return { success: false, error: "No authentication token available" };
    }

    console.log("[IAP] Calling apple-verify-purchase with refreshed token");
    // Use fetch with explicit Authorization header to ensure we use the fresh token
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/apple-verify-purchase`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
          apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "",
        },
        body: JSON.stringify({
          transactionId,
          originalTransactionId,
          productId,
          appAccountToken,
          priceDisplay,
        }),
      }
    );

    const responseData = await response.json();

    if (!response.ok) {
      console.error("[IAP] Verification failed:", response.status, responseData);
      return {
        success: false,
        error: responseData.error || `Verification failed (${response.status})`,
      };
    }

    return {
      success: true,
      entitled: responseData?.entitled ?? false,
    };
  } catch (e: any) {
    console.error("[IAP] verifyPurchaseWithServer error:", e);
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
    const plugin = getPlugin();
    // Note: openManagement may not exist on this plugin - check docs
    if ('openManagement' in plugin) {
      await (plugin as any).openManagement();
    } else {
      throw new Error("openManagement not available");
    }
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
