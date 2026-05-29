import type {
  Citation,
  ContentBlock,
  Message,
  Source,
  StreamChunk,
  Tool,
  WebSearchResultItem,
  WebSearchToolResultContent,
} from "./ai-types.ts";

const OPENAI_RESPONSES_API_URL = "https://api.openai.com/v1/responses";
export const DEFAULT_OPENAI_MODEL = "gpt-5.5";
const DEFAULT_REASONING_EFFORT = "medium";
const OPENAI_STREAM_IDLE_TIMEOUT_MS = 30_000;
const GENERIC_PROVIDER_ERROR_MESSAGE =
  "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.";

export type OpenAITool = Tool;

type OpenAIInputItem = Record<string, unknown>;

type FunctionCallAccumulator = {
  id: string;
  callId: string;
  name: string;
  argumentsJson: string;
};

type TextAccumulator = {
  text: string;
  citations: Citation[];
};

export class OpenAIProviderError extends Error {
  readonly status: number;
  readonly providerType?: string;
  readonly providerMessage?: string;
  readonly requestId?: string;
  readonly publicMessage: string;

  constructor(options: {
    status: number;
    providerType?: string;
    providerMessage?: string;
    requestId?: string;
    publicMessage?: string;
  }) {
    const providerSummary = options.providerMessage?.trim() ||
      (options.providerType
        ? `OpenAI provider error: ${options.providerType}`
        : `OpenAI API error: ${options.status}`);
    super(providerSummary);
    this.name = "OpenAIProviderError";
    this.status = options.status;
    this.providerType = options.providerType;
    this.providerMessage = options.providerMessage;
    this.requestId = options.requestId;
    this.publicMessage = options.publicMessage ??
      GENERIC_PROVIDER_ERROR_MESSAGE;
  }
}

export function resolveOpenAIModel(configuredModel?: string | null): string {
  const trimmedModel = configuredModel?.trim() ?? "";
  return trimmedModel || DEFAULT_OPENAI_MODEL;
}

function parseOpenAIEvent(line: string): Record<string, unknown> | null {
  if (!line.startsWith("data: ")) return null;
  const data = line.slice(6).trim();
  if (!data || data === "[DONE]") return null;

  try {
    return JSON.parse(data) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function parseObjectRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function parseInputRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    if (!value.trim()) return {};
    try {
      return parseObjectRecord(JSON.parse(value));
    } catch {
      return { INVALID_JSON: value };
    }
  }

  return parseObjectRecord(value);
}

function getDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

function normalizeSource(
  source: Partial<Source> & { url?: string | null; title?: string | null },
): Source | null {
  const url = source.url?.trim();
  if (!url) return null;

  const title = source.title?.trim() || getDomain(url);
  return {
    id: url,
    title,
    url,
    domain: getDomain(url),
  };
}

function normalizeCitation(value: unknown): Citation | null {
  const record = parseObjectRecord(value);
  const url = typeof record.url === "string" ? record.url : undefined;
  const title = typeof record.title === "string" ? record.title : undefined;
  if (!url && !title) return null;

  return {
    type: typeof record.type === "string" ? record.type : undefined,
    cited_text: typeof record.cited_text === "string"
      ? record.cited_text
      : undefined,
    url,
    title,
    document_title: typeof record.document_title === "string"
      ? record.document_title
      : undefined,
    encrypted_index: typeof record.encrypted_index === "string"
      ? record.encrypted_index
      : undefined,
  };
}

function sourcesFromCitations(citations: Citation[]): Source[] {
  return citations
    .map((citation) =>
      normalizeSource({
        url: citation.url,
        title: citation.title ?? citation.document_title,
      })
    )
    .filter((source): source is Source => source !== null);
}

function normalizeWebSearchResultItem(
  item: unknown,
): WebSearchResultItem | null {
  const record = parseObjectRecord(item);
  const url = typeof record.url === "string" ? record.url : undefined;
  if (!url) return null;

  return {
    type: "web_search_result",
    title: typeof record.title === "string" ? record.title : undefined,
    url,
  };
}

function sourcesFromWebSearchOutput(item: Record<string, unknown>): Source[] {
  const rawResults = Array.isArray(item.results)
    ? item.results
    : Array.isArray(item.content)
    ? item.content
    : [];

  return rawResults
    .map(normalizeWebSearchResultItem)
    .filter((result): result is WebSearchResultItem => result !== null)
    .map((result) => normalizeSource({ url: result.url, title: result.title }))
    .filter((source): source is Source => source !== null);
}

function isContentBlockArray(
  content: Message["content"],
): content is ContentBlock[] {
  return Array.isArray(content);
}

function contentBlocksToInputContent(
  blocks: ContentBlock[],
  role: Message["role"],
): Array<Record<string, unknown>> {
  return blocks.flatMap((block): Array<Record<string, unknown>> => {
    if (block.type === "text") {
      return [{
        type: role === "assistant" ? "output_text" : "input_text",
        text: block.text,
      }];
    }

    if (block.type === "image") {
      return [{
        type: "input_image",
        image_url:
          `data:${block.source.media_type};base64,${block.source.data}`,
      }];
    }

    if (block.type === "compaction") {
      return [{
        type: "input_text",
        text: `<conversation_summary>${block.content}</conversation_summary>`,
      }];
    }

    return [];
  });
}

function messageToInputItems(message: Message): OpenAIInputItem[] {
  if (typeof message.content === "string") {
    return [{
      role: message.role,
      content: message.content,
    }];
  }

  const messageContent = contentBlocksToInputContent(
    message.content,
    message.role,
  );
  const items: OpenAIInputItem[] = [];
  const textBlocks = message.content.filter((block) =>
    block.type === "text" || block.type === "image" ||
    block.type === "compaction"
  );

  if (textBlocks.length > 0 || messageContent.length > 0) {
    items.push({
      role: message.role,
      content: messageContent,
    });
  }

  for (const block of message.content) {
    if (block.type === "tool_use") {
      items.push({
        type: "function_call",
        call_id: block.id,
        name: block.name,
        arguments: JSON.stringify(block.input),
      });
    } else if (block.type === "tool_result") {
      items.push({
        type: "function_call_output",
        call_id: block.tool_use_id,
        output: block.content,
      });
    } else if (block.type === "web_search_tool_result") {
      items.push({
        role: "user",
        content: [{
          type: "input_text",
          text: JSON.stringify(block),
        }],
      });
    }
  }

  return items;
}

function convertMessagesToOpenAIInput(messages: Message[]): OpenAIInputItem[] {
  return messages.flatMap(messageToInputItems);
}

function convertTool(tool: OpenAITool): Record<string, unknown> | null {
  if ("input_schema" in tool) {
    const { input_examples, input_schema, strict, ...functionTool } = tool;
    const description = input_examples?.length
      ? `${functionTool.description}\n\nInput examples:\n${
        input_examples.map((example) => JSON.stringify(example)).join("\n")
      }`
      : functionTool.description;
    const parameters = strict
      ? { ...input_schema, additionalProperties: false }
      : input_schema;

    return {
      type: "function",
      name: functionTool.name,
      description,
      parameters,
      strict: strict === true,
    };
  }

  if (tool.name === "web_search") {
    return { type: "web_search" };
  }

  if (tool.name === "web_fetch") {
    return {
      type: "function",
      name: "web_fetch",
      description:
        "Fetch a public web page or PDF URL when the user or prior search result provides a specific source to inspect.",
      parameters: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "The absolute http or https URL to fetch.",
          },
        },
        required: ["url"],
        additionalProperties: false,
      },
      strict: true,
    };
  }

  return null;
}

function parseOpenAIErrorResponse(
  status: number,
  errorText: string,
  requestId?: string | null,
): OpenAIProviderError {
  let providerType: string | undefined;
  let providerMessage: string | undefined;

  try {
    const parsed = JSON.parse(errorText) as {
      error?: { type?: string; message?: string; code?: string };
    };
    providerType = parsed.error?.type ?? parsed.error?.code;
    providerMessage = parsed.error?.message;
  } catch {
    providerMessage = errorText.trim() || undefined;
  }

  return new OpenAIProviderError({
    status,
    providerType,
    providerMessage,
    requestId: requestId ?? undefined,
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
            new Error(`OpenAI stream was idle for more than ${timeoutMs}ms`),
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

function getOutputItem(
  event: Record<string, unknown>,
): Record<string, unknown> {
  return parseObjectRecord(event.item ?? event.output_item);
}

function getOutputIndex(event: Record<string, unknown>): number | undefined {
  return typeof event.output_index === "number"
    ? event.output_index
    : typeof event.item_index === "number"
    ? event.item_index
    : undefined;
}

function getFunctionCallId(item: Record<string, unknown>): string {
  return String(item.call_id ?? item.id ?? crypto.randomUUID());
}

function getFunctionName(item: Record<string, unknown>): string {
  return String(item.name ?? "");
}

function extractTextDelta(event: Record<string, unknown>): string {
  if (typeof event.delta === "string") return event.delta;
  const delta = parseObjectRecord(event.delta);
  if (typeof delta.text === "string") return delta.text;
  if (typeof delta.value === "string") return delta.value;
  return "";
}

function extractFunctionArgumentsDelta(event: Record<string, unknown>): string {
  if (typeof event.delta === "string") return event.delta;
  if (typeof event.arguments === "string") return event.arguments;
  const delta = parseObjectRecord(event.delta);
  if (typeof delta.arguments === "string") return delta.arguments;
  return "";
}

export async function* streamOpenAIChat(options: {
  apiKey: string;
  model: string;
  messages: Message[];
  system?: string;
  tools?: OpenAITool[];
  maxTokens?: number;
  signal?: AbortSignal;
  idleTimeoutMs?: number;
}): AsyncIterable<StreamChunk> {
  const {
    apiKey,
    model,
    messages,
    system,
    tools,
    maxTokens = 4096,
    signal,
    idleTimeoutMs = OPENAI_STREAM_IDLE_TIMEOUT_MS,
  } = options;

  if (!apiKey.trim()) {
    throw new Error("Missing OPENAI_API_KEY");
  }

  if (!model.trim()) {
    throw new Error("Missing OPENAI_MODEL");
  }

  const convertedTools = (tools ?? [])
    .map(convertTool)
    .filter((tool): tool is Record<string, unknown> => tool !== null);

  const body: Record<string, unknown> = {
    model,
    input: convertMessagesToOpenAIInput(messages),
    stream: true,
    max_output_tokens: maxTokens,
    reasoning: { effort: DEFAULT_REASONING_EFFORT },
  };

  if (system) {
    body.instructions = system;
  }

  if (convertedTools.length > 0) {
    body.tools = convertedTools;
  }

  const response = await fetch(OPENAI_RESPONSES_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw parseOpenAIErrorResponse(
      response.status,
      errorText,
      response.headers.get("x-request-id"),
    );
  }

  if (!response.body) {
    throw new Error("OpenAI API returned no response body");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let activeText: TextAccumulator | null = null;
  const functionCallsByOutputIndex = new Map<number, FunctionCallAccumulator>();
  const functionCallsByItemId = new Map<string, FunctionCallAccumulator>();
  const emittedToolUseIds = new Set<string>();

  try {
    while (true) {
      const { done, value } = await readWithIdleTimeout(reader, idleTimeoutMs);
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.trim()) continue;

        const event = parseOpenAIEvent(line);
        if (!event) continue;

        const eventType = typeof event.type === "string" ? event.type : "";

        switch (eventType) {
          case "response.output_item.added": {
            const item = getOutputItem(event);
            const outputIndex = getOutputIndex(event);
            if (item.type === "function_call") {
              const accumulator = {
                id: String(item.id ?? getFunctionCallId(item)),
                callId: getFunctionCallId(item),
                name: getFunctionName(item),
                argumentsJson: typeof item.arguments === "string"
                  ? item.arguments
                  : "",
              };
              if (outputIndex !== undefined) {
                functionCallsByOutputIndex.set(outputIndex, accumulator);
              }
              functionCallsByItemId.set(accumulator.id, accumulator);
              yield {
                type: "tool_use_start",
                id: accumulator.callId,
                name: accumulator.name,
                input: parseInputRecord(accumulator.argumentsJson),
              };
            } else if (
              item.type === "web_search_call" ||
              item.type === "web_search"
            ) {
              yield {
                type: "built_in_tool_start",
                id: String(item.id ?? crypto.randomUUID()),
                name: "web_search",
                input: parseObjectRecord(item.action ?? item),
              };
            } else if (item.type === "message") {
              activeText = { text: "", citations: [] };
              yield { type: "text_start" };
            }
            break;
          }

          case "response.output_text.delta":
          case "response.refusal.delta": {
            const content = extractTextDelta(event);
            if (!content) break;
            if (!activeText) {
              activeText = { text: "", citations: [] };
              yield { type: "text_start" };
            }
            activeText.text += content;
            yield { type: "text", content };
            break;
          }

          case "response.output_text.annotation.added": {
            const annotation = normalizeCitation(event.annotation);
            if (!annotation) break;
            if (!activeText) {
              activeText = { text: "", citations: [] };
            }
            activeText.citations.push(annotation);
            break;
          }

          case "response.function_call_arguments.delta": {
            const outputIndex = getOutputIndex(event);
            const delta = extractFunctionArgumentsDelta(event);
            const itemId = typeof event.item_id === "string"
              ? event.item_id
              : undefined;
            const accumulator = outputIndex === undefined
              ? itemId ? functionCallsByItemId.get(itemId) : undefined
              : functionCallsByOutputIndex.get(outputIndex);
            if (accumulator) {
              accumulator.argumentsJson += delta;
            }
            break;
          }

          case "response.function_call_arguments.done": {
            const outputIndex = getOutputIndex(event);
            const itemId = typeof event.item_id === "string"
              ? event.item_id
              : undefined;
            const accumulator = outputIndex === undefined
              ? itemId ? functionCallsByItemId.get(itemId) : undefined
              : functionCallsByOutputIndex.get(outputIndex);
            if (!accumulator) break;
            if (typeof event.arguments === "string") {
              accumulator.argumentsJson = event.arguments;
            }
            if (emittedToolUseIds.has(accumulator.callId)) {
              break;
            }
            emittedToolUseIds.add(accumulator.callId);
            yield {
              type: "tool_use",
              id: accumulator.callId,
              name: accumulator.name,
              input: parseInputRecord(accumulator.argumentsJson),
            };
            break;
          }

          case "response.output_item.done": {
            const item = getOutputItem(event);
            if (item.type === "function_call") {
              const callId = getFunctionCallId(item);
              const name = getFunctionName(item);
              const argumentsJson = typeof item.arguments === "string"
                ? item.arguments
                : "";
              if (emittedToolUseIds.has(callId)) {
                break;
              }
              emittedToolUseIds.add(callId);
              yield {
                type: "tool_use",
                id: callId,
                name,
                input: parseInputRecord(argumentsJson),
              };
            } else if (
              item.type === "web_search_call" ||
              item.type === "web_search"
            ) {
              const id = String(item.id ?? crypto.randomUUID());
              const sourceItems = sourcesFromWebSearchOutput(item);
              if (sourceItems.length > 0) {
                yield { type: "sources", items: sourceItems };
              }
              const result: WebSearchToolResultContent = {
                type: "web_search_tool_result",
                tool_use_id: id,
                content: sourceItems.map((source) => ({
                  type: "web_search_result",
                  title: source.title,
                  url: source.url,
                })),
              };
              yield {
                type: "built_in_tool_result",
                id,
                name: "web_search",
                success: true,
                summary: {
                  tool: "web_search",
                  resultCount: result.content.length,
                  urls: result.content.map((item) => item.url).filter(Boolean),
                },
                result,
              };
            }
            break;
          }

          case "response.completed": {
            if (activeText?.citations.length) {
              yield {
                type: "text",
                content: "",
                citations: activeText.citations,
              };
              const items = sourcesFromCitations(activeText.citations);
              if (items.length > 0) {
                yield { type: "sources", items };
              }
            }
            activeText = null;
            yield { type: "done", stopReason: "completed" };
            return;
          }

          case "response.failed": {
            const responsePayload = parseObjectRecord(event.response);
            const error = parseObjectRecord(responsePayload.error);
            throw new OpenAIProviderError({
              status: 500,
              providerType: typeof error.type === "string"
                ? error.type
                : undefined,
              providerMessage: typeof error.message === "string"
                ? error.message
                : "OpenAI response failed",
            });
          }

          case "error": {
            const error = parseObjectRecord(event.error);
            throw new OpenAIProviderError({
              status: 500,
              providerType: typeof error.type === "string"
                ? error.type
                : undefined,
              providerMessage: typeof error.message === "string"
                ? error.message
                : "OpenAI streaming error",
            });
          }
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}
