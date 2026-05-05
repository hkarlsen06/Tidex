import { assert, assertEquals } from "jsr:@std/assert";

import { DEFAULT_CLAUDE_MODEL } from "./claude.ts";
import { DEFAULT_OPENAI_MODEL } from "./openai.ts";
import {
  assistantLikelyClaimsWriteAction,
  handleWageyRequest,
  isReadOnlyToolUse,
  userLikelyRequestedWriteAction,
} from "./router.ts";
import type { WageyRequestContext } from "./context.ts";

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

function createDelayedSseResponse(
  events: Record<string, unknown>[],
  delayMs: number,
): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const [index, event] of events.entries()) {
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
        );

        if (delayMs > 0 && index < events.length - 1) {
          await new Promise((resolve) => setTimeout(resolve, delayMs));
        }
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

async function readChunksUntil(
  response: Response,
  predicate: (chunk: Record<string, unknown>) => boolean,
  timeoutMs: number,
): Promise<Array<Record<string, unknown>>> {
  assert(response.body, "Expected streaming response body");

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const chunks: Array<Record<string, unknown>> = [];
  let buffer = "";
  let didMatch = false;

  try {
    const deadline = Date.now() + timeoutMs;

    while (!didMatch && Date.now() < deadline) {
      const remainingMs = Math.max(1, deadline - Date.now());
      let timeoutId: number | undefined;
      const next = await Promise.race([
        reader.read(),
        new Promise<"timeout">((resolve) => {
          timeoutId = setTimeout(() => resolve("timeout"), remainingMs);
        }),
      ]);
      if (timeoutId !== undefined) {
        clearTimeout(timeoutId);
      }

      if (next === "timeout") {
        break;
      }

      const { done, value } = next;
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });

      let boundaryIndex = buffer.indexOf("\n\n");
      while (boundaryIndex != -1) {
        const block = buffer.slice(0, boundaryIndex);
        buffer = buffer.slice(boundaryIndex + 2);

        const line = block
          .split("\n")
          .find((entry) => entry.startsWith("data: "));
        if (line) {
          const payload = JSON.parse(line.slice(6)) as {
            type?: string;
            chunk?: Record<string, unknown>;
          };
          if (payload.type === "chunk" && payload.chunk) {
            chunks.push(payload.chunk);
            if (predicate(payload.chunk)) {
              didMatch = true;
              break;
            }
          }
        }

        boundaryIndex = buffer.indexOf("\n\n");
      }
    }

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }

  return chunks;
}

function buildRequestBody(userId: string, capabilities: string[]): string {
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
    },
  });
}

function buildResearchEvents(): Record<string, unknown>[] {
  return [
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
      delta: { type: "text_delta", text: "Jeg fant en oppdatert tariff." },
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
    { type: "message_delta", delta: { stop_reason: "end_turn" } },
    { type: "message_stop" },
  ];
}

function buildSlowTextOnlyEvents(): Record<string, unknown>[] {
  return [
    {
      type: "content_block_start",
      content_block: { type: "text" },
    },
    {
      type: "content_block_delta",
      delta: { type: "text_delta", text: "Dette er første del." },
    },
    {
      type: "content_block_delta",
      delta: { type: "text_delta", text: " Dette er andre del." },
    },
    { type: "content_block_stop" },
    { type: "message_delta", delta: { stop_reason: "end_turn" } },
    { type: "message_stop" },
  ];
}

function buildMessageBreakEvents(): Record<string, unknown>[] {
  return [
    {
      type: "content_block_start",
      content_block: { type: "text" },
    },
    {
      type: "content_block_delta",
      delta: { type: "text_delta", text: "Første del.\n<wagey_mess" },
    },
    {
      type: "content_block_delta",
      delta: { type: "text_delta", text: "age_break/>\nAndre del." },
    },
    { type: "content_block_stop" },
    { type: "message_delta", delta: { stop_reason: "end_turn" } },
    { type: "message_stop" },
  ];
}

function buildOpenAITextOnlyEvents(): Record<string, unknown>[] {
  return [
    {
      type: "response.output_item.added",
      output_index: 0,
      item: { type: "message", id: "msg_1" },
    },
    {
      type: "response.output_text.delta",
      delta: "Dette kommer fra GPT-5.5.",
    },
    {
      type: "response.completed",
      response: { status: "completed" },
    },
  ];
}

Deno.test("handleWageyRequest emits built-in tool events and deduped sources for capable clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
  globalThis.fetch = async () => createSseResponse(buildResearchEvents());

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

    const builtInResultChunk = chunks.find((chunk) =>
      chunk.type === "wagey_built_in_tool_result"
    );
    assert(builtInResultChunk);
    assertEquals(
      builtInResultChunk.result,
      JSON.stringify({
        type: "web_search_tool_result",
        tool_use_id: "search_1",
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
    assertEquals((sourcesChunk.items as unknown[]).length, 1);
    assertEquals(
      sourcesChunk.items,
      [
        {
          id: "https://example.com/tariff",
          title: "Tariffavtalen",
          url: "https://example.com/tariff",
          domain: "example.com",
        },
      ],
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest suppresses built-in tool events and sources for legacy clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
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
    assert(chunks.some((chunk) => chunk.type === "text"));
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest streams text chunks before the upstream turn fully completes", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
  globalThis.fetch = async () =>
    createDelayedSseResponse(buildSlowTextOnlyEvents(), 60);

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

    const earlyChunks = await readChunksUntil(
      response,
      (chunk) => chunk.type === "text",
      180,
    );

    assert(
      earlyChunks.some((chunk) => chunk.type === "text_start"),
      "Expected text_start to arrive before stream completion",
    );
    assert(
      earlyChunks.some((chunk) => chunk.type === "text"),
      "Expected text chunk to arrive before stream completion",
    );
    assert(
      !earlyChunks.some((chunk) => chunk.type === "done"),
      "Expected stream to still be in progress when first text arrives",
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest emits explicit message_break chunks only for capable clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
  globalThis.fetch = async () => createSseResponse(buildMessageBreakEvents());

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(userId, ["message_break_v1"]),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    const chunks = await readChunkStream(response);

    assertEquals(
      chunks.filter((chunk) => chunk.type === "message_break").length,
      1,
    );
    assertEquals(
      chunks.filter((chunk) => chunk.type === "text").map((chunk) =>
        chunk.content
      ),
      ["Første del.", "Andre del."],
    );
    assert(
      !chunks.some((chunk) =>
        typeof chunk.content === "string" &&
        chunk.content.includes("<wagey_message_break/>")
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest does not emit message_break chunks for legacy clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
  globalThis.fetch = async () => createSseResponse(buildMessageBreakEvents());

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

    assert(!chunks.some((chunk) => chunk.type === "message_break"));
    assert(
      !chunks.some((chunk) =>
        typeof chunk.content === "string" &&
        chunk.content.includes("<wagey_message_break/>")
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest sends the explicit Opus 4.6 rollback model when configured", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");
  let capturedModel: string | null = null;

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", "claude-opus-4-6");
  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    const body = JSON.parse(request?.body ?? "{}") as { model?: string };
    capturedModel = body.model ?? null;
    return createSseResponse(buildSlowTextOnlyEvents());
  };

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

    await readChunkStream(response);
    assertEquals(capturedModel, "claude-opus-4-6");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest can route Wagey through OpenAI GPT-5.5", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalProvider = Deno.env.get("WAGEY_AI_PROVIDER");
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");
  let capturedUrl = "";
  let capturedModel: string | null = null;

  Deno.env.set("WAGEY_AI_PROVIDER", "openai");
  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
  globalThis.fetch = async (input, init) => {
    capturedUrl = String(input);
    const request = init as { body?: string } | undefined;
    const body = JSON.parse(request?.body ?? "{}") as { model?: string };
    capturedModel = body.model ?? null;
    return createSseResponse(buildOpenAITextOnlyEvents());
  };

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

    assertEquals(capturedUrl, "https://api.openai.com/v1/responses");
    assertEquals(capturedModel, DEFAULT_OPENAI_MODEL);
    assert(
      chunks.some((chunk) =>
        chunk.type === "text" &&
        chunk.content === "Dette kommer fra GPT-5.5."
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
    if (originalProvider === undefined) {
      Deno.env.delete("WAGEY_AI_PROVIDER");
    } else {
      Deno.env.set("WAGEY_AI_PROVIDER", originalProvider);
    }
    if (originalApiKey === undefined) {
      Deno.env.delete("OPENAI_API_KEY");
    } else {
      Deno.env.set("OPENAI_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("OPENAI_MODEL");
    } else {
      Deno.env.set("OPENAI_MODEL", originalModel);
    }
  }
});

Deno.test("handleWageyRequest falls back to default Opus 4.7 for unsupported CLAUDE_MODEL", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalWarn = console.warn;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");
  let capturedModel: string | null = null;
  const warnings: string[] = [];

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", "claude-sonnet-4-6");
  console.warn = (message?: unknown, ...optionalParams: unknown[]) => {
    warnings.push([message, ...optionalParams].map(String).join(" "));
  };
  globalThis.fetch = async (_input, init) => {
    const request = init as { body?: string } | undefined;
    const body = JSON.parse(request?.body ?? "{}") as { model?: string };
    capturedModel = body.model ?? null;
    return createSseResponse(buildSlowTextOnlyEvents());
  };

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

    await readChunkStream(response);

    assertEquals(capturedModel, DEFAULT_CLAUDE_MODEL);
    assert(warnings.some((warning) => warning.includes("default Opus 4.7")));
  } finally {
    globalThis.fetch = originalFetch;
    console.warn = originalWarn;
    if (originalApiKey === undefined) {
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});

Deno.test("userLikelyRequestedWriteAction detects direct mutation requests", () => {
  assertEquals(
    userLikelyRequestedWriteAction("Can you set my tax to 10%?"),
    true,
  );
  assertEquals(
    userLikelyRequestedWriteAction("Kan du oppdatere skatten til 10 prosent?"),
    true,
  );
  assertEquals(userLikelyRequestedWriteAction("Hva er skatten min nå?"), false);
});

Deno.test("assistantLikelyClaimsWriteAction detects promise/complete mutation language", () => {
  assertEquals(
    assistantLikelyClaimsWriteAction("Done - I've updated your tax to 10%."),
    true,
  );
  assertEquals(
    assistantLikelyClaimsWriteAction(
      "Jeg skal oppdatere skatteinnstillingen din nå.",
    ),
    true,
  );
  assertEquals(
    assistantLikelyClaimsWriteAction("Jeg sjekker lønnsinnstillingene dine."),
    false,
  );
});

Deno.test("isReadOnlyToolUse treats event planning tools as read-only", () => {
  assertEquals(
    isReadOnlyToolUse({ id: "tool_1", name: "query_events", input: {} }),
    true,
  );
  assertEquals(
    isReadOnlyToolUse({
      id: "tool_2",
      name: "plan_schedule",
      input: { action: "agenda" },
    }),
    true,
  );
  assertEquals(
    isReadOnlyToolUse({
      id: "tool_3",
      name: "manage_event",
      input: { action: "create" },
    }),
    false,
  );
});

Deno.test("handleWageyRequest returns a safe generic error for Anthropic billing failures", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("CLAUDE_API_KEY");
  const originalModel = Deno.env.get("CLAUDE_MODEL");

  Deno.env.set("CLAUDE_API_KEY", "test-key");
  Deno.env.set("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL);
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
      Deno.env.delete("CLAUDE_API_KEY");
    } else {
      Deno.env.set("CLAUDE_API_KEY", originalApiKey);
    }
    if (originalModel === undefined) {
      Deno.env.delete("CLAUDE_MODEL");
    } else {
      Deno.env.set("CLAUDE_MODEL", originalModel);
    }
  }
});
