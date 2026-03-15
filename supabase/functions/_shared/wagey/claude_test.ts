import { assertEquals } from "jsr:@std/assert";

import { streamClaudeChat } from "./claude.ts";
import type { StreamChunk } from "./ai-types.ts";

function createSseResponse(events: Record<string, unknown>[]): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const event of events) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
      }
      controller.close();
    },
  });

  return new Response(body, { status: 200 });
}

Deno.test("streamClaudeChat parses Anthropic built-in tools, citations, and function tools", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        type: "content_block_start",
        content_block: {
          type: "server_tool_use",
          id: "search_1",
          name: "web_search",
          input: { query: "HK Virke tariff 2026" },
        },
      },
      { type: "content_block_stop" },
      {
        type: "content_block_start",
        content_block: {
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
      },
      { type: "content_block_stop" },
      {
        type: "content_block_start",
        content_block: { type: "text" },
      },
      {
        type: "content_block_delta",
        delta: { type: "text_delta", text: "Live tariff found." },
      },
      {
        type: "content_block_delta",
        delta: {
          type: "citations_delta",
          citation: {
            type: "web_search_result_location",
            title: "Tariffavtalen",
            url: "https://example.com/tariff",
          },
        },
      },
      { type: "content_block_stop" },
      {
        type: "content_block_start",
        content_block: {
          type: "tool_use",
          id: "tool_1",
          name: "get_wage_info",
        },
      },
      {
        type: "content_block_delta",
        delta: {
          type: "input_json_delta",
          partial_json: "{\"jobId\":null}",
        },
      },
      { type: "content_block_stop" },
      {
        type: "message_delta",
        delta: { stop_reason: "tool_use" },
      },
      { type: "message_stop" },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (const chunk of streamClaudeChat({
      apiKey: "test-key",
      model: "claude-opus-4-6",
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
    })) {
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
    assertEquals(chunks[3], {
      type: "text_start",
    });
    assertEquals(chunks[4], {
      type: "text",
      content: "Live tariff found.",
    });
    assertEquals(chunks[5], {
      type: "text",
      content: "",
      citations: [
        {
          type: "web_search_result_location",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          cited_text: undefined,
          document_title: undefined,
          encrypted_index: undefined,
        },
      ],
    });
    assertEquals(chunks[6], {
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
    assertEquals(chunks[7], {
      type: "tool_use_start",
      id: "tool_1",
      name: "get_wage_info",
      input: {},
    });
    assertEquals(chunks[8], {
      type: "tool_use",
      id: "tool_1",
      name: "get_wage_info",
      input: { jobId: null },
    });
    assertEquals(chunks[9], {
      type: "done",
      stopReason: "tool_use",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamClaudeChat enables extended thinking with low effort", async () => {
  const originalFetch = globalThis.fetch;
  let capturedBody: { thinking?: unknown; output_config?: unknown } | null = null;

  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    capturedBody = JSON.parse(request?.body ?? "{}") as {
      thinking?: unknown;
      output_config?: unknown;
    };
    return createSseResponse([
      {
        type: "message_delta",
        delta: { stop_reason: "end_turn" },
      },
      { type: "message_stop" },
    ]);
  };

  try {
    for await (const _chunk of streamClaudeChat({
      apiKey: "test-key",
      model: "claude-opus-4-6",
      messages: [{ role: "user", content: "Hei" }],
    })) {
      // Exhaust the stream so the request completes.
    }

    if (!capturedBody) {
      throw new Error("Expected Claude request body to be captured");
    }

    const requestBody = capturedBody as Record<string, unknown>;
    assertEquals(requestBody["thinking"], { type: "adaptive" });
    assertEquals(requestBody["output_config"], { effort: "low" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamClaudeChat fails fast when the Claude stream goes idle", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () => {
    const body = new ReadableStream<Uint8Array>({
      start() {
        // Intentionally keep the stream open without emitting any bytes.
      },
    });

    return new Response(body, { status: 200 });
  };

  try {
    let caught: Error | null = null;

    try {
      for await (const _chunk of streamClaudeChat({
        apiKey: "test-key",
        model: "claude-opus-4-6",
        messages: [{ role: "user", content: "Hei" }],
        idleTimeoutMs: 10,
      })) {
        // No chunks expected.
      }
    } catch (error) {
      caught = error as Error;
    }

    if (!caught) {
      throw new Error("Expected idle timeout error");
    }

    assertEquals(caught.message, "Claude stream was idle for more than 10ms");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamClaudeChat emits thinking_start when Anthropic opens a thinking block", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        type: "content_block_start",
        content_block: { type: "thinking" },
      },
      {
        type: "content_block_delta",
        delta: { type: "thinking_delta", thinking: "Checking sources" },
      },
      {
        type: "content_block_delta",
        delta: { type: "signature_delta", signature: "sig_1" },
      },
      { type: "content_block_stop" },
      { type: "message_delta", delta: { stop_reason: "end_turn" } },
      { type: "message_stop" },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (const chunk of streamClaudeChat({
      apiKey: "test-key",
      model: "claude-opus-4-6",
      messages: [{ role: "user", content: "Hei" }],
    })) {
      chunks.push(chunk);
    }

    assertEquals(chunks[0], { type: "thinking_start" });
    assertEquals(chunks[1], {
      type: "thinking",
      thinking: "Checking sources",
      signature: "sig_1",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamClaudeChat sanitizes Anthropic billing errors into provider errors", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        type: "error",
        error: {
          type: "invalid_request_error",
          message:
            "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.",
        },
        request_id: "req_test_low_credit",
      }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );

  try {
    let caught: Error | null = null;

    try {
      for await (const _chunk of streamClaudeChat({
        apiKey: "test-key",
        model: "claude-opus-4-6",
        messages: [{ role: "user", content: "Hei" }],
      })) {
        // No chunks expected.
      }
    } catch (error) {
      caught = error as Error;
    }

    if (!caught) {
      throw new Error("Expected provider error");
    }

    assertEquals(caught.name, "ClaudeProviderError");
    assertEquals(
      (caught as Error & { publicMessage?: string }).publicMessage,
      "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
