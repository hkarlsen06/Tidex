import { assertEquals, assertRejects } from "jsr:@std/assert";

import type { StreamChunk } from "./ai-types.ts";
import { MistralProviderError, streamMistralChat } from "./mistral.ts";

type SseRecord = {
  event: string;
  data: Record<string, unknown>;
};

function createSseResponse(records: SseRecord[]): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const record of records) {
        controller.enqueue(
          encoder.encode(
            `event: ${record.event}\ndata: ${JSON.stringify(record.data)}\n\n`,
          ),
        );
      }
      controller.close();
    },
  });

  return new Response(body, { status: 200 });
}

Deno.test("streamMistralChat parses function-call deltas into tool chunks", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "conversation.response.started",
        data: {
          type: "conversation.response.started",
          conversation_id: "conv_test",
        },
      },
      {
        event: "function.call.delta",
        data: {
          type: "function.call.delta",
          id: "fc_test",
          tool_call_id: "mELkEWxGf",
          model: "mistral-large-2512",
          name: "get_wage_info",
          arguments: '{"jobId":',
        },
      },
      {
        event: "function.call.delta",
        data: {
          type: "function.call.delta",
          id: "fc_test",
          tool_call_id: "mELkEWxGf",
          model: "mistral-large-2512",
          name: "get_wage_info",
          arguments: "null}",
        },
      },
      {
        event: "conversation.response.done",
        data: {
          type: "conversation.response.done",
          usage: { total_tokens: 10 },
        },
      },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (
      const chunk of streamMistralChat({
        apiKey: "test-key",
        instructions: "You are Wagey.",
        inputs: [{ role: "user", content: "Hei" }],
      })
    ) {
      chunks.push(chunk);
    }

    assertEquals(chunks[0], {
      type: "tool_use_start",
      id: "mELkEWxGf",
      name: "get_wage_info",
      input: {},
    });
    assertEquals(chunks[1], {
      type: "tool_use",
      id: "mELkEWxGf",
      name: "get_wage_info",
      input: { jobId: null },
    });
    assertEquals(chunks[2], {
      type: "done",
      stopReason: "tool_use",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat maps built-in web_search executions and tool references", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "conversation.response.started",
        data: {
          type: "conversation.response.started",
          conversation_id: "conv_search",
        },
      },
      {
        event: "tool.execution.started",
        data: {
          type: "tool.execution.started",
          id: "tool_exec_1",
          name: "web_search",
          function: "web_search",
          arguments: '{"',
        },
      },
      {
        event: "tool.execution.delta",
        data: {
          type: "tool.execution.delta",
          id: "tool_exec_1",
          name: "web_search",
          function: "web_search",
          arguments: 'query": "current VAT rate in Norway 2026"}',
        },
      },
      {
        event: "tool.execution.done",
        data: {
          type: "tool.execution.done",
          id: "tool_exec_1",
          name: "web_search",
          function: "web_search",
          info: {},
        },
      },
      {
        event: "message.output.delta",
        data: {
          type: "message.output.delta",
          id: "msg_1",
          output_index: 1,
          content_index: 0,
          role: "assistant",
          content: "The standard VAT rate in Norway is 25%.",
        },
      },
      {
        event: "message.output.delta",
        data: {
          type: "message.output.delta",
          id: "msg_1",
          output_index: 1,
          content_index: 1,
          role: "assistant",
          content: {
            type: "tool_reference",
            tool: "web_search",
            title: "Norwegian VAT Rates for 2026",
            url: "https://example.com/norway-vat",
            description: "The standard VAT rate is 25%.",
          },
        },
      },
      {
        event: "conversation.response.done",
        data: {
          type: "conversation.response.done",
          usage: { total_tokens: 20 },
        },
      },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (
      const chunk of streamMistralChat({
        apiKey: "test-key",
        instructions: "You are Wagey.",
        inputs: [{ role: "user", content: "Hei" }],
        tools: [{ type: "web_search", name: "web_search" }],
      })
    ) {
      chunks.push(chunk);
    }

    assertEquals(chunks[0], {
      type: "built_in_tool_start",
      id: "tool_exec_1",
      name: "web_search",
      input: {},
    });
    assertEquals(chunks[1], { type: "text_start" });
    assertEquals(chunks[2], {
      type: "text",
      content: "The standard VAT rate in Norway is 25%.",
    });
    assertEquals(chunks[3], {
      type: "sources",
      items: [{
        id: "https://example.com/norway-vat",
        title: "Norwegian VAT Rates for 2026",
        url: "https://example.com/norway-vat",
        domain: "example.com",
      }],
    });
    assertEquals(chunks[4], {
      type: "built_in_tool_result",
      id: "tool_exec_1",
      name: "web_search",
      success: true,
      summary: {
        tool: "web_search",
        resultCount: 1,
        urls: ["https://example.com/norway-vat"],
      },
      result: {
        type: "web_search_tool_result",
        tool_use_id: "tool_exec_1",
        content: [{
          type: "web_search_result",
          title: "Norwegian VAT Rates for 2026",
          url: "https://example.com/norway-vat",
        }],
      },
    });
    assertEquals(chunks[5], {
      type: "done",
      stopReason: "end_turn",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat emits results for multiple built-in web searches", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "tool.execution.started",
        data: {
          type: "tool.execution.started",
          id: "tool_exec_1",
          name: "web_search",
          function: "web_search",
          arguments: '{"',
        },
      },
      {
        event: "tool.execution.done",
        data: {
          type: "tool.execution.done",
          id: "tool_exec_1",
          name: "web_search",
          function: "web_search",
          info: {},
        },
      },
      {
        event: "tool.execution.started",
        data: {
          type: "tool.execution.started",
          id: "tool_exec_2",
          name: "web_search",
          function: "web_search",
          arguments: '{"',
        },
      },
      {
        event: "tool.execution.done",
        data: {
          type: "tool.execution.done",
          id: "tool_exec_2",
          name: "web_search",
          function: "web_search",
          info: {},
        },
      },
      {
        event: "message.output.delta",
        data: {
          type: "message.output.delta",
          id: "msg_multi",
          output_index: 1,
          content_index: 0,
          role: "assistant",
          content: {
            type: "tool_reference",
            tool: "web_search",
            title: "First source",
            url: "https://example.com/one",
          },
        },
      },
      {
        event: "message.output.delta",
        data: {
          type: "message.output.delta",
          id: "msg_multi",
          output_index: 1,
          content_index: 1,
          role: "assistant",
          content: {
            type: "tool_reference",
            tool: "web_search",
            title: "Second source",
            url: "https://example.com/two",
          },
        },
      },
      {
        event: "conversation.response.done",
        data: {
          type: "conversation.response.done",
          usage: { total_tokens: 10 },
        },
      },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (
      const chunk of streamMistralChat({
        apiKey: "test-key",
        instructions: "You are Wagey.",
        inputs: [{ role: "user", content: "Hei" }],
        tools: [{ type: "web_search", name: "web_search" }],
      })
    ) {
      chunks.push(chunk);
    }

    assertEquals(
      chunks.filter((chunk) => chunk.type === "built_in_tool_result").map((
        chunk,
      ) => chunk.id),
      ["tool_exec_1", "tool_exec_2"],
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat falls back to INVALID_JSON when tool arguments are malformed", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "function.call.delta",
        data: {
          type: "function.call.delta",
          id: "fc_bad",
          tool_call_id: "Qf5c2uPMc",
          model: "mistral-large-2512",
          name: "ping",
          arguments: '{"value": "broken"',
        },
      },
      {
        event: "conversation.response.done",
        data: {
          type: "conversation.response.done",
          usage: { total_tokens: 5 },
        },
      },
    ]);

  try {
    const chunks: StreamChunk[] = [];
    for await (
      const chunk of streamMistralChat({
        apiKey: "test-key",
        instructions: "You are Wagey.",
        inputs: [{ role: "user", content: "Hei" }],
      })
    ) {
      chunks.push(chunk);
    }

    assertEquals(chunks[1], {
      type: "tool_use",
      id: "Qf5c2uPMc",
      name: "ping",
      input: { INVALID_JSON: '{"value": "broken"' },
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat fails fast when the stream goes idle", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () => {
    const body = new ReadableStream<Uint8Array>({
      start() {
        // Keep the stream open without emitting bytes.
      },
    });

    return new Response(body, { status: 200 });
  };

  try {
    await assertRejects(
      async () => {
        for await (
          const _chunk of streamMistralChat({
            apiKey: "test-key",
            instructions: "You are Wagey.",
            inputs: [{ role: "user", content: "Hei" }],
            idleTimeoutMs: 10,
          })
        ) {
          // No chunks expected.
        }
      },
      Error,
      "Mistral stream was idle for more than 10ms",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat sanitizes provider errors", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        type: "invalid_request_error",
        code: 3001,
        message: "Invalid request payload",
      }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );

  try {
    await assertRejects(
      async () => {
        for await (
          const _chunk of streamMistralChat({
            apiKey: "test-key",
            instructions: "You are Wagey.",
            inputs: [{ role: "user", content: "Hei" }],
          })
        ) {
          // No chunks expected.
        }
      },
      MistralProviderError,
      "Invalid request payload",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("streamMistralChat handles conversation.response.error events", async () => {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "conversation.response.error",
        data: {
          type: "conversation.response.error",
          error: {
            type: "invalid_request_error",
            code: 3001,
            message: "Stream payload rejected",
            request_id: "req_stream_error",
          },
        },
      },
    ]);

  try {
    await assertRejects(
      async () => {
        for await (
          const _chunk of streamMistralChat({
            apiKey: "test-key",
            instructions: "You are Wagey.",
            inputs: [{ role: "user", content: "Hei" }],
          })
        ) {
          // No chunks expected.
        }
      },
      MistralProviderError,
      "Stream payload rejected",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
