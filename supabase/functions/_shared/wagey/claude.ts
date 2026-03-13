import type {
  CompactionContent,
  ContentBlock,
  FunctionTool,
  ImageContent,
  Message,
  RedactedThinkingContent,
  StreamChunk,
  ThinkingContent,
} from "./ai-types.ts";

const CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";
const COMPACTION_BETA = "compact-2026-01-12";
const OPUS_46_MODEL_PREFIX = "claude-opus-4-6";
export const DEFAULT_CLAUDE_MODEL = "claude-sonnet-4-5";

export type ClaudeTool = FunctionTool;

export type StreamOptions = {
  messages: Message[];
  system?: string;
  tools?: ClaudeTool[];
  temperature?: number;
  maxTokens?: number;
  signal?: AbortSignal;
};

function isOpus46Model(model: string): boolean {
  return model.startsWith(OPUS_46_MODEL_PREFIX);
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

function isContentBlockArray(content: Message["content"]): content is ContentBlock[] {
  return Array.isArray(content);
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
          block.type === "compaction" ||
          block.type === "thinking" ||
          block.type === "redacted_thinking",
      ) as ContentBlock[],
    };
  });
}

export async function* streamClaudeChat(options: {
  apiKey: string;
  model: string;
  messages: Message[];
  system?: string;
  tools?: ClaudeTool[];
  temperature?: number;
  maxTokens?: number;
  signal?: AbortSignal;
}): AsyncIterable<StreamChunk> {
  const {
    apiKey,
    model,
    messages,
    system,
    tools,
    temperature,
    maxTokens = 4096,
    signal,
  } = options;

  if (!apiKey.trim()) {
    throw new Error("Missing CLAUDE_API_KEY");
  }

  if (!model.trim()) {
    throw new Error("Missing CLAUDE_MODEL");
  }

  const opus46Enabled = isOpus46Model(model);
  const compactionEnabled = opus46Enabled;
  const adaptiveThinkingEnabled = opus46Enabled;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
  };

  if (compactionEnabled) {
    headers["anthropic-beta"] = COMPACTION_BETA;
  }

  const body: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    stream: true,
    messages: stripUnsupportedBlocks(messages),
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
    body.tools = tools.map(({ input_examples: _input_examples, ...tool }) => ({
      ...tool,
      eager_input_streaming: true,
    }));
  }

  const response = await fetch(CLAUDE_API_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal,
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw new Error(errorText || `Claude API error: ${response.status}`);
  }

  if (!response.body) {
    throw new Error("Claude API returned no response body");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let currentToolUse: { id: string; name: string; inputJson: string } | null = null;
  let currentCompaction: CompactionContent | null = null;
  let currentThinking: ThinkingContent | null = null;
  let currentRedactedThinking: RedactedThinkingContent | null = null;

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

        const event = parseClaudeEvent(line);
        if (!event) continue;

        const eventType = typeof event.type === "string" ? event.type : "";

        switch (eventType) {
          case "content_block_start": {
            const block = event.content_block as Record<string, unknown>;
            if (block?.type === "tool_use") {
              currentToolUse = {
                id: String(block.id ?? ""),
                name: String(block.name ?? ""),
                inputJson: "",
              };
            } else if (block?.type === "compaction") {
              currentCompaction = { type: "compaction", content: "" };
            } else if (block?.type === "thinking") {
              currentThinking = { type: "thinking", thinking: "", signature: "" };
            } else if (block?.type === "redacted_thinking") {
              currentRedactedThinking = {
                type: "redacted_thinking",
                data: typeof block.data === "string" ? block.data : "",
              };
            }
            break;
          }

          case "content_block_delta": {
            const delta = event.delta as Record<string, unknown>;
            if (delta?.type === "text_delta" && typeof delta.text === "string") {
              yield { type: "text", content: delta.text };
            }
            if (
              delta?.type === "input_json_delta" &&
              typeof delta.partial_json === "string" &&
              currentToolUse
            ) {
              currentToolUse.inputJson += delta.partial_json;
            }
            if (delta?.type === "compaction_delta" && currentCompaction && typeof delta.content === "string") {
              currentCompaction.content = delta.content;
            }
            if (delta?.type === "thinking_delta" && currentThinking && typeof delta.thinking === "string") {
              currentThinking.thinking += delta.thinking;
            }
            if (delta?.type === "signature_delta" && currentThinking && typeof delta.signature === "string") {
              currentThinking.signature = delta.signature;
            }
            if (
              delta?.type === "redacted_thinking_delta" &&
              currentRedactedThinking &&
              typeof delta.data === "string"
            ) {
              currentRedactedThinking.data += delta.data;
            }
            break;
          }

          case "content_block_stop": {
            if (currentToolUse) {
              try {
                yield {
                  type: "tool_use",
                  id: currentToolUse.id,
                  name: currentToolUse.name,
                  input: JSON.parse(currentToolUse.inputJson || "{}") as Record<string, unknown>,
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
            const delta = event.delta as Record<string, unknown>;
            if (typeof delta?.stop_reason === "string") {
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
            const error = event.error as Record<string, unknown>;
            throw new Error(
              typeof error?.message === "string" ? error.message : "Claude streaming error",
            );
          }
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}
