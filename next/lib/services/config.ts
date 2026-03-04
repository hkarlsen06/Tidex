/**
 * Configuration Service
 *
 * Effect-based configuration management with schema validation.
 * Provides type-safe access to environment variables with proper error handling.
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const config = yield* AppConfig
 *   console.log(config.supabase.url)
 * })
 * ```
 */

import { Context, Effect, Layer, Schema, Redacted, ParseResult } from "effect";
import { ConfigError } from "../errors/tagged";

export type WageyAIProvider = "claude" | "chatgpt";

/**
 * Supabase Configuration Schema
 * Validates Supabase connection settings
 */
const SupabaseConfigSchema = Schema.Struct({
  url: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.pattern(/^https?:\/\/.+/),
    Schema.annotations({
      message: () => "Must be a valid HTTP or HTTPS URL",
    })
  ),
  publishableKey: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Supabase publishable key is required",
    })
  ),
});

/**
 * Stripe Configuration Schema
 * Validates Stripe subscription price IDs
 */
const StripeConfigSchema = Schema.Struct({
  proPriceId: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Stripe Pro price ID is required",
    })
  ),
  maxPriceId: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Stripe Max price ID is required",
    })
  ),
  proYearlyPriceId: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Stripe Pro yearly price ID is required",
    })
  ),
  maxYearlyPriceId: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Stripe Max yearly price ID is required",
    })
  ),
});

/**
 * Security Configuration Schema
 * Validates security-related settings
 */
const SecurityConfigSchema = Schema.Struct({
  turnstileSiteKey: Schema.String.pipe(
    Schema.nonEmptyString(),
    Schema.annotations({
      message: () => "Cloudflare Turnstile site key is required",
    })
  ),
});

/**
 * Complete Application Configuration Schema
 */
const AppConfigSchema = Schema.Struct({
  supabase: SupabaseConfigSchema,
  stripe: StripeConfigSchema,
  security: SecurityConfigSchema,
});

/**
 * Application Configuration Service
 * Context.Tag for dependency injection
 */
export class AppConfig extends Context.Tag("AppConfig")<
  AppConfig,
  {
    readonly supabase: {
      readonly url: string;
      readonly publishableKey: Redacted.Redacted<string>;
    };
    readonly stripe: {
      readonly proPriceId: string;
      readonly maxPriceId: string;
      readonly proYearlyPriceId: string;
      readonly maxYearlyPriceId: string;
    };
    readonly security: {
      readonly turnstileSiteKey: Redacted.Redacted<string>;
    };
    readonly ai: {
      readonly provider: WageyAIProvider;
      readonly claudeApiKey: Redacted.Redacted<string>;
      readonly claudeModel: string;
      readonly openaiApiKey: Redacted.Redacted<string>;
      readonly openaiModel: string;
      readonly openaiRealtimeModel: string;
    };
  }
>() {}

const DEFAULT_WAGEY_PROVIDER: WageyAIProvider = "claude";
const DEFAULT_OPENAI_MODEL = "gpt-5.3-codex";
const DEFAULT_OPENAI_REALTIME_MODEL = "gpt-realtime";
const FALLBACK_UNUSED_SECRET = "__unused__";

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === "string" && value.trim().length > 0;

const normalizeProvider = (
  provider: string | undefined
): Effect.Effect<WageyAIProvider, ConfigError> => {
  const normalized = (provider ?? DEFAULT_WAGEY_PROVIDER).trim().toLowerCase();

  if (normalized === "claude" || normalized === "chatgpt") {
    return Effect.succeed(normalized);
  }

  return Effect.fail(
    new ConfigError({
      configKey: "WAGEY_AI_PROVIDER",
      reason: "invalid",
      cause: `Expected 'claude' or 'chatgpt', got '${provider ?? ""}'`,
    })
  );
};

/**
 * Load configuration from environment variables
 * Validates and transforms raw env vars into typed config
 */
const loadConfig = Effect.gen(function* () {
  const rawConfig = {
    supabase: {
      url: process.env.NEXT_PUBLIC_SUPABASE_URL,
      publishableKey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    },
    stripe: {
      proPriceId: process.env.NEXT_PUBLIC_PRO_PRICE_ID,
      maxPriceId: process.env.NEXT_PUBLIC_MAX_PRICE_ID,
      proYearlyPriceId: process.env.NEXT_PUBLIC_PRO_YEARLY_ID,
      maxYearlyPriceId: process.env.NEXT_PUBLIC_MAX_YEARLY_ID,
    },
    security: {
      turnstileSiteKey: process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY,
    },
  };

  const validated = yield* Schema.decodeUnknown(AppConfigSchema)(rawConfig).pipe(
    Effect.mapError((parseError) => {
      const errors = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ConfigError({
        configKey: "AppConfig",
        reason: "parse_failed",
        cause: errors,
      });
    })
  );

  const provider = yield* normalizeProvider(process.env.WAGEY_AI_PROVIDER);

  const claudeApiKey = process.env.CLAUDE_API_KEY?.trim();
  const claudeModel = process.env.CLAUDE_MODEL?.trim();
  const openaiApiKey = process.env.OPENAI_API_KEY?.trim();
  const openaiModel = process.env.OPENAI_MODEL?.trim() || DEFAULT_OPENAI_MODEL;
  const openaiRealtimeModel =
    process.env.OPENAI_REALTIME_MODEL?.trim() || DEFAULT_OPENAI_REALTIME_MODEL;

  if (provider === "claude") {
    if (!isNonEmptyString(claudeApiKey)) {
      return yield* Effect.fail(
        new ConfigError({
          configKey: "CLAUDE_API_KEY",
          reason: "missing",
          cause: "Claude API key is required when WAGEY_AI_PROVIDER=claude",
        })
      );
    }
    if (!isNonEmptyString(claudeModel)) {
      return yield* Effect.fail(
        new ConfigError({
          configKey: "CLAUDE_MODEL",
          reason: "missing",
          cause: "Claude model is required when WAGEY_AI_PROVIDER=claude",
        })
      );
    }
  }

  if (provider === "chatgpt" && !isNonEmptyString(openaiApiKey)) {
    return yield* Effect.fail(
      new ConfigError({
        configKey: "OPENAI_API_KEY",
        reason: "missing",
        cause: "OpenAI API key is required when WAGEY_AI_PROVIDER=chatgpt",
      })
    );
  }

  const resolvedClaudeApiKey =
    claudeApiKey ??
    (provider === "chatgpt" ? FALLBACK_UNUSED_SECRET : claudeApiKey);
  const resolvedClaudeModel =
    claudeModel ?? (provider === "chatgpt" ? "claude-opus-4-6" : claudeModel);
  const resolvedOpenAIApiKey =
    openaiApiKey ??
    (provider === "claude" ? FALLBACK_UNUSED_SECRET : openaiApiKey);

  if (!isNonEmptyString(resolvedClaudeApiKey)) {
    return yield* Effect.fail(
      new ConfigError({
        configKey: "CLAUDE_API_KEY",
        reason: "missing",
      })
    );
  }

  if (!isNonEmptyString(resolvedClaudeModel)) {
    return yield* Effect.fail(
      new ConfigError({
        configKey: "CLAUDE_MODEL",
        reason: "missing",
      })
    );
  }

  if (!isNonEmptyString(resolvedOpenAIApiKey)) {
    return yield* Effect.fail(
      new ConfigError({
        configKey: "OPENAI_API_KEY",
        reason: "missing",
      })
    );
  }

  return {
    supabase: {
      url: validated.supabase.url,
      publishableKey: Redacted.make(validated.supabase.publishableKey),
    },
    stripe: {
      proPriceId: validated.stripe.proPriceId,
      maxPriceId: validated.stripe.maxPriceId,
      proYearlyPriceId: validated.stripe.proYearlyPriceId,
      maxYearlyPriceId: validated.stripe.maxYearlyPriceId,
    },
    security: {
      turnstileSiteKey: Redacted.make(validated.security.turnstileSiteKey),
    },
    ai: {
      provider,
      claudeApiKey: Redacted.make(resolvedClaudeApiKey),
      claudeModel: resolvedClaudeModel,
      openaiApiKey: Redacted.make(resolvedOpenAIApiKey),
      openaiModel,
      openaiRealtimeModel,
    },
  };
});

/**
 * Live Layer for AppConfig
 * Provides the configuration service
 */
export const AppConfigLive = Layer.effect(AppConfig, loadConfig);

/**
 * Helper to access raw config (for backward compatibility)
 * Returns unvalidated env vars - use AppConfig service in new code
 *
 * @deprecated Use AppConfig service instead
 */
export const ENV = {
  URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  PUBLISHABLE: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  PRO_PRICE_ID: process.env.NEXT_PUBLIC_PRO_PRICE_ID,
  MAX_PRICE_ID: process.env.NEXT_PUBLIC_MAX_PRICE_ID,
  PRO_YEARLY_PRICE_ID: process.env.NEXT_PUBLIC_PRO_YEARLY_ID,
  MAX_YEARLY_PRICE_ID: process.env.NEXT_PUBLIC_MAX_YEARLY_ID,
  TURNSTILE_SITE_KEY: process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY,
  WAGEY_AI_PROVIDER: process.env.WAGEY_AI_PROVIDER,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY,
  OPENAI_MODEL: process.env.OPENAI_MODEL,
  OPENAI_REALTIME_MODEL: process.env.OPENAI_REALTIME_MODEL,
  CLAUDE_API_KEY: process.env.CLAUDE_API_KEY,
  CLAUDE_MODEL: process.env.CLAUDE_MODEL,
} as const;

/**
 * Validate environment at startup
 * Throws if configuration is invalid - use during app initialization
 */
export const validateConfig = (): void => {
  Effect.runSync(
    loadConfig.pipe(
      Effect.tapError((error) =>
        Effect.sync(() => {
          console.error("❌ Configuration validation failed:");
          console.error(`   ${error.message}`);
          console.error(`   Working directory: ${process.cwd()}`);
          if (error.cause) {
            console.error(`   Details: ${JSON.stringify(error.cause, null, 2)}`);
          }
        })
      ),
      Effect.catchAll((error) => Effect.die(error))
    )
  );
};
