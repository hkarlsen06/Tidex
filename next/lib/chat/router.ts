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
});

export type ChatInput = z.infer<typeof chatInputSchema>;

/**
 * Verify authentication using the Effect-based auth service
 * Supports both Bearer token (iOS) and cookie session (web) via the service layer
 */
async function verifyAuthentication(
  _request: NextRequest,
  expectedUserId: string
): Promise<{ userId: string } | null> {
  const { AuthService } = await import("@/lib/services/auth");
  const { SupabaseAuthLive } = await import("@/lib/layers/app");

  const program = Effect.gen(function* () {
    const auth = yield* AuthService;
    const user = yield* auth.verifyUserId(expectedUserId);
    return user;
  }).pipe(
    Effect.provide(SupabaseAuthLive),
    Effect.scoped,
    Effect.catchAll(() => Effect.succeed(null))
  );

  const user = await Effect.runPromise(program);

  if (user) {
    return { userId: user.id };
  }

  return null;
}

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
    const { messages, userId, userName, compaction } = input;

    // Verify authentication first (supports both Bearer token for iOS and cookies for web)
    const authResult = await verifyAuthentication(adapterRequest, userId);
    if (!authResult) {
      await stream.appendChunk({
        type: "error",
        error: "Authentication failed",
      });
      await stream.close();
      return;
    }

    // Get locale from cookie for localized tool messages
    const locale = (adapterRequest.cookies.get(LOCALE_COOKIE)?.value || defaultLocale) as Locale;

    // Import dependencies
    const { getDaysUntilReset } = await import("@/lib/wagey/types");

    // Use DAL functions for wagey access (works with both Bearer token and cookies via Effect layer)
    // Note: We no longer block operations based on server-side subscription checks.
    // The iOS app handles entitlement via StoreKit which may have newer information than the DB.
    // We still track usage and send warnings, but let the device decide if the user can proceed.
    const { useWageyInvocation, getWageyAccessForUser } = await import("@/data-access/wagey");
    const accessInfo = await getWageyAccessForUser(userId);
    const result = await useWageyInvocation(userId);

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
    const session = await openOpenAISession(abortSignal);

    try {
      while (iterationCount < MAX_ITERATIONS) {
        iterationCount++;

        const response = await session.createResponse({
          instructions: system,
          input: pendingInput,
          tools,
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

              // Send tool_start chunk to frontend
              await stream.appendChunk({
                type: "tool_start",
                toolName: chunk.name,
                toolCallId: chunk.id,
                toolArguments: JSON.stringify(chunk.input),
              });
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

        const toolResults: ToolResultContent[] = [];

        for (const toolUse of toolUses) {
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

              await stream.appendChunk({
                type: "tool_result",
                toolName: toolUse.name,
                toolCallId: toolUse.id,
                result: JSON.stringify(invalidResult),
                success: false,
              });

              toolResults.push({
                type: "tool_result",
                tool_use_id: toolUse.id,
                content: JSON.stringify(invalidResult),
                is_error: true,
              });
              continue;
            }

            const result = await executeTool(
              toolUse.name as ToolName,
              JSON.stringify(toolUse.input),
              userId,
              locale
            );

            // Send tool_result chunk to UI for both success and failure
            // iOS needs this to track tool call state and include results in subsequent requests
            await stream.appendChunk({
              type: "tool_result",
              toolName: toolUse.name,
              toolCallId: toolUse.id,
              result: JSON.stringify(result),
              success: result.success,
            });

            toolResults.push({
              type: "tool_result",
              tool_use_id: toolUse.id,
              content: JSON.stringify(result),
              is_error: !result.success,
            });
          } catch (error) {
            const errorMessage =
              error instanceof Error ? error.message : "Unknown error";
            const errorResult = JSON.stringify({
              success: false,
              message: errorMessage,
            });

            // Send tool_result chunk to UI for exception case
            // iOS needs this to track tool call state and include results in subsequent requests
            await stream.appendChunk({
              type: "tool_result",
              toolName: toolUse.name,
              toolCallId: toolUse.id,
              result: errorResult,
              success: false,
            });

            toolResults.push({
              type: "tool_result",
              tool_use_id: toolUse.id,
              content: errorResult,
              is_error: true,
            });
          }
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
