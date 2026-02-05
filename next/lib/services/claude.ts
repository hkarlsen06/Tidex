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

export type ImageContent = {
  type: "image";
  source: {
    type: "base64";
    media_type: string;
    data: string;
  };
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

export type ThinkingContent = {
  type: "thinking";
  thinking: string;
  signature: string;
};

export type RedactedThinkingContent = {
  type: "redacted_thinking";
  data: string;
};

export type CompactionContent = {
  type: "compaction";
  content: string;
};

export type ContentBlock =
  | TextContent
  | ImageContent
  | ToolUseContent
  | ToolResultContent
  | ThinkingContent
  | RedactedThinkingContent
  | CompactionContent;

/**
 * Message type (Claude format)
 */
export type Message = {
  role: MessageRole;
  content: string | ContentBlock[];
};

/**
 * Tool input example - raw object matching the tool's input_schema
 * See: https://www.anthropic.com/engineering/advanced-tool-use
 */
export type ToolInputExample = Record<string, unknown>;

/**
 * Tool definition type (Claude format with input_examples)
 */
export type Tool = {
  name: string;
  description: string;
  eager_input_streaming?: boolean;
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
      type: "compaction";
      content: string;
    }
  | {
      type: "thinking";
      thinking: string;
      signature: string;
    }
  | {
      type: "redacted_thinking";
      data: string;
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
const COMPACTION_BETA = "compact-2026-01-12";
const OPUS_46_MODEL_PREFIX = "claude-opus-4-6";

function isOpus46Model(model: string): boolean {
  return model.startsWith(OPUS_46_MODEL_PREFIX);
}

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
          temperature,
          maxTokens = 4096,
        } = options;
        const opus46Enabled = isOpus46Model(defaultModel);
        const compactionEnabled = opus46Enabled;
        const adaptiveThinkingEnabled = opus46Enabled;

        // Build headers
        const headers: Record<string, string> = {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        };

        if (compactionEnabled) {
          headers["anthropic-beta"] = COMPACTION_BETA;
        }

        // Build request body
        const body: Record<string, unknown> = {
          model: defaultModel,
          max_tokens: maxTokens,
          stream: true,
          messages,
        };

        if (adaptiveThinkingEnabled) {
          body.thinking = { type: "adaptive" };
          body.output_config = { effort: "high" };
        } else if (typeof temperature === "number") {
          body.temperature = temperature;
        }

        if (compactionEnabled) {
          body.context_management = {
            edits: [
              {
                type: "compact_20260112",
                pause_after_compaction: false,
                instructions:
                  "Summarize this conversation between a user and Wagey, a shift/wage assistant. Preserve: shift IDs and dates mentioned, tool call results and their outcomes, user preferences and settings discussed, any pending actions or unresolved requests, and the user's name if known. Keep it concise. Wrap in <summary></summary>.",
              },
            ],
          };
        }

        if (system) {
          body.system = system;
        }

        if (tools?.length) {
          // Strip input_examples from tools - not supported without beta header.
          // Enable eager tool input streaming for lower latency tool argument delivery.
          body.tools = tools.map(({ input_examples: _input_examples, ...tool }) => ({
            ...tool,
            eager_input_streaming: true,
          }));
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

          // Log the actual error for debugging
          console.error(`[Claude API Error] Status: ${response.status}`);
          console.error(`[Claude API Error] Body: ${errorText}`);

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
            let currentCompaction: { content: string } | null = null;
            let currentThinking: { thinking: string; signature: string } | null = null;
            let currentRedactedThinking: { data: string } | null = null;

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
                      } else if (block.type === "compaction") {
                        currentCompaction = { content: "" };
                      } else if (block.type === "thinking") {
                        currentThinking = { thinking: "", signature: "" };
                      } else if (block.type === "redacted_thinking") {
                        currentRedactedThinking = {
                          data: typeof block.data === "string" ? block.data : "",
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

                      // Compaction delta (single delta with full content)
                      if (delta.type === "compaction_delta" && currentCompaction) {
                        currentCompaction.content = delta.content as string;
                      }

                      // Thinking deltas
                      if (delta.type === "thinking_delta" && currentThinking) {
                        currentThinking.thinking += (delta.thinking as string) || "";
                      }
                      if (delta.type === "signature_delta" && currentThinking) {
                        currentThinking.signature = (delta.signature as string) || "";
                      }
                      if (delta.type === "redacted_thinking_delta" && currentRedactedThinking) {
                        currentRedactedThinking.data += (delta.data as string) || "";
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
                          // Invalid JSON (possible with fine-grained tool streaming).
                          // Preserve raw payload so caller can pass back a structured error.
                          yield {
                            type: "tool_use",
                            id: currentToolUse.id,
                            name: currentToolUse.name,
                            input: {
                              INVALID_JSON: currentToolUse.inputJson,
                            },
                          };
                        }
                        currentToolUse = null;
                      }

                      // Emit completed compaction block
                      if (currentCompaction) {
                        yield {
                          type: "compaction",
                          content: currentCompaction.content,
                        };
                        currentCompaction = null;
                      }

                      if (currentThinking) {
                        yield {
                          type: "thinking",
                          thinking: currentThinking.thinking,
                          signature: currentThinking.signature,
                        };
                        currentThinking = null;
                      }

                      if (currentRedactedThinking) {
                        yield {
                          type: "redacted_thinking",
                          data: currentRedactedThinking.data,
                        };
                        currentRedactedThinking = null;
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
