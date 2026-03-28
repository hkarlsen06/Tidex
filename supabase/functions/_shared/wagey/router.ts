import { z } from "npm:zod";

import type {
  ContentBlock,
  Message,
  RedactedThinkingContent,
  Source,
  ThinkingContent,
  Tool,
  ToolResultContent,
} from "./ai-types.ts";
import type {
  MistralConversationInput,
  MistralMessageContentPart,
} from "./mistral.ts";
import {
  createMistralSummary,
  MistralProviderError,
  streamMistralChat,
} from "./mistral.ts";
import { invalidateWageyCache, type WageyRequestContext } from "./context.ts";
import { consumeWageyInvocation, getWageyAccess } from "./data.ts";
import { executeTool } from "./executor.ts";
import { maxIterationsReached } from "./i18n.ts";
import { getSystemPrompt, type SystemPromptContext } from "./system-prompt.ts";
import { type ToolName, tools } from "./tools.ts";

const REQUEST_ID_HEADER = "x-wagey-request-id";
const SSE_HEARTBEAT_MS = 15_000;
const SSE_FLUSH_PADDING = ": " + " ".repeat(2048) + "\n\n";

export type ChatChunk =
  | { type: "text_start" }
  | { type: "text"; content: string }
  | { type: "status"; status: "thinking" }
  | {
    type: "tool_start";
    toolName: string;
    toolCallId: string;
    toolArguments?: string;
  }
  | {
    type: "tool_result";
    toolName: string;
    toolCallId: string;
    result: string;
    success: boolean;
  }
  | { type: "done" }
  | { type: "error"; error: string }
  | {
    type: "wagey_limit";
    remaining: number;
    resetDays: number;
    exceeded?: boolean;
    bonus?: number;
  }
  | { type: "wagey_no_access" }
  | { type: "wagey_sources"; items: Source[] }
  | { type: "wagey_built_in_tool_start"; toolName: string; toolCallId: string }
  | {
    type: "wagey_built_in_tool_result";
    toolName: string;
    toolCallId: string;
    result: string;
    success: boolean;
  }
  | { type: "wagey_compaction"; content: string };

const imageContentBlockSchema = z.object({
  type: z.literal("image"),
  source: z.object({
    type: z.literal("base64"),
    media_type: z.string(),
    data: z.string(),
  }),
});

const textContentBlockSchema = z.object({
  type: z.literal("text"),
  text: z.string(),
});

const contentSchema = z.union([
  z.string().nullable(),
  z.array(z.union([textContentBlockSchema, imageContentBlockSchema])),
]);

const clientCapabilitySchema = z.enum([
  "rich_sources_v1",
  "rich_built_in_tool_events_v1",
]);

const chatInputSchema = z.object({
  messages: z.array(
    z.object({
      role: z.enum(["system", "user", "assistant", "tool"]),
      content: contentSchema,
      tool_calls: z
        .array(
          z.object({
            id: z.string(),
            type: z.literal("function"),
            function: z.object({
              name: z.string(),
              arguments: z.string(),
            }),
          }),
        )
        .optional(),
      tool_call_id: z.string().optional(),
      name: z.string().optional(),
    }),
  ),
  userId: z.string().uuid(),
  userName: z.string().optional(),
  compaction: z.string().optional(),
  client: z
    .object({
      platform: z.enum(["ios", "web"]).optional(),
      appVersion: z.string().optional(),
      capabilities: z.array(clientCapabilitySchema).optional(),
    })
    .optional(),
});

const bodySchema = z.object({
  routerStreamKey: z.literal("wagey"),
  input: chatInputSchema,
});

type ChatInput = z.infer<typeof chatInputSchema>;

type PendingToolUse = {
  id: string;
  name: string;
  input: Record<string, unknown>;
};

const BUILT_IN_TOOLS: Tool[] = [
  {
    type: "web_search",
    name: "web_search",
  },
];

const READ_ONLY_TOOL_NAMES = new Set<ToolName>([
  "query_shifts",
  "calculate_wages",
  "draft_recurring_shift",
  "get_statistics",
  "get_wage_info",
  "calculate_earnings",
  "list_workplaces",
  "list_friends",
  "query_friend_shifts",
  "query_friend_featured_shift",
]);

function extractTextContent(
  content: ChatInput["messages"][0]["content"],
): string {
  if (typeof content === "string") return content;
  if (content === null) return "";
  return content
    .filter((block): block is z.infer<typeof textContentBlockSchema> =>
      block.type === "text"
    )
    .map((block) => block.text)
    .join("");
}

function hasClientCapability(
  client: ChatInput["client"],
  capability: z.infer<typeof clientCapabilitySchema>,
): boolean {
  return client?.capabilities?.includes(capability) ?? false;
}

const MISTRAL_TOOL_ID_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const MISTRAL_CONTEXT_WINDOW_TOKENS = 256_000;
const MISTRAL_COMPACTION_THRESHOLD = Math.floor(
  MISTRAL_CONTEXT_WINDOW_TOKENS * 0.7,
);

function fnv1a64(value: string): bigint {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;

  for (const char of value) {
    hash ^= BigInt(char.codePointAt(0) ?? 0);
    hash = (hash * prime) & 0xffffffffffffffffn;
  }

  return hash;
}

function toBase62(value: bigint): string {
  if (value === 0n) return MISTRAL_TOOL_ID_ALPHABET[0];

  let remaining = value;
  let result = "";
  const base = BigInt(MISTRAL_TOOL_ID_ALPHABET.length);

  while (remaining > 0n) {
    const index = Number(remaining % base);
    result = MISTRAL_TOOL_ID_ALPHABET[index] + result;
    remaining /= base;
  }

  return result;
}

function normalizeToolCallId(
  originalId: string,
  idMap: Map<string, string>,
): string {
  const existing = idMap.get(originalId);
  if (existing) return existing;

  if (/^[A-Za-z0-9]{9}$/.test(originalId)) {
    idMap.set(originalId, originalId);
    return originalId;
  }

  let counter = 0;
  while (true) {
    const candidate = toBase62(
      fnv1a64(counter === 0 ? originalId : `${originalId}:${counter}`),
    )
      .padStart(9, MISTRAL_TOOL_ID_ALPHABET[0])
      .slice(-9);
    if (![...idMap.values()].includes(candidate)) {
      idMap.set(originalId, candidate);
      return candidate;
    }
    counter += 1;
  }
}

function buildCompactionInstructions(compaction?: string): string | undefined {
  const trimmed = compaction?.trim();
  if (!trimmed) return undefined;

  return [
    "<compressed_context>",
    "Use this as a Tidex-authored summary of older conversation history.",
    "Prefer newer raw messages if they conflict with this summary.",
    trimmed,
    "</compressed_context>",
  ].join("\n");
}

function buildMistralInstructions(
  systemPrompt?: string,
  compaction?: string,
): string | undefined {
  const parts = [
    systemPrompt?.trim(),
    buildCompactionInstructions(compaction),
  ].filter((part): part is string => Boolean(part));

  return parts.length > 0 ? parts.join("\n\n") : undefined;
}

function buildImageUrl(
  block: z.infer<typeof imageContentBlockSchema>,
): MistralMessageContentPart {
  return {
    type: "image_url",
    image_url: {
      url: `data:${block.source.media_type};base64,${block.source.data}`,
    },
  };
}

function flushMessageEntry(
  entries: MistralConversationInput[],
  role: "user" | "assistant",
  parts: MistralMessageContentPart[],
): void {
  if (parts.length === 0) return;

  if (parts.length === 1 && parts[0]?.type === "text") {
    entries.push({
      role,
      content: parts[0].text,
    });
    return;
  }

  entries.push({
    role,
    content: parts,
  });
}

function appendResearchContext(
  target: MistralMessageContentPart[],
  block: Extract<
    ContentBlock,
    { type: "server_tool_use" | "web_search_tool_result" }
  >,
): void {
  if (block.type === "server_tool_use") {
    const query = typeof block.input.query === "string"
      ? block.input.query.trim()
      : "";
    if (query) {
      target.push({
        type: "text",
        text: `[Research context: web_search query "${query}"]`,
      });
    }
    return;
  }

  if (block.content.length > 0) {
    const summary = block.content
      .map((item) => [item.title, item.url].filter(Boolean).join(" - "))
      .filter(Boolean)
      .join("; ");
    if (summary) {
      target.push({
        type: "text",
        text: `[Research sources: ${summary}]`,
      });
    }
  }
}

function estimateConversationTokens(options: {
  instructions?: string;
  inputs: MistralConversationInput[];
}): number {
  return Math.ceil(JSON.stringify(options).length / 4);
}

export function convertToMistralConversation(
  openAiMessages: ChatInput["messages"],
  compaction?: string,
): {
  instructions?: string;
  messages: Message[];
  inputs: MistralConversationInput[];
} {
  let systemPrompt: string | undefined;
  const messages: Message[] = [];
  const inputs: MistralConversationInput[] = [];
  const toolIdMap = new Map<string, string>();

  for (const msg of openAiMessages) {
    if (msg.role === "system") {
      const text = extractTextContent(msg.content);
      if (text) {
        systemPrompt = systemPrompt ? `${systemPrompt}\n\n${text}` : text;
      }
      continue;
    }

    if (msg.role === "user") {
      const contentBlocks: ContentBlock[] = [];
      const parts: MistralMessageContentPart[] = [];

      if (Array.isArray(msg.content)) {
        for (const block of msg.content) {
          if (block.type === "image") {
            contentBlocks.push({
              type: "image",
              source: {
                type: "base64",
                media_type: block.source.media_type,
                data: block.source.data,
              },
            });
            parts.push(buildImageUrl(block));
            continue;
          }

          contentBlocks.push({ type: "text", text: block.text });
          parts.push({ type: "text", text: block.text });
        }
      } else {
        const text = extractTextContent(msg.content);
        if (text) {
          contentBlocks.push({ type: "text", text });
          parts.push({ type: "text", text });
        }
      }

      messages.push({
        role: "user",
        content: contentBlocks.length > 0
          ? contentBlocks
          : extractTextContent(msg.content),
      });
      flushMessageEntry(inputs, "user", parts);
      continue;
    }

    if (msg.role === "assistant") {
      const contentBlocks: ContentBlock[] = [];
      const parts: MistralMessageContentPart[] = [];
      const textContent = extractTextContent(msg.content);
      if (textContent) {
        contentBlocks.push({ type: "text", text: textContent });
        parts.push({ type: "text", text: textContent });
      }

      if (msg.tool_calls) {
        for (const toolCall of msg.tool_calls) {
          const normalizedToolCallId = normalizeToolCallId(
            toolCall.id,
            toolIdMap,
          );
          let input: Record<string, unknown> = {};
          try {
            input = JSON.parse(toolCall.function.arguments);
          } catch {
            input = {};
          }

          contentBlocks.push({
            type: "tool_use",
            id: normalizedToolCallId,
            name: toolCall.function.name,
            input,
          });

          flushMessageEntry(inputs, "assistant", parts);
          parts.length = 0;
          inputs.push({
            tool_call_id: normalizedToolCallId,
            name: toolCall.function.name,
            arguments: toolCall.function.arguments || "{}",
          });
        }
      }

      messages.push({
        role: "assistant",
        content: contentBlocks.length > 0 ? contentBlocks : textContent,
      });
      flushMessageEntry(inputs, "assistant", parts);
      continue;
    }

    if (msg.role === "tool" && msg.tool_call_id) {
      const resultContent = extractTextContent(msg.content);
      const normalizedToolCallId = normalizeToolCallId(
        msg.tool_call_id,
        toolIdMap,
      );
      const lastMessage = messages[messages.length - 1];
      if (lastMessage?.role === "user" && Array.isArray(lastMessage.content)) {
        (lastMessage.content as ContentBlock[]).push({
          type: "tool_result",
          tool_use_id: normalizedToolCallId,
          content: resultContent,
        });
      } else {
        messages.push({
          role: "user",
          content: [{
            type: "tool_result",
            tool_use_id: normalizedToolCallId,
            content: resultContent,
          }],
        });
      }

      inputs.push({
        tool_call_id: normalizedToolCallId,
        result: resultContent,
      });
    }
  }

  return {
    instructions: buildMistralInstructions(systemPrompt, compaction),
    messages,
    inputs,
  };
}

function buildCompactionImagePlaceholder(
  mediaType: string,
  base64Data: string,
): MistralMessageContentPart {
  return {
    type: "text",
    text:
      `[Image omitted from compaction summary: ${mediaType}, ${base64Data.length} base64 chars]`,
  };
}

function buildMistralInputsFromMessages(
  messages: Message[],
  options: {
    includeInlineImages?: boolean;
  } = {},
): MistralConversationInput[] {
  const inputs: MistralConversationInput[] = [];
  const toolIdMap = new Map<string, string>();
  const includeInlineImages = options.includeInlineImages ?? true;

  for (const message of messages) {
    if (typeof message.content === "string") {
      if (message.content) {
        inputs.push({
          role: message.role,
          content: message.content,
        });
      }
      continue;
    }

    const parts: MistralMessageContentPart[] = [];
    for (const block of message.content) {
      if (block.type === "text") {
        parts.push({ type: "text", text: block.text });
        continue;
      }

      if (block.type === "image") {
        parts.push(
          includeInlineImages
            ? {
              type: "image_url",
              image_url: {
                url:
                  `data:${block.source.media_type};base64,${block.source.data}`,
              },
            }
            : buildCompactionImagePlaceholder(
              block.source.media_type,
              block.source.data,
            ),
        );
        continue;
      }

      if (block.type === "tool_use") {
        flushMessageEntry(inputs, "assistant", parts);
        parts.length = 0;
        inputs.push({
          tool_call_id: normalizeToolCallId(block.id, toolIdMap),
          name: block.name,
          arguments: JSON.stringify(block.input),
        });
        continue;
      }

      if (block.type === "tool_result") {
        flushMessageEntry(inputs, "user", parts);
        parts.length = 0;
        inputs.push({
          tool_call_id: normalizeToolCallId(block.tool_use_id, toolIdMap),
          result: block.content,
        });
        continue;
      }

      if (
        block.type === "server_tool_use" ||
        block.type === "web_search_tool_result"
      ) {
        appendResearchContext(parts, block);
      }
    }

    flushMessageEntry(inputs, message.role, parts);
  }

  return inputs;
}

function isReadOnlyToolUse(toolUse: PendingToolUse): boolean {
  const toolName = toolUse.name as ToolName;
  if (READ_ONLY_TOOL_NAMES.has(toolName)) return true;
  if (toolName === "manage_settings") {
    return toolUse.input.action === undefined ||
      toolUse.input.action === "view";
  }
  if (toolName === "manage_recurring_shift") {
    return toolUse.input.action === "list";
  }
  return false;
}

async function executeSingleToolUse(
  ctx: WageyRequestContext,
  toolUse: PendingToolUse,
): Promise<
  {
    uiChunk: Extract<ChatChunk, { type: "tool_result" }>;
    toolResult: ToolResultContent;
  }
> {
  try {
    const invalidJson = toolUse.input.INVALID_JSON;
    if (typeof invalidJson === "string") {
      const invalidResult = {
        success: false,
        message:
          "Tool input was invalid or incomplete JSON. Please resend a valid JSON object for this tool call.",
        invalid_input: { INVALID_JSON: invalidJson },
      };
      const serialized = JSON.stringify(invalidResult);
      return {
        uiChunk: {
          type: "tool_result",
          toolName: toolUse.name,
          toolCallId: toolUse.id,
          result: serialized,
          success: false,
        },
        toolResult: {
          type: "tool_result",
          tool_use_id: toolUse.id,
          content: serialized,
          is_error: true,
        },
      };
    }

    const result = await executeTool(
      ctx,
      toolUse.name,
      JSON.stringify(toolUse.input),
    );
    if (result.success && !isReadOnlyToolUse(toolUse)) {
      invalidateWageyCache(ctx);
    }
    const serialized = JSON.stringify(result);
    return {
      uiChunk: {
        type: "tool_result",
        toolName: toolUse.name,
        toolCallId: toolUse.id,
        result: serialized,
        success: result.success,
      },
      toolResult: {
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: serialized,
        is_error: !result.success,
      },
    };
  } catch (error) {
    const serialized = JSON.stringify({
      success: false,
      message: error instanceof Error ? error.message : "Unknown error",
    });
    return {
      uiChunk: {
        type: "tool_result",
        toolName: toolUse.name,
        toolCallId: toolUse.id,
        result: serialized,
        success: false,
      },
      toolResult: {
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: serialized,
        is_error: true,
      },
    };
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

function getRequestId(req: Request): string {
  return req.headers.get(REQUEST_ID_HEADER) ?? crypto.randomUUID();
}

function log(
  level: "info" | "warn" | "error",
  requestId: string,
  message: string,
  metadata: Record<string, unknown> = {},
): void {
  const payload = {
    scope: "wagey-router",
    requestId,
    message,
    ...metadata,
  };

  if (level === "error") {
    console.error(JSON.stringify(payload));
    return;
  }
  if (level === "warn") {
    console.warn(JSON.stringify(payload));
    return;
  }
  console.log(JSON.stringify(payload));
}

function getPublicErrorMessage(error: unknown): string {
  if (error instanceof MistralProviderError) {
    return error.publicMessage;
  }

  return error instanceof Error ? error.message : "Failed to initialize Wagey";
}

function getLoggableErrorMetadata(error: unknown): Record<string, unknown> {
  if (error instanceof MistralProviderError) {
    return {
      error: error.message,
      status: error.status,
      providerType: error.providerType,
      providerCode: error.providerCode,
      providerMessage: error.providerMessage,
      requestId: error.requestId,
      publicMessage: error.publicMessage,
    };
  }

  return {
    error: error instanceof Error ? error.message : String(error),
  };
}

function getMistralConfig(): { apiKey: string } {
  const apiKey = Deno.env.get("MISTRAL_API_KEY")?.trim() ?? "";
  if (!apiKey) {
    throw new Error("Missing MISTRAL_API_KEY");
  }
  return { apiKey };
}

function getResetDays(resetDate: Date | null): number {
  const targetDate = resetDate ??
    new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1);
  return Math.max(
    0,
    Math.ceil((targetDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24)),
  );
}

async function maybeCreateCompactionSummary(options: {
  apiKey: string;
  instructions?: string;
  messages: Message[];
  signal?: AbortSignal;
}): Promise<string | undefined> {
  const inputs = buildMistralInputsFromMessages(options.messages);
  const estimatedTokens = estimateConversationTokens({
    instructions: options.instructions,
    inputs,
  });

  if (estimatedTokens <= MISTRAL_COMPACTION_THRESHOLD) {
    return undefined;
  }

  const compactionInputs = buildMistralInputsFromMessages(options.messages, {
    includeInlineImages: false,
  });
  const transcript = JSON.stringify(
    {
      instructions: options.instructions,
      inputs: compactionInputs,
    },
    null,
    2,
  );

  return await createMistralSummary({
    apiKey: options.apiKey,
    transcript,
    signal: options.signal,
  });
}

export async function handleWageyRequest(
  req: Request,
  ctxOrFactory: WageyRequestContext | (() => Promise<WageyRequestContext>),
): Promise<Response> {
  const requestId = getRequestId(req);
  const rawBody = await req.json().catch(() => null);
  const parsed = bodySchema.safeParse(rawBody);
  if (!parsed.success) {
    log("warn", requestId, "Invalid request body", {
      issueCount: parsed.error.issues.length,
    });
    return json({ error: "Invalid input", details: parsed.error.issues }, 400);
  }

  const { input } = parsed.data;
  const ctx = typeof ctxOrFactory === "function"
    ? await ctxOrFactory()
    : ctxOrFactory;
  const supportsRichSources = hasClientCapability(
    input.client,
    "rich_sources_v1",
  );
  const supportsRichBuiltInToolEvents = hasClientCapability(
    input.client,
    "rich_built_in_tool_events_v1",
  );

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let streamClosed = false;
      let heartbeatHandle: number | null = null;

      const stopHeartbeat = () => {
        if (heartbeatHandle !== null) {
          clearInterval(heartbeatHandle);
          heartbeatHandle = null;
        }
      };

      const markStreamClosed = () => {
        if (streamClosed) return;
        streamClosed = true;
        stopHeartbeat();
      };

      const tryEnqueue = (payload: string): boolean => {
        if (streamClosed || req.signal.aborted) {
          markStreamClosed();
          return false;
        }

        try {
          controller.enqueue(encoder.encode(payload));
          return true;
        } catch {
          markStreamClosed();
          return false;
        }
      };

      const sendChunk = (chunk: ChatChunk) => {
        tryEnqueue(`data: ${JSON.stringify({ type: "chunk", chunk })}\n\n`);
      };

      const sendComment = (comment: string) => {
        tryEnqueue(`: ${comment}\n\n`);
      };

      const closeStream = (reason: string) => {
        if (streamClosed) return;
        markStreamClosed();
        try {
          controller.close();
        } catch {
          // Client already disconnected; nothing left to do.
        }
      };

      const sendErrorAndClose = (message: string) => {
        if (streamClosed || req.signal.aborted) {
          closeStream("error_after_abort");
          return;
        }
        log("error", requestId, "Sending stream error", { error: message });
        try {
          sendChunk({ type: "error", error: message });
        } finally {
          closeStream("error");
        }
      };

      try {
        tryEnqueue(SSE_FLUSH_PADDING);
        sendComment("connected");
        heartbeatHandle = setInterval(() => {
          sendComment("keep-alive");
        }, SSE_HEARTBEAT_MS);
        sendChunk({ type: "status", status: "thinking" });

        if (input.userId !== ctx.user.id) {
          log("warn", requestId, "User mismatch", {
            inputUserId: input.userId,
            authUserId: ctx.user.id,
          });
          sendErrorAndClose("User mismatch");
          return;
        }

        const access = await getWageyAccess(ctx);
        const availableBeforeTurn = Math.max(0, Number(access.remaining) || 0) +
          Math.max(0, Number(access.bonus) || 0);
        const limitExceeded = availableBeforeTurn <= 0;

        if (limitExceeded) {
          sendChunk({
            type: "wagey_limit",
            remaining: Math.max(0, Number(access.remaining) || 0),
            resetDays: getResetDays(access.resetDate),
            exceeded: true,
            bonus: Math.max(0, Number(access.bonus) || 0),
          });
          sendChunk({ type: "done" });
          closeStream("limit_exceeded");
          return;
        }

        const projectedRemaining = Math.max(
          0,
          Math.max(0, Number(access.remaining) || 0) - 1,
        );
        const projectedBonus = Math.max(
          0,
          projectedRemaining === 0
            ? Math.max(0, Number(access.bonus) || 0) -
              (Math.max(0, Number(access.remaining) || 0) > 0 ? 0 : 1)
            : Math.max(0, Number(access.bonus) || 0),
        );
        const projectedUsed = Math.max(
          0,
          Number(access.used) || 0,
        ) + (Math.max(0, Number(access.remaining) || 0) > 0 ? 1 : 0);

        const systemContext: SystemPromptContext = {
          accessLevel: access.level,
          used: projectedUsed,
          remaining: projectedRemaining,
          bonus: projectedBonus,
          userName: input.userName,
        };

        let { instructions, messages, inputs } = convertToMistralConversation(
          input.messages,
          input.compaction,
        );
        if (!instructions) {
          instructions = getSystemPrompt(systemContext);
        }

        const mistral = getMistralConfig();

        let iterationCount = 0;
        const MAX_ITERATIONS = 10;
        let aiLoopFailed = false;
        let hasUserVisibleAssistantOutput = false;
        let latestCompactionContent: string | undefined;
        let conversationMessages = [...messages];
        const collectedSources = new Map<string, Source>();
        let invocationConsumed = false;
        let finalRemaining = projectedRemaining;
        let finalBonus = projectedBonus;

        const ensureInvocationConsumed = async (): Promise<boolean> => {
          if (invocationConsumed) {
            return true;
          }

          const invocation = await consumeWageyInvocation(
            ctx,
            access.limit ?? 0,
          );
          const consumedRemaining = Math.max(
            0,
            Number(invocation.remaining) || 0,
          );
          const consumedBonus = Math.max(0, Number(invocation.bonus) || 0);

          if (!invocation.allowed && consumedRemaining + consumedBonus <= 0) {
            sendChunk({
              type: "wagey_limit",
              remaining: consumedRemaining,
              resetDays: getResetDays(access.resetDate),
              exceeded: true,
              bonus: consumedBonus,
            });
            sendChunk({ type: "done" });
            closeStream("limit_race_lost");
            return false;
          }

          invocationConsumed = true;
          finalRemaining = consumedRemaining;
          finalBonus = consumedBonus;
          return true;
        };

        try {
          while (iterationCount < MAX_ITERATIONS) {
            iterationCount += 1;
            sendChunk({ type: "status", status: "thinking" });
            inputs = buildMistralInputsFromMessages(conversationMessages);

            const toolUses: PendingToolUse[] = [];
            const startedToolUseIds = new Set<string>();
            const assistantContent: ContentBlock[] = [];

            let shouldStartNewAssistantTextBlock = true;

            const appendAssistantText = (content: string) => {
              if (!content) return;

              const lastBlock = assistantContent[assistantContent.length - 1];
              if (
                !shouldStartNewAssistantTextBlock && lastBlock?.type === "text"
              ) {
                lastBlock.text += content;
              } else {
                assistantContent.push({ type: "text", text: content });
              }
              shouldStartNewAssistantTextBlock = false;
            };

            for await (
              const chunk of streamMistralChat({
                apiKey: mistral.apiKey,
                instructions,
                inputs,
                tools: [...tools, ...BUILT_IN_TOOLS],
                signal: req.signal,
              })
            ) {
              if (req.signal.aborted) break;

              if (chunk.type === "text_start") {
                shouldStartNewAssistantTextBlock = true;
                sendChunk({ type: "text_start" });
              } else if (chunk.type === "text") {
                if (!chunk.content) {
                  continue;
                }
                if (!(await ensureInvocationConsumed())) {
                  return;
                }
                hasUserVisibleAssistantOutput = true;
                appendAssistantText(chunk.content);
                sendChunk({ type: "text", content: chunk.content });
              } else if (chunk.type === "built_in_tool_start") {
                if (!(await ensureInvocationConsumed())) {
                  return;
                }
                hasUserVisibleAssistantOutput = true;
                shouldStartNewAssistantTextBlock = true;
                assistantContent.push({
                  type: "server_tool_use",
                  id: chunk.id,
                  name: chunk.name,
                  input: chunk.input,
                });
                if (supportsRichBuiltInToolEvents) {
                  sendChunk({
                    type: "wagey_built_in_tool_start",
                    toolName: chunk.name,
                    toolCallId: chunk.id,
                  });
                }
              } else if (chunk.type === "tool_use_start") {
                if (!(await ensureInvocationConsumed())) {
                  return;
                }
                hasUserVisibleAssistantOutput = true;
                shouldStartNewAssistantTextBlock = true;
                startedToolUseIds.add(chunk.id);
                sendChunk({
                  type: "tool_start",
                  toolName: chunk.name,
                  toolCallId: chunk.id,
                  toolArguments: Object.keys(chunk.input).length > 0
                    ? JSON.stringify(chunk.input)
                    : undefined,
                });
              } else if (chunk.type === "built_in_tool_result") {
                if (!(await ensureInvocationConsumed())) {
                  return;
                }
                hasUserVisibleAssistantOutput = true;
                shouldStartNewAssistantTextBlock = true;
                assistantContent.push(chunk.result);
                if (supportsRichBuiltInToolEvents) {
                  sendChunk({
                    type: "wagey_built_in_tool_result",
                    toolName: chunk.name,
                    toolCallId: chunk.id,
                    result: JSON.stringify(chunk.result),
                    success: chunk.success,
                  });
                }
              } else if (chunk.type === "tool_use") {
                if (!(await ensureInvocationConsumed())) {
                  return;
                }
                const duplicate = toolUses.some((use) => use.id === chunk.id);
                if (!duplicate) {
                  toolUses.push({
                    id: chunk.id,
                    name: chunk.name,
                    input: chunk.input,
                  });
                  hasUserVisibleAssistantOutput = true;
                  shouldStartNewAssistantTextBlock = true;
                  assistantContent.push({
                    type: "tool_use",
                    id: chunk.id,
                    name: chunk.name,
                    input: chunk.input,
                  });
                  if (!startedToolUseIds.has(chunk.id)) {
                    sendChunk({
                      type: "tool_start",
                      toolName: chunk.name,
                      toolCallId: chunk.id,
                      toolArguments: JSON.stringify(chunk.input),
                    });
                  }
                }
              } else if (chunk.type === "sources") {
                for (const item of chunk.items) {
                  collectedSources.set(item.url, item);
                }
              } else if (chunk.type === "thinking_start") {
                sendChunk({ type: "status", status: "thinking" });
              } else if (chunk.type === "thinking") {
                shouldStartNewAssistantTextBlock = true;
                assistantContent.push({
                  type: "thinking",
                  thinking: chunk.thinking,
                  signature: chunk.signature,
                });
              } else if (chunk.type === "redacted_thinking") {
                shouldStartNewAssistantTextBlock = true;
                assistantContent.push({
                  type: "redacted_thinking",
                  data: chunk.data,
                });
              }
            }

            conversationMessages.push({
              role: "assistant",
              content: assistantContent.length > 0 ? assistantContent : "",
            });

            if (req.signal.aborted || toolUses.length === 0) {
              break;
            }

            const executedToolUses =
              toolUses.length > 1 && toolUses.every(isReadOnlyToolUse)
                ? await Promise.all(
                  toolUses.map((toolUse) => executeSingleToolUse(ctx, toolUse)),
                )
                : await (async () => {
                  const results: Array<
                    Awaited<ReturnType<typeof executeSingleToolUse>>
                  > = [];
                  for (const toolUse of toolUses) {
                    results.push(await executeSingleToolUse(ctx, toolUse));
                  }
                  return results;
                })();

            const toolResults: ToolResultContent[] = [];
            for (const executed of executedToolUses) {
              sendChunk(executed.uiChunk);
              toolResults.push(executed.toolResult);
            }

            const toolResultBlocks: ContentBlock[] = [...toolResults];
            if (toolResults.some((result) => result.is_error)) {
              toolResultBlocks.push({
                type: "text",
                text:
                  "Note: Some tool calls failed. Please analyze the error messages and try again with corrected parameters if possible, or explain the issue to the user if you cannot proceed.",
              });
            }

            conversationMessages.push({
              role: "user",
              content: toolResultBlocks,
            });
          }
        } catch (error) {
          aiLoopFailed = true;
          log(
            "error",
            requestId,
            "Mistral loop failed",
            getLoggableErrorMetadata(error),
          );
          sendChunk({
            type: "error",
            error: getPublicErrorMessage(error),
          });
        }

        if (!aiLoopFailed && !req.signal.aborted) {
          latestCompactionContent = await maybeCreateCompactionSummary({
            apiKey: mistral.apiKey,
            instructions,
            messages: conversationMessages,
            signal: req.signal,
          }).catch((error) => {
            log(
              "warn",
              requestId,
              "Compaction summary failed",
              getLoggableErrorMetadata(error),
            );
            return undefined;
          });
        }

        if (
          !aiLoopFailed && !hasUserVisibleAssistantOutput && !req.signal.aborted
        ) {
          log("warn", requestId, "No user-visible assistant output");
          sendChunk({
            type: "error",
            error: "No response from Mistral provider",
          });
        }

        if (iterationCount >= MAX_ITERATIONS) {
          log("warn", requestId, "Max iterations reached", { iterationCount });
          if (!invocationConsumed) {
            const didConsume = await ensureInvocationConsumed();
            if (!didConsume) {
              return;
            }
          }
          sendChunk({ type: "text", content: `\n\n${maxIterationsReached}` });
        }

        if (!invocationConsumed) {
          finalRemaining = Math.max(0, Number(access.remaining) || 0);
          finalBonus = Math.max(0, Number(access.bonus) || 0);
        }

        if (supportsRichSources && collectedSources.size > 0) {
          sendChunk({
            type: "wagey_sources",
            items: Array.from(collectedSources.values()),
          });
        }

        sendChunk({
          type: "wagey_limit",
          remaining: finalRemaining,
          resetDays: getResetDays(access.resetDate),
          exceeded: finalRemaining + finalBonus <= 0,
          bonus: finalBonus,
        });

        if (latestCompactionContent) {
          sendChunk({
            type: "wagey_compaction",
            content: latestCompactionContent,
          });
        }

        sendChunk({ type: "done" });
        closeStream("done");
      } catch (error) {
        if (streamClosed || req.signal.aborted) {
          closeStream("aborted");
          return;
        }
        log(
          "error",
          requestId,
          "Stream start failed",
          getLoggableErrorMetadata(error),
        );
        sendErrorAndClose(getPublicErrorMessage(error));
      }
    },
    cancel() {},
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
      "Content-Encoding": "identity",
      Connection: "keep-alive",
    },
  });
}
