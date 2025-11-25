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
import { getSystemPrompt } from "./system-prompt";
import { tools, type ToolName } from "./tools";
import { executeTool } from "./executor";

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
  .runner(async ({ input, stream, abortSignal }) => {
    const { messages, userId } = input;

    // Check Wagey access and usage limits BEFORE Claude API call
    // Use getWageyAccessForUser (not getWageyAccess) because we're in a Route Handler
    // where verifySession()/redirect() doesn't work
    const { getWageyAccessForUser, useWageyInvocation } = await import("@/data-access/wagey");
    const { getDaysUntilReset } = await import("@/lib/wagey/types");

    const access = await getWageyAccessForUser(userId);

    // Free users cannot use Wagey
    if (!access.hasAccess) {
      await stream.appendChunk({ type: "wagey_no_access" });
      await stream.close();
      return;
    }

    // Grandfathered users skip limit check
    if (access.level !== "grandfathered") {
      const result = await useWageyInvocation(userId);

      if (!result.allowed) {
        await stream.appendChunk({
          type: "wagey_limit",
          remaining: result.remaining,
          resetDays: getDaysUntilReset(),
        });
        await stream.close();
        return;
      }
    }

    // Convert messages and add system prompt if not present
    let { system, messages: claudeMessages } = convertToClaudeMessages(messages);

    // Use our system prompt if none provided
    if (!system) {
      system = getSystemPrompt();
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
            userId
          );

          // Only send tool_result chunk to UI if successful
          if (result.success) {
            await stream.appendChunk({
              type: "tool_result",
              toolName: toolUse.name,
              toolCallId: toolUse.id,
              result: JSON.stringify(result),
              success: true,
            });
          }

          toolResults.push({
            type: "tool_result",
            tool_use_id: toolUse.id,
            content: JSON.stringify(result),
            is_error: !result.success,
          });
        } catch (error) {
          const errorMessage =
            error instanceof Error ? error.message : "Ukjent feil";

          toolResults.push({
            type: "tool_result",
            tool_use_id: toolUse.id,
            content: JSON.stringify({
              success: false,
              message: errorMessage,
            }),
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
      await stream.appendChunk({
        type: "text",
        content:
          "\n\n(Nådde maksimalt antall handlinger. Hvis du trenger mer hjelp, send en ny melding.)",
      });
    }

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
