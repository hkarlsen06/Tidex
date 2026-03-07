import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Effect, Layer, Context } from "effect";
import { NextRequest } from "next/server";
import { parseSSEMessage } from "@/lib/river/helpers";

const mocks = vi.hoisted(() => ({
  beginWageyTurn: vi.fn(),
  executeTool: vi.fn(),
}));

class MockAuthService extends Context.Tag("AuthService")<
  MockAuthService,
  {
    readonly verifyUserId: (userId: string) => Effect.Effect<{ id: string }, never, never>;
  }
>() {}

const mockSession = {
  createResponse: vi.fn(),
  close: vi.fn(),
};

vi.mock("@/lib/services/auth", () => ({
  AuthService: MockAuthService,
}));

vi.mock("@/lib/layers/app", async () => {
  const { OpenAIService } = await import("@/lib/services/openai");

  return {
    SupabaseAuthLive: Layer.succeed(MockAuthService, {
      verifyUserId: (userId: string) => Effect.succeed({ id: userId }),
    }),
    OpenAILive: Layer.succeed(OpenAIService, {
      openSession: () => Effect.succeed(mockSession),
      streamChat: vi.fn(),
    }),
  };
});

vi.mock("@/data-access/wagey", () => ({
  beginWageyTurn: mocks.beginWageyTurn,
}));

vi.mock("@/lib/chat/executor", () => ({
  executeTool: mocks.executeTool,
}));

function createStream(
  chunks: Array<Record<string, unknown>>,
  responseId: string
) {
  return {
    events: {
      async *[Symbol.asyncIterator]() {
        for (const chunk of chunks) {
          yield chunk;
        }
      },
    },
    completed: Promise.resolve({
      responseId,
      stopReason: "completed",
    }),
  };
}

function parseChunkItems(payload: string) {
  return payload
    .split("\n\n")
    .map((message) => parseSSEMessage(message))
    .filter(Boolean)
    .filter((item) => item?.type === "chunk");
}

describe("/api/chat route", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    mocks.beginWageyTurn.mockResolvedValue({
      access: {
        level: "pro",
        hasAccess: true,
        limit: 20,
        used: 4,
        remaining: 16,
        bonus: 1,
        resetDate: "2026-04-01",
      },
      invocation: {
        allowed: true,
        count: 5,
        remaining: 15,
        bonus: 1,
      },
    });
    mocks.executeTool.mockResolvedValue({
      success: true,
      message: "Created shift",
      data: { id: "shift_1" },
    });

    mockSession.createResponse
      .mockResolvedValueOnce(
        createStream(
          [
            { type: "text", content: "Checking your shifts. " },
            {
              type: "tool_use",
              id: "call_1",
              name: "manage_shift",
              input: { action: "create", dates: ["2026-03-08"] },
            },
          ],
          "resp_1"
        )
      )
      .mockResolvedValueOnce(
        createStream(
          [{ type: "text", content: "Done. Your shift is added." }],
          "resp_2"
        )
      );
    mockSession.close.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.resetModules();
  });

  it("keeps the public SSE contract while chaining tool rounds with previous_response_id", async () => {
    const { POST } = await import("@/app/api/chat/route");

    const request = new NextRequest("http://localhost/api/chat", {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify({
        routerStreamKey: "wagey",
        input: {
          messages: [
            {
              role: "user",
              content: "Add a shift tomorrow from 08:00 to 16:00",
            },
          ],
          userId: "032d8c2a-9af6-4777-99f0-24e2c4058bf3",
          userName: "Hjalmar",
        },
      }),
    });

    const response = await POST(request);
    expect(response.status).toBe(200);

    const body = await response.text();
    const chunkItems = parseChunkItems(body);
    const chunks = chunkItems.map((item) => item?.chunk);

    expect(chunks).toEqual(
      expect.arrayContaining([
        { type: "status", status: "thinking" },
        { type: "text", content: "Checking your shifts. " },
        {
          type: "tool_start",
          toolName: "manage_shift",
          toolCallId: "call_1",
          toolArguments: "{\"action\":\"create\",\"dates\":[\"2026-03-08\"]}",
        },
        {
          type: "tool_result",
          toolName: "manage_shift",
          toolCallId: "call_1",
          result: "{\"success\":true,\"message\":\"Created shift\",\"data\":{\"id\":\"shift_1\"}}",
          success: true,
        },
        { type: "status", status: "thinking" },
        { type: "text", content: "Done. Your shift is added." },
        {
          type: "wagey_limit",
          remaining: 15,
          resetDays: expect.any(Number),
          exceeded: false,
          bonus: 1,
        },
        { type: "done" },
      ])
    );

    expect(mockSession.createResponse).toHaveBeenCalledTimes(2);
    expect(mockSession.createResponse.mock.calls[1][0].previousResponseId).toBe("resp_1");
    expect(mockSession.createResponse.mock.calls[1][0].input).toEqual([
      {
        type: "function_call_output",
        call_id: "call_1",
        output: "{\"success\":true,\"message\":\"Created shift\",\"data\":{\"id\":\"shift_1\"}}",
      },
    ]);
    expect(mockSession.close).toHaveBeenCalled();
  });

  it("executes parallel-safe tool rounds concurrently and preserves the SSE contract", async () => {
    const { POST } = await import("@/app/api/chat/route");

    let firstResolved = false;
    let secondStarted = false;

    mockSession.createResponse
      .mockReset()
      .mockResolvedValueOnce(
        createStream(
          [
            {
              type: "tool_use",
              id: "call_query",
              name: "query_shifts",
              input: { startDate: "2026-03-01", endDate: "2026-03-31" },
            },
            {
              type: "tool_use",
              id: "call_stats",
              name: "get_statistics",
              input: { metric: "current_month" },
            },
          ],
          "resp_parallel_1"
        )
      )
      .mockResolvedValueOnce(
        createStream(
          [{ type: "text", content: "Here is the overview." }],
          "resp_parallel_2"
        )
      );

    mocks.executeTool.mockImplementation(async (toolName: string) => {
      if (toolName === "query_shifts") {
        await new Promise((resolve) => setTimeout(resolve, 25));
        firstResolved = true;
        return {
          success: true,
          message: "Fetched shifts",
        };
      }

      secondStarted = true;
      expect(firstResolved).toBe(false);
      return {
        success: true,
        message: "Fetched statistics",
      };
    });

    const request = new NextRequest("http://localhost/api/chat", {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify({
        routerStreamKey: "wagey",
        input: {
          messages: [
            {
              role: "user",
              content: "Summarize this month and list my shifts",
            },
          ],
          userId: "032d8c2a-9af6-4777-99f0-24e2c4058bf3",
        },
      }),
    });

    const response = await POST(request);
    expect(response.status).toBe(200);

    const body = await response.text();
    expect(secondStarted).toBe(true);
    const chunkItems = parseChunkItems(body);
    const chunks = chunkItems.map((item) => item?.chunk);

    expect(chunks).toEqual(
      expect.arrayContaining([
        {
          type: "tool_result",
          toolName: "query_shifts",
          toolCallId: "call_query",
          result: "{\"success\":true,\"message\":\"Fetched shifts\"}",
          success: true,
        },
        {
          type: "tool_result",
          toolName: "get_statistics",
          toolCallId: "call_stats",
          result: "{\"success\":true,\"message\":\"Fetched statistics\"}",
          success: true,
        },
        { type: "text", content: "Here is the overview." },
      ])
    );
    expect(mockSession.createResponse).toHaveBeenCalledTimes(2);
  });
});
