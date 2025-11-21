/**
 * Wagey Chat Router
 *
 * River stream definition for the chat interface
 */

import { z } from "zod";
import { NextRequest } from "next/server";
import { Effect } from "effect";
import {
  createRiverStream,
  createRiverRouter,
  defaultRiverProvider,
} from "@/lib/river";
import type { Message } from "@/lib/services/openrouter";
import { getSystemPrompt } from "./system-prompt";
import { tools, type ToolName } from "./tools";
import { executeTool } from "./executor";

/**
 * Chat chunk types
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
    };

/**
 * Chat input schema
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

    // Add system prompt if not present
    const messagesWithSystem: Message[] =
      messages[0]?.role === "system"
        ? (messages as Message[])
        : [
            { role: "system", content: getSystemPrompt() },
            ...(messages as Message[]),
          ];

    // Dynamically import OpenRouter service to avoid static analysis issues
    const { OpenRouterService } = await import("@/lib/services/openrouter");
    const { OpenRouterLive } = await import("@/lib/layers/app");

    // Agentic loop: continues until AI stops making tool calls
    let conversationMessages = [...messagesWithSystem];
    let iterationCount = 0;
    const MAX_ITERATIONS = 10; // Safety limit to prevent infinite loops

    while (iterationCount < MAX_ITERATIONS) {
      iterationCount++;

      // Get AI response
      const getAiStream = Effect.gen(function* () {
        const openRouter = yield* OpenRouterService;
        return yield* openRouter.streamChat({
          messages: conversationMessages,
          tools,
          temperature: 0.7,
          maxTokens: 4000,
        });
      }).pipe(Effect.provide(OpenRouterLive), Effect.scoped);

      const aiStream = await Effect.runPromise(getAiStream);

      let currentAssistantMessage = "";
      const toolCalls: Array<{
        id: string;
        type: "function";
        function: { name: string; arguments: string };
      }> = [];

      // Process stream chunks
      for await (const chunk of aiStream) {
        if (abortSignal.aborted) {
          break;
        }

        if (chunk.type === "text") {
          currentAssistantMessage += chunk.content;
          await stream.appendChunk({
            type: "text",
            content: chunk.content,
          });
        } else if (chunk.type === "tool_call") {
          const isDuplicateCall = toolCalls.some(
            (call) =>
              call.function.name === chunk.toolCall.function.name &&
              call.function.arguments === chunk.toolCall.function.arguments
          );

          if (!isDuplicateCall) {
            toolCalls.push(chunk.toolCall);

            // Only send tool_start chunk for new tool calls (not duplicates)
            await stream.appendChunk({
              type: "tool_start",
              toolName: chunk.toolCall.function.name,
              toolCallId: chunk.toolCall.id,
              toolArguments: chunk.toolCall.function.arguments,
            });
          }
        }
      }

      // If aborted, break out of agentic loop
      if (abortSignal.aborted) {
        break;
      }

      // Add assistant message to conversation
      conversationMessages.push({
        role: "assistant",
        content: currentAssistantMessage || null,
        tool_calls: toolCalls.length > 0 ? toolCalls : undefined,
      });

      // If no tool calls, we're done - AI has decided to stop
      if (toolCalls.length === 0) {
        break;
      }

      // Execute all tool calls
      const toolResults = await Promise.all(
        toolCalls.map(async (toolCall) => {
          try {
            const result = await executeTool(
              toolCall.function.name as ToolName,
              toolCall.function.arguments,
              userId
            );

            // Only send tool_result chunk to UI if successful
            // Failures are only sent to AI for retry, not shown to user
            if (result.success) {
              await stream.appendChunk({
                type: "tool_result",
                toolName: toolCall.function.name,
                toolCallId: toolCall.id,
                result: JSON.stringify(result),
                success: true,
              });
            }

            return {
              toolCallId: toolCall.id,
              name: toolCall.function.name,
              content: JSON.stringify(result),
            };
          } catch (error) {
            const errorMessage =
              error instanceof Error ? error.message : "Ukjent feil";

            // Don't send error to UI - only to AI for retry
            // User sees "working" indicator while AI attempts to fix

            return {
              toolCallId: toolCall.id,
              name: toolCall.function.name,
              content: JSON.stringify({
                success: false,
                message: errorMessage,
              }),
            };
          }
        })
      );

      // Add tool results to conversation
      conversationMessages.push(
        ...toolResults.map((result) => ({
          role: "tool" as const,
          content: result.content,
          tool_call_id: result.toolCallId,
          name: result.name,
        }))
      );

      // Check if any tool calls failed
      const hasFailures = toolResults.some((result) => {
        try {
          const parsed = JSON.parse(result.content);
          return parsed.success === false;
        } catch {
          return false;
        }
      });

      // If there were failures, add a system hint to guide the AI to retry
      if (hasFailures) {
        conversationMessages.push({
          role: "system" as const,
          content:
            "The tool call failed. Please analyze the error message and try again with corrected parameters if possible, or explain the issue to the user if you cannot proceed.",
        });
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
