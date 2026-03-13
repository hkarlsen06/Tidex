/**
 * Wagey Chat Router
 *
 * River stream definition for the chat interface.
 * Uses OpenAI Responses API over WebSocket mode.
 */

import { z } from "zod";
import { NextRequest } from "next/server";
import { Effect } from "effect";
import {
  createRiverStream,
  createRiverRouter,
  defaultRiverProvider,
} from "@/lib/river";
import type {
  Message,
  CompactionContent,
  ContentBlock,
  ImageContent,
  Source,
  Tool,
  ToolResultContent,
} from "@/lib/services/ai-types";
import { getSystemPrompt, type SystemPromptContext } from "./system-prompt";
import { tools, type ToolName } from "./tools";
import { executeTool } from "./executor";
import { LOCALE_COOKIE, defaultLocale, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import type {
  OpenAIInputItem,
  OpenAIResponseSession,
} from "@/lib/services/openai";
import { toOpenAIInput } from "@/lib/services/openai";

/**
 * Chat chunk types (sent to frontend)
 */
export type ChatChunk =
  | {
      type: "text";
      content: string;
    }
  | {
      type: "status";
      status: "thinking";
    }
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
  | {
      type: "done";
    }
  | {
      type: "error";
      error: string;
    }
  | {
      type: "wagey_limit";
      remaining: number;
      resetDays: number;
      /** Whether the limit was exceeded (added in 2.2.0, optional for backwards compatibility) */
      exceeded?: boolean;
      /** Remaining bonus messages */
      bonus?: number;
    }
  | {
      type: "wagey_no_access";
    }
  | {
      type: "wagey_sources";
      items: Source[];
    }
  | {
      type: "wagey_built_in_tool_start";
      toolName: string;
      toolCallId: string;
    }
  | {
      type: "wagey_built_in_tool_result";
      toolName: string;
      toolCallId: string;
      result: string;
      success: boolean;
    }
  | {
      /**
       * Optional compaction state for clients that support it.
       * Older clients ignore unknown chunk types.
       */
      type: "wagey_compaction";
      content: string;
    };

/**
 * Image content block schema (for multimodal messages)
 */
const imageContentBlockSchema = z.object({
  type: z.literal("image"),
  source: z.object({
    type: z.literal("base64"),
    media_type: z.string(),
    data: z.string(),
  }),
});

/**
 * Text content block schema
 */
const textContentBlockSchema = z.object({
  type: z.literal("text"),
  text: z.string(),
});

/**
 * Content can be a string or array of content blocks (for multimodal messages)
 */
const contentSchema = z.union([
  z.string().nullable(),
  z.array(z.union([textContentBlockSchema, imageContentBlockSchema])),
]);

const clientCapabilitySchema = z.enum([
  "rich_sources_v1",
  "rich_built_in_tool_events_v1",
]);

const clientContextSchema = z
  .object({
    platform: z.enum(["ios", "web"]).optional(),
    appVersion: z.string().optional(),
    capabilities: z.array(clientCapabilitySchema).optional(),
  })
  .optional();

/**
 * Chat input schema (from frontend - OpenAI format for backwards compatibility)
 * Now supports multimodal content (images) in user messages
 */
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
          })
        )
        .optional(),
      tool_call_id: z.string().optional(),
      name: z.string().optional(),
    })
  ),
  userId: z.string().uuid(),
  userName: z.string().optional(),
  /**
   * Optional compaction summary to preserve long conversation context across requests.
   * Backwards compatible: older clients omit this field.
   */
  compaction: z.string().optional(),
  client: clientContextSchema,
});

export type ChatInput = z.infer<typeof chatInputSchema>;

const BUILT_IN_TOOLS: Tool[] = [
  {
    type: "web_search",
    search_context_size: "medium",
  },
  {
    type: "code_interpreter",
    container: {
      type: "auto",
    },
  },
];

/**
 * Helper to extract text from content (handles both string and array formats)
 */
function extractTextContent(content: ChatInput["messages"][0]["content"]): string {
  if (typeof content === "string") {
    return content;
  }
  if (content === null) {
    return "";
  }
  // Array of content blocks - extract text
  return content
    .filter((block): block is z.infer<typeof textContentBlockSchema> => block.type === "text")
    .map((block) => block.text)
    .join("");
}

/**
 * Convert OpenAI-style messages from frontend to provider-neutral model history.
 * Supports multimodal messages with images
 */
export function convertToOpenAIMessages(
  openAiMessages: ChatInput["messages"],
  compaction?: string
): { system?: string; messages: Message[] } {
  let systemPrompt: string | undefined;
  const modelMessages: Message[] = [];

  if (compaction) {
    modelMessages.push({
      role: "assistant",
      content: [
        {
          type: "compaction",
          content: compaction,
        } satisfies CompactionContent,
      ],
    });
  }

  for (const msg of openAiMessages) {
    // Extract system prompt separately (Claude doesn't include it in messages)
    if (msg.role === "system") {
      systemPrompt = extractTextContent(msg.content) || undefined;
      continue;
    }

    // Handle user messages (may include images)
    if (msg.role === "user") {
      // Check if content is multimodal (array with images)
      if (Array.isArray(msg.content)) {
        const hasImages = msg.content.some((block) => block.type === "image");
        if (hasImages) {
          const modelContent: ContentBlock[] = msg.content.map((block) => {
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
            // Text block
            return {
              type: "text" as const,
              text: block.text,
            };
          });

          modelMessages.push({
            role: "user",
            content: modelContent,
          });
          continue;
        }
      }

      modelMessages.push({
        role: "user",
        content: extractTextContent(msg.content),
      });
      continue;
    }

    // Handle assistant messages with tool calls
    if (msg.role === "assistant") {
      const contentBlocks: ContentBlock[] = [];

      // Add text content if present
      const textContent = extractTextContent(msg.content);
      if (textContent) {
        contentBlocks.push({
          type: "text",
          text: textContent,
        });
      }

      // Add tool use blocks
      if (msg.tool_calls) {
        for (const toolCall of msg.tool_calls) {
          let input: Record<string, unknown> = {};
          try {
            input = JSON.parse(toolCall.function.arguments);
          } catch {
            // Keep empty input on parse failure
          }

          contentBlocks.push({
            type: "tool_use",
            id: toolCall.id,
            name: toolCall.function.name,
            input,
          });
        }
      }

      modelMessages.push({
        role: "assistant",
        content: contentBlocks.length > 0 ? contentBlocks : textContent,
      });
      continue;
    }

    if (msg.role === "tool" && msg.tool_call_id) {
      const resultContent = extractTextContent(msg.content);
      const lastMessage = modelMessages[modelMessages.length - 1];
      if (lastMessage?.role === "user" && Array.isArray(lastMessage.content)) {
        (lastMessage.content as ContentBlock[]).push({
          type: "tool_result",
          tool_use_id: msg.tool_call_id,
          content: resultContent,
        });
      } else {
        modelMessages.push({
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: msg.tool_call_id,
              content: resultContent,
            },
          ],
        });
      }
    }
  }

  return { system: systemPrompt, messages: modelMessages };
}

async function openOpenAISession(
  abortSignal: AbortSignal
): Promise<OpenAIResponseSession> {
  const { OpenAIService } = await import("@/lib/services/openai");
  const { OpenAILive } = await import("@/lib/layers/app");

  const getSession = Effect.gen(function* () {
    const openai = yield* OpenAIService;
    return yield* openai.openSession({
      signal: abortSignal,
    });
  }).pipe(Effect.provide(OpenAILive), Effect.scoped);

  return Effect.runPromise(getSession);
}

function buildToolResultInput(
  toolResults: ToolResultContent[],
  hasFailures: boolean
): OpenAIInputItem[] {
  const input: OpenAIInputItem[] = toolResults.map((result) => ({
    type: "function_call_output",
    call_id: result.tool_use_id,
    output: result.content,
  }));

  if (hasFailures) {
    input.push({
      type: "message",
      role: "user",
      content: [
        {
          type: "input_text",
          text: "Some tool calls failed. Analyze the errors, retry with corrected parameters if possible, or explain clearly what blocked the request.",
        },
      ],
    });
  }

  return input;
}

function hasClientCapability(
  client: ChatInput["client"],
  capability: z.infer<typeof clientCapabilitySchema>
): boolean {
  return client?.capabilities?.includes(capability) ?? false;
}

type PendingToolUse = {
  id: string;
  name: string;
  input: Record<string, unknown>;
};

type ExecutedToolUse = {
  uiChunk: Extract<ChatChunk, { type: "tool_result" }>;
  toolResult: ToolResultContent;
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

function isReadOnlyToolUse(toolUse: PendingToolUse): boolean {
  const toolName = toolUse.name as ToolName;

  if (READ_ONLY_TOOL_NAMES.has(toolName)) {
    return true;
  }

  if (toolName === "manage_settings") {
    return toolUse.input.action === undefined || toolUse.input.action === "view";
  }

  if (toolName === "manage_recurring_shift") {
    return toolUse.input.action === "list";
  }

  return false;
}

async function executeSingleToolUse(
  toolUse: PendingToolUse,
  userId: string,
  locale: Locale
): Promise<ExecutedToolUse> {
  try {
    const invalidJson = toolUse.input.INVALID_JSON;
    if (typeof invalidJson === "string") {
      const invalidResult = {
        success: false,
        message:
          "Tool input was invalid or incomplete JSON. Please resend a valid JSON object for this tool call.",
        invalid_input: {
          INVALID_JSON: invalidJson,
        },
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
      toolUse.name as ToolName,
      JSON.stringify(toolUse.input),
      userId,
      locale
    );
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
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    const serialized = JSON.stringify({
      success: false,
      message: errorMessage,
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

/**
 * Wagey Chat Stream
 *
 * Uses in-memory provider (no Redis persistence).
 * Redis support removed due to connection issues in development.
 */
const wageyChatStream = createRiverStream<ChatChunk, NextRequest>()
  .input(chatInputSchema)
  .provider(defaultRiverProvider())
  .runner(async ({ input, stream, abortSignal, adapterRequest }) => {
    const { messages, userId, userName, compaction, client } = input;
    const supportsRichSources = hasClientCapability(client, "rich_sources_v1");
    const supportsRichBuiltInToolEvents = hasClientCapability(
      client,
      "rich_built_in_tool_events_v1"
    );

    // Get locale from cookie for localized tool messages
    const locale = (adapterRequest.cookies.get(LOCALE_COOKIE)?.value || defaultLocale) as Locale;

    // Import dependencies
    const { getDaysUntilReset } = await import("@/lib/wagey/types");

    // Use DAL functions for wagey access (works with both Bearer token and cookies via Effect layer)
    // Note: We no longer block operations based on server-side subscription checks.
    // The iOS app handles entitlement via StoreKit which may have newer information than the DB.
    // We still track usage and send warnings, but let the device decide if the user can proceed.
    const { beginWageyTurn } = await import("@/data-access/wagey");
    let turn;
    try {
      turn = await beginWageyTurn(userId);
    } catch {
      await stream.appendChunk({
        type: "error",
        error: "Failed to initialize Wagey",
      });
      await stream.close();
      return;
    }

    const accessInfo = turn.access;
    const result = turn.invocation;

    // Normalize usage fields so warning logic stays correct even if older backends
    // omit bonus in RPC responses.
    const remaining = Math.max(0, Number(result.remaining) || 0);
    const bonusFromRpc = Number(result.bonus);
    const fallbackBonus = Number(accessInfo.bonus ?? 0);
    const bonus = Math.max(
      0,
      Number.isFinite(bonusFromRpc) ? bonusFromRpc : fallbackBonus
    );
    const effectiveRemaining = remaining + bonus;

    // Track if the limit was exceeded (for warning purposes, not blocking).
    // Only mark exceeded when the invocation was denied AND no effective credits remain.
    const limitExceeded = !result.allowed && effectiveRemaining <= 0;

    // Send warning if limit exceeded, but continue processing (backwards compatible)
    // iOS 2.1.0 will receive this but the stream continues with content
    // Newer iOS versions can use the 'exceeded' field to show appropriate UI
    if (limitExceeded) {
      await stream.appendChunk({
        type: "wagey_limit",
        remaining,
        resetDays: getDaysUntilReset(),
        exceeded: true,
        bonus,
      });
      // Note: We intentionally do NOT close the stream here anymore.
      // The operation continues and the device handles entitlement checks.
    }

    // Build system prompt context with usage info
    const systemPromptContext: SystemPromptContext = {
      accessLevel: accessInfo.level,
      used: result.count,
      remaining,
      bonus,
      userName,
    };

    // Convert messages and add system prompt if not present
    let { system, messages: modelMessages } = convertToOpenAIMessages(messages, compaction);

    // Use our system prompt if none provided
    if (!system) {
      system = getSystemPrompt(systemPromptContext);
    }

    // Agentic loop: continues until AI stops making tool calls
    let iterationCount = 0;
    const MAX_ITERATIONS = 10; // Safety limit to prevent infinite loops
    let aiLoopFailed = false;
    let hasUserVisibleAssistantOutput = false;
    let previousResponseId: string | undefined;
    let pendingInput = toOpenAIInput(modelMessages);
    const collectedSources = new Map<string, Source>();
    const announcedToolCallIds = new Set<string>();
    const session = await openOpenAISession(abortSignal);

    try {
      while (iterationCount < MAX_ITERATIONS) {
        iterationCount++;

        await stream.appendChunk({
          type: "status",
          status: "thinking",
        });

        const response = await session.createResponse({
          instructions: system,
          input: pendingInput,
          tools: [...tools, ...BUILT_IN_TOOLS],
          maxTokens: 2048,
          previousResponseId,
        });

        const toolUses: Array<{
          id: string;
          name: string;
          input: Record<string, unknown>;
        }> = [];

        for await (const chunk of response.events) {
          if (abortSignal.aborted) {
            break;
          }

          if (chunk.type === "text") {
            hasUserVisibleAssistantOutput = true;
            await stream.appendChunk({
              type: "text",
              content: chunk.content,
            });
          } else if (chunk.type === "tool_start") {
            hasUserVisibleAssistantOutput = true;
            announcedToolCallIds.add(chunk.id);
            await stream.appendChunk({
              type: "tool_start",
              toolName: chunk.name,
              toolCallId: chunk.id,
            });
          } else if (chunk.type === "built_in_tool_start") {
            if (supportsRichBuiltInToolEvents) {
              hasUserVisibleAssistantOutput = true;
              await stream.appendChunk({
                type: "wagey_built_in_tool_start",
                toolName: chunk.name,
                toolCallId: chunk.id,
              });
            }
          } else if (chunk.type === "built_in_tool_result") {
            if (supportsRichBuiltInToolEvents) {
              hasUserVisibleAssistantOutput = true;
              await stream.appendChunk({
                type: "wagey_built_in_tool_result",
                toolName: chunk.name,
                toolCallId: chunk.id,
                result: JSON.stringify(chunk.summary),
                success: chunk.success,
              });
            }
          } else if (chunk.type === "sources") {
            for (const item of chunk.items) {
              collectedSources.set(item.url, item);
            }
          } else if (chunk.type === "tool_use") {
            // Check for duplicate tool calls
            const isDuplicateCall = toolUses.some(
              (use) =>
                use.name === chunk.name &&
                JSON.stringify(use.input) === JSON.stringify(chunk.input)
            );

            if (!isDuplicateCall) {
              toolUses.push({
                id: chunk.id,
                name: chunk.name,
                input: chunk.input,
              });
              hasUserVisibleAssistantOutput = true;

              // Send tool_start chunk to frontend unless an early start signal
              // has already been forwarded for this call.
              if (!announcedToolCallIds.has(chunk.id)) {
                announcedToolCallIds.add(chunk.id);
                await stream.appendChunk({
                  type: "tool_start",
                  toolName: chunk.name,
                  toolCallId: chunk.id,
                  toolArguments: JSON.stringify(chunk.input),
                });
              }
            }
          }
        }

        const completion = await response.completed;
        previousResponseId = completion.responseId ?? previousResponseId;

        if (abortSignal.aborted) {
          break;
        }

        if (toolUses.length === 0) {
          break;
        }

        const canRunInParallel =
          toolUses.length > 1 && toolUses.every(isReadOnlyToolUse);
        const executedToolUses = canRunInParallel
          ? await Promise.all(
              toolUses.map((toolUse) =>
                executeSingleToolUse(toolUse, userId, locale)
              )
            )
          : await (async () => {
              const results: ExecutedToolUse[] = [];
              for (const toolUse of toolUses) {
                results.push(await executeSingleToolUse(toolUse, userId, locale));
              }
              return results;
            })();

        const toolResults: ToolResultContent[] = [];

        for (const executedToolUse of executedToolUses) {
          await stream.appendChunk(executedToolUse.uiChunk);
          toolResults.push(executedToolUse.toolResult);
        }

        const hasFailures = toolResults.some((result) => result.is_error);
        pendingInput = buildToolResultInput(toolResults, hasFailures);
      }
    } catch (error) {
      aiLoopFailed = true;
      const message =
        error instanceof Error
          ? error.message
          : "AI stream failed before producing a response";
      await stream.appendChunk({
        type: "error",
        error: message,
      });
    } finally {
      await session.close();
    }

    if (!aiLoopFailed && !hasUserVisibleAssistantOutput && !abortSignal.aborted) {
      await stream.appendChunk({
        type: "error",
        error: "No response from AI provider",
      });
    }

    // If we hit max iterations, inform the user
    if (iterationCount >= MAX_ITERATIONS) {
      const dict = getDictionary(locale);
      await stream.appendChunk({
        type: "text",
        content: `\n\n${dict.pages.wagey.maxIterationsReached}`,
      });
    }

    if (supportsRichSources && collectedSources.size > 0) {
      await stream.appendChunk({
        type: "wagey_sources",
        items: Array.from(collectedSources.values()),
      });
    }

    // Always send usage info so client can update progress bar
    await stream.appendChunk({
      type: "wagey_limit",
      remaining,
      resetDays: getDaysUntilReset(),
      exceeded: limitExceeded,
      bonus,
    });

    // Send done chunk
    await stream.appendChunk({ type: "done" });

    await stream.close();
  });

/**
 * Chat Router
 */
export const chatRouter = createRiverRouter({
  wagey: wageyChatStream.build(),
});

export type ChatRouter = typeof chatRouter;
