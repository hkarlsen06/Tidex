/**
 * Claude API Service
 *
 * Effect-based service for Claude Messages API with streaming and tool calling.
 * Supports the input_examples beta feature for improved tool use accuracy.
 */

import "server-only";

import { Context, Effect, Layer, Redacted } from "effect";
import { AIError } from "@/lib/errors/tagged";
import { AppConfig } from "./config";

/**
 * Message role type (Claude format)
 */
export type MessageRole = "user" | "assistant";

/**
 * Content block types
 */
export type TextContent = {
  type: "text";
  text: string;
};

export type ToolUseContent = {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
};

export type ToolResultContent = {
  type: "tool_result";
  tool_use_id: string;
  content: string;
  is_error?: boolean;
};

export type ContentBlock = TextContent | ToolUseContent | ToolResultContent;

/**
 * Message type (Claude format)
 */
export type Message = {
  role: MessageRole;
  content: string | ContentBlock[];
};

/**
 * Tool input example
 */
export type ToolInputExample = {
  input: Record<string, unknown>;
  description?: string;
};

/**
 * Tool definition type (Claude format with input_examples)
 */
export type Tool = {
  name: string;
  description: string;
  input_schema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
  input_examples?: ToolInputExample[];
};

/**
 * Stream chunk types
 */
export type StreamChunk =
  | {
      type: "text";
      content: string;
    }
  | {
      type: "tool_use";
      id: string;
      name: string;
      input: Record<string, unknown>;
    }
  | {
      type: "done";
      stopReason: string;
    };

/**
 * Claude streaming options
 */
export type StreamOptions = {
  messages: Message[];
  system?: string;
  tools?: Tool[];
  temperature?: number;
  maxTokens?: number;
};

/**
 * Claude Service
 */
export class ClaudeService extends Context.Tag("ClaudeService")<
  ClaudeService,
  {
    readonly streamChat: (
      options: StreamOptions
    ) => Effect.Effect<AsyncIterable<StreamChunk>, AIError, never>;
  }
>() {}

/**
 * Claude API endpoint
 */
const CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";

/**
 * Parse SSE event from Claude streaming response
 */
function parseClaudeEvent(
  line: string
): { event: string; data: unknown } | null {
  if (!line.startsWith("data: ")) {
    return null;
  }

  const data = line.slice(6).trim();
  if (!data) return null;

  try {
    return { event: "data", data: JSON.parse(data) };
  } catch {
    return null;
  }
}

/**
 * Create Claude Service (Live)
 */
export const ClaudeServiceLive = Layer.effect(
  ClaudeService,
  Effect.gen(function* () {
    const config = yield* AppConfig;
    const apiKey = Redacted.value(config.ai.claudeApiKey);
    const defaultModel = config.ai.claudeModel;

    /**
     * Stream chat completion from Claude
     */
    const streamChat = (
      options: StreamOptions
    ): Effect.Effect<AsyncIterable<StreamChunk>, AIError, never> =>
      Effect.gen(function* () {
        const {
          messages,
          system,
          tools,
          temperature = 0.7,
          maxTokens = 4096,
        } = options;

        // Build headers - include beta header for input_examples
        const headers: Record<string, string> = {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        };

        // Add beta header if using tools with input_examples
        if (tools?.some((t) => t.input_examples?.length)) {
          headers["anthropic-beta"] = "interleaved-thinking-2025-05-14,tool-use-examples-2025-05-14";
        }

        // Build request body
        const body: Record<string, unknown> = {
          model: defaultModel,
          max_tokens: maxTokens,
          temperature,
          stream: true,
          messages,
        };

        if (system) {
          body.system = system;
        }

        if (tools?.length) {
          body.tools = tools;
        }

        // Make API request
        const response = yield* Effect.tryPromise({
          try: () =>
            fetch(CLAUDE_API_URL, {
              method: "POST",
              headers,
              body: JSON.stringify(body),
            }),
          catch: (error) =>
            new AIError({
              provider: "anthropic",
              operation: "stream_chat",
              message: error instanceof Error ? error.message : "Fetch failed",
              cause: error,
            }),
        });

        if (!response.ok) {
          const errorText = yield* Effect.tryPromise({
            try: () => response.text(),
            catch: (error) =>
              new AIError({
                provider: "anthropic",
                operation: "stream_chat",
                message: "Failed to read error response",
                cause: error,
              }),
          });

          return yield* Effect.fail(
            new AIError({
              provider: "anthropic",
              operation: "stream_chat",
              message: `Claude API error: ${response.status}`,
              cause: errorText,
            })
          );
        }

        if (!response.body) {
          return yield* Effect.fail(
            new AIError({
              provider: "anthropic",
              operation: "stream_chat",
              message: "No response body",
            })
          );
        }

        // Create async iterable from ReadableStream
        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        const asyncIterable: AsyncIterable<StreamChunk> = {
          async *[Symbol.asyncIterator]() {
            let buffer = "";
            let currentToolUse: {
              id: string;
              name: string;
              inputJson: string;
            } | null = null;

            try {
              while (true) {
                const { done, value } = await reader.read();

                if (done) {
                  break;
                }

                buffer += decoder.decode(value, { stream: true });

                const lines = buffer.split("\n");
                buffer = lines.pop() || "";

                for (const line of lines) {
                  if (!line.trim()) continue;

                  const parsed = parseClaudeEvent(line);
                  if (!parsed) continue;

                  const event = parsed.data as Record<string, unknown>;
                  const eventType = event.type as string;

                  switch (eventType) {
                    case "content_block_start": {
                      const block = event.content_block as Record<
                        string,
                        unknown
                      >;
                      if (block.type === "tool_use") {
                        currentToolUse = {
                          id: block.id as string,
                          name: block.name as string,
                          inputJson: "",
                        };
                      }
                      break;
                    }

                    case "content_block_delta": {
                      const delta = event.delta as Record<string, unknown>;

                      // Text delta
                      if (delta.type === "text_delta" && delta.text) {
                        yield { type: "text", content: delta.text as string };
                      }

                      // Tool input delta
                      if (
                        delta.type === "input_json_delta" &&
                        delta.partial_json &&
                        currentToolUse
                      ) {
                        currentToolUse.inputJson += delta.partial_json as string;
                      }
                      break;
                    }

                    case "content_block_stop": {
                      // Emit completed tool use
                      if (currentToolUse) {
                        try {
                          const input = JSON.parse(currentToolUse.inputJson || "{}");
                          yield {
                            type: "tool_use",
                            id: currentToolUse.id,
                            name: currentToolUse.name,
                            input,
                          };
                        } catch {
                          // Invalid JSON - emit with empty input
                          yield {
                            type: "tool_use",
                            id: currentToolUse.id,
                            name: currentToolUse.name,
                            input: {},
                          };
                        }
                        currentToolUse = null;
                      }
                      break;
                    }

                    case "message_delta": {
                      const delta = event.delta as Record<string, unknown>;
                      if (delta.stop_reason) {
                        yield {
                          type: "done",
                          stopReason: delta.stop_reason as string,
                        };
                      }
                      break;
                    }

                    case "message_stop": {
                      // Message complete
                      return;
                    }

                    case "error": {
                      const error = event.error as Record<string, unknown>;
                      throw new Error(
                        (error.message as string) || "Claude streaming error"
                      );
                    }
                  }
                }
              }
            } finally {
              reader.releaseLock();
            }
          },
        };

        return asyncIterable;
      });

    return {
      streamChat,
    };
  })
);
