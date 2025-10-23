/**
 * Session Refresh Telemetry
 *
 * Tracks session refresh attempts, successes, and failures to monitor
 * auth stability and identify issues in production.
 *
 * NO PII is logged - only aggregated metrics and error codes.
 */

export type RefreshReason = "visibilitychange" | "pageshow" | "focus" | "initial" | "error_recovery";

export type RefreshEvent = {
  type:
    | "session_refresh_attempt"
    | "session_refresh_success"
    | "session_refresh_failure"
    | "session_refresh_skipped_no_cookie"; // Cookie missing at wake
  reason: RefreshReason;
  timestamp: number;
  error_code?: string;
  duration_ms?: number;
};

// In-memory store for dev metrics (last 24h)
const DEV_METRICS_WINDOW = 24 * 60 * 60 * 1000; // 24 hours
const devMetrics: RefreshEvent[] = [];

/**
 * Log a session refresh event
 * - Development: Console + in-memory store
 * - Production: Send to analytics endpoint (placeholder for now)
 */
export function logSessionRefresh(
  type: RefreshEvent["type"],
  reason: RefreshReason,
  options?: {
    error?: Error | unknown;
    duration_ms?: number;
  }
) {
  const event: RefreshEvent = {
    type,
    reason,
    timestamp: Date.now(),
    error_code: extractErrorCode(options?.error),
    duration_ms: options?.duration_ms,
  };

  // Development: Detailed console logging
  if (process.env.NODE_ENV === "development") {
    const emoji =
      type === "session_refresh_success" ? "✅" : type === "session_refresh_failure" ? "❌" : "🔄";
    console.log(
      `${emoji} [SESSION TELEMETRY] ${type}`,
      JSON.stringify({
        reason,
        error_code: event.error_code,
        duration_ms: event.duration_ms,
      })
    );

    // Store in memory for dev metrics
    devMetrics.push(event);
    cleanupOldMetrics();
  }

  // Production: Send to analytics (placeholder)
  if (process.env.NODE_ENV === "production") {
    // TODO: Send to your analytics service (e.g., Vercel Analytics, PostHog, etc.)
    // Example:
    // fetch('/api/analytics', {
    //   method: 'POST',
    //   body: JSON.stringify(event),
    //   keepalive: true,
    // });

    // For now, just log to console (will appear in Vercel logs)
    console.log("[SESSION TELEMETRY]", JSON.stringify(event));
  }
}

/**
 * Extract a sanitized error code from an error object
 * NO PII is included - only error type/code
 */
function extractErrorCode(error: unknown): string | undefined {
  if (!error) return undefined;

  if (error instanceof Error) {
    // Supabase errors have a code property
    const supabaseError = error as any;
    if (supabaseError.code) return supabaseError.code;
    if (supabaseError.status) return `http_${supabaseError.status}`;
    return error.name || "unknown_error";
  }

  if (typeof error === "object" && error !== null) {
    const errorObj = error as any;
    if (errorObj.code) return errorObj.code;
    if (errorObj.status) return `http_${errorObj.status}`;
  }

  return "unknown_error";
}

/**
 * Remove events older than 24 hours from dev metrics
 */
function cleanupOldMetrics() {
  const cutoff = Date.now() - DEV_METRICS_WINDOW;
  while (devMetrics.length > 0 && devMetrics[0].timestamp < cutoff) {
    devMetrics.shift();
  }
}

/**
 * Get aggregated metrics for the last 24 hours (dev only)
 */
export function getDevMetrics() {
  if (process.env.NODE_ENV !== "development") {
    return null;
  }

  cleanupOldMetrics();

  const total = devMetrics.length;
  const attempts = devMetrics.filter((e) => e.type === "session_refresh_attempt").length;
  const successes = devMetrics.filter((e) => e.type === "session_refresh_success").length;
  const failures = devMetrics.filter((e) => e.type === "session_refresh_failure").length;
  const skippedNoCookie = devMetrics.filter((e) => e.type === "session_refresh_skipped_no_cookie").length;

  const byReason = devMetrics.reduce(
    (acc, event) => {
      acc[event.reason] = (acc[event.reason] || 0) + 1;
      return acc;
    },
    {} as Record<RefreshReason, number>
  );

  const errorCodes = devMetrics
    .filter((e) => e.error_code)
    .reduce(
      (acc, event) => {
        const code = event.error_code!;
        acc[code] = (acc[code] || 0) + 1;
        return acc;
      },
      {} as Record<string, number>
    );

  const avgDuration =
    devMetrics
      .filter((e) => e.duration_ms !== undefined)
      .reduce((sum, e) => sum + (e.duration_ms || 0), 0) /
      devMetrics.filter((e) => e.duration_ms !== undefined).length || 0;

  return {
    window: "24h",
    total_events: total,
    attempts,
    successes,
    failures,
    skipped_no_cookie: skippedNoCookie,
    success_rate: attempts > 0 ? ((successes / attempts) * 100).toFixed(1) + "%" : "N/A",
    by_reason: byReason,
    error_codes: errorCodes,
    avg_duration_ms: Math.round(avgDuration),
  };
}

/**
 * Print dev metrics to console (call from browser console)
 */
export function printDevMetrics() {
  const metrics = getDevMetrics();
  if (!metrics) {
    console.log("Metrics only available in development");
    return;
  }

  console.group("📊 Session Refresh Metrics (24h)");
  console.log("Total events:", metrics.total_events);
  console.log("Success rate:", metrics.success_rate);
  console.log("Skipped (no cookie):", metrics.skipped_no_cookie);
  console.log("By reason:", metrics.by_reason);
  console.log("Error codes:", metrics.error_codes);
  console.log("Avg duration:", metrics.avg_duration_ms, "ms");
  console.groupEnd();

  return metrics;
}

/**
 * Check if auth cookie exists (client-side only)
 * Returns true if Supabase auth cookie is present, false otherwise
 */
export function hasAuthCookie(): boolean {
  if (typeof document === "undefined") return false;

  // Check for Supabase auth cookie pattern: sb-*-auth-token
  const cookies = document.cookie.split(";");
  return cookies.some((cookie) => {
    const trimmed = cookie.trim();
    return trimmed.startsWith("sb-") && trimmed.includes("-auth-token=");
  });
}

// Expose for browser console debugging
if (typeof window !== "undefined") {
  (window as any).__sessionMetrics = {
    getMetrics: getDevMetrics,
    printMetrics: printDevMetrics,
    hasAuthCookie,
  };
}
