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
  type: "web_search";
  search_context_size?: "low" | "medium" | "high";
  user_location?: {
    type: "approximate";
    city?: string;
    country?: string;
    region?: string;
    timezone?: string;
  };
};

export type CodeInterpreterTool = {
  type: "code_interpreter";
  container?: {
    type: "auto";
  };
};

export type Tool = FunctionTool | WebSearchTool | CodeInterpreterTool;

export type BuiltInToolName = "web_search" | "code_interpreter";

export type Source = {
  id: string;
  title: string;
  url: string;
  domain: string;
};

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
