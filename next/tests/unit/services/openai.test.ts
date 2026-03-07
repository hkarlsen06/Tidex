import { afterEach, describe, expect, it, vi } from "vitest";
import { Effect } from "effect";
import type { Message } from "@/lib/services/ai-types";

const wsState = vi.hoisted(() => ({
  instances: [] as any[],
}));

vi.mock("ws", async () => {
  const { EventEmitter } = await import("node:events");

  class MockWebSocket extends EventEmitter {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;

    readyState = MockWebSocket.CONNECTING;
    sent: string[] = [];
    url: string;

    constructor(url: string) {
      super();
      this.url = url;
      wsState.instances.push(this);
      queueMicrotask(() => {
        this.readyState = MockWebSocket.OPEN;
        this.emit("open");
      });
    }

    send(data: string, callback?: (error?: Error) => void) {
      this.sent.push(data);
      callback?.();
    }

    close(code = 1000, reason = "") {
      this.readyState = MockWebSocket.CLOSED;
      queueMicrotask(() => {
        this.emit("close", code, Buffer.from(reason));
      });
    }
  }

  return {
    default: MockWebSocket,
  };
});

const originalEnv = { ...process.env };

function setBaseEnv() {
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_test";
  process.env.NEXT_PUBLIC_PRO_PRICE_ID = "price_pro_test";
  process.env.NEXT_PUBLIC_MAX_PRICE_ID = "price_max_test";
  process.env.NEXT_PUBLIC_PRO_YEARLY_ID = "price_pro_yearly_test";
  process.env.NEXT_PUBLIC_MAX_YEARLY_ID = "price_max_yearly_test";
  process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY = "turnstile_test";
  process.env.OPENAI_API_KEY = "test_openai_key";
  process.env.OPENAI_MODEL = "gpt-5.4";
  process.env.OPENAI_REASONING_EFFORT = "medium";
}

async function createSession(options?: { timeoutMs?: number }) {
  const { OpenAIService } = await import("@/lib/services/openai");
  const { OpenAILive } = await import("@/lib/layers/app");

  return Effect.runPromise(
    Effect.gen(function* () {
      const service = yield* OpenAIService;
      return yield* service.openSession(options);
    }).pipe(Effect.provide(OpenAILive), Effect.scoped)
  );
}

async function createStream(messages: Message[]) {
  const { OpenAIService } = await import("@/lib/services/openai");
  const { OpenAILive } = await import("@/lib/layers/app");

  return Effect.runPromise(
    Effect.gen(function* () {
      const service = yield* OpenAIService;
      return yield* service.streamChat({
        messages,
        system: "You are Wagey",
        tools: [
          {
            name: "manage_shift",
            description: "Manage shifts",
            input_schema: {
              type: "object",
              properties: {
                action: { type: "string" },
              },
              required: ["action"],
            },
          },
        ],
      });
    }).pipe(Effect.provide(OpenAILive), Effect.scoped)
  );
}

function emitEvent(instance: any, event: Record<string, unknown>) {
  instance.emit("message", JSON.stringify(event));
}

afterEach(() => {
  process.env = { ...originalEnv };
  wsState.instances.length = 0;
  vi.restoreAllMocks();
});

describe("OpenAIService WebSocket mode", () => {
  it("normalizes array-union tool schemas by adding items", async () => {
    const { toOpenAITools } = await import("@/lib/services/openai");

    const mapped = toOpenAITools([
      {
        name: "manage_wage_snapshots",
        description: "test",
        input_schema: {
          type: "object",
          properties: {
            supplements: {
              type: ["string", "array"],
            },
          },
          required: ["supplements"],
        },
      },
    ]);

    const params = mapped?.[0]?.parameters as {
      properties?: { supplements?: { items?: unknown } };
    };

    expect(params.properties?.supplements?.items).toEqual({});
  });

  it("sends response.create payloads with GPT-5.4 defaults", async () => {
    setBaseEnv();

    const session = await createSession();
    const responsePromise = session.createResponse({
      instructions: "You are Wagey",
      input: [{ role: "user", content: [{ type: "input_text", text: "Hello" }] }],
      maxTokens: 512,
    });

    const instance = wsState.instances[0];
    await Promise.resolve();

    const payload = JSON.parse(instance.sent[0]);
    expect(payload.type).toBe("response.create");
    expect(payload.response.model).toBe("gpt-5.4");
    expect(payload.response.reasoning).toEqual({ effort: "medium" });
    expect(payload.response.max_output_tokens).toBe(512);

    emitEvent(instance, {
      type: "response.completed",
      status: "completed",
      response: { id: "resp_1" },
    });

    const response = await responsePromise;
    await response.completed;
    await session.close();
  });

  it("streams text chunks and done", async () => {
    setBaseEnv();
    const stream = await createStream([{ role: "user", content: "Hello" }]);
    const instance = wsState.instances[0];

    emitEvent(instance, { type: "response.output_text.delta", delta: "Hei" });
    emitEvent(instance, {
      type: "response.completed",
      status: "completed",
      response: { id: "resp_1" },
    });

    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of stream) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }

    expect(chunks).toEqual([
      { type: "text", content: "Hei" },
      { type: "done", stopReason: "completed", responseId: "resp_1" },
    ]);
  });

  it("streams function call arguments and emits tool_use", async () => {
    setBaseEnv();
    const session = await createSession();
    const response = await session.createResponse({
      instructions: "You are Wagey",
      input: [{ role: "user", content: [{ type: "input_text", text: "Create shift" }] }],
      tools: [
        {
          name: "manage_shift",
          description: "Manage shifts",
          input_schema: {
            type: "object",
            properties: {
              action: { type: "string" },
            },
          },
        },
      ],
      previousResponseId: "resp_prev",
    });

    const instance = wsState.instances[0];
    const secondPayload = JSON.parse(instance.sent[0]);
    expect(secondPayload.response.previous_response_id).toBe("resp_prev");

    emitEvent(instance, {
      type: "response.output_item.added",
      item: {
        type: "function_call",
        id: "item_1",
        call_id: "call_1",
        name: "manage_shift",
        arguments: "",
      },
    });
    emitEvent(instance, {
      type: "response.function_call_arguments.delta",
      item_id: "item_1",
      delta: "{\"action\":\"create\"",
    });
    emitEvent(instance, {
      type: "response.function_call_arguments.delta",
      item_id: "item_1",
      delta: "}",
    });
    emitEvent(instance, {
      type: "response.output_item.done",
      item: {
        type: "function_call",
        id: "item_1",
        call_id: "call_1",
        name: "manage_shift",
      },
    });
    emitEvent(instance, {
      type: "response.completed",
      status: "completed",
      response: { id: "resp_1" },
    });

    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of response.events) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }
    const completion = await response.completed;

    expect(chunks[0]).toEqual({
      type: "tool_use",
      id: "call_1",
      name: "manage_shift",
      input: { action: "create" },
    });
    expect(completion.responseId).toBe("resp_1");
    await session.close();
  });

  it("emits INVALID_JSON when function call arguments cannot be parsed", async () => {
    setBaseEnv();
    const session = await createSession();
    const response = await session.createResponse({
      input: [{ role: "user", content: [{ type: "input_text", text: "Create shift" }] }],
    });

    const instance = wsState.instances[0];
    emitEvent(instance, {
      type: "response.output_item.added",
      item: {
        type: "function_call",
        id: "item_2",
        call_id: "call_2",
        name: "manage_shift",
        arguments: "",
      },
    });
    emitEvent(instance, {
      type: "response.function_call_arguments.delta",
      item_id: "item_2",
      delta: "{\"action\":",
    });
    emitEvent(instance, {
      type: "response.output_item.done",
      item: {
        type: "function_call",
        id: "item_2",
        call_id: "call_2",
        name: "manage_shift",
      },
    });
    emitEvent(instance, {
      type: "response.completed",
      status: "completed",
      response: { id: "resp_2" },
    });

    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of response.events) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }

    expect((chunks[0].input as Record<string, unknown>).INVALID_JSON).toContain(
      "{\"action\":"
    );
    await session.close();
  });

  it("fails the stream on upstream error events", async () => {
    setBaseEnv();
    const session = await createSession();
    const response = await session.createResponse({
      input: [{ role: "user", content: [{ type: "input_text", text: "Hello" }] }],
    });

    const instance = wsState.instances[0];
    emitEvent(instance, {
      type: "error",
      error: {
        message: "Upstream exploded",
      },
    });

    const iterator = response.events[Symbol.asyncIterator]();
    await expect(iterator.next()).rejects.toThrow(/Upstream exploded/);
    await expect(response.completed).rejects.toThrow(/Upstream exploded/);
    await session.close();
  });

  it("treats the timeout as inactivity-based instead of wall-clock based", async () => {
    setBaseEnv();
    vi.useFakeTimers();

    try {
      const session = await createSession({ timeoutMs: 1_000 });
      const response = await session.createResponse({
        input: [{ role: "user", content: [{ type: "input_text", text: "Hello" }] }],
      });

      const instance = wsState.instances[0];

      await vi.advanceTimersByTimeAsync(900);
      emitEvent(instance, { type: "response.output_text.delta", delta: "A" });

      await vi.advanceTimersByTimeAsync(900);
      emitEvent(instance, { type: "response.output_text.delta", delta: "B" });

      await vi.advanceTimersByTimeAsync(900);
      emitEvent(instance, {
        type: "response.completed",
        status: "completed",
        response: { id: "resp_timeout_reset" },
      });

      const chunks: Array<{ type: string; [key: string]: unknown }> = [];
      for await (const chunk of response.events) {
        chunks.push(chunk as { type: string; [key: string]: unknown });
      }

      expect(chunks).toEqual([
        { type: "text", content: "A" },
        { type: "text", content: "B" },
        {
          type: "done",
          stopReason: "completed",
          responseId: "resp_timeout_reset",
        },
      ]);

      await session.close();
    } finally {
      vi.useRealTimers();
    }
  });

  it("fails active responses when the socket closes normally before completion", async () => {
    setBaseEnv();
    const session = await createSession();
    const response = await session.createResponse({
      input: [{ role: "user", content: [{ type: "input_text", text: "Hello" }] }],
    });

    const instance = wsState.instances[0];
    instance.close(1000, "server_shutdown");
    await Promise.resolve();

    const iterator = response.events[Symbol.asyncIterator]();
    await expect(iterator.next()).rejects.toThrow(/closed before the response completed/);
    await expect(response.completed).rejects.toThrow(/closed before the response completed/);
  });
});
