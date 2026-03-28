import { assert, assertEquals } from "jsr:@std/assert";

import { convertToMistralConversation, handleWageyRequest } from "./router.ts";
import type { WageyRequestContext } from "./context.ts";

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

function createMockContext(userId: string): WageyRequestContext {
  return {
    user: { id: userId } as WageyRequestContext["user"],
    cache: new Map(),
    supabase: ({
      rpc: async (name: string) => {
        if (name === "increment_wagey_invocation") {
          return {
            data: {
              allowed: true,
              count: 1,
              remaining: 39,
              bonus: 0,
            },
            error: null,
          };
        }

        throw new Error(`Unexpected supabase rpc: ${name}`);
      },
    } as unknown) as WageyRequestContext["supabase"],
    supabaseAdmin: ({
      rpc: async (name: string) => {
        if (name === "get_wagey_access_context") {
          return {
            data: {
              before_paywall: true,
              wagey_invocations: { count: 0, month: "2026-03", bonus: 0 },
              status: null,
              product_id: null,
              current_period_end: null,
              price_id: null,
              provider: null,
            },
            error: null,
          };
        }

        throw new Error(`Unexpected supabase admin rpc: ${name}`);
      },
    } as unknown) as WageyRequestContext["supabaseAdmin"],
  };
}

async function readChunkStream(
  response: Response,
): Promise<Array<Record<string, unknown>>> {
  const text = await response.text();
  const chunks: Array<Record<string, unknown>> = [];

  for (const block of text.split("\n\n")) {
    const line = block
      .split("\n")
      .find((entry) => entry.startsWith("data: "));
    if (!line) continue;

    const payload = JSON.parse(line.slice(6)) as {
      type?: string;
      chunk?: Record<string, unknown>;
    };
    if (payload.type === "chunk" && payload.chunk) {
      chunks.push(payload.chunk);
    }
  }

  return chunks;
}

function buildRequestBody(
  userId: string,
  capabilities: string[],
  extraInput: Record<string, unknown> = {},
): string {
  return JSON.stringify({
    routerStreamKey: "wagey",
    input: {
      messages: [
        {
          role: "user",
          content: "Matcher lønna mi med live tariff?",
        },
      ],
      userId,
      client: {
        platform: "ios",
        appVersion: "1.0",
        capabilities,
      },
      ...extraInput,
    },
  });
}

function buildResearchEvents(): SseRecord[] {
  return [
    {
      event: "conversation.response.started",
      data: {
        type: "conversation.response.started",
        conversation_id: "conv_1",
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
        arguments: 'query": "HK Virke tariff 2026"}',
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
        content: "Jeg fant en oppdatert tariff.",
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
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          description: "Oppdatert tarifftekst.",
        },
      },
    },
    {
      event: "conversation.response.done",
      data: {
        type: "conversation.response.done",
        usage: { total_tokens: 25 },
      },
    },
  ];
}

Deno.test("convertToMistralConversation preserves image input and function tool history", () => {
  const { instructions, messages, inputs } = convertToMistralConversation([
    {
      role: "system",
      content: "You are Wagey.",
    },
    {
      role: "user",
      content: [
        {
          type: "image",
          source: {
            type: "base64",
            media_type: "image/jpeg",
            data: "abc123",
          },
        },
        {
          type: "text",
          text: "What logo is this?",
        },
      ],
    },
    {
      role: "assistant",
      content: "Checking your workplace info.",
      tool_calls: [{
        id: "tool_call_original",
        type: "function",
        function: {
          name: "list_workplaces",
          arguments: '{"includeArchived":true}',
        },
      }],
    },
    {
      role: "tool",
      tool_call_id: "tool_call_original",
      name: "list_workplaces",
      content: '{"success":true}',
    },
  ], "<summary>Older summary</summary>");

  assertEquals(messages.length, 3);
  assertEquals(instructions?.includes("<compressed_context>"), true);
  assertEquals(inputs[0], {
    role: "user",
    content: [
      {
        type: "image_url",
        image_url: {
          url: "data:image/jpeg;base64,abc123",
        },
      },
      {
        type: "text",
        text: "What logo is this?",
      },
    ],
  });

  const toolCallEntry = inputs.find((entry) =>
    "name" in entry && entry.name === "list_workplaces"
  );
  assert(toolCallEntry);
  assertEquals(
    "tool_call_id" in toolCallEntry &&
      /^[A-Za-z0-9]{9}$/.test(toolCallEntry.tool_call_id),
    true,
  );

  const toolResultEntry = inputs.find((entry) => "result" in entry);
  assert(toolResultEntry);
  assertEquals(
    "tool_call_id" in toolCallEntry && "tool_call_id" in toolResultEntry
      ? toolCallEntry.tool_call_id
      : null,
    "tool_call_id" in toolResultEntry ? toolResultEntry.tool_call_id : null,
  );
});

Deno.test("handleWageyRequest emits built-in tool events and deduped sources for capable clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async (_input, init) => {
    const body = JSON.parse((init as { body?: string }).body ?? "{}") as Record<
      string,
      unknown
    >;
    if (body["stream"] === true) {
      return createSseResponse(buildResearchEvents());
    }

    throw new Error("Unexpected non-stream summary request");
  };

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, [
          "rich_sources_v1",
          "rich_built_in_tool_events_v1",
        ]),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);

    assert(chunks.some((chunk) => chunk.type === "text_start"));
    assert(chunks.some((chunk) => chunk.type === "wagey_built_in_tool_start"));
    assert(chunks.some((chunk) => chunk.type === "wagey_built_in_tool_result"));
    assert(chunks.some((chunk) => chunk.type === "wagey_sources"));
    assert(!chunks.some((chunk) => chunk.type === "tool_result"));
    assert(!chunks.some((chunk) => chunk.toolName === "web_fetch"));

    const builtInResultChunk = chunks.find((chunk) =>
      chunk.type === "wagey_built_in_tool_result"
    );
    assert(builtInResultChunk);
    assertEquals(
      builtInResultChunk.result,
      JSON.stringify({
        type: "web_search_tool_result",
        tool_use_id: "tool_exec_1",
        content: [
          {
            type: "web_search_result",
            title: "Tariffavtalen",
            url: "https://example.com/tariff",
          },
        ],
      }),
    );

    const sourcesChunk = chunks.find((chunk) => chunk.type === "wagey_sources");
    assert(sourcesChunk);
    assertEquals(sourcesChunk.items, [
      {
        id: "https://example.com/tariff",
        title: "Tariffavtalen",
        url: "https://example.com/tariff",
        domain: "example.com",
      },
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});

Deno.test("handleWageyRequest suppresses built-in tool events and sources for legacy clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async () => createSseResponse(buildResearchEvents());

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, []),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);
    assert(!chunks.some((chunk) => chunk.type === "wagey_built_in_tool_start"));
    assert(
      !chunks.some((chunk) => chunk.type === "wagey_built_in_tool_result"),
    );
    assert(!chunks.some((chunk) => chunk.type === "wagey_sources"));
    assert(!chunks.some((chunk) => chunk.toolName === "web_fetch"));
    assert(chunks.some((chunk) => chunk.type === "text"));
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});

Deno.test("handleWageyRequest returns a safe generic error for provider failures", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        type: "invalid_request_error",
        code: 3001,
        message: "Bad provider request",
      }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, []),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);
    const errorChunk = chunks.find((chunk) => chunk.type === "error");

    assert(errorChunk);
    assertEquals(
      errorChunk.error,
      "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.",
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});

Deno.test("handleWageyRequest emits wagey_compaction when the conversation exceeds the threshold", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async (_input, init) => {
    const body = JSON.parse((init as { body?: string }).body ?? "{}") as Record<
      string,
      unknown
    >;
    if (body["stream"] === true) {
      return createSseResponse([
        {
          event: "message.output.delta",
          data: {
            type: "message.output.delta",
            id: "msg_1",
            output_index: 0,
            content_index: 0,
            role: "assistant",
            content: "Kort svar.",
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
    }

    return new Response(
      JSON.stringify({
        outputs: [{
          content: "<summary>Compacted history</summary>",
        }],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  };

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, [], {
          compaction: "x".repeat(900_000),
        }),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);
    const compactionChunk = chunks.find((chunk) =>
      chunk.type === "wagey_compaction"
    );
    assert(compactionChunk);
    assertEquals(
      compactionChunk.content,
      "<summary>Compacted history</summary>",
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});

Deno.test("handleWageyRequest omits inline image data from compaction summaries", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");
  const largeImageData = "a".repeat(900_000);
  let sawSanitizedSummaryRequest = false;

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async (_input, init) => {
    const body = JSON.parse((init as { body?: string }).body ?? "{}") as Record<
      string,
      unknown
    >;
    if (body["stream"] === true) {
      return createSseResponse([
        {
          event: "message.output.delta",
          data: {
            type: "message.output.delta",
            id: "msg_image",
            output_index: 0,
            content_index: 0,
            role: "assistant",
            content: "Ser på bildet.",
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
    }

    const transcript = (body["inputs"] as Array<Record<string, unknown>>)[0]
      ?.["content"];
    if (typeof transcript !== "string") {
      throw new Error("Expected compaction transcript string");
    }

    if (
      transcript.includes(largeImageData) ||
      transcript.includes("data:image/jpeg;base64,")
    ) {
      throw new Error("Compaction transcript leaked inline image data");
    }

    sawSanitizedSummaryRequest = transcript.includes(
      "[Image omitted from compaction summary:",
    );

    return new Response(
      JSON.stringify({
        outputs: [{
          content: "<summary>Image-safe compacted history</summary>",
        }],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  };

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, [], {
          messages: [{
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: "image/jpeg",
                  data: largeImageData,
                },
              },
              {
                type: "text",
                text: "Hva viser dette?",
              },
            ],
          }],
        }),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);
    const compactionChunk = chunks.find((chunk) =>
      chunk.type === "wagey_compaction"
    );
    assert(compactionChunk);
    assertEquals(
      compactionChunk.content,
      "<summary>Image-safe compacted history</summary>",
    );
    assertEquals(sawSanitizedSummaryRequest, true);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});

Deno.test("handleWageyRequest emits a no-response fallback when the provider returns nothing visible", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("MISTRAL_API_KEY");

  Deno.env.set("MISTRAL_API_KEY", "test-key");
  globalThis.fetch = async () =>
    createSseResponse([
      {
        event: "conversation.response.started",
        data: {
          type: "conversation.response.started",
          conversation_id: "conv_empty",
        },
      },
      {
        event: "conversation.response.done",
        data: {
          type: "conversation.response.done",
          usage: { total_tokens: 1 },
        },
      },
    ]);

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, []),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);
    const errorChunk = chunks.find((chunk) => chunk.type === "error");
    assert(errorChunk);
    assertEquals(errorChunk.error, "No response from Mistral provider");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("MISTRAL_API_KEY");
    } else {
      Deno.env.set("MISTRAL_API_KEY", originalApiKey);
    }
  }
});
