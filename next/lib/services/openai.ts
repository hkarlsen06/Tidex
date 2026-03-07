/**
 * OpenAI Responses API service over official WebSocket mode.
 */

import "server-only";

import WebSocket from "ws";
import { Context, Effect, Layer, Redacted } from "effect";
import { AIError } from "@/lib/errors/tagged";
import { AppConfig } from "./config";
import type {
  ContentBlock,
  FunctionTool,
  Message,
  StreamChunk,
  Tool,
} from "./ai-types";

const OPENAI_RESPONSES_WS_URL = "wss://api.openai.com/v1/responses";
const DEFAULT_TIMEOUT_MS = 60_000;

export type OpenAIInputItem = Record<string, unknown>;

export type OpenAIResponseOptions = {
  instructions?: string;
  input: OpenAIInputItem[];
  tools?: Tool[];
  maxTokens?: number;
  previousResponseId?: string;
};

export type OpenAIResponseCompletion = {
  responseId?: string;
  stopReason: string;
};

export type OpenAIResponseStream = {
  events: AsyncIterable<StreamChunk>;
  completed: Promise<OpenAIResponseCompletion>;
};

export type OpenAIResponseSession = {
  createResponse: (options: OpenAIResponseOptions) => Promise<OpenAIResponseStream>;
  close: () => Promise<void>;
};

type JsonObject = Record<string, unknown>;
type JsonSchema = JsonObject;

type FunctionCallAccumulator = {
  itemId: string;
  callId?: string;
  name?: string;
  arguments: string;
};

type OpenAIEvent = Record<string, unknown>;

class AsyncQueue<T> implements AsyncIterable<T> {
  private items: T[] = [];
  private pending:
    | { resolve: (value: IteratorResult<T>) => void; reject: (error: unknown) => void }
    | null = null;
  private closed = false;
  private failure: unknown;

  push(item: T): void {
    if (this.closed || this.failure) return;
    if (this.pending) {
      const pending = this.pending;
      this.pending = null;
      pending.resolve({ done: false, value: item });
      return;
    }
    this.items.push(item);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    if (this.pending) {
      const pending = this.pending;
      this.pending = null;
      pending.resolve({ done: true, value: undefined });
    }
  }

  fail(error: unknown): void {
    if (this.closed || this.failure) return;
    this.failure = error;
    if (this.pending) {
      const pending = this.pending;
      this.pending = null;
      pending.reject(error);
    }
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: async (): Promise<IteratorResult<T>> => {
        if (this.items.length > 0) {
          const value = this.items.shift() as T;
          return { done: false, value };
        }
        if (this.failure) {
          throw this.failure;
        }
        if (this.closed) {
          return { done: true, value: undefined };
        }

        return await new Promise<IteratorResult<T>>((resolve, reject) => {
          this.pending = { resolve, reject };
        });
      },
    };
  }
}

class ResponseState {
  readonly events = new AsyncQueue<StreamChunk>();
  readonly functionCalls = new Map<string, FunctionCallAccumulator>();
  readonly completed: Promise<OpenAIResponseCompletion>;

  responseId?: string;

  private completedResolve!: (value: OpenAIResponseCompletion) => void;
  private completedReject!: (reason?: unknown) => void;
  private finished = false;

  constructor() {
    this.completed = new Promise<OpenAIResponseCompletion>((resolve, reject) => {
      this.completedResolve = resolve;
      this.completedReject = reject;
    });
  }

  setResponseId(responseId: string | undefined): void {
    if (responseId) {
      this.responseId = responseId;
    }
  }

  push(chunk: StreamChunk): void {
    this.events.push(chunk);
  }

  complete(stopReason: string): void {
    if (this.finished) return;
    this.finished = true;
    this.events.push({
      type: "done",
      stopReason,
      responseId: this.responseId,
    });
    this.events.close();
    this.completedResolve({
      responseId: this.responseId,
      stopReason,
    });
  }

  fail(error: unknown): void {
    if (this.finished) return;
    this.finished = true;
    this.events.fail(error);
    this.completedReject(error);
  }
}

function toAIError(message: string, cause?: unknown): AIError {
  return new AIError({
    provider: "openai",
    operation: "responses_websocket",
    message,
    cause,
  });
}

function parseEvent(rawData: WebSocket.RawData): OpenAIEvent | null {
  const payload = typeof rawData === "string" ? rawData : rawData.toString();
  try {
    return JSON.parse(payload) as OpenAIEvent;
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

function getNestedRecord(
  obj: Record<string, unknown>,
  key: string
): Record<string, unknown> | undefined {
  const value = obj[key];
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function extractResponseId(event: OpenAIEvent): string | undefined {
  const direct = getStringField(event, "response_id");
  if (direct) return direct;
  const response = getNestedRecord(event, "response");
  return response ? getStringField(response, "id") : undefined;
}

function extractStopReason(event: OpenAIEvent): string {
  return (
    getStringField(event, "status") ??
    getStringField(event, "reason") ??
    getStringField(event, "stop_reason") ??
    "completed"
  );
}

function extractErrorMessage(event: OpenAIEvent): string {
  const error = getNestedRecord(event, "error");
  return (
    (error ? getStringField(error, "message") : undefined) ??
    getStringField(event, "message") ??
    "OpenAI websocket request failed"
  );
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

function isJsonObject(value: unknown): value is JsonObject {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function isObjectSchema(schema: JsonObject): boolean {
  const rawType = schema.type;
  return rawType === "object" || (Array.isArray(rawType) && rawType.includes("object"));
}

function schemaAllowsNull(schema: unknown): boolean {
  if (!isJsonObject(schema)) {
    return false;
  }

  const rawType = schema.type;
  if (rawType === "null" || (Array.isArray(rawType) && rawType.includes("null"))) {
    return true;
  }

  if (Array.isArray(schema.enum) && schema.enum.includes(null)) {
    return true;
  }

  return ["anyOf", "oneOf", "allOf"].some((key) => {
    const variants = schema[key];
    return Array.isArray(variants) && variants.some((variant) => schemaAllowsNull(variant));
  });
}

function makeNullableSchema(schema: unknown): unknown {
  if (!isJsonObject(schema) || schemaAllowsNull(schema)) {
    return schema;
  }

  return {
    anyOf: [schema, { type: "null" }],
  };
}

function normalizeSchemaForOpenAI(schema: unknown): unknown {
  if (Array.isArray(schema)) {
    return schema.map((entry) => normalizeSchemaForOpenAI(entry));
  }

  if (!isJsonObject(schema)) {
    return schema;
  }

  const normalized: JsonObject = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === "properties" && isJsonObject(value)) {
      const normalizedProperties: JsonObject = {};
      for (const [propKey, propSchema] of Object.entries(value)) {
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

function toStrictOpenAISchema(schema: unknown): unknown {
  if (!isJsonObject(schema)) {
    return schema;
  }

  const strictSchema = normalizeSchemaForOpenAI(schema);
  if (!isJsonObject(strictSchema)) {
    return strictSchema;
  }

  const normalized = { ...strictSchema } as JsonSchema;

  if (isObjectSchema(normalized)) {
    const properties = isJsonObject(normalized.properties) ? normalized.properties : undefined;
    const requiredSet = new Set(
      Array.isArray(normalized.required)
        ? normalized.required.filter((entry): entry is string => typeof entry === "string")
        : []
    );

    if (properties) {
      const strictProperties: JsonObject = {};
      const strictRequired: string[] = [];

      for (const [propKey, propSchema] of Object.entries(properties)) {
        const strictPropertySchema = toStrictOpenAISchema(propSchema);
        strictProperties[propKey] = requiredSet.has(propKey)
          ? strictPropertySchema
          : makeNullableSchema(strictPropertySchema);
        strictRequired.push(propKey);
      }

      normalized.properties = strictProperties;
      normalized.required = strictRequired;
    } else if (normalized.required === undefined) {
      normalized.required = [];
    }

    if (properties) {
      normalized.additionalProperties = false;
    }
  }

  if (normalized.items !== undefined) {
    normalized.items = toStrictOpenAISchema(normalized.items);
  }

  for (const key of ["anyOf", "oneOf", "allOf"] as const) {
    const variants = normalized[key];
    if (Array.isArray(variants)) {
      normalized[key] = variants.map((variant) => toStrictOpenAISchema(variant));
    }
  }

  return normalized;
}

function buildToolDescription(tool: FunctionTool): string {
  const parts = [tool.description.trim()];

  if (tool.input_examples?.length) {
    const examples = tool.input_examples
      .slice(0, 3)
      .map((example, index) => `${index + 1}. ${JSON.stringify(example)}`)
      .join("\n");

    parts.push(`Valid example arguments:\n${examples}`);
  }

  parts.push("For optional fields, use null when unused. Never send empty strings.");

  return parts.join("\n\n");
}

function flushUserContentBuffer(
  input: OpenAIInputItem[],
  bufferedBlocks: OpenAIInputItem[]
): void {
  if (bufferedBlocks.length === 0) return;
  input.push({
    type: "message",
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
    type: "message",
    role: "assistant",
    content: bufferedBlocks.splice(0, bufferedBlocks.length),
  });
}

export function toOpenAIInput(messages: Message[]): OpenAIInputItem[] {
  const input: OpenAIInputItem[] = [];

  for (const message of messages) {
    if (typeof message.content === "string") {
      const text = message.content.trim();
      if (!text) continue;
      input.push({
        type: "message",
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
          case "text":
            if (block.text.trim()) {
              userContentBuffer.push(toUserTextBlock(block.text));
            }
            break;
          case "image":
            userContentBuffer.push(toUserImageBlock(block));
            break;
          case "tool_result":
            flushUserContentBuffer(input, userContentBuffer);
            input.push({
              type: "function_call_output",
              call_id: block.tool_use_id,
              output: block.content,
            });
            break;
          case "compaction":
            userContentBuffer.push(toUserTextBlock(block.content));
            break;
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
        case "text":
          if (block.text.trim()) {
            assistantContentBuffer.push(toAssistantTextBlock(block.text));
          }
          break;
        case "tool_use":
          flushAssistantContentBuffer(input, assistantContentBuffer);
          input.push({
            type: "function_call",
            call_id: block.id,
            name: block.name,
            arguments: JSON.stringify(block.input ?? {}),
          });
          break;
        case "compaction":
          if (block.content.trim()) {
            assistantContentBuffer.push(toAssistantTextBlock(block.content));
          }
          break;
        default:
          break;
      }
    }
    flushAssistantContentBuffer(input, assistantContentBuffer);
  }

  return input;
}

function toOpenAIFunctionTool(tool: FunctionTool): OpenAIInputItem {
  return {
    type: "function",
    name: tool.name,
    description: buildToolDescription(tool),
    parameters: toStrictOpenAISchema(tool.input_schema),
    strict: true,
  };
}

export function toOpenAITools(tools: Tool[] | undefined): OpenAIInputItem[] | undefined {
  if (!tools?.length) return undefined;

  return tools.map((tool) => toOpenAIFunctionTool(tool));
}

function pushFunctionCallDelta(
  accumulators: Map<string, FunctionCallAccumulator>,
  event: OpenAIEvent
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
  event: OpenAIEvent
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

class WebSocketResponsesSession implements OpenAIResponseSession {
  private ws: WebSocket;
  private readonly openPromise: Promise<void>;
  private readonly signal?: AbortSignal;
  private readonly timeoutMs: number;
  private readonly defaultModel: string;
  private readonly reasoningEffort: "none" | "low" | "medium" | "high" | "xhigh";
  private readonly apiKey: string;
  private activeResponse: ResponseState | null = null;
  private timeoutHandle: ReturnType<typeof setTimeout> | null = null;
  private closed = false;
  private aborted = false;

  constructor(options: {
    apiKey: string;
    defaultModel: string;
    reasoningEffort: "none" | "low" | "medium" | "high" | "xhigh";
    signal?: AbortSignal;
    timeoutMs?: number;
  }) {
    this.signal = options.signal;
    this.timeoutMs = Math.max(1_000, options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
    this.defaultModel = options.defaultModel;
    this.reasoningEffort = options.reasoningEffort;
    this.apiKey = options.apiKey;

    this.ws = new WebSocket(
      `${OPENAI_RESPONSES_WS_URL}?model=${encodeURIComponent(this.defaultModel)}`,
      {
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
      }
    );

    this.openPromise = new Promise<void>((resolve, reject) => {
      this.ws.once("open", () => resolve());
      this.ws.once("error", (error) => {
        reject(toAIError("Failed to open OpenAI websocket session", error));
      });
    });

    this.ws.on("message", (data) => this.handleMessage(data));
    this.ws.on("error", (error) => {
      this.failActiveResponse(toAIError("OpenAI websocket error", error));
    });
    this.ws.on("close", (code, reason) => {
      const reasonText = reason.toString();
      if (this.closed) return;

      if (this.aborted) {
        this.failActiveResponse(toAIError("OpenAI websocket session aborted"));
        return;
      }

      if (this.activeResponse) {
        this.failActiveResponse(
          toAIError(
            `OpenAI websocket closed before the response completed with code ${code}${reasonText ? ` (${reasonText})` : ""}`
          )
        );
      }
    });

    if (this.signal) {
      if (this.signal.aborted) {
        this.aborted = true;
        this.ws.close(1000, "client_aborted");
      } else {
        this.signal.addEventListener("abort", () => {
          this.aborted = true;
          this.ws.close(1000, "client_aborted");
        });
      }
    }
  }

  async createResponse(options: OpenAIResponseOptions): Promise<OpenAIResponseStream> {
    await this.openPromise;

    if (this.closed) {
      throw toAIError("OpenAI websocket session is already closed");
    }
    if (this.activeResponse) {
      throw toAIError("OpenAI websocket session already has an active response");
    }

    const state = new ResponseState();
    this.activeResponse = state;
    this.armTimeout();

    const payload: Record<string, unknown> = {
      type: "response.create",
      model: this.defaultModel,
      store: false,
      instructions: options.instructions,
      input: options.input,
      parallel_tool_calls: true,
      tool_choice: "auto",
      max_output_tokens: options.maxTokens ?? 2048,
      reasoning: {
        effort: this.reasoningEffort,
      },
      previous_response_id: options.previousResponseId,
    };

    const mappedTools = toOpenAITools(options.tools);
    if (mappedTools?.length) {
      payload.tools = mappedTools;
    }

    if (!options.instructions) {
      delete payload.instructions;
    }
    if (!options.previousResponseId) {
      delete payload.previous_response_id;
    }

    await new Promise<void>((resolve, reject) => {
      this.ws.send(JSON.stringify(payload), (error) => {
        if (error) {
          reject(toAIError("Failed to send response.create", error));
          return;
        }
        resolve();
      });
    });

    const completed = state.completed.finally(() => {
      if (this.activeResponse === state) {
        this.activeResponse = null;
      }
      this.clearTimeout();
    });

    return {
      events: state.events,
      completed,
    };
  }

  async close(): Promise<void> {
    this.closed = true;
    this.clearTimeout();
    if (
      this.ws.readyState === WebSocket.OPEN ||
      this.ws.readyState === WebSocket.CONNECTING
    ) {
      await new Promise<void>((resolve) => {
        this.ws.once("close", () => resolve());
        this.ws.close(1000, "session_complete");
      });
    }
  }

  private armTimeout(): void {
    this.clearTimeout();
    this.timeoutHandle = setTimeout(() => {
      this.failActiveResponse(
        toAIError(`OpenAI response timed out after ${this.timeoutMs}ms`)
      );
      this.ws.close(1000, "response_timeout");
    }, this.timeoutMs);
  }

  private clearTimeout(): void {
    if (this.timeoutHandle) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = null;
    }
  }

  private handleMessage(data: WebSocket.RawData): void {
    const event = parseEvent(data);
    if (!event || !this.activeResponse) return;

    const state = this.activeResponse;
    state.setResponseId(extractResponseId(event));

    const eventType = getStringField(event, "type") ?? "";
    const isTerminalEvent =
      eventType === "response.completed" ||
      eventType === "response.done" ||
      eventType === "error" ||
      eventType === "response.failed";

    if (!isTerminalEvent) {
      this.armTimeout();
    }

    if (eventType === "response.output_text.delta") {
      const delta = getStringField(event, "delta");
      if (delta) {
        state.push({ type: "text", content: delta });
      }
      return;
    }

    if (eventType === "response.function_call_arguments.delta") {
      pushFunctionCallDelta(state.functionCalls, event);
      return;
    }

    if (eventType === "response.output_item.added") {
      const item = event.item;
      if (item && typeof item === "object") {
        const parsedItem = item as Record<string, unknown>;
        if (parsedItem.type === "function_call") {
          const itemId = getStringField(parsedItem, "id");
          if (itemId) {
            state.functionCalls.set(itemId, {
              itemId,
              callId: getStringField(parsedItem, "call_id"),
              name: getStringField(parsedItem, "name"),
              arguments: getStringField(parsedItem, "arguments") ?? "",
            });
          }
        }
      }
      return;
    }

    if (eventType === "response.output_item.done") {
      const chunk = parseToolUseChunk(state.functionCalls, event);
      if (chunk) {
        state.push(chunk);
      }
      return;
    }

    if (eventType === "response.completed" || eventType === "response.done") {
      state.complete(extractStopReason(event));
      return;
    }

    if (eventType === "error" || eventType === "response.failed") {
      state.fail(toAIError(extractErrorMessage(event), event));
    }
  }

  private failActiveResponse(error: AIError): void {
    this.clearTimeout();
    if (this.activeResponse) {
      this.activeResponse.fail(error);
      this.activeResponse = null;
    }
  }
}

export class OpenAIService extends Context.Tag("OpenAIService")<
  OpenAIService,
  {
    readonly openSession: (options?: {
      signal?: AbortSignal;
      timeoutMs?: number;
    }) => Effect.Effect<OpenAIResponseSession, AIError, never>;
    readonly streamChat: (
      options: {
        messages: Message[];
        system?: string;
        tools?: Tool[];
        maxTokens?: number;
        signal?: AbortSignal;
      }
    ) => Effect.Effect<AsyncIterable<StreamChunk>, AIError, never>;
  }
>() {}

export const OpenAIServiceLive = Layer.effect(
  OpenAIService,
  Effect.gen(function* () {
    const config = yield* AppConfig;
    const apiKey = Redacted.value(config.ai.openaiApiKey);
    const defaultModel = config.ai.openaiModel;
    const reasoningEffort = config.ai.openaiReasoningEffort;

    const openSession = (options?: {
      signal?: AbortSignal;
      timeoutMs?: number;
    }): Effect.Effect<OpenAIResponseSession, AIError, never> =>
      Effect.try({
        try: () =>
          new WebSocketResponsesSession({
            apiKey,
            defaultModel,
            reasoningEffort,
            signal: options?.signal,
            timeoutMs: options?.timeoutMs,
          }),
        catch: (error) =>
          toAIError("Failed to create OpenAI websocket session", error),
      });

    const streamChat = (options: {
      messages: Message[];
      system?: string;
      tools?: Tool[];
      maxTokens?: number;
      signal?: AbortSignal;
    }): Effect.Effect<AsyncIterable<StreamChunk>, AIError, never> =>
      Effect.gen(function* () {
        const session = yield* openSession({ signal: options.signal });

        const result = yield* Effect.tryPromise({
          try: async () => {
            const response = await session.createResponse({
              instructions: options.system,
              input: toOpenAIInput(options.messages),
              tools: options.tools,
              maxTokens: options.maxTokens,
            });

            const iterable: AsyncIterable<StreamChunk> = {
              async *[Symbol.asyncIterator]() {
                try {
                  for await (const chunk of response.events) {
                    yield chunk;
                  }
                  await response.completed;
                } finally {
                  await session.close();
                }
              },
            };

            return iterable;
          },
          catch: (error) =>
            error instanceof AIError
              ? error
              : toAIError("Failed to stream chat", error),
        });

        return result;
      });

    return {
      openSession,
      streamChat,
    };
  })
);
