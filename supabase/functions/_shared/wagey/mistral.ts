import type {
  ContentBlock,
  Message,
  Source,
  StreamChunk,
  Tool,
  WebSearchResultItem,
  WebSearchToolResultContent,
} from "./ai-types.ts";

const MISTRAL_API_URL = "https://api.mistral.ai/v1/conversations";
const MISTRAL_STREAM_IDLE_TIMEOUT_MS = 30_000;
const GENERIC_PROVIDER_ERROR_MESSAGE =
  "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.";

export const WAGEY_MISTRAL_MODEL = "mistral-large-2512";

export type MistralMessageContentPart =
  | {
    type: "text";
    text: string;
  }
  | {
    type: "image_url";
    image_url: {
      url: string;
    };
  };

export type MistralConversationInput =
  | {
    role: "user" | "assistant";
    content: string | MistralMessageContentPart[];
  }
  | {
    tool_call_id: string;
    name: string;
    arguments: string;
  }
  | {
    tool_call_id: string;
    result: string;
  };

type PendingFunctionCall = {
  name: string;
  toolCallId: string;
  argumentsJson: string;
  started: boolean;
};

type PendingWebSearch = {
  id: string;
  argumentsJson: string;
  input: Record<string, unknown>;
  completed: boolean;
};

type ParsedSseEvent = {
  event?: string;
  data?: string;
};

type MistralErrorPayload = {
  message?: unknown;
  type?: unknown;
  code?: unknown;
  request_id?: unknown;
  detail?: unknown;
};

type ConversationResponsePayload = {
  outputs?: Array<{
    content?: unknown;
  }>;
};

export class MistralProviderError extends Error {
  readonly status: number;
  readonly providerType?: string;
  readonly providerCode?: string;
  readonly providerMessage?: string;
  readonly requestId?: string;
  readonly publicMessage: string;

  constructor(options: {
    status: number;
    providerType?: string;
    providerCode?: string;
    providerMessage?: string;
    requestId?: string;
    publicMessage?: string;
  }) {
    const providerSummary = options.providerMessage?.trim() ||
      (options.providerType
        ? `Mistral provider error: ${options.providerType}`
        : `Mistral API error: ${options.status}`);
    super(providerSummary);
    this.name = "MistralProviderError";
    this.status = options.status;
    this.providerType = options.providerType;
    this.providerCode = options.providerCode;
    this.providerMessage = options.providerMessage;
    this.requestId = options.requestId;
    this.publicMessage = options.publicMessage ??
      GENERIC_PROVIDER_ERROR_MESSAGE;
  }
}

function isContentBlockArray(
  content: Message["content"],
): content is ContentBlock[] {
  return Array.isArray(content);
}

function parseObjectRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function parseInputRecord(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value);
    return parseObjectRecord(parsed);
  } catch {
    return {};
  }
}

function getDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

function normalizeSource(url: string, title?: string): Source {
  const normalizedUrl = url.trim();
  return {
    id: normalizedUrl,
    title: title?.trim() || getDomain(normalizedUrl),
    url: normalizedUrl,
    domain: getDomain(normalizedUrl),
  };
}

function normalizeWebSearchResultItem(
  item: unknown,
): WebSearchResultItem | null {
  const record = parseObjectRecord(item);
  const url = typeof record.url === "string" ? record.url.trim() : "";
  if (!url) return null;

  return {
    type: "web_search_result",
    title: typeof record.title === "string" ? record.title : undefined,
    url,
  };
}

function buildWebSearchSourceList(items: WebSearchResultItem[]): Source[] {
  return items
    .map((item) => (item.url ? normalizeSource(item.url, item.title) : null))
    .filter((item): item is Source => item !== null);
}

function buildWebSearchSummary(
  result: WebSearchToolResultContent,
): Record<string, unknown> {
  return {
    tool: "web_search",
    resultCount: result.content.length,
    urls: result.content.map((item) => item.url).filter(Boolean),
  };
}

function parseSseRecord(record: string): ParsedSseEvent | null {
  const event: ParsedSseEvent = {};

  for (const line of record.split("\n")) {
    if (!line) continue;
    if (line.startsWith(":")) continue;
    if (line.startsWith("event:")) {
      event.event = line.slice(6).trim();
      continue;
    }
    if (line.startsWith("data:")) {
      const value = line.slice(5).trim();
      event.data = event.data ? `${event.data}\n${value}` : value;
    }
  }

  return event.data ? event : null;
}

function buildRequestTools(
  tools: Tool[] | undefined,
): Array<Record<string, unknown>> | undefined {
  if (!tools?.length) return undefined;

  return tools.flatMap((tool) => {
    if ("input_schema" in tool) {
      return [{
        type: "function",
        function: {
          name: tool.name,
          description: tool.description,
          parameters: tool.input_schema,
        },
      }];
    }

    if (tool.type === "web_search") {
      return [{
        type: "web_search",
      }];
    }

    return [];
  });
}

function parseMistralErrorResponse(
  status: number,
  errorText: string,
): MistralProviderError {
  let providerType: string | undefined;
  let providerCode: string | undefined;
  let providerMessage: string | undefined;
  let requestId: string | undefined;

  try {
    const parsed = JSON.parse(errorText) as MistralErrorPayload;
    providerType = typeof parsed.type === "string" ? parsed.type : undefined;
    providerCode =
      typeof parsed.code === "string" || typeof parsed.code === "number"
        ? String(parsed.code)
        : undefined;
    requestId = typeof parsed.request_id === "string"
      ? parsed.request_id
      : undefined;

    if (typeof parsed.message === "string") {
      providerMessage = parsed.message;
    } else if (Array.isArray(parsed.detail)) {
      providerMessage = parsed.detail
        .map((entry) => {
          const record = parseObjectRecord(entry);
          const message = typeof record.msg === "string"
            ? record.msg
            : undefined;
          const location = Array.isArray(record.loc)
            ? record.loc.join(".")
            : undefined;
          return message && location ? `${location}: ${message}` : message;
        })
        .filter((entry): entry is string => Boolean(entry))
        .join("; ");
    }
  } catch {
    providerMessage = errorText.trim() || undefined;
  }

  return new MistralProviderError({
    status,
    providerType,
    providerCode,
    providerMessage,
    requestId,
    publicMessage: GENERIC_PROVIDER_ERROR_MESSAGE,
  });
}

function parseMistralStreamError(
  event: Record<string, unknown>,
): MistralProviderError {
  const nestedError = parseObjectRecord(event.error);
  const source = Object.keys(nestedError).length > 0 ? nestedError : event;
  const status = typeof source.status === "number"
    ? source.status
    : typeof event.status === "number"
    ? event.status
    : 400;
  const providerType = typeof source.type === "string" &&
      source.type !== "conversation.response.error"
    ? source.type
    : undefined;
  const providerCode =
    typeof source.code === "string" || typeof source.code === "number"
      ? String(source.code)
      : undefined;
  const providerMessage = typeof source.message === "string"
    ? source.message
    : typeof source.detail === "string"
    ? source.detail
    : "Mistral streaming error";
  const requestId = typeof source.request_id === "string"
    ? source.request_id
    : typeof event.request_id === "string"
    ? event.request_id
    : undefined;

  return new MistralProviderError({
    status,
    providerType,
    providerCode,
    providerMessage,
    requestId,
    publicMessage: GENERIC_PROVIDER_ERROR_MESSAGE,
  });
}

async function readWithIdleTimeout(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs: number,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  let timeoutId: ReturnType<typeof setTimeout> | undefined;

  try {
    return await Promise.race([
      reader.read(),
      new Promise<ReadableStreamReadResult<Uint8Array>>((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(
            new Error(`Mistral stream was idle for more than ${timeoutMs}ms`),
          );
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }
  }
}

function extractOutputText(payload: ConversationResponsePayload): string {
  const parts: string[] = [];

  for (const output of payload.outputs ?? []) {
    if (typeof output.content === "string") {
      parts.push(output.content);
      continue;
    }

    if (Array.isArray(output.content)) {
      for (const item of output.content) {
        const record = parseObjectRecord(item);
        if (typeof record.text === "string") {
          parts.push(record.text);
        } else if (typeof record.content === "string") {
          parts.push(record.content);
        }
      }
    }
  }

  return parts.join("").trim();
}

function ensureWrappedSummary(content: string): string {
  const trimmed = content.trim();
  if (trimmed.startsWith("<summary>") && trimmed.endsWith("</summary>")) {
    return trimmed;
  }
  return `<summary>${trimmed}</summary>`;
}

export async function createMistralSummary(options: {
  apiKey: string;
  transcript: string;
  signal?: AbortSignal;
}): Promise<string> {
  const { apiKey, transcript, signal } = options;

  if (!apiKey.trim()) {
    throw new Error("Missing MISTRAL_API_KEY");
  }

  const response = await fetch(MISTRAL_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: WAGEY_MISTRAL_MODEL,
      store: false,
      stream: false,
      instructions:
        "Summarize this conversation between a user and Wagey, a shift/wage assistant. Preserve: shift IDs and dates mentioned, tool call results and their outcomes, user preferences and settings discussed, any pending actions or unresolved requests, and the user's name if known. Keep it concise. Output only the summary and wrap it in <summary></summary>.",
      inputs: [{
        role: "user",
        content: transcript,
      }],
    }),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw parseMistralErrorResponse(response.status, errorText);
  }

  const payload = await response.json() as ConversationResponsePayload;
  const content = extractOutputText(payload);
  if (!content) {
    throw new Error("Mistral summary response was empty");
  }

  return ensureWrappedSummary(content);
}

export async function* streamMistralChat(options: {
  apiKey: string;
  instructions?: string;
  inputs: MistralConversationInput[];
  tools?: Tool[];
  temperature?: number;
  signal?: AbortSignal;
  idleTimeoutMs?: number;
}): AsyncIterable<StreamChunk> {
  const {
    apiKey,
    instructions,
    inputs,
    tools,
    temperature,
    signal,
    idleTimeoutMs = MISTRAL_STREAM_IDLE_TIMEOUT_MS,
  } = options;

  if (!apiKey.trim()) {
    throw new Error("Missing MISTRAL_API_KEY");
  }

  const response = await fetch(MISTRAL_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: WAGEY_MISTRAL_MODEL,
      store: false,
      stream: true,
      inputs,
      tools: buildRequestTools(tools),
      instructions,
      ...(typeof temperature === "number" ? { temperature } : {}),
    }),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw parseMistralErrorResponse(response.status, errorText);
  }

  if (!response.body) {
    throw new Error("Mistral API returned no response body");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  const pendingFunctionCalls = new Map<string, PendingFunctionCall>();
  const pendingFunctionCallOrder: string[] = [];
  const pendingWebSearches = new Map<string, PendingWebSearch>();
  const completedWebSearches: PendingWebSearch[] = [];
  const webSearchReferences: WebSearchResultItem[] = [];
  let activeTextContentIndex: number | null = null;
  let sawLocalFunctionCall = false;

  const finalizeFunctionCalls = (): StreamChunk[] => {
    const chunks: StreamChunk[] = [];

    for (const toolCallId of pendingFunctionCallOrder) {
      const pending = pendingFunctionCalls.get(toolCallId);
      if (!pending) continue;

      sawLocalFunctionCall = true;
      try {
        chunks.push({
          type: "tool_use",
          id: pending.toolCallId,
          name: pending.name,
          input: JSON.parse(pending.argumentsJson || "{}") as Record<
            string,
            unknown
          >,
        });
      } catch {
        chunks.push({
          type: "tool_use",
          id: pending.toolCallId,
          name: pending.name,
          input: { INVALID_JSON: pending.argumentsJson },
        });
      }
    }

    pendingFunctionCalls.clear();
    pendingFunctionCallOrder.length = 0;
    return chunks;
  };

  const finalizeWebSearches = (): StreamChunk[] => {
    if (completedWebSearches.length === 0) {
      return [];
    }

    const chunks: StreamChunk[] = [];
    const sources = buildWebSearchSourceList(webSearchReferences);
    if (sources.length > 0) {
      chunks.push({ type: "sources", items: sources });
    }

    for (const completed of completedWebSearches) {
      const result: WebSearchToolResultContent = {
        type: "web_search_tool_result",
        tool_use_id: completed.id,
        content: webSearchReferences,
      };

      chunks.push({
        type: "built_in_tool_result",
        id: completed.id,
        name: "web_search",
        success: true,
        summary: buildWebSearchSummary(result),
        result,
      });
    }

    return chunks;
  };

  try {
    while (true) {
      const { done, value } = await readWithIdleTimeout(reader, idleTimeoutMs);
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });

      let recordBoundary = buffer.indexOf("\n\n");
      while (recordBoundary !== -1) {
        const rawRecord = buffer.slice(0, recordBoundary);
        buffer = buffer.slice(recordBoundary + 2);
        recordBoundary = buffer.indexOf("\n\n");

        const sseEvent = parseSseRecord(rawRecord);
        if (!sseEvent?.data) continue;

        const parsed = JSON.parse(sseEvent.data) as Record<string, unknown>;
        const eventType = typeof parsed.type === "string"
          ? parsed.type
          : sseEvent.event ?? "";

        if (eventType !== "function.call.delta") {
          for (const chunk of finalizeFunctionCalls()) {
            yield chunk;
          }
        }

        switch (eventType) {
          case "conversation.response.started":
            break;

          case "function.call.delta": {
            const event = parseObjectRecord(parsed);
            const eventId = typeof event.id === "string" ? event.id : "";
            if (!eventId) break;

            const toolCallId = typeof event.tool_call_id === "string"
              ? event.tool_call_id
              : eventId;

            const pending = pendingFunctionCalls.get(eventId) ?? {
              name: typeof event.name === "string" ? event.name : "",
              toolCallId,
              argumentsJson: "",
              started: false,
            };

            pending.name = typeof event.name === "string"
              ? event.name
              : pending.name;
            pending.argumentsJson += typeof event.arguments === "string"
              ? event.arguments
              : "";

            if (!pending.started) {
              pending.started = true;
              pendingFunctionCallOrder.push(eventId);
              yield {
                type: "tool_use_start",
                id: pending.toolCallId,
                name: pending.name,
                input: parseInputRecord(pending.argumentsJson),
              };
            }

            pendingFunctionCalls.set(eventId, pending);
            activeTextContentIndex = null;
            break;
          }

          case "tool.execution.started":
          case "tool.execution.delta":
          case "tool.execution.done": {
            const event = parseObjectRecord(parsed);
            const id = typeof event.id === "string" ? event.id : "";
            const name = typeof event.name === "string" ? event.name : "";
            const functionName = typeof event.function === "string"
              ? event.function
              : "";
            const isWebSearch = name === "web_search" ||
              functionName === "web_search";
            if (!id || !isWebSearch) {
              activeTextContentIndex = null;
              break;
            }

            let pending = pendingWebSearches.get(id);
            if (!pending) {
              pending = {
                id,
                argumentsJson: "",
                input: {},
                completed: false,
              };
              pendingWebSearches.set(id, pending);
            }

            const argumentsChunk = typeof event.arguments === "string"
              ? event.arguments
              : "";
            if (argumentsChunk) {
              pending.argumentsJson += argumentsChunk;
              pending.input = parseInputRecord(pending.argumentsJson);
            }

            if (eventType === "tool.execution.started") {
              yield {
                type: "built_in_tool_start",
                id,
                name: "web_search",
                input: pending.input,
              };
            }

            if (eventType === "tool.execution.done" && !pending.completed) {
              pending.completed = true;
              completedWebSearches.push(pending);
              pendingWebSearches.delete(id);
            }

            activeTextContentIndex = null;
            break;
          }

          case "message.output.delta": {
            const event = parseObjectRecord(parsed);
            const content = event.content;
            const contentIndex = typeof event.content_index === "number"
              ? event.content_index
              : null;

            if (typeof content === "string") {
              if (
                contentIndex === null || activeTextContentIndex !== contentIndex
              ) {
                activeTextContentIndex = contentIndex;
                yield { type: "text_start" };
              }
              if (content) {
                yield { type: "text", content };
              }
              break;
            }

            const contentRecord = parseObjectRecord(content);
            if (
              contentRecord.type === "tool_reference" &&
              contentRecord.tool === "web_search"
            ) {
              const item = normalizeWebSearchResultItem(contentRecord);
              if (item) {
                webSearchReferences.push(item);
              }
            }

            activeTextContentIndex = null;
            break;
          }

          case "conversation.response.done": {
            for (const chunk of finalizeFunctionCalls()) {
              yield chunk;
            }
            for (const chunk of finalizeWebSearches()) {
              yield chunk;
            }
            yield {
              type: "done",
              stopReason: sawLocalFunctionCall ? "tool_use" : "end_turn",
            };
            return;
          }

          case "conversation.response.error":
          case "error": {
            throw parseMistralStreamError(parsed);
          }

          default:
            activeTextContentIndex = null;
            break;
        }
      }
    }

    for (const chunk of finalizeFunctionCalls()) {
      yield chunk;
    }
    for (const chunk of finalizeWebSearches()) {
      yield chunk;
    }
  } finally {
    reader.releaseLock();
  }
}
