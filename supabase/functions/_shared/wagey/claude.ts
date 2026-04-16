import type {
  Citation,
  CompactionContent,
  ContentBlock,
  ImageContent,
  Message,
  RedactedThinkingContent,
  Source,
  StreamChunk,
  ThinkingContent,
  Tool,
  WebFetchResultDocument,
  WebFetchToolResultContent,
  WebSearchResultItem,
  WebSearchToolResultContent,
} from "./ai-types.ts";

const CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";
const COMPACTION_BETA = "compact-2026-01-12";
const CODE_EXECUTION_WEB_TOOLS_BETA = "code-execution-web-tools-2026-02-09";
export const SUPPORTED_CLAUDE_MODEL_PREFIXES = [
  "claude-opus-4-7",
  "claude-opus-4-6",
] as const;
export const DEFAULT_CLAUDE_MODEL = "claude-opus-4-7";
const DEFAULT_REASONING_EFFORT = "high";
const CLAUDE_STREAM_IDLE_TIMEOUT_MS = 30_000;
const GENERIC_PROVIDER_ERROR_MESSAGE =
  "Wagey er midlertidig utilgjengelig akkurat nå. Prøv igjen litt senere.";

export type ClaudeTool = Tool;

export type StreamOptions = {
  messages: Message[];
  system?: string;
  tools?: ClaudeTool[];
  maxTokens?: number;
  signal?: AbortSignal;
  idleTimeoutMs?: number;
};

type TextAccumulator = {
  text: string;
  citations: Citation[];
};

type FunctionToolUseAccumulator = {
  id: string;
  name: string;
  inputJson: string;
};

type ServerToolUseAccumulator = {
  id: string;
  name: "web_search" | "web_fetch";
  inputJson: string;
  input: Record<string, unknown>;
};

type ActiveBuiltInToolName = "web_search" | "web_fetch";

export class ClaudeProviderError extends Error {
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
        ? `Claude provider error: ${options.providerType}`
        : `Claude API error: ${options.status}`);
    super(providerSummary);
    this.name = "ClaudeProviderError";
    this.status = options.status;
    this.providerType = options.providerType;
    this.providerMessage = options.providerMessage;
    this.requestId = options.requestId;
    this.publicMessage = options.publicMessage ??
      GENERIC_PROVIDER_ERROR_MESSAGE;
  }
}

export function isSupportedClaudeModel(model: string): boolean {
  return SUPPORTED_CLAUDE_MODEL_PREFIXES.some((prefix) =>
    model.startsWith(prefix)
  );
}

export function resolveClaudeModel(configuredModel?: string | null): string {
  const trimmedModel = configuredModel?.trim() ?? "";
  return isSupportedClaudeModel(trimmedModel)
    ? trimmedModel
    : DEFAULT_CLAUDE_MODEL;
}

function parseClaudeEvent(line: string): Record<string, unknown> | null {
  if (!line.startsWith("data: ")) return null;
  const data = line.slice(6).trim();
  if (!data) return null;

  try {
    return JSON.parse(data) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function isContentBlockArray(
  content: Message["content"],
): content is ContentBlock[] {
  return Array.isArray(content);
}

function isBuiltInTool(
  tool: ClaudeTool,
): tool is Extract<ClaudeTool, { type: string }> {
  return "type" in tool;
}

function stripUnsupportedBlocks(messages: Message[]): Message[] {
  return messages.map((message) => {
    if (!isContentBlockArray(message.content)) {
      return message;
    }

    return {
      ...message,
      content: message.content.filter(
        (block) =>
          block.type === "text" ||
          block.type === "image" ||
          block.type === "tool_use" ||
          block.type === "tool_result" ||
          block.type === "server_tool_use" ||
          block.type === "web_search_tool_result" ||
          block.type === "web_fetch_tool_result" ||
          block.type === "compaction" ||
          block.type === "thinking" ||
          block.type === "redacted_thinking",
      ) as ContentBlock[],
    };
  });
}

function parseObjectRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function parseInputRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    try {
      return parseObjectRecord(JSON.parse(value));
    } catch {
      return {};
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

function normalizeCitation(citation: unknown): Citation | null {
  const record = parseObjectRecord(citation);
  const url = typeof record.url === "string" ? record.url : undefined;
  const title = typeof record.title === "string"
    ? record.title
    : typeof record.document_title === "string"
    ? record.document_title
    : undefined;

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

function normalizeWebFetchResultDocument(
  content: unknown,
): WebFetchResultDocument {
  const record = parseObjectRecord(content);
  return {
    type: typeof record.type === "string" ? record.type : undefined,
    url: typeof record.url === "string" ? record.url : undefined,
    title: typeof record.title === "string" ? record.title : undefined,
    content: record.content,
  };
}

function buildSourceListFromWebSearch(
  content: WebSearchResultItem[],
): Source[] {
  return content
    .map((item) => normalizeSource({ url: item.url, title: item.title }))
    .filter((source): source is Source => source !== null);
}

function buildSourceListFromWebFetch(
  content: WebFetchResultDocument,
): Source[] {
  const source = normalizeSource({ url: content.url, title: content.title });
  return source ? [source] : [];
}

function normalizeBuiltInToolName(name: string): ActiveBuiltInToolName | null {
  if (name === "web_search" || name === "web_fetch") return name;
  return null;
}

function parseWebSearchToolResult(
  block: Record<string, unknown>,
): WebSearchToolResultContent | null {
  const toolUseId = typeof block.tool_use_id === "string"
    ? block.tool_use_id
    : "";
  if (!toolUseId) return null;

  const rawContent = Array.isArray(block.content) ? block.content : [];
  const content = rawContent
    .map(normalizeWebSearchResultItem)
    .filter((item): item is WebSearchResultItem => item !== null);

  return {
    type: "web_search_tool_result",
    tool_use_id: toolUseId,
    content,
  };
}

function parseWebFetchToolResult(
  block: Record<string, unknown>,
): WebFetchToolResultContent | null {
  const toolUseId = typeof block.tool_use_id === "string"
    ? block.tool_use_id
    : "";
  if (!toolUseId) return null;

  return {
    type: "web_fetch_tool_result",
    tool_use_id: toolUseId,
    content: normalizeWebFetchResultDocument(block.content),
  };
}

function buildBuiltInToolSummary(
  name: ActiveBuiltInToolName,
  result: WebSearchToolResultContent | WebFetchToolResultContent,
): Record<string, unknown> {
  if (name === "web_search" && result.type === "web_search_tool_result") {
    return {
      tool: name,
      resultCount: result.content.length,
      urls: result.content.map((item) => item.url).filter(Boolean),
    };
  }

  if (name === "web_fetch" && result.type === "web_fetch_tool_result") {
    return {
      tool: name,
      url: result.content.url ?? null,
      title: result.content.title ?? null,
    };
  }

  return { tool: name };
}

function addBetaHeader(headers: Record<string, string>, beta: string): void {
  const existing = headers["anthropic-beta"];
  headers["anthropic-beta"] = existing ? `${existing},${beta}` : beta;
}

function parseClaudeErrorResponse(
  status: number,
  errorText: string,
): ClaudeProviderError {
  let providerType: string | undefined;
  let providerMessage: string | undefined;
  let requestId: string | undefined;

  try {
    const parsed = JSON.parse(errorText) as {
      error?: { type?: string; message?: string };
      request_id?: string;
    };
    providerType = parsed.error?.type;
    providerMessage = parsed.error?.message;
    requestId = parsed.request_id;
  } catch {
    providerMessage = errorText.trim() || undefined;
  }

  const normalizedMessage = providerMessage?.toLowerCase() ?? "";
  const isLowCreditError =
    normalizedMessage.includes("credit balance is too low") ||
    normalizedMessage.includes("purchase credits");

  return new ClaudeProviderError({
    status,
    providerType,
    providerMessage,
    requestId,
    publicMessage: isLowCreditError
      ? GENERIC_PROVIDER_ERROR_MESSAGE
      : GENERIC_PROVIDER_ERROR_MESSAGE,
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
            new Error(`Claude stream was idle for more than ${timeoutMs}ms`),
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

export async function* streamClaudeChat(options: {
  apiKey: string;
  model: string;
  messages: Message[];
  system?: string;
  tools?: ClaudeTool[];
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
    idleTimeoutMs = CLAUDE_STREAM_IDLE_TIMEOUT_MS,
  } = options;

  if (!apiKey.trim()) {
    throw new Error("Missing CLAUDE_API_KEY");
  }

  if (!model.trim()) {
    throw new Error("Missing CLAUDE_MODEL");
  }

  if (!isSupportedClaudeModel(model)) {
    throw new Error(
      `CLAUDE_MODEL must be a supported Wagey Opus model. Received: ${model}`,
    );
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
  };

  addBetaHeader(headers, COMPACTION_BETA);
  if (tools?.some(isBuiltInTool)) {
    addBetaHeader(headers, CODE_EXECUTION_WEB_TOOLS_BETA);
  }

  const body: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    stream: true,
    messages: stripUnsupportedBlocks(messages),
    thinking: { type: "adaptive" },
    output_config: { effort: DEFAULT_REASONING_EFFORT },
    context_management: {
      edits: [
        {
          type: "compact_20260112",
          pause_after_compaction: false,
          instructions:
            "Summarize this conversation between a user and Wagey, a shift/wage assistant. Preserve: shift IDs and dates mentioned, tool call results and their outcomes, user preferences and settings discussed, any pending actions or unresolved requests, and the user's name if known. Keep it concise. Wrap in <summary></summary>.",
        },
      ],
    },
  };

  if (system) {
    body.system = system;
  }

  if (tools?.length) {
    body.tools = tools.map((tool) => {
      if ("input_schema" in tool) {
        const { input_examples: _inputExamples, ...functionTool } = tool;
        return {
          ...functionTool,
          eager_input_streaming: true,
        };
      }

      return tool;
    });
  }

  const response = await fetch(CLAUDE_API_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw parseClaudeErrorResponse(response.status, errorText);
  }

  if (!response.body) {
    throw new Error("Claude API returned no response body");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let currentText: TextAccumulator | null = null;
  let currentToolUse: FunctionToolUseAccumulator | null = null;
  let currentServerToolUse: ServerToolUseAccumulator | null = null;
  let currentCompaction: CompactionContent | null = null;
  let currentThinking: ThinkingContent | null = null;
  let currentRedactedThinking: RedactedThinkingContent | null = null;
  const builtInToolNamesById = new Map<string, ActiveBuiltInToolName>();

  try {
    while (true) {
      const { done, value } = await readWithIdleTimeout(reader, idleTimeoutMs);
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.trim()) continue;

        const event = parseClaudeEvent(line);
        if (!event) continue;

        const eventType = typeof event.type === "string" ? event.type : "";

        switch (eventType) {
          case "content_block_start": {
            const block = parseObjectRecord(event.content_block);

            if (block.type === "text") {
              currentText = { text: "", citations: [] };
              yield { type: "text_start" };
            } else if (block.type === "tool_use") {
              currentToolUse = {
                id: String(block.id ?? ""),
                name: String(block.name ?? ""),
                inputJson: "",
              };
              yield {
                type: "tool_use_start",
                id: currentToolUse.id,
                name: currentToolUse.name,
                input: parseInputRecord(block.input),
              };
            } else if (block.type === "server_tool_use") {
              const normalizedName = normalizeBuiltInToolName(
                String(block.name ?? ""),
              );
              if (!normalizedName) {
                break;
              }

              currentServerToolUse = {
                id: String(block.id ?? ""),
                name: normalizedName,
                inputJson: "",
                input: parseInputRecord(block.input),
              };
              builtInToolNamesById.set(currentServerToolUse.id, normalizedName);
              yield {
                type: "built_in_tool_start",
                id: currentServerToolUse.id,
                name: normalizedName,
                input: currentServerToolUse.input,
              };
            } else if (block.type === "web_search_tool_result") {
              const result = parseWebSearchToolResult(block);
              if (!result) break;

              const name = builtInToolNamesById.get(result.tool_use_id) ??
                "web_search";
              const items = buildSourceListFromWebSearch(result.content);
              if (items.length > 0) {
                yield { type: "sources", items };
              }
              yield {
                type: "built_in_tool_result",
                id: result.tool_use_id,
                name,
                success: true,
                summary: buildBuiltInToolSummary(name, result),
                result,
              };
            } else if (block.type === "web_fetch_tool_result") {
              const result = parseWebFetchToolResult(block);
              if (!result) break;

              const name = builtInToolNamesById.get(result.tool_use_id) ??
                "web_fetch";
              const items = buildSourceListFromWebFetch(result.content);
              if (items.length > 0) {
                yield { type: "sources", items };
              }
              yield {
                type: "built_in_tool_result",
                id: result.tool_use_id,
                name,
                success: true,
                summary: buildBuiltInToolSummary(name, result),
                result,
              };
            } else if (block.type === "compaction") {
              currentCompaction = { type: "compaction", content: "" };
            } else if (block.type === "thinking") {
              currentThinking = {
                type: "thinking",
                thinking: "",
                signature: "",
              };
              yield { type: "thinking_start" };
            } else if (block.type === "redacted_thinking") {
              currentRedactedThinking = {
                type: "redacted_thinking",
                data: typeof block.data === "string" ? block.data : "",
              };
            }
            break;
          }

          case "content_block_delta": {
            const delta = parseObjectRecord(event.delta);

            if (delta.type === "text_delta" && typeof delta.text === "string") {
              if (!currentText) {
                currentText = { text: "", citations: [] };
              }
              currentText.text += delta.text;
              yield { type: "text", content: delta.text };
            }

            if (delta.type === "citations_delta") {
              const citation = normalizeCitation(delta.citation);
              if (citation) {
                if (!currentText) {
                  currentText = { text: "", citations: [] };
                }
                currentText.citations.push(citation);
              }
            }

            if (
              delta.type === "input_json_delta" &&
              typeof delta.partial_json === "string"
            ) {
              if (currentToolUse) {
                currentToolUse.inputJson += delta.partial_json;
              } else if (currentServerToolUse) {
                currentServerToolUse.inputJson += delta.partial_json;
              }
            }

            if (
              delta.type === "compaction_delta" && currentCompaction &&
              typeof delta.content === "string"
            ) {
              currentCompaction.content = delta.content;
            }

            if (
              delta.type === "thinking_delta" && currentThinking &&
              typeof delta.thinking === "string"
            ) {
              currentThinking.thinking += delta.thinking;
            }

            if (
              delta.type === "signature_delta" && currentThinking &&
              typeof delta.signature === "string"
            ) {
              currentThinking.signature = delta.signature;
            }

            if (
              delta.type === "redacted_thinking_delta" &&
              currentRedactedThinking && typeof delta.data === "string"
            ) {
              currentRedactedThinking.data += delta.data;
            }
            break;
          }

          case "content_block_stop": {
            if (currentText) {
              if (currentText.citations.length > 0) {
                yield {
                  type: "text",
                  content: "",
                  citations: currentText.citations,
                };
                const items = sourcesFromCitations(currentText.citations);
                if (items.length > 0) {
                  yield { type: "sources", items };
                }
              }
              currentText = null;
            }

            if (currentToolUse) {
              try {
                yield {
                  type: "tool_use",
                  id: currentToolUse.id,
                  name: currentToolUse.name,
                  input: JSON.parse(currentToolUse.inputJson || "{}") as Record<
                    string,
                    unknown
                  >,
                };
              } catch {
                yield {
                  type: "tool_use",
                  id: currentToolUse.id,
                  name: currentToolUse.name,
                  input: { INVALID_JSON: currentToolUse.inputJson },
                };
              }
              currentToolUse = null;
            }

            if (currentServerToolUse) {
              if (currentServerToolUse.inputJson.trim()) {
                currentServerToolUse.input = parseInputRecord(
                  currentServerToolUse.inputJson,
                );
              }
              currentServerToolUse = null;
            }

            if (currentCompaction) {
              yield currentCompaction;
              currentCompaction = null;
            }

            if (currentThinking) {
              yield currentThinking;
              currentThinking = null;
            }

            if (currentRedactedThinking) {
              yield currentRedactedThinking;
              currentRedactedThinking = null;
            }
            break;
          }

          case "message_delta": {
            const delta = parseObjectRecord(event.delta);
            if (typeof delta.stop_reason === "string") {
              yield {
                type: "done",
                stopReason: delta.stop_reason,
              };
            }
            break;
          }

          case "message_stop":
            return;

          case "error": {
            const error = parseObjectRecord(event.error);
            throw new Error(
              typeof error.message === "string"
                ? error.message
                : "Claude streaming error",
            );
          }
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}
