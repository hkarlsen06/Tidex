/**
 * OpenAI Responses API Service
 *
 * Effect-based service for OpenAI with streaming and tool calling.
 * Uses the same message/tool contract as ClaudeService so the chat router
 * can swap providers at runtime.
 */

import "server-only";

import { Context, Effect, Layer, Redacted } from "effect";
import { AIError } from "@/lib/errors/tagged";
import { AppConfig } from "./config";
import type {
  ContentBlock,
  Message,
  StreamChunk,
  StreamOptions,
  Tool,
} from "./claude";

const OPENAI_RESPONSES_API_URL = "https://api.openai.com/v1/responses";

type OpenAIInputItem = Record<string, unknown>;

type FunctionCallAccumulator = {
  itemId: string;
  callId?: string;
  name?: string;
  arguments: string;
};

type JsonObject = Record<string, unknown>;

function extractOpenAIErrorMessage(errorText: string): string | null {
  if (!errorText) return null;
  try {
    const parsed = JSON.parse(errorText) as {
      error?: { message?: unknown };
    };
    const message = parsed.error?.message;
    if (typeof message === "string" && message.trim().length > 0) {
      return message.trim();
    }
  } catch {
    // Ignore JSON parse failures and fall back to status-only message.
  }
  return null;
}

function safeJsonParse(input: string): Record<string, unknown> {
  return JSON.parse(input) as Record<string, unknown>;
}

function toAssistantTextBlock(text: string): OpenAIInputItem {
  return {
    type: "output_text",
    text,
  };
}

function toUserTextBlock(text: string): OpenAIInputItem {
  return {
    type: "input_text",
    text,
  };
}

function toUserImageBlock(block: Extract<ContentBlock, { type: "image" }>): OpenAIInputItem {
  return {
    type: "input_image",
    image_url: `data:${block.source.media_type};base64,${block.source.data}`,
  };
}

function normalizeSchemaForOpenAI(schema: unknown): unknown {
  if (Array.isArray(schema)) {
    return schema.map((entry) => normalizeSchemaForOpenAI(entry));
  }

  if (!schema || typeof schema !== "object") {
    return schema;
  }

  const normalized: JsonObject = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === "properties" && value && typeof value === "object" && !Array.isArray(value)) {
      const normalizedProperties: JsonObject = {};
      for (const [propKey, propSchema] of Object.entries(value as JsonObject)) {
        normalizedProperties[propKey] = normalizeSchemaForOpenAI(propSchema);
      }
      normalized[key] = normalizedProperties;
      continue;
    }

    if (key === "items") {
      normalized[key] = normalizeSchemaForOpenAI(value);
      continue;
    }

    if (key === "anyOf" || key === "allOf" || key === "oneOf") {
      normalized[key] = Array.isArray(value)
        ? value.map((entry) => normalizeSchemaForOpenAI(entry))
        : value;
      continue;
    }

    normalized[key] = normalizeSchemaForOpenAI(value);
  }

  const rawType = normalized.type;
  const isArrayType =
    rawType === "array" || (Array.isArray(rawType) && rawType.includes("array"));

  if (isArrayType && normalized.items === undefined) {
    normalized.items = {};
  }

  return normalized;
}

function flushUserContentBuffer(
  input: OpenAIInputItem[],
  bufferedBlocks: OpenAIInputItem[]
): void {
  if (bufferedBlocks.length === 0) return;
  input.push({
    role: "user",
    content: bufferedBlocks.splice(0, bufferedBlocks.length),
  });
}

function flushAssistantContentBuffer(
  input: OpenAIInputItem[],
  bufferedBlocks: OpenAIInputItem[]
): void {
  if (bufferedBlocks.length === 0) return;
  input.push({
    role: "assistant",
    content: bufferedBlocks.splice(0, bufferedBlocks.length),
  });
}

/**
 * Convert Claude-style history into OpenAI Responses input items.
 */
export function toOpenAIInput(messages: Message[]): OpenAIInputItem[] {
  const input: OpenAIInputItem[] = [];

  for (const message of messages) {
    if (typeof message.content === "string") {
      const text = message.content.trim();
      if (!text) continue;
      input.push({
        role: message.role,
        content: [
          message.role === "assistant"
            ? toAssistantTextBlock(text)
            : toUserTextBlock(text),
        ],
      });
      continue;
    }

    if (message.role === "user") {
      const userContentBuffer: OpenAIInputItem[] = [];
      for (const block of message.content) {
        switch (block.type) {
          case "text": {
            if (block.text.trim()) {
              userContentBuffer.push(toUserTextBlock(block.text));
            }
            break;
          }
          case "image": {
            userContentBuffer.push(toUserImageBlock(block));
            break;
          }
          case "tool_result": {
            flushUserContentBuffer(input, userContentBuffer);
            input.push({
              type: "function_call_output",
              call_id: block.tool_use_id,
              output: block.content,
            });
            break;
          }
          default:
            break;
        }
      }
      flushUserContentBuffer(input, userContentBuffer);
      continue;
    }

    const assistantContentBuffer: OpenAIInputItem[] = [];
    for (const block of message.content) {
      switch (block.type) {
        case "text": {
          if (block.text.trim()) {
            assistantContentBuffer.push(toAssistantTextBlock(block.text));
          }
          break;
        }
        case "tool_use": {
          flushAssistantContentBuffer(input, assistantContentBuffer);
          input.push({
            type: "function_call",
            call_id: block.id,
            name: block.name,
            arguments: JSON.stringify(block.input ?? {}),
          });
          break;
        }
        default:
          break;
      }
    }
    flushAssistantContentBuffer(input, assistantContentBuffer);
  }

  return input;
}

/**
 * Convert Claude-style tool definition to OpenAI Responses tool format.
 */
export function toOpenAITools(tools: Tool[] | undefined): OpenAIInputItem[] | undefined {
  if (!tools?.length) return undefined;

  return tools.map(({ input_examples: _inputExamples, ...tool }) => ({
    type: "function",
    name: tool.name,
    description: tool.description,
    parameters: normalizeSchemaForOpenAI(tool.input_schema),
  }));
}

/**
 * Parse a JSON payload from an SSE data line.
 */
function parseDataLine(line: string): Record<string, unknown> | null {
  if (!line.startsWith("data:")) return null;
  const rawData = line.slice(5).trim();
  if (!rawData || rawData === "[DONE]") return null;

  try {
    return JSON.parse(rawData) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function getStringField(
  obj: Record<string, unknown>,
  key: string
): string | undefined {
  const value = obj[key];
  return typeof value === "string" ? value : undefined;
}

function pushFunctionCallDelta(
  accumulators: Map<string, FunctionCallAccumulator>,
  event: Record<string, unknown>
): void {
  const itemId = getStringField(event, "item_id");
  if (!itemId) return;

  const current = accumulators.get(itemId) ?? {
    itemId,
    arguments: "",
  };

  const callId = getStringField(event, "call_id");
  if (callId) {
    current.callId = callId;
  }

  const name = getStringField(event, "name");
  if (name) {
    current.name = name;
  }

  current.arguments += getStringField(event, "delta") ?? "";
  accumulators.set(itemId, current);
}

function parseToolUseChunk(
  accumulators: Map<string, FunctionCallAccumulator>,
  event: Record<string, unknown>
): StreamChunk | null {
  const item = event.item;
  if (!item || typeof item !== "object") return null;

  const parsedItem = item as Record<string, unknown>;
  if (parsedItem.type !== "function_call") return null;

  const itemId = getStringField(parsedItem, "id");
  if (!itemId) return null;

  const accumulator = accumulators.get(itemId);

  const callId =
    getStringField(parsedItem, "call_id") ??
    accumulator?.callId ??
    itemId;
  const name =
    getStringField(parsedItem, "name") ??
    accumulator?.name ??
    "unknown_tool";
  const argumentsJson =
    getStringField(parsedItem, "arguments") ?? accumulator?.arguments ?? "{}";

  accumulators.delete(itemId);

  try {
    return {
      type: "tool_use",
      id: callId,
      name,
      input: safeJsonParse(argumentsJson || "{}"),
    };
  } catch {
    return {
      type: "tool_use",
      id: callId,
      name,
      input: {
        INVALID_JSON: argumentsJson,
      },
    };
  }
}

/**
 * OpenAI Service
 */
export class OpenAIService extends Context.Tag("OpenAIService")<
  OpenAIService,
  {
    readonly streamChat: (
      options: StreamOptions
    ) => Effect.Effect<AsyncIterable<StreamChunk>, AIError, never>;
  }
>() {}

/**
 * Create OpenAI Service (Live)
 */
export const OpenAIServiceLive = Layer.effect(
  OpenAIService,
  Effect.gen(function* () {
    const config = yield* AppConfig;
    const apiKey = Redacted.value(config.ai.openaiApiKey);
    const defaultModel = config.ai.openaiModel;

    const streamChat = (
      options: StreamOptions
    ): Effect.Effect<AsyncIterable<StreamChunk>, AIError, never> =>
      Effect.gen(function* () {
        const { messages, system, tools, maxTokens = 4096 } = options;

        const body: Record<string, unknown> = {
          model: defaultModel,
          stream: true,
          store: false,
          parallel_tool_calls: true,
          tool_choice: "auto",
          max_output_tokens: maxTokens,
          input: toOpenAIInput(messages),
        };

        if (system) {
          body.instructions = system;
        }

        const mappedTools = toOpenAITools(tools);
        if (mappedTools?.length) {
          body.tools = mappedTools;
        }

        const response = yield* Effect.tryPromise({
          try: () =>
            fetch(OPENAI_RESPONSES_API_URL, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify(body),
            }),
          catch: (error) =>
            new AIError({
              provider: "openai",
              operation: "stream_chat",
              message: error instanceof Error ? error.message : "Fetch failed",
              cause: error,
            }),
        });

        if (!response.ok) {
          const errorText = yield* Effect.promise(() => response.text()).pipe(
            Effect.catchAll(() => Effect.succeed(""))
          );
          const upstreamMessage = extractOpenAIErrorMessage(errorText);
          const message = upstreamMessage
            ? `OpenAI Responses API error: ${response.status} (${upstreamMessage})`
            : `OpenAI Responses API error: ${response.status}`;

          return yield* Effect.fail(
            new AIError({
              provider: "openai",
              operation: "stream_chat",
              message,
              cause: errorText,
            })
          );
        }

        if (!response.body) {
          return yield* Effect.fail(
            new AIError({
              provider: "openai",
              operation: "stream_chat",
              message: "No response body",
            })
          );
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        const asyncIterable: AsyncIterable<StreamChunk> = {
          async *[Symbol.asyncIterator]() {
            let buffer = "";
            let currentEventName: string | null = null;
            let doneEmitted = false;
            const functionCallAccumulators = new Map<string, FunctionCallAccumulator>();

            try {
              while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split("\n");
                buffer = lines.pop() ?? "";

                for (const rawLine of lines) {
                  const line = rawLine.trim();
                  if (!line) {
                    currentEventName = null;
                    continue;
                  }

                  if (line.startsWith("event:")) {
                    currentEventName = line.slice(6).trim();
                    continue;
                  }

                  if (line === "data: [DONE]") {
                    if (!doneEmitted) {
                      doneEmitted = true;
                      yield { type: "done", stopReason: "stop" };
                    }
                    return;
                  }

                  const event = parseDataLine(line);
                  if (!event) continue;

                  const eventType =
                    getStringField(event, "type") ?? currentEventName ?? "";

                  if (eventType === "response.output_text.delta") {
                    const delta = getStringField(event, "delta");
                    if (delta) {
                      yield { type: "text", content: delta };
                    }
                    continue;
                  }

                  if (eventType === "response.function_call_arguments.delta") {
                    pushFunctionCallDelta(functionCallAccumulators, event);
                    continue;
                  }

                  if (eventType === "response.output_item.added") {
                    const item = event.item;
                    if (item && typeof item === "object") {
                      const parsedItem = item as Record<string, unknown>;
                      if (parsedItem.type === "function_call") {
                        const itemId = getStringField(parsedItem, "id");
                        if (itemId) {
                          functionCallAccumulators.set(itemId, {
                            itemId,
                            callId: getStringField(parsedItem, "call_id"),
                            name: getStringField(parsedItem, "name"),
                            arguments: getStringField(parsedItem, "arguments") ?? "",
                          });
                        }
                      }
                    }
                    continue;
                  }

                  if (eventType === "response.output_item.done") {
                    const toolUseChunk = parseToolUseChunk(
                      functionCallAccumulators,
                      event
                    );
                    if (toolUseChunk) {
                      yield toolUseChunk;
                    }
                    continue;
                  }

                  if (
                    eventType === "response.completed" ||
                    eventType === "response.done"
                  ) {
                    if (!doneEmitted) {
                      doneEmitted = true;
                      const status =
                        getStringField(event, "status") ??
                        "completed";
                      yield { type: "done", stopReason: status };
                    }
                    return;
                  }

                  if (eventType === "error") {
                    const err = event.error;
                    const message =
                      err && typeof err === "object"
                        ? getStringField(err as Record<string, unknown>, "message")
                        : undefined;
                    throw new Error(message ?? "OpenAI streaming error");
                  }
                }
              }

              if (!doneEmitted) {
                yield { type: "done", stopReason: "stop" };
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
