import { afterEach, describe, expect, it, vi } from "vitest";
import { Effect } from "effect";
import type { Message } from "@/lib/services/claude";

const originalEnv = { ...process.env };
const originalFetch = global.fetch;

function setBaseEnv() {
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_test";
  process.env.NEXT_PUBLIC_PRO_PRICE_ID = "price_pro_test";
  process.env.NEXT_PUBLIC_MAX_PRICE_ID = "price_max_test";
  process.env.NEXT_PUBLIC_PRO_YEARLY_ID = "price_pro_yearly_test";
  process.env.NEXT_PUBLIC_MAX_YEARLY_ID = "price_max_yearly_test";
  process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY = "turnstile_test";
  process.env.WAGEY_AI_PROVIDER = "chatgpt";
  process.env.OPENAI_API_KEY = "test_openai_key";
  process.env.OPENAI_MODEL = "gpt-5.3-codex";
}

function asSseResponse(events: string): Response {
  return new Response(events, {
    status: 200,
    headers: { "Content-Type": "text/event-stream" },
  });
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

afterEach(() => {
  process.env = { ...originalEnv };
  global.fetch = originalFetch;
  vi.restoreAllMocks();
});

describe("OpenAIService streaming", () => {
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

  it("streams text chunks and done", async () => {
    setBaseEnv();
    global.fetch = vi.fn().mockResolvedValue(
      asSseResponse(
        [
          "event: response.output_text.delta",
          'data: {"type":"response.output_text.delta","delta":"Hei"}',
          "",
          "event: response.completed",
          'data: {"type":"response.completed","status":"completed"}',
          "",
        ].join("\n")
      )
    ) as typeof fetch;

    const stream = await createStream([{ role: "user", content: "Hello" }]);
    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of stream) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }

    expect(chunks.some((chunk) => chunk.type === "text")).toBe(true);
    expect(chunks.some((chunk) => chunk.type === "done")).toBe(true);
  });

  it("streams function call arguments and emits tool_use", async () => {
    setBaseEnv();
    global.fetch = vi.fn().mockResolvedValue(
      asSseResponse(
        [
          "event: response.output_item.added",
          'data: {"type":"response.output_item.added","item":{"type":"function_call","id":"item_1","call_id":"call_1","name":"manage_shift","arguments":""}}',
          "",
          "event: response.function_call_arguments.delta",
          'data: {"type":"response.function_call_arguments.delta","item_id":"item_1","delta":"{\\"action\\":\\"create\\""}',
          "",
          "event: response.function_call_arguments.delta",
          'data: {"type":"response.function_call_arguments.delta","item_id":"item_1","delta":"}"}',
          "",
          "event: response.output_item.done",
          'data: {"type":"response.output_item.done","item":{"type":"function_call","id":"item_1","call_id":"call_1","name":"manage_shift"}}',
          "",
          "event: response.completed",
          'data: {"type":"response.completed","status":"completed"}',
          "",
        ].join("\n")
      )
    ) as typeof fetch;

    const stream = await createStream([{ role: "user", content: "Add shift" }]);
    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of stream) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }

    const toolChunk = chunks.find((chunk) => chunk.type === "tool_use");
    expect(toolChunk).toBeTruthy();
    expect(toolChunk?.id).toBe("call_1");
    expect(toolChunk?.name).toBe("manage_shift");
    expect(toolChunk?.input).toEqual({ action: "create" });
  });

  it("emits INVALID_JSON when function call arguments cannot be parsed", async () => {
    setBaseEnv();
    global.fetch = vi.fn().mockResolvedValue(
      asSseResponse(
        [
          "event: response.output_item.added",
          'data: {"type":"response.output_item.added","item":{"type":"function_call","id":"item_2","call_id":"call_2","name":"manage_shift","arguments":""}}',
          "",
          "event: response.function_call_arguments.delta",
          'data: {"type":"response.function_call_arguments.delta","item_id":"item_2","delta":"{\\"action\\":"}',
          "",
          "event: response.output_item.done",
          'data: {"type":"response.output_item.done","item":{"type":"function_call","id":"item_2","call_id":"call_2","name":"manage_shift"}}',
          "",
          "event: response.completed",
          'data: {"type":"response.completed","status":"completed"}',
          "",
        ].join("\n")
      )
    ) as typeof fetch;

    const stream = await createStream([{ role: "user", content: "Add shift" }]);
    const chunks: Array<{ type: string; [key: string]: unknown }> = [];
    for await (const chunk of stream) {
      chunks.push(chunk as { type: string; [key: string]: unknown });
    }

    const toolChunk = chunks.find((chunk) => chunk.type === "tool_use");
    expect(toolChunk).toBeTruthy();
    expect((toolChunk?.input as Record<string, unknown>).INVALID_JSON).toContain(
      '{"action":'
    );
  });

  it("returns AIError on non-200 responses", async () => {
    setBaseEnv();
    global.fetch = vi.fn().mockResolvedValue(
      new Response("upstream failed", { status: 500 })
    ) as typeof fetch;

    await expect(
      createStream([{ role: "user", content: "Hello" }])
    ).rejects.toThrow(/OpenAI Responses API error: 500/);
  });
});
