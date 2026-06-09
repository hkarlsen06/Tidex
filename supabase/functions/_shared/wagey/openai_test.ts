import { assertEquals } from "jsr:@std/assert";

import type { StreamChunk } from "./ai-types.ts";
import {
  DEFAULT_OPENAI_MODEL,
  DEFAULT_OPENAI_STREAM_IDLE_TIMEOUT_MS,
  resolveOpenAIModel,
  streamOpenAIChat,
} from "./openai.ts";

function createSseResponse(events: Record<string, unknown>[]): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const event of events) {
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
        );
      }
      controller.close();
    },
  });

  return new Response(body, { status: 200 });
}

Deno.test("streamOpenAIChat parses text, citations, web search, and function tools", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        type: "response.output_item.added",
        output_index: 0,
        item: {
          type: "web_search_call",
          id: "search_1",
          action: { query: "HK Virke tariff 2026" },
        },
      },
      {
        type: "response.output_item.done",
        output_index: 0,
        item: {
          type: "web_search_call",
          id: "search_1",
          results: [
            {
              title: "Tariffavtalen",
              url: "https://example.com/tariff",
            },
          ],
        },
      },
      {
        type: "response.output_item.added",
        output_index: 1,
        item: { type: "message", id: "msg_1" },
      },
      {
        type: "response.output_text.delta",
        delta: "Live tariff found.",
      },
      {
        type: "response.output_text.annotation.added",
        annotation: {
          type: "url_citation",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
        },
      },
      {
        type: "response.output_item.added",
        output_index: 2,
        item: {
          type: "function_call",
          id: "fc_1",
          call_id: "tool_1",
          name: "get_wage_info",
        },
      },
      {
        type: "response.function_call_arguments.delta",
        output_index: 2,
        delta: '{"jobId":',
      },
      {
        type: "response.function_call_arguments.done",
        output_index: 2,
        arguments: '{"jobId":null}',
      },
      {
        type: "response.completed",
        response: { status: "completed" },
      },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (
      const chunk of streamOpenAIChat({
        apiKey: "test-key",
        model: DEFAULT_OPENAI_MODEL,
        messages: [{ role: "user", content: "Matcher lønna?" }],
        tools: [
          {
            name: "get_wage_info",
            description: "Get wage info",
            input_schema: {
              type: "object",
              properties: {},
            },
          },
          {
            type: "web_search_20260209",
            name: "web_search",
            max_uses: 3,
          },
        ],
      })
    ) {
      chunks.push(chunk);
    }

    assertEquals(chunks[0], {
      type: "built_in_tool_start",
      id: "search_1",
      name: "web_search",
      input: { query: "HK Virke tariff 2026" },
    });
    assertEquals(chunks[1], {
      type: "sources",
      items: [
        {
          id: "https://example.com/tariff",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          domain: "example.com",
        },
      ],
    });
    assertEquals(chunks[2], {
      type: "built_in_tool_result",
      id: "search_1",
      name: "web_search",
      success: true,
      summary: {
        tool: "web_search",
        resultCount: 1,
        urls: ["https://example.com/tariff"],
      },
      result: {
        type: "web_search_tool_result",
        tool_use_id: "search_1",
        content: [
          {
            type: "web_search_result",
            title: "Tariffavtalen",
            url: "https://example.com/tariff",
          },
        ],
      },
    });
    assertEquals(chunks[3], { type: "text_start" });
    assertEquals(chunks[4], {
      type: "text",
      content: "Live tariff found.",
    });
    assertEquals(chunks[5], {
      type: "tool_use_start",
      id: "tool_1",
      name: "get_wage_info",
      input: {},
    });
    assertEquals(chunks[6], {
      type: "tool_use",
      id: "tool_1",
      name: "get_wage_info",
      input: { jobId: null },
    });
    assertEquals(chunks[7], {
      type: "text",
      content: "",
      citations: [
        {
          type: "url_citation",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          cited_text: undefined,
          document_title: undefined,
          encrypted_index: undefined,
        },
      ],
    });
    assertEquals(chunks[8], {
      type: "sources",
      items: [
        {
          id: "https://example.com/tariff",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          domain: "example.com",
        },
      ],
    });
    assertEquals(chunks[9], {
      type: "done",
      stopReason: "completed",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamOpenAIChat sends Responses API request shape", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | null = null;

  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    capturedBody = JSON.parse(request?.body ?? "{}") as Record<
      string,
      unknown
    >;
    return createSseResponse([
      {
        type: "response.completed",
        response: { status: "completed" },
      },
    ]);
  };

  try {
    for await (
      const _chunk of streamOpenAIChat({
        apiKey: "test-key",
        model: DEFAULT_OPENAI_MODEL,
        system: "You are Wagey.",
        messages: [{ role: "user", content: "Hei" }],
      })
    ) {
      // Exhaust the stream so the request completes.
    }

    if (!capturedBody) {
      throw new Error("Expected OpenAI request body to be captured");
    }

    const requestBody = capturedBody as Record<string, unknown>;
    assertEquals(requestBody.model, DEFAULT_OPENAI_MODEL);
    assertEquals(requestBody.instructions, "You are Wagey.");
    assertEquals(requestBody.stream, true);
    assertEquals(requestBody.reasoning, { effort: "medium" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamOpenAIChat preserves action-dependent optional tool schemas", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | null = null;

  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    capturedBody = JSON.parse(request?.body ?? "{}") as Record<
      string,
      unknown
    >;
    return createSseResponse([
      {
        type: "response.completed",
        response: { status: "completed" },
      },
    ]);
  };

  try {
    for await (
      const _chunk of streamOpenAIChat({
        apiKey: "test-key",
        model: DEFAULT_OPENAI_MODEL,
        messages: [{ role: "user", content: "Lag en vakt i morgen" }],
        tools: [
          {
            name: "manage_shift",
            description: "Create, update, or delete shifts.",
            input_schema: {
              type: "object",
              properties: {
                action: {
                  type: "string",
                  enum: ["create", "update", "delete"],
                },
                dates: { type: "array", items: { type: "string" } },
                start: { type: "string" },
                end: { type: "string" },
                shiftId: { type: "string" },
              },
              required: ["action"],
            },
          },
          {
            type: "web_fetch_20260209",
            name: "web_fetch",
          },
          {
            name: "manage_recurring_exclusion",
            description: "Add or remove an excluded date.",
            strict: true,
            input_schema: {
              type: "object",
              properties: {
                recurringId: { type: "string" },
                date: { type: "string" },
                action: { type: "string", enum: ["add", "remove"] },
              },
              required: ["recurringId", "date", "action"],
            },
          },
        ],
      })
    ) {
      // Exhaust the stream so the request completes.
    }

    if (!capturedBody) {
      throw new Error("Expected OpenAI request body to be captured");
    }

    const tools = (capturedBody as { tools: Array<Record<string, unknown>> })
      .tools;
    const manageShift = tools.find((tool) => tool.name === "manage_shift");
    const webFetch = tools.find((tool) => tool.name === "web_fetch");
    const recurringExclusion = tools.find((tool) =>
      tool.name === "manage_recurring_exclusion"
    );

    assertEquals(manageShift?.strict, false);
    assertEquals(recurringExclusion?.strict, true);
    assertEquals(
      (recurringExclusion?.parameters as { additionalProperties?: boolean })
        .additionalProperties,
      false,
    );
    assertEquals(webFetch?.strict, true);
    assertEquals(
      (webFetch?.parameters as { additionalProperties?: boolean })
        .additionalProperties,
      false,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamOpenAIChat serializes assistant history as output_text", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: Record<string, unknown> | null = null;

  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    capturedBody = JSON.parse(request?.body ?? "{}") as Record<
      string,
      unknown
    >;
    return createSseResponse([
      {
        type: "response.completed",
        response: { status: "completed" },
      },
    ]);
  };

  try {
    for await (
      const _chunk of streamOpenAIChat({
        apiKey: "test-key",
        model: DEFAULT_OPENAI_MODEL,
        messages: [
          { role: "user", content: "Hei" },
          {
            role: "assistant",
            content: [{ type: "text", text: "Hei!" }],
          },
          {
            role: "user",
            content: [{
              type: "tool_result",
              tool_use_id: "tool_1",
              content: '{"success":true}',
            }],
          },
        ],
      })
    ) {
      // Exhaust the stream so the request completes.
    }

    if (!capturedBody) {
      throw new Error("Expected OpenAI request body to be captured");
    }

    const input = (capturedBody as { input: Array<Record<string, unknown>> })
      .input;
    assertEquals(input[1], {
      role: "assistant",
      content: [{ type: "output_text", text: "Hei!" }],
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("resolveOpenAIModel defaults to GPT-5.5", () => {
  assertEquals(resolveOpenAIModel("gpt-5.5"), "gpt-5.5");
  assertEquals(resolveOpenAIModel("gpt-5.5-2026-05-01"), "gpt-5.5-2026-05-01");
  assertEquals(resolveOpenAIModel(""), DEFAULT_OPENAI_MODEL);
});

Deno.test("streamOpenAIChat allows long reasoning pauses", () => {
  assertEquals(DEFAULT_OPENAI_STREAM_IDLE_TIMEOUT_MS, 120_000);
});

Deno.test("streamOpenAIChat sanitizes idle timeout errors", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      new ReadableStream<Uint8Array>({
        start() {
          // Keep the upstream response open without emitting SSE events.
        },
      }),
      { status: 200 },
    );

  try {
    let caught: Error | null = null;

    try {
      for await (
        const _chunk of streamOpenAIChat({
          apiKey: "test-key",
          model: DEFAULT_OPENAI_MODEL,
          messages: [{ role: "user", content: "Hei" }],
          idleTimeoutMs: 5,
        })
      ) {
        // No chunks expected.
      }
    } catch (error) {
      caught = error as Error;
    }

    if (!caught) {
      throw new Error("Expected idle timeout error");
    }

    assertEquals(caught.name, "OpenAIProviderError");
    assertEquals(
      (caught as Error & { providerType?: string }).providerType,
      "stream_idle_timeout",
    );
    assertEquals(
      (caught as Error & { publicMessage?: string }).publicMessage,
      "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamOpenAIChat sanitizes provider errors", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: {
          type: "insufficient_quota",
          message: "Billing quota exceeded.",
        },
      }),
      {
        status: 429,
        headers: { "Content-Type": "application/json" },
      },
    );

  try {
    let caught: Error | null = null;

    try {
      for await (
        const _chunk of streamOpenAIChat({
          apiKey: "test-key",
          model: DEFAULT_OPENAI_MODEL,
          messages: [{ role: "user", content: "Hei" }],
        })
      ) {
        // No chunks expected.
      }
    } catch (error) {
      caught = error as Error;
    }

    if (!caught) {
      throw new Error("Expected provider error");
    }

    assertEquals(caught.name, "OpenAIProviderError");
    assertEquals(
      (caught as Error & { publicMessage?: string }).publicMessage,
      "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
