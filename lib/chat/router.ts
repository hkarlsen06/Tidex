/**
 * Wagey Chat Router
 *
 * River stream definition for the chat interface.
 * Uses Claude API directly for improved tool use with input_examples.
 */

import { z } from "zod";
import { NextRequest } from "next/server";
import { Effect } from "effect";
import { createClient } from "@supabase/supabase-js";
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
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
 * Verify authentication from either Bearer token (iOS) or cookie session (web)
 * Returns the authenticated user ID or null if not authenticated
 */
async function verifyAuthentication(
  request: NextRequest,
  expectedUserId: string
): Promise<{ userId: string } | null> {
  // Try Bearer token first (native iOS app)
  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.substring(7);

    // Create a Supabase client with the user's JWT to verify it
    const supabaseWithToken = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
      {
        global: {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
      }
    );

    const { data, error } = await supabaseWithToken.auth.getUser();
    if (!error && data.user) {
      // Verify the token's user matches the requested userId
      if (data.user.id === expectedUserId) {
        return { userId: data.user.id };
      }
    }
  }

  // Fall back to cookie-based session (web app)
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.getUser();
    if (!error && data.user && data.user.id === expectedUserId) {
      return { userId: data.user.id };
    }
  } catch {
    // Cookie-based auth failed
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

    // Check if this is a Bearer token request (iOS) - needs direct DB access
    const isBearerAuth = adapterRequest.headers.get("Authorization")?.startsWith("Bearer ");

    // Import dependencies
    const { getDaysUntilReset, getCurrentMonth, WAGEY_LIMITS } = await import("@/lib/wagey/types");
    const { getUserTier } = await import("@/lib/subscription/getUserTier");

    let accessInfo: { level: "free" | "pro" | "max"; hasAccess: boolean; limit: number | null; used: number; remaining: number | null; resetDate: Date | null };
    let result: { allowed: boolean; count: number; remaining: number };

    if (isBearerAuth) {
      // For Bearer token auth (iOS), call the database directly
      // This bypasses the Effect-based auth verification which expects cookies
      const token = adapterRequest.headers.get("Authorization")!.substring(7);
      const supabaseWithToken = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
        {
          global: {
            headers: {
              Authorization: `Bearer ${token}`,
            },
          },
        }
      );

      // Get subscription and profile data
      const [subResult, profileResult] = await Promise.all([
        supabaseWithToken.from("subscriptions").select("*").eq("user_id", userId).maybeSingle(),
        supabaseWithToken.from("profiles").select("id, before_paywall, wagey_invocations").eq("id", userId).single(),
      ]);

      const subscription = subResult.data;
      const profile = profileResult.data;

      // Determine tier and limit
      const level = getUserTier(subscription, profile);
      const limit = WAGEY_LIMITS[level];
      const currentMonth = getCurrentMonth();

      // Get current usage
      const invocations = profile?.wagey_invocations as { count: number; month: string | null } | null;
      const used = invocations?.month === currentMonth ? invocations.count : 0;

      accessInfo = {
        level,
        hasAccess: level !== "free",
        limit,
        used,
        remaining: Math.max(0, limit - used),
        resetDate: null,
      };

      // Call the RPC to atomically check and increment
      const { data: rpcResult, error: rpcError } = await supabaseWithToken.rpc("increment_wagey_invocation", {
        p_user_id: userId,
        p_current_month: currentMonth,
        p_max_invocations: limit,
      });

      if (rpcError) {
        console.error("[chat/router] RPC error:", rpcError);
        result = { allowed: false, count: 0, remaining: 0 };
      } else {
        result = rpcResult as { allowed: boolean; count: number; remaining: number };
      }
    } else {
      // For cookie auth (web), use the existing DAL functions
      const { useWageyInvocation, getWageyAccessForUser } = await import("@/data-access/wagey");
      accessInfo = await getWageyAccessForUser(userId);
      result = await useWageyInvocation(userId);
    }

    if (!result.allowed) {
      await stream.appendChunk({
        type: "wagey_limit",
        remaining: result.remaining,
        resetDays: getDaysUntilReset(),
      });
      await stream.close();
      return;
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
            error instanceof Error ? error.message : "Unknown error";

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
      const dict = getDictionary(locale);
      await stream.appendChunk({
        type: "text",
        content: `\n\n${dict.pages.wagey.maxIterationsReached}`,
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
