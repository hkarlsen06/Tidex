/**
 * Wagey Chat Router
 *
 * River stream definition for the chat interface.
 * Uses Claude API directly for improved tool use with input_examples.
 */

import { z } from "zod";
import { NextRequest } from "next/server";
import { Effect } from "effect";
import {
  createRiverStream,
  createRiverRouter,
  defaultRiverProvider,
} from "@/lib/river";
import type { Message, ContentBlock, ToolResultContent } from "@/lib/services/claude";
import { getSystemPrompt, type SystemPromptContext } from "./system-prompt";
import { tools, type ToolName } from "./tools";
import { executeTool } from "./executor";
import { LOCALE_COOKIE, defaultLocale, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";

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
    }
  | {
      type: "wagey_no_access";
    };

/**
 * Chat input schema (from frontend - OpenAI format for backwards compatibility)
 */
const chatInputSchema = z.object({
  messages: z.array(
    z.object({
      role: z.enum(["system", "user", "assistant", "tool"]),
      content: z.string().nullable(),
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
 * Convert OpenAI-style messages from frontend to Claude format
 */
function convertToClaudeMessages(
  openAiMessages: ChatInput["messages"]
): { system?: string; messages: Message[] } {
  let systemPrompt: string | undefined;
  const claudeMessages: Message[] = [];

  for (const msg of openAiMessages) {
    // Extract system prompt separately (Claude doesn't include it in messages)
    if (msg.role === "system") {
      systemPrompt = msg.content || undefined;
      continue;
    }

    // Handle user messages
    if (msg.role === "user") {
      claudeMessages.push({
        role: "user",
        content: msg.content || "",
      });
      continue;
    }

    // Handle assistant messages with tool calls
    if (msg.role === "assistant") {
      const contentBlocks: ContentBlock[] = [];

      // Add text content if present
      if (msg.content) {
        contentBlocks.push({
          type: "text",
          text: msg.content,
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

      claudeMessages.push({
        role: "assistant",
        content: contentBlocks.length > 0 ? contentBlocks : msg.content || "",
      });
      continue;
    }

    // Handle tool results - Claude expects them as user messages with tool_result content
    if (msg.role === "tool" && msg.tool_call_id) {
      // Check if last message is a user message with tool results, if so append to it
      const lastMessage = claudeMessages[claudeMessages.length - 1];
      if (lastMessage?.role === "user" && Array.isArray(lastMessage.content)) {
        // Append to existing tool results
        (lastMessage.content as ContentBlock[]).push({
          type: "tool_result",
          tool_use_id: msg.tool_call_id,
          content: msg.content || "",
        });
      } else {
        // Create new user message with tool result
        claudeMessages.push({
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: msg.tool_call_id,
              content: msg.content || "",
            },
          ],
        });
      }
    }
  }

  return { system: systemPrompt, messages: claudeMessages };
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
    const { messages, userId, userName } = input;

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

    // Track if the limit was exceeded (for warning purposes, not blocking)
    const limitExceeded = !result.allowed;

    // Send warning if limit exceeded, but continue processing (backwards compatible)
    // iOS 2.1.0 will receive this but the stream continues with content
    // Newer iOS versions can use the 'exceeded' field to show appropriate UI
    if (limitExceeded) {
      await stream.appendChunk({
        type: "wagey_limit",
        remaining: result.remaining,
        resetDays: getDaysUntilReset(),
        exceeded: true,
      });
      // Note: We intentionally do NOT close the stream here anymore.
      // The operation continues and the device handles entitlement checks.
    }

    // Build system prompt context with usage info
    const systemPromptContext: SystemPromptContext = {
      accessLevel: accessInfo.level,
      used: result.count,
      remaining: result.remaining,
      userName,
    };

    // Convert messages and add system prompt if not present
    let { system, messages: claudeMessages } = convertToClaudeMessages(messages);

    // Use our system prompt if none provided
    if (!system) {
      system = getSystemPrompt(systemPromptContext);
    }

    // Dynamically import Claude service to avoid static analysis issues
    const { ClaudeService } = await import("@/lib/services/claude");
    const { ClaudeLive } = await import("@/lib/layers/app");

    // Agentic loop: continues until AI stops making tool calls
    let conversationMessages = [...claudeMessages];
    let iterationCount = 0;
    const MAX_ITERATIONS = 10; // Safety limit to prevent infinite loops

    while (iterationCount < MAX_ITERATIONS) {
      iterationCount++;

      // Get AI response
      const getAiStream = Effect.gen(function* () {
        const claude = yield* ClaudeService;
        return yield* claude.streamChat({
          system,
          messages: conversationMessages,
          tools,
          temperature: 0.7,
          maxTokens: 4096,
        });
      }).pipe(Effect.provide(ClaudeLive), Effect.scoped);

      const aiStream = await Effect.runPromise(getAiStream);

      let currentTextContent = "";
      const toolUses: Array<{
        id: string;
        name: string;
        input: Record<string, unknown>;
      }> = [];

      // Process stream chunks
      for await (const chunk of aiStream) {
        if (abortSignal.aborted) {
          break;
        }

        if (chunk.type === "text") {
          currentTextContent += chunk.content;
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

      // If aborted, break out of agentic loop
      if (abortSignal.aborted) {
        break;
      }

      // Build assistant message content blocks
      const assistantContent: ContentBlock[] = [];
      if (currentTextContent) {
        assistantContent.push({
          type: "text",
          text: currentTextContent,
        });
      }
      for (const toolUse of toolUses) {
        assistantContent.push({
          type: "tool_use",
          id: toolUse.id,
          name: toolUse.name,
          input: toolUse.input,
        });
      }

      // Add assistant message to conversation
      conversationMessages.push({
        role: "assistant",
        content: assistantContent.length > 0 ? assistantContent : currentTextContent,
      });

      // If no tool calls, we're done - AI has decided to stop
      if (toolUses.length === 0) {
        break;
      }

      // Execute all tool calls
      const toolResults: ToolResultContent[] = [];

      for (const toolUse of toolUses) {
        try {
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

      // Add tool results as a user message (Claude format)
      conversationMessages.push({
        role: "user",
        content: toolResults,
      });

      // Check if any tool calls failed
      const hasFailures = toolResults.some((result) => result.is_error);

      // If there were failures, add a system hint in the next user message
      if (hasFailures) {
        // Add hint as a text block to help Claude understand the failure
        const lastUserMessage = conversationMessages[conversationMessages.length - 1];
        if (Array.isArray(lastUserMessage.content)) {
          (lastUserMessage.content as ContentBlock[]).push({
            type: "text",
            text: "Note: Some tool calls failed. Please analyze the error messages and try again with corrected parameters if possible, or explain the issue to the user if you cannot proceed.",
          } as any);
        }
      }

      // Continue the loop - AI will get another chance to make tool calls or respond with text
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
      remaining: result.remaining,
      resetDays: getDaysUntilReset(),
      exceeded: limitExceeded,
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
