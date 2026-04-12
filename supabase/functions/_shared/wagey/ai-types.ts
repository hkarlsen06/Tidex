/**
 * Provider-neutral AI types used by Wagey's backend.
 */

export type MessageRole = "user" | "assistant";

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

export type ServerToolUseContent = {
  type: "server_tool_use";
  id: string;
  name: BuiltInToolName;
  input: Record<string, unknown>;
};

export type WebSearchResultItem = {
  type: "web_search_result";
  title?: string;
  url?: string;
};

export type WebSearchToolResultContent = {
  type: "web_search_tool_result";
  tool_use_id: string;
  content: WebSearchResultItem[];
};

export type WebFetchResultDocument = {
  type?: string;
  url?: string;
  title?: string;
  content?: unknown;
};

export type WebFetchToolResultContent = {
  type: "web_fetch_tool_result";
  tool_use_id: string;
  content: WebFetchResultDocument;
};

export type CompactionContent = {
  type: "compaction";
  content: string;
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

export type ContentBlock =
  | TextContent
  | ImageContent
  | ToolUseContent
  | ToolResultContent
  | ServerToolUseContent
  | WebSearchToolResultContent
  | WebFetchToolResultContent
  | CompactionContent
  | ThinkingContent
  | RedactedThinkingContent;

export type Message = {
  role: MessageRole;
  content: string | ContentBlock[];
};

export type ToolInputExample = Record<string, unknown>;

export type FunctionTool = {
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

export type WebSearchTool = {
  type: "web_search_20260209";
  name: "web_search";
  max_uses?: number;
  search_context_size?: "low" | "medium" | "high";
  user_location?: {
    type: "approximate";
    city?: string;
    country?: string;
    region?: string;
    timezone?: string;
  };
};

export type WebFetchTool = {
  type: "web_fetch_20260209";
  name: "web_fetch";
  max_uses?: number;
};

export type Tool = FunctionTool | WebSearchTool | WebFetchTool;

export type BuiltInToolName = "web_search" | "web_fetch";

export type Source = {
  id: string;
  title: string;
  url: string;
  domain: string;
};

export type Citation = {
  type?: string;
  cited_text?: string;
  url?: string;
  title?: string;
  document_title?: string;
  encrypted_index?: string;
};

export type StreamChunk =
  | {
    type: "text_start";
  }
  | {
    type: "text";
    content: string;
    citations?: Citation[];
  }
  | {
    type: "tool_use_start";
    id: string;
    name: string;
    input: Record<string, unknown>;
  }
  | {
    type: "tool_use";
    id: string;
    name: string;
    input: Record<string, unknown>;
  }
  | {
    type: "built_in_tool_start";
    id: string;
    name: BuiltInToolName;
    input: Record<string, unknown>;
  }
  | {
    type: "built_in_tool_result";
    id: string;
    name: BuiltInToolName;
    success: boolean;
    summary: Record<string, unknown>;
    result:
      | WebSearchToolResultContent
      | WebFetchToolResultContent;
  }
  | {
    type: "sources";
    items: Source[];
  }
  | {
    type: "compaction";
    content: string;
  }
  | {
    type: "thinking_start";
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
