import { z } from "npm:zod";

import type {
  CompactionContent,
  ContentBlock,
  ImageContent,
  Message,
  RedactedThinkingContent,
  Source,
  ThinkingContent,
  Tool,
  ToolResultContent,
} from "./ai-types.ts";
import {
  ClaudeProviderError,
  DEFAULT_CLAUDE_MODEL,
  streamClaudeChat,
} from "./claude.ts";
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
    type: "web_search_20260209",
    name: "web_search",
    max_uses: 3,
  },
  {
    type: "web_fetch_20260209",
    name: "web_fetch",
    max_uses: 3,
  },
];

const READ_ONLY_TOOL_NAMES = new Set<ToolName>([
  "query_shifts",
  "query_events",
  "plan_schedule",
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

export function convertToClaudeMessages(
  openAiMessages: ChatInput["messages"],
  compaction?: string,
): { system?: string; messages: Message[] } {
  let systemPrompt: string | undefined;
  const claudeMessages: Message[] = [];

  if (compaction) {
    claudeMessages.push({
      role: "assistant",
      content: [
        { type: "compaction", content: compaction } satisfies CompactionContent,
      ],
    });
  }

  for (const msg of openAiMessages) {
    if (msg.role === "system") {
      systemPrompt = extractTextContent(msg.content) || undefined;
      continue;
    }

    if (msg.role === "user") {
      if (Array.isArray(msg.content)) {
        const hasImages = msg.content.some((block) => block.type === "image");
        if (hasImages) {
          claudeMessages.push({
            role: "user",
            content: msg.content.map((block) => {
              if (block.type === "image") {
                return {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: block.source.media_type,
                    data: block.source.data,
                  },
                } satisfies ImageContent;
              }
              return { type: "text", text: block.text };
            }),
          });
          continue;
        }
      }

      claudeMessages.push({
        role: "user",
        content: extractTextContent(msg.content),
      });
      continue;
    }

    if (msg.role === "assistant") {
      const contentBlocks: ContentBlock[] = [];
      const textContent = extractTextContent(msg.content);
      if (textContent) {
        contentBlocks.push({ type: "text", text: textContent });
      }

      if (msg.tool_calls) {
        for (const toolCall of msg.tool_calls) {
          let input: Record<string, unknown> = {};
          try {
            input = JSON.parse(toolCall.function.arguments);
          } catch {
            input = {};
          }

          contentBlocks.push({
            type: "tool_use",
            id: toolCall.id,
            name: toolCall.function.name,
            input,
          });
        }
      }

      claudeMessages.push({
        role: "assistant",
        content: contentBlocks.length > 0 ? contentBlocks : textContent,
      });
      continue;
    }

    if (msg.role === "tool" && msg.tool_call_id) {
      const resultContent = extractTextContent(msg.content);
      const lastMessage = claudeMessages[claudeMessages.length - 1];
      if (lastMessage?.role === "user" && Array.isArray(lastMessage.content)) {
        (lastMessage.content as ContentBlock[]).push({
          type: "tool_result",
          tool_use_id: msg.tool_call_id,
          content: resultContent,
        });
      } else {
        claudeMessages.push({
          role: "user",
          content: [{
            type: "tool_result",
            tool_use_id: msg.tool_call_id,
            content: resultContent,
          }],
        });
      }
    }
  }

  return { system: systemPrompt, messages: claudeMessages };
}

export function isReadOnlyToolUse(toolUse: PendingToolUse): boolean {
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

function getLatestUserText(messages: Message[]): string {
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const message = messages[i];
    if (message?.role !== "user") continue;
    if (typeof message.content === "string") return message.content;
    return message.content
      .filter((block): block is Extract<ContentBlock, { type: "text" }> =>
        block.type === "text"
      )
      .map((block) => block.text)
      .join(" ");
  }
  return "";
}

export function userLikelyRequestedWriteAction(text: string): boolean {
  const normalized = text.toLowerCase();
  return /\b(set|change|update|delete|remove|create|edit|save)\b/.test(
    normalized,
  ) ||
    /\b(kan du|endre|oppdater|slett|fjern|lag|sett)\b/.test(normalized);
}

export function assistantLikelyClaimsWriteAction(text: string): boolean {
  const normalized = text.toLowerCase();
  return /\b(done|updated|changed|created|deleted|saved|i('ve| have) (updated|changed|set|created|deleted|saved))\b/
    .test(normalized) ||
    /\b(i('| wi)ll (update|change|set|create|delete|save))\b/.test(
      normalized,
    ) ||
    /\b(jeg har (oppdatert|endret|satt|laget|slettet)|oppdatert|endret|satt)\b/
      .test(normalized) ||
    /\b(jeg skal (oppdatere|endre|sette|lage|slette))\b/.test(normalized);
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
  if (error instanceof ClaudeProviderError) {
    return error.publicMessage;
  }

  return error instanceof Error ? error.message : "Failed to initialize Wagey";
}

function getLoggableErrorMetadata(error: unknown): Record<string, unknown> {
  if (error instanceof ClaudeProviderError) {
    return {
      error: error.message,
      status: error.status,
      providerType: error.providerType,
      providerMessage: error.providerMessage,
      requestId: error.requestId,
      publicMessage: error.publicMessage,
    };
  }

  return {
    error: error instanceof Error ? error.message : String(error),
  };
}

function getClaudeConfig(): { apiKey: string; model: string } {
  const apiKey = Deno.env.get("CLAUDE_API_KEY")?.trim() ?? "";
  const configuredModel = Deno.env.get("CLAUDE_MODEL")?.trim() ?? "";

  if (!apiKey) {
    throw new Error("Missing CLAUDE_API_KEY");
  }

  const model = configuredModel.startsWith("claude-opus-4-6")
    ? configuredModel
    : DEFAULT_CLAUDE_MODEL;

  if (configuredModel && configuredModel !== model) {
    console.warn(JSON.stringify({
      scope: "wagey-router",
      message:
        "Ignoring unsupported CLAUDE_MODEL for Wagey; falling back to default Opus 4.6",
      configuredModel,
      fallbackModel: model,
    }));
  }

  return { apiKey, model };
}

function getResetDays(resetDate: Date | null): number {
  const targetDate = resetDate ??
    new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1);
  return Math.max(
    0,
    Math.ceil((targetDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24)),
  );
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

        let { system, messages } = convertToClaudeMessages(
          input.messages,
          input.compaction,
        );
        if (!system) {
          system = getSystemPrompt(systemContext);
        }

        const claude = getClaudeConfig();

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
              const chunk of streamClaudeChat({
                apiKey: claude.apiKey,
                model: claude.model,
                system,
                messages: conversationMessages,
                tools: [...tools, ...BUILT_IN_TOOLS],
                maxTokens: 2048,
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
                appendAssistantText(chunk.content);
                sendChunk({ type: "text", content: chunk.content });
                hasUserVisibleAssistantOutput = true;
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
              } else if (chunk.type === "compaction") {
                shouldStartNewAssistantTextBlock = true;
                assistantContent.push({
                  type: "compaction",
                  content: chunk.content,
                });
                latestCompactionContent = chunk.content;
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

            const assistantText = assistantContent
              .filter((
                block,
              ): block is Extract<ContentBlock, { type: "text" }> =>
                block.type === "text"
              )
              .map((block) => block.text)
              .join(" ")
              .trim();
            const latestUserText = getLatestUserText(
              conversationMessages.slice(0, -1),
            );
            const looksLikeUnexecutedWriteClaim = toolUses.length === 0 &&
              userLikelyRequestedWriteAction(latestUserText) &&
              assistantLikelyClaimsWriteAction(assistantText);

            if (looksLikeUnexecutedWriteClaim) {
              conversationMessages.push({
                role: "user",
                content: [{
                  type: "text",
                  text:
                    "System check: You implied a write action without executing a write tool. Either perform the required write tool call now, or clearly tell the user you cannot perform that change here.",
                }],
              });
              continue;
            }

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
            "Claude loop failed",
            getLoggableErrorMetadata(error),
          );
          sendChunk({
            type: "error",
            error: getPublicErrorMessage(error),
          });
        }

        if (
          !aiLoopFailed && !hasUserVisibleAssistantOutput && !req.signal.aborted
        ) {
          log("warn", requestId, "No user-visible assistant output");
          sendChunk({
            type: "error",
            error: "No response from Claude provider",
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
