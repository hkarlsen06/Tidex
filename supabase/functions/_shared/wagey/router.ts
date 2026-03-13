import { z } from "npm:zod";

import type {
  CompactionContent,
  ContentBlock,
  ImageContent,
  Message,
  RedactedThinkingContent,
  ThinkingContent,
  ToolResultContent,
} from "./ai-types.ts";
import { DEFAULT_CLAUDE_MODEL, streamClaudeChat } from "./claude.ts";
import type { WageyRequestContext } from "./context.ts";
import { beginWageyTurn } from "./data.ts";
import { executeTool } from "./executor.ts";
import { maxIterationsReached } from "./i18n.ts";
import { getSystemPrompt, type SystemPromptContext } from "./system-prompt.ts";
import { tools, type ToolName } from "./tools.ts";

const REQUEST_ID_HEADER = "x-wagey-request-id";
const SSE_HEARTBEAT_MS = 1_000;
const SSE_FLUSH_PADDING = ": " + " ".repeat(2048) + "\n\n";

export type ChatChunk =
  | { type: "text"; content: string }
  | { type: "status"; status: "thinking" }
  | { type: "tool_start"; toolName: string; toolCallId: string; toolArguments?: string }
  | { type: "tool_result"; toolName: string; toolCallId: string; result: string; success: boolean }
  | { type: "done" }
  | { type: "error"; error: string }
  | { type: "wagey_limit"; remaining: number; resetDays: number; exceeded?: boolean; bonus?: number }
  | { type: "wagey_no_access" }
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

const clientCapabilitySchema = z.enum(["rich_sources_v1", "rich_built_in_tool_events_v1"]);

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

function extractTextContent(content: ChatInput["messages"][0]["content"]): string {
  if (typeof content === "string") return content;
  if (content === null) return "";
  return content
    .filter((block): block is z.infer<typeof textContentBlockSchema> => block.type === "text")
    .map((block) => block.text)
    .join("");
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
      content: [{ type: "compaction", content: compaction } satisfies CompactionContent],
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

function isReadOnlyToolUse(toolUse: PendingToolUse): boolean {
  const toolName = toolUse.name as ToolName;
  if (READ_ONLY_TOOL_NAMES.has(toolName)) return true;
  if (toolName === "manage_settings") return toolUse.input.action === undefined || toolUse.input.action === "view";
  if (toolName === "manage_recurring_shift") return toolUse.input.action === "list";
  return false;
}

async function executeSingleToolUse(
  ctx: WageyRequestContext,
  toolUse: PendingToolUse,
): Promise<{ uiChunk: Extract<ChatChunk, { type: "tool_result" }>; toolResult: ToolResultContent }> {
  try {
    const invalidJson = toolUse.input.INVALID_JSON;
    if (typeof invalidJson === "string") {
      const invalidResult = {
        success: false,
        message: "Tool input was invalid or incomplete JSON. Please resend a valid JSON object for this tool call.",
        invalid_input: { INVALID_JSON: invalidJson },
      };
      const serialized = JSON.stringify(invalidResult);
      return {
        uiChunk: { type: "tool_result", toolName: toolUse.name, toolCallId: toolUse.id, result: serialized, success: false },
        toolResult: { type: "tool_result", tool_use_id: toolUse.id, content: serialized, is_error: true },
      };
    }

    const result = await executeTool(ctx, toolUse.name, JSON.stringify(toolUse.input));
    const serialized = JSON.stringify(result);
    return {
      uiChunk: { type: "tool_result", toolName: toolUse.name, toolCallId: toolUse.id, result: serialized, success: result.success },
      toolResult: { type: "tool_result", tool_use_id: toolUse.id, content: serialized, is_error: !result.success },
    };
  } catch (error) {
    const serialized = JSON.stringify({
      success: false,
      message: error instanceof Error ? error.message : "Unknown error",
    });
    return {
      uiChunk: { type: "tool_result", toolName: toolUse.name, toolCallId: toolUse.id, result: serialized, success: false },
      toolResult: { type: "tool_result", tool_use_id: toolUse.id, content: serialized, is_error: true },
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

function log(level: "info" | "warn" | "error", requestId: string, message: string, metadata: Record<string, unknown> = {}): void {
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

function getClaudeConfig(): { apiKey: string; model: string } {
  const apiKey = Deno.env.get("CLAUDE_API_KEY")?.trim() ?? "";
  const model = Deno.env.get("CLAUDE_MODEL")?.trim() ?? DEFAULT_CLAUDE_MODEL;

  if (!apiKey) {
    throw new Error("Missing CLAUDE_API_KEY");
  }

  return { apiKey, model };
}

function getResetDays(resetDate: Date | null): number {
  const targetDate = resetDate ?? new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1);
  return Math.max(0, Math.ceil((targetDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24)));
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
  const ctx = typeof ctxOrFactory === "function" ? await ctxOrFactory() : ctxOrFactory;

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let streamClosed = false;
      let heartbeatHandle: number | null = null;

      const sendChunk = (chunk: ChatChunk) => {
        if (streamClosed) return;

        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: "chunk", chunk })}\n\n`));
      };

      const sendComment = (comment: string) => {
        if (streamClosed) return;
        controller.enqueue(encoder.encode(`: ${comment}\n\n`));
      };

      const closeStream = (reason: string) => {
        if (streamClosed) return;
        streamClosed = true;
        if (heartbeatHandle !== null) {
          clearInterval(heartbeatHandle);
          heartbeatHandle = null;
        }
        controller.close();
      };

      const sendErrorAndClose = (message: string) => {
        log("error", requestId, "Sending stream error", { error: message });
        try {
          sendChunk({ type: "error", error: message });
        } finally {
          closeStream("error");
        }
      };

      try {
        controller.enqueue(encoder.encode(SSE_FLUSH_PADDING));
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

        const turn = await beginWageyTurn(ctx);
        const remaining = Math.max(0, Number(turn.invocation.remaining) || 0);
        const bonus = Math.max(0, Number(turn.invocation.bonus) || 0);
        const limitExceeded = !turn.invocation.allowed && remaining + bonus <= 0;

        if (limitExceeded) {
          sendChunk({
            type: "wagey_limit",
            remaining,
            resetDays: getResetDays(turn.access.resetDate),
            exceeded: true,
            bonus,
          });
        }

        const systemContext: SystemPromptContext = {
          accessLevel: turn.access.level,
          used: turn.invocation.count,
          remaining,
          bonus,
          userName: input.userName,
        };

        let { system, messages } = convertToClaudeMessages(input.messages, input.compaction);
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

        try {
          while (iterationCount < MAX_ITERATIONS) {
            iterationCount += 1;
            sendChunk({ type: "status", status: "thinking" });

            const toolUses: PendingToolUse[] = [];
            let currentTextContent = "";
            let compactionBlock: CompactionContent | null = null;
            const thinkingBlocks: Array<ThinkingContent | RedactedThinkingContent> = [];

            for await (const chunk of streamClaudeChat({
              apiKey: claude.apiKey,
              model: claude.model,
              system,
              messages: conversationMessages,
              tools,
              maxTokens: 2048,
              signal: req.signal,
            })) {
              if (req.signal.aborted) break;

              if (chunk.type === "text") {
                hasUserVisibleAssistantOutput = true;
                currentTextContent += chunk.content;
                sendChunk({ type: "text", content: chunk.content });
              } else if (chunk.type === "tool_use") {
                const duplicate = toolUses.some((use) => use.name === chunk.name && JSON.stringify(use.input) === JSON.stringify(chunk.input));
                if (!duplicate) {
                  toolUses.push({ id: chunk.id, name: chunk.name, input: chunk.input });
                  hasUserVisibleAssistantOutput = true;
                  sendChunk({
                    type: "tool_start",
                    toolName: chunk.name,
                    toolCallId: chunk.id,
                    toolArguments: JSON.stringify(chunk.input),
                  });
                }
              } else if (chunk.type === "compaction") {
                compactionBlock = { type: "compaction", content: chunk.content };
                latestCompactionContent = chunk.content;
              } else if (chunk.type === "thinking") {
                thinkingBlocks.push({
                  type: "thinking",
                  thinking: chunk.thinking,
                  signature: chunk.signature,
                });
              } else if (chunk.type === "redacted_thinking") {
                thinkingBlocks.push({
                  type: "redacted_thinking",
                  data: chunk.data,
                });
              }
            }

            const assistantContent: ContentBlock[] = [];
            if (compactionBlock) {
              assistantContent.push(compactionBlock);
            }
            if (thinkingBlocks.length > 0) {
              assistantContent.push(...thinkingBlocks);
            }
            if (currentTextContent) {
              assistantContent.push({ type: "text", text: currentTextContent });
            }
            for (const toolUse of toolUses) {
              assistantContent.push({
                type: "tool_use",
                id: toolUse.id,
                name: toolUse.name,
                input: toolUse.input,
              });
            }

            conversationMessages.push({
              role: "assistant",
              content: assistantContent.length > 0 ? assistantContent : currentTextContent,
            });

            if (req.signal.aborted || toolUses.length === 0) {
              break;
            }

            const executedToolUses = toolUses.length > 1 && toolUses.every(isReadOnlyToolUse)
              ? await Promise.all(toolUses.map((toolUse) => executeSingleToolUse(ctx, toolUse)))
              : await (async () => {
                  const results: Array<Awaited<ReturnType<typeof executeSingleToolUse>>> = [];
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
                text: "Note: Some tool calls failed. Please analyze the error messages and try again with corrected parameters if possible, or explain the issue to the user if you cannot proceed.",
              });
            }

            conversationMessages.push({
              role: "user",
              content: toolResultBlocks,
            });
          }
        } catch (error) {
          aiLoopFailed = true;
          log("error", requestId, "Claude loop failed", {
            error: error instanceof Error ? error.message : String(error),
          });
          sendChunk({
            type: "error",
            error: error instanceof Error ? error.message : "Claude stream failed before producing a response",
          });
        }

        if (!aiLoopFailed && !hasUserVisibleAssistantOutput && !req.signal.aborted) {
          log("warn", requestId, "No user-visible assistant output");
          sendChunk({ type: "error", error: "No response from Claude provider" });
        }

        if (iterationCount >= MAX_ITERATIONS) {
          log("warn", requestId, "Max iterations reached", { iterationCount });
          sendChunk({ type: "text", content: `\n\n${maxIterationsReached}` });
        }

        sendChunk({
          type: "wagey_limit",
          remaining,
          resetDays: getResetDays(turn.access.resetDate),
          exceeded: limitExceeded,
          bonus,
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
        log("error", requestId, "Stream start failed", {
          error: error instanceof Error ? error.message : String(error),
        });
        sendErrorAndClose(error instanceof Error ? error.message : "Failed to initialize Wagey");
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
