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
import { JobsServiceLive } from "../services/jobs";
import { StatsServiceLive } from "../services/stats";
import { SubscriptionServiceLive } from "../services/subscription";
import { OpenAIServiceLive } from "../services/openai";
import { WageyServiceLive } from "../services/wagey";
import { SharingServiceLive } from "../services/sharing";

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
 * Layer for jobs operations
 * Use this when you need multi-job CRUD/read operations
 */
export const JobsLive = Layer.provideMerge(
  JobsServiceLive,
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
 * Layer for OpenAI AI operations
 * Use this when you need AI/LLM capabilities via OpenAI Responses API
 *
 * Dependencies: none (provides AppConfig and OpenAIService)
 */
export const OpenAILive = Layer.provideMerge(
  OpenAIServiceLive,
  AppConfigLive
);

/**
 * Layer for Wagey AI assistant operations
 * Use this when you need Wagey access control and usage tracking
 *
 * Dependencies: none (provides all services including WageyService)
 */
export const WageyLive = Layer.provideMerge(
  WageyServiceLive,
  SubscriptionLive
);

/**
 * Layer for sharing operations
 * Use this when you need shift sharing functionality
 *
 * Dependencies: none (provides all services including SharingService)
 */
export const SharingLive = Layer.provideMerge(
  SharingServiceLive,
  SubscriptionLive
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
 * - OpenAIService: AI/LLM capabilities via OpenAI Responses API
 * - WageyService: Wagey access control and usage tracking
 * - SharingService: Shift sharing functionality
 *
 * Dependencies: none (fully self-contained)
 */
export const AppLive = Layer.mergeAll(
  AuthSettingsLive,
  AuthSnapshotsLive,
  JobsLive,
  ShiftsLive,
  StatsLive,
  SubscriptionLive,
  OpenAILive,
  WageyLive,
  SharingLive
);
