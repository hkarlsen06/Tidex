/**
 * Client-side Error Reporting
 *
 * Reports errors to the developer via push notification.
 * Used for tracking production issues that are hard to debug.
 */

interface ErrorReportContext {
  [key: string]: unknown
}

/**
 * Report an error to the developer.
 * Sends a push notification with error details.
 *
 * @param errorType - Category of error (e.g., "IAP_NO_PRODUCTS", "IAP_PURCHASE_FAILED")
 * @param message - Human-readable error message
 * @param context - Additional context (will be JSON stringified)
 */
export async function reportError(
  errorType: string,
  message: string,
  context?: ErrorReportContext
): Promise<void> {
  try {
    const response = await fetch("/api/error-report", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        errorType,
        message,
        context,
      }),
    })

    if (!response.ok) {
      console.error("[ErrorReporting] Failed to report error:", await response.text())
    }
  } catch (e) {
    // Don't throw - error reporting should never break the app
    console.error("[ErrorReporting] Failed to send error report:", e)
  }
}

// Convenience functions for specific error types

export function reportIAPError(message: string, context?: ErrorReportContext): Promise<void> {
  return reportError("IAP_ERROR", message, context)
}

export function reportIAPNoProducts(context?: ErrorReportContext): Promise<void> {
  return reportError("IAP_NO_PRODUCTS", "No products returned from App Store", context)
}

export function reportIAPPurchaseFailed(message: string, context?: ErrorReportContext): Promise<void> {
  return reportError("IAP_PURCHASE_FAILED", message, context)
}

export function reportIAPVerificationFailed(message: string, context?: ErrorReportContext): Promise<void> {
  return reportError("IAP_VERIFICATION_FAILED", message, context)
}
