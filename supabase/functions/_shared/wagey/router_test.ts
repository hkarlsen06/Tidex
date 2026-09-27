import { assert, assertEquals } from "jsr:@std/assert";

import { DEFAULT_OPENAI_MODEL } from "./openai.ts";
import {
  assistantLikelyClaimsWriteAction,
  handleWageyRequest,
  isReadOnlyToolUse,
  serializeToolResultPayload,
  userLikelyRequestedWriteAction,
} from "./router.ts";
import type { WageyRequestContext } from "./context.ts";
import { tools } from "./tools.ts";

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

Deno.test("serializeToolResultPayload removes floating point artifacts recursively", () => {
  const serialized = serializeToolResultPayload({
    success: true,
    currency: "kr",
    data: {
      totalEarnings: 85821.020000000004,
      totalHours: 399.07999999999998,
      shiftCount: 62,
      nested: [{ rate: 204.99999999999997 }],
    },
  });

  assertEquals(
    serialized,
    '{"success":true,"currency":"kr","data":{"totalEarnings":85821.02,"totalHours":399.08,"shiftCount":62,"nested":[{"rate":205}]}}',
  );
});

function createMockContext(userId: string): WageyRequestContext {
  return {
    user: { id: userId } as WageyRequestContext["user"],
    cache: new Map(),
    supabase: ({
      rpc: async (name: string) => {
        throw new Error(`Unexpected supabase rpc: ${name}`);
      },
    } as unknown) as WageyRequestContext["supabase"],
    supabaseAdmin: ({
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

Deno.test("Wagey exposes 19 app tools after structural consolidation", () => {
  const toolNames = tools.map((tool) => tool.name);

  assertEquals(toolNames.length, 19);
  assert(toolNames.includes("manage_account"));
  assert(toolNames.includes("manage_recurring_shift"));
  assert(toolNames.includes("manage_payroll_adjustment"));
  assert(toolNames.includes("query_friend_shifts"));
  assert(!toolNames.includes("draft_recurring_shift"));
  assert(!toolNames.includes("confirm_recurring_shift"));
  assert(!toolNames.includes("manage_recurring_exclusion"));
  assert(!toolNames.includes("query_friend_featured_shift"));
  assert(!toolNames.includes("manage_settings"));
  assert(!toolNames.includes("manage_feedback"));
  assert(!toolNames.includes("manage_profile"));
});

Deno.test("manage_payroll_adjustment advertises strict nullable schema", () => {
  const tool = tools.find((candidate) =>
    candidate.name === "manage_payroll_adjustment"
  );

  assert(tool && "input_schema" in tool);
  assertEquals(tool.strict, true);
  assertEquals(tool.input_schema.additionalProperties, false);

  const required = tool.input_schema.required ?? [];
  assertEquals(required.includes("action"), true);
  assertEquals(required.includes("amount"), true);
  assertEquals(required.includes("description"), true);
  assertEquals(required.includes("title"), false);
  assertEquals(required.includes("payoutMonth"), true);
  assertEquals(required.includes("earnedToDate"), true);
  assertEquals(required.includes("clearFields"), true);

  const properties = tool.input_schema.properties as Record<
    string,
    Record<string, unknown>
  >;
  assertEquals(properties.action.enum, ["list", "create", "update", "delete"]);
  assertEquals(properties.amount.type, ["number", "null"]);
  assertEquals(properties.description.type, ["string", "null"]);
  assert(typeof properties.description.description === "string");
  assertEquals("title" in properties, false);
  assertEquals(properties.taxTreatment.enum, [
    "gross_taxable",
    "net_manual",
    "excluded_from_tax_estimate",
    null,
  ]);
  assertEquals(properties.clearFields.type, ["array", "null"]);
  assert(typeof properties.clearFields.description === "string");
  assert(typeof properties.payoutDate.description === "string");
  assert(typeof properties.earnedFromDate.description === "string");
});

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
      let timeoutId: ReturnType<typeof setTimeout> | undefined;
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

function buildRequestBody(
  userId: string,
  capabilities: string[],
  deeplinks?: Array<{ destination: string; url: string; parameters?: string[] }>,
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
        ...(deeplinks ? { deeplinks } : {}),
      },
    },
  });
}

function buildResearchEvents(): Record<string, unknown>[] {
  return [
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
      delta: "Jeg fant en oppdatert tariff.",
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
      type: "response.completed",
      response: { status: "completed" },
    },
  ];
}

function buildSlowTextOnlyEvents(): Record<string, unknown>[] {
  return [
    {
      type: "response.output_item.added",
      output_index: 0,
      item: { type: "message", id: "msg_1" },
    },
    {
      type: "response.output_text.delta",
      delta: "Dette er første del.",
    },
    {
      type: "response.output_text.delta",
      delta: " Dette er andre del.",
    },
    {
      type: "response.completed",
      response: { status: "completed" },
    },
  ];
}

function buildMessageBreakEvents(): Record<string, unknown>[] {
  return [
    {
      type: "response.output_item.added",
      output_index: 0,
      item: { type: "message", id: "msg_1" },
    },
    {
      type: "response.output_text.delta",
      delta: "Første del.\n<wagey_mess",
    },
    {
      type: "response.output_text.delta",
      delta: "age_break/>\nAndre del.",
    },
    {
      type: "response.completed",
      response: { status: "completed" },
    },
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
      delta: "Dette kommer fra GPT-5.6 Luna.",
    },
    {
      type: "response.completed",
      response: { status: "completed" },
    },
  ];
}

function buildFunctionToolEvents(): Record<string, unknown>[] {
  return [
    {
      type: "response.output_item.added",
      output_index: 0,
      item: {
        type: "function_call",
        id: "fc_1",
        call_id: "tool_1",
        name: "get_statistics",
      },
    },
    {
      type: "response.function_call_arguments.done",
      output_index: 0,
      arguments: '{"metric":"bad_metric"}',
    },
    {
      type: "response.completed",
      response: { status: "completed" },
    },
    {
      type: "response.output_item.added",
      output_index: 0,
      item: { type: "message", id: "msg_2" },
    },
    {
      type: "response.output_text.delta",
      delta: "Denne måneden har du tjent 0 kr.",
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
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
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

    const firstTextIndex = chunks.findIndex((chunk) => chunk.type === "text");
    const firstToolStartIndex = chunks.findIndex((chunk) =>
      chunk.type === "wagey_built_in_tool_start"
    );
    assert(firstTextIndex >= 0);
    assert(firstToolStartIndex >= 0);
    assertEquals(
      chunks[firstTextIndex].content,
      "Jeg fant en oppdatert tariff.",
    );
    assertEquals(
      chunks[firstToolStartIndex].toolArguments,
      '{"query":"HK Virke tariff 2026"}',
    );
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

Deno.test("handleWageyRequest accepts deeplink-capable clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
  globalThis.fetch = async () =>
    createSseResponse([
      {
        type: "response.output_text.delta",
        delta: "Her er en lenke.",
      },
      {
        type: "response.completed",
        response: { status: "completed" },
      },
    ]);

  try {
    const response = await handleWageyRequest(
      new Request("https://example.com/functions/v1/wagey-chat-v2", {
        method: "POST",
        body: buildRequestBody(
          userId,
          ["deeplinks_v1"],
          [
            {
              destination: "settings.pay",
              url: "tidex://settings/pay?jobId=JOB_ID",
              parameters: ["jobId"],
            },
          ],
        ),
        headers: {
          "Content-Type": "application/json",
        },
      }),
      createMockContext(userId),
    );

    assertEquals(response.status, 200);
    const chunks = await readChunkStream(response);
    assert(chunks.some((chunk) => chunk.type === "text"));
  } finally {
    globalThis.fetch = originalFetch;
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

Deno.test("handleWageyRequest suppresses built-in tool events and sources for legacy clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
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

Deno.test("handleWageyRequest includes final function input on tool_result chunks", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");
  let fetchCount = 0;

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
  globalThis.fetch = async () => {
    const events = fetchCount === 0
      ? buildFunctionToolEvents().slice(0, 3)
      : buildFunctionToolEvents().slice(3);
    fetchCount += 1;
    return createSseResponse(events);
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
    const resultChunk = chunks.find((chunk) => chunk.type === "tool_result");

    assert(resultChunk);
    assertEquals(resultChunk.toolName, "get_statistics");
    assertEquals(resultChunk.toolArguments, '{"metric":"bad_metric"}');
  } finally {
    globalThis.fetch = originalFetch;
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

Deno.test("handleWageyRequest streams text chunks before the upstream turn fully completes", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
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

Deno.test("handleWageyRequest emits explicit message_break chunks only for capable clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
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

Deno.test("handleWageyRequest does not emit message_break chunks for legacy clients", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");

  Deno.env.set("OPENAI_API_KEY", "test-key");
  Deno.env.set("OPENAI_MODEL", DEFAULT_OPENAI_MODEL);
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

Deno.test("handleWageyRequest sends Wagey through OpenAI GPT-5.6 Luna", async () => {
  const userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const originalFetch = globalThis.fetch;
  const originalApiKey = Deno.env.get("OPENAI_API_KEY");
  const originalModel = Deno.env.get("OPENAI_MODEL");
  let capturedUrl = "";
  let capturedModel: string | null = null;

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
        chunk.content === "Dette kommer fra GPT-5.6 Luna."
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
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
