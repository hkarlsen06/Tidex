import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Context, Effect, Layer } from "effect";
import { AuthError, DatabaseError } from "@/lib/errors/tagged";

const mocks = vi.hoisted(() => ({
  beginTurn: vi.fn(),
  loggerError: vi.fn(),
}));

class MockWageyService extends Context.Tag("WageyService")<
  MockWageyService,
  {
    readonly beginTurn: (userId: string) => Effect.Effect<unknown, unknown, never>;
    readonly getWageyAccess: () => Effect.Effect<unknown, never, never>;
    readonly useInvocation: () => Effect.Effect<unknown, never, never>;
  }
>() {}

vi.mock("@/lib/services/wagey", () => ({
  WageyService: MockWageyService,
}));

vi.mock("@/lib/layers/app", () => ({
  WageyLive: Layer.succeed(MockWageyService, {
    beginTurn: (userId: string) => mocks.beginTurn(userId),
    getWageyAccess: () => Effect.succeed({}),
    useInvocation: () => Effect.succeed({}),
  }),
}));

vi.mock("@/lib/logger", () => ({
  logger: {
    error: mocks.loggerError,
  },
}));

vi.mock("@/data-access/auth", () => ({
  verifySession: vi.fn(),
}));

describe("beginWageyTurn", () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetModules();
  });

  it("falls back to degraded usage state on database failures", async () => {
    mocks.beginTurn.mockReturnValue(
      Effect.fail(
        new DatabaseError({
          query: "increment_wagey_invocation",
          errorMessage: "RPC failed",
        })
      )
    );

    const { beginWageyTurn } = await import("@/data-access/wagey");

    await expect(beginWageyTurn(userId)).resolves.toEqual({
      access: {
        level: "free",
        hasAccess: false,
        limit: 0,
        used: 0,
        remaining: 0,
        bonus: 0,
        resetDate: null,
      },
      invocation: {
        allowed: false,
        count: 0,
        remaining: 0,
        bonus: 0,
      },
    });
  });

  it("still surfaces authentication failures", async () => {
    mocks.beginTurn.mockReturnValue(
      Effect.fail(
        new AuthError({
          reason: "invalid_session",
        })
      )
    );

    const { beginWageyTurn } = await import("@/data-access/wagey");

    await expect(beginWageyTurn(userId)).rejects.toThrow(
      "Invalid or expired session"
    );
  });
});
