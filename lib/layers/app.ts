/**
 * Application Layer Composition
 *
 * Composes all services into a single AppLive layer for use throughout the application.
 * This provides a centralized place to wire up all dependencies.
 *
 * Layer dependency graph:
 * ```
 * AppConfigLive
 *   └─> SupabaseServiceLive
 *         └─> AuthServiceLive
 *               ├─> SettingsServiceLive
 *               ├─> SnapshotsServiceLive
 *               └─> ShiftsServiceLive (depends on SettingsService)
 * ```
 *
 * Usage:
 * ```typescript
 * import { AppLive } from '@/lib/layers/app'
 *
 * const program = Effect.gen(function* () {
 *   const auth = yield* AuthService
 *   const settings = yield* SettingsService
 *   const shifts = yield* ShiftsService
 *   // Use services...
 * }).pipe(Effect.provide(AppLive))
 * ```
 */

import { Layer } from "effect";
import { AppConfigLive } from "../services/config";
import { SupabaseServiceLive } from "../services/supabase";
import { AuthServiceLive } from "../services/auth";
import { SettingsServiceLive } from "../services/settings";
import { SnapshotsServiceLive } from "../services/snapshots";
import { ShiftsServiceLive } from "../services/shifts";
import { StatsServiceLive } from "../services/stats";
import { SubscriptionServiceLive } from "../services/subscription";
import { ClaudeServiceLive } from "../services/claude";

/**
 * Layer for just configuration and Supabase
 * Use this for database operations without authentication
 *
 * Dependencies: none (provides AppConfig and SupabaseService)
 */
export const SupabaseLive = Layer.provideMerge(
  SupabaseServiceLive,
  AppConfigLive
);

/**
 * Layer for Supabase + Auth operations
 * Use this when you need database access with authentication
 *
 * Dependencies: none (provides AppConfig, SupabaseService, AuthService)
 */
export const SupabaseAuthLive = Layer.provideMerge(
  AuthServiceLive,
  SupabaseLive
);

/**
 * Layer for auth + settings operations
 * Use this when you need authentication and settings but not direct Supabase access
 *
 * Dependencies: none (provides AppConfig, SupabaseService, AuthService, SettingsService)
 */
export const AuthSettingsLive = Layer.provideMerge(
  SettingsServiceLive,
  SupabaseAuthLive
);

/**
 * Layer for auth + snapshots operations
 * Use this when you need authentication and wage snapshots
 *
 * Dependencies: none (provides AppConfig, SupabaseService, AuthService, SnapshotsService)
 */
export const AuthSnapshotsLive = Layer.provideMerge(
  SnapshotsServiceLive,
  SupabaseAuthLive
);

/**
 * Layer for shifts operations
 * Use this when you need shift data with computations
 *
 * Dependencies: none (provides all services including ShiftsService)
 */
export const ShiftsLive = Layer.provideMerge(
  ShiftsServiceLive,
  AuthSettingsLive
);

/**
 * Layer for stats operations
 * Use this when you need statistics and analytics
 *
 * Dependencies: none (provides all services including StatsService)
 */
export const StatsLive = Layer.provideMerge(
  StatsServiceLive,
  ShiftsLive
);

/**
 * Layer for subscription operations
 * Use this when you need subscription and profile data
 *
 * Dependencies: none (provides all services including SubscriptionService)
 */
export const SubscriptionLive = Layer.provideMerge(
  SubscriptionServiceLive,
  SupabaseAuthLive
);

/**
 * Layer for Claude AI operations
 * Use this when you need AI/LLM capabilities
 *
 * Dependencies: none (provides AppConfig and ClaudeService)
 */
export const ClaudeLive = Layer.provideMerge(
  ClaudeServiceLive,
  AppConfigLive
);

/**
 * Complete application layer with all services
 *
 * Provides:
 * - AppConfig: Environment configuration
 * - SupabaseService: Database operations with retry and timeout
 * - AuthService: Authentication and session management
 * - SettingsService: User settings and profile management
 * - SnapshotsService: Wage snapshot management
 * - ShiftsService: Shift data with payroll computations
 * - StatsService: Statistics and analytics with projections
 * - SubscriptionService: Subscription and profile management
 * - ClaudeService: AI/LLM capabilities via Claude API
 *
 * Dependencies: none (fully self-contained)
 */
export const AppLive = Layer.mergeAll(
  AuthSettingsLive,
  AuthSnapshotsLive,
  ShiftsLive,
  StatsLive,
  SubscriptionLive,
  ClaudeLive
);
