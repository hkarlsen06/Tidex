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

export type ContentBlock =
  | TextContent
  | ImageContent
  | ToolUseContent
  | ToolResultContent
  | CompactionContent;

export type Message = {
  role: MessageRole;
  content: string | ContentBlock[];
};

export type ToolInputExample = Record<string, unknown>;

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
      responseId?: string;
    };
