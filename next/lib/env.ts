/**
 * Environment Variables (Legacy)
 *
 * This module provides backward-compatible access to environment variables.
 * For new code, use the Effect-based AppConfig service from lib/services/config.ts
 *
 * Migration: This file now delegates to the Effect-based config system for validation.
 */

import { validateConfig, ENV as RAW_ENV } from "./services/config";

// Validate configuration at module load time (server only).
// Browser bundles don't have access to server-only keys (e.g. OpenRouter), so skip there.
const isServer = typeof window === "undefined";
if (isServer) {
  validateConfig();
}

/**
 * Environment variables (backward compatible export)
 * @deprecated Use AppConfig service from lib/services/config.ts in new code
 */
export const ENV = RAW_ENV;
