import { describe, expect, it, afterEach } from "vitest";
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

describe("AppConfig AI provider validation", () => {
  it("defaults provider to claude when WAGEY_AI_PROVIDER is unset", async () => {
    setBaseEnv();
    delete process.env.WAGEY_AI_PROVIDER;
    process.env.CLAUDE_API_KEY = "test_claude_key";
    process.env.CLAUDE_MODEL = "claude-opus-4-6";
    delete process.env.OPENAI_API_KEY;

    const { AppConfig, AppConfigLive } = await import("@/lib/services/config");
    const provider = await Effect.runPromise(
      Effect.gen(function* () {
        const config = yield* AppConfig;
        return config.ai.provider;
      }).pipe(Effect.provide(AppConfigLive), Effect.scoped)
    );

    expect(provider).toBe("claude");
  });

  it("fails when provider is chatgpt and OPENAI_API_KEY is missing", async () => {
    setBaseEnv();
    process.env.WAGEY_AI_PROVIDER = "chatgpt";
    delete process.env.OPENAI_API_KEY;
    process.env.OPENAI_MODEL = "gpt-5.3-codex";
    delete process.env.CLAUDE_API_KEY;
    delete process.env.CLAUDE_MODEL;

    const { validateConfig } = await import("@/lib/services/config");
    expect(() => validateConfig()).toThrow();
  });

  it("passes when provider is chatgpt with OPENAI_API_KEY and OPENAI_MODEL", async () => {
    setBaseEnv();
    process.env.WAGEY_AI_PROVIDER = "chatgpt";
    process.env.OPENAI_API_KEY = "test_openai_key";
    process.env.OPENAI_MODEL = "gpt-5.3-codex";
    delete process.env.CLAUDE_API_KEY;
    delete process.env.CLAUDE_MODEL;

    const { validateConfig, AppConfig, AppConfigLive } = await import(
      "@/lib/services/config"
    );

    expect(() => validateConfig()).not.toThrow();

    const provider = await Effect.runPromise(
      Effect.gen(function* () {
        const config = yield* AppConfig;
        return config.ai.provider;
      }).pipe(Effect.provide(AppConfigLive), Effect.scoped)
    );

    expect(provider).toBe("chatgpt");
  });

  it("fails when provider is claude and CLAUDE_API_KEY is missing", async () => {
    setBaseEnv();
    process.env.WAGEY_AI_PROVIDER = "claude";
    delete process.env.CLAUDE_API_KEY;
    process.env.CLAUDE_MODEL = "claude-opus-4-6";
    delete process.env.OPENAI_API_KEY;
    delete process.env.OPENAI_MODEL;

    const { validateConfig } = await import("@/lib/services/config");
    expect(() => validateConfig()).toThrow();
  });
});
