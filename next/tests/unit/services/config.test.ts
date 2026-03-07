import { afterEach, describe, expect, it } from "vitest";
import { Effect } from "effect";

const originalEnv = { ...process.env };

function setBaseEnv() {
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_test";
  process.env.NEXT_PUBLIC_PRO_PRICE_ID = "price_pro_test";
  process.env.NEXT_PUBLIC_MAX_PRICE_ID = "price_max_test";
  process.env.NEXT_PUBLIC_PRO_YEARLY_ID = "price_pro_yearly_test";
  process.env.NEXT_PUBLIC_MAX_YEARLY_ID = "price_max_yearly_test";
  process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY = "turnstile_test";
}

afterEach(() => {
  process.env = { ...originalEnv };
});

describe("AppConfig OpenAI validation", () => {
  it("defaults Wagey to gpt-5.4 with medium reasoning", async () => {
    setBaseEnv();
    process.env.OPENAI_API_KEY = "test_openai_key";
    delete process.env.OPENAI_MODEL;
    delete process.env.OPENAI_REASONING_EFFORT;

    const { AppConfig, AppConfigLive } = await import("@/lib/services/config");
    const config = await Effect.runPromise(
      Effect.gen(function* () {
        return yield* AppConfig;
      }).pipe(Effect.provide(AppConfigLive), Effect.scoped)
    );

    expect(config.ai.openaiModel).toBe("gpt-5.4");
    expect(config.ai.openaiReasoningEffort).toBe("medium");
  });

  it("fails when OPENAI_API_KEY is missing", async () => {
    setBaseEnv();
    delete process.env.OPENAI_API_KEY;
    process.env.OPENAI_MODEL = "gpt-5.4";

    const { validateConfig } = await import("@/lib/services/config");
    expect(() => validateConfig()).toThrow();
  });

  it("accepts supported reasoning effort values beyond the original enum", async () => {
    setBaseEnv();
    process.env.OPENAI_API_KEY = "test_openai_key";
    process.env.OPENAI_MODEL = "gpt-5.4";
    process.env.OPENAI_REASONING_EFFORT = "xhigh";

    const { AppConfig, AppConfigLive } = await import("@/lib/services/config");
    const config = await Effect.runPromise(
      Effect.gen(function* () {
        return yield* AppConfig;
      }).pipe(Effect.provide(AppConfigLive), Effect.scoped)
    );

    expect(config.ai.openaiReasoningEffort).toBe("xhigh");
  });

  it("fails on invalid reasoning effort", async () => {
    setBaseEnv();
    process.env.OPENAI_API_KEY = "test_openai_key";
    process.env.OPENAI_REASONING_EFFORT = "extreme";

    const { validateConfig } = await import("@/lib/services/config");
    expect(() => validateConfig()).toThrow();
  });
});
