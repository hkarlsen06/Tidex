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
  attempt_id?: string; // UUID to pair attempt with success/failure
  error_code?: string;
  duration_ms?: number;
};

// In-memory store for dev metrics (last 24h)
const DEV_METRICS_WINDOW = 24 * 60 * 60 * 1000; // 24 hours
const devMetrics: RefreshEvent[] = [];

// Wake debounce: Prevent multiple refresh attempts within 1 second
const WAKE_DEBOUNCE_MS = 1000;
let lastWakeAttempt = 0;

/**
 * Generate a simple UUID v4
 */
function generateUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Log a session refresh event
 * - Development: Console + in-memory store
 * - Production: Send to analytics endpoint (placeholder for now)
 *
 * Returns attemptId for pairing attempt with success/failure
 */
export function logSessionRefresh(
  type: RefreshEvent["type"],
  reason: RefreshReason,
  options?: {
    attempt_id?: string; // Provided by caller to pair success/failure with attempt
    error?: Error | unknown;
    duration_ms?: number;
  }
): string | undefined {
  // Generate attemptId for new attempts
  const attemptId = type === "session_refresh_attempt" ? generateUUID() : options?.attempt_id;

  const event: RefreshEvent = {
    type,
    reason,
    timestamp: Date.now(),
    attempt_id: attemptId,
    error_code: extractErrorCode(options?.error),
    duration_ms: options?.duration_ms,
  };

  // Development: Detailed console logging
  if (process.env.NODE_ENV === "development") {
    const emoji =
      type === "session_refresh_success" ? "✅" : type === "session_refresh_failure" ? "❌" : "🔄";
    const logData: any = {
      reason,
      attempt_id: event.attempt_id,
      error_code: event.error_code,
      duration_ms: event.duration_ms,
    };
    if (options?.error) {
      logData.error = serializeError(options.error);
    }
    console.log(`${emoji} [SESSION TELEMETRY] ${type}`, JSON.stringify(logData));

    // Store in memory for dev metrics
    devMetrics.push(event);
    cleanupOldMetrics();
  }

  // Production: Send to analytics (placeholder)
  if (process.env.NODE_ENV === "production") {
    // Prepare serialized event for logging/analytics
    const serializedEvent: any = {
      type: event.type,
      reason: event.reason,
      timestamp: event.timestamp,
      attempt_id: event.attempt_id,
      error_code: event.error_code,
      duration_ms: event.duration_ms,
    };
    if (options?.error) {
      serializedEvent.error = serializeError(options.error);
    }

    // TODO: Send to your analytics service (e.g., Vercel Analytics, PostHog, etc.)
    // Example:
    // fetch('/api/analytics', {
    //   method: 'POST',
    //   body: JSON.stringify(serializedEvent),
    //   keepalive: true,
    // });

    // For now, just log to console (will appear in Vercel logs)
    console.log("[SESSION TELEMETRY]", JSON.stringify(serializedEvent));
  }

  // Return attemptId for pairing
  return attemptId;
}

/**
 * Serialize error for logging/analytics
 * Returns a plain object with safe-to-log fields (no PII, no circular refs)
 */
function serializeError(error: unknown): {
  name?: string;
  message?: string;
  stack?: string;
  status?: number;
  code?: string;
} {
  if (!error) return {};

  if (error instanceof Error) {
    const supabaseError = error as any;
    return {
      name: error.name,
      message: error.message?.slice(0, 200), // Truncate long messages
      stack: error.stack?.split("\n").slice(0, 3).join("\n"), // First 3 lines only
      status: supabaseError.status,
      code: supabaseError.code,
    };
  }

  if (typeof error === "object" && error !== null) {
    const errorObj = error as any;
    return {
      name: errorObj.name,
      message: errorObj.message?.slice(0, 200),
      status: errorObj.status,
      code: errorObj.code,
    };
  }

  return {
    message: String(error).slice(0, 200),
  };
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
 * Optimized: O(n) single splice instead of O(n²) repeated shifts
 */
function cleanupOldMetrics() {
  const cutoff = Date.now() - DEV_METRICS_WINDOW;
  const firstValidIndex = devMetrics.findIndex((e) => e.timestamp >= cutoff);

  if (firstValidIndex > 0) {
    // Remove all events before the first valid one
    devMetrics.splice(0, firstValidIndex);
  } else if (firstValidIndex === -1 && devMetrics.length > 0) {
    // All events are old, clear the array
    devMetrics.length = 0;
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
  const attempts = devMetrics.filter((e) => e.type === "session_refresh_attempt");
  const successes = devMetrics.filter((e) => e.type === "session_refresh_success");
  const failures = devMetrics.filter((e) => e.type === "session_refresh_failure");
  const skippedNoCookie = devMetrics.filter((e) => e.type === "session_refresh_skipped_no_cookie").length;

  // Calculate success rate by matching attemptIds
  const attemptIds = new Set(attempts.map((e) => e.attempt_id).filter(Boolean));
  const completedAttempts = [...successes, ...failures].filter((e) => e.attempt_id && attemptIds.has(e.attempt_id));
  const successfulAttempts = completedAttempts.filter((e) => e.type === "session_refresh_success");

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
    attempts: attempts.length,
    successes: successes.length,
    failures: failures.length,
    completed_attempts: completedAttempts.length,
    skipped_no_cookie: skippedNoCookie,
    success_rate:
      completedAttempts.length > 0
        ? ((successfulAttempts.length / completedAttempts.length) * 100).toFixed(1) + "%"
        : "N/A",
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
 * Check if auth cookie exists and has valid value (client-side only)
 * Returns true if Supabase auth cookie is present with valid session data
 */
export function hasAuthCookie(): boolean {
  if (typeof document === "undefined") return false;

  // Check for Supabase auth cookie pattern: sb-*-auth-token
  const cookies = document.cookie.split(";");
  return cookies.some((cookie) => {
    const trimmed = cookie.trim();
    if (!trimmed.startsWith("sb-") || !trimmed.includes("-auth-token=")) {
      return false;
    }

    // Extract value after "="
    const equalIndex = trimmed.indexOf("=");
    if (equalIndex === -1) return false;

    const value = trimmed.substring(equalIndex + 1);

    // Check for empty or deleted cookie
    if (!value || value === "" || value === "deleted") {
      return false;
    }

    // Try to parse as JSON and verify it has tokens
    try {
      const parsed = JSON.parse(decodeURIComponent(value));
      // Must have at least one token (access_token or refresh_token)
      return !!(parsed.access_token || parsed.refresh_token);
    } catch {
      // If not valid JSON, might be base64 or encrypted - assume valid
      return true;
    }
  });
}

/**
 * Wake debounce gate: Prevents multiple refresh attempts within a short time window
 * Used by visibilitychange, pageshow, and focus handlers to avoid refresh spam
 *
 * Returns true if refresh should proceed, false if debounced
 */
export function shouldAttemptWakeRefresh(reason: RefreshReason): boolean {
  const now = Date.now();

  // Check if we're within debounce window
  if (now - lastWakeAttempt < WAKE_DEBOUNCE_MS) {
    console.log(`[SUPABASE] Debouncing ${reason} refresh (last attempt ${now - lastWakeAttempt}ms ago)`);
    logSessionRefresh("session_refresh_skipped_no_cookie", reason); // Reuse "skipped" type for debounced attempts
    return false;
  }

  // Update last attempt time
  lastWakeAttempt = now;
  return true;
}

// Expose for browser console debugging
if (typeof window !== "undefined") {
  (window as any).__sessionMetrics = {
    getMetrics: getDevMetrics,
    printMetrics: printDevMetrics,
    hasAuthCookie,
    shouldAttemptWakeRefresh,
  };
}
