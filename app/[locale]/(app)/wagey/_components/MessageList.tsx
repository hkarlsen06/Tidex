"use client";

/**
 * Message List Component
 *
 * Displays chat messages with markdown support
 */

import type { ReactNode } from "react";
import { useState } from "react";
import { Card } from "@/components/app/Card";
import { useTranslations } from "@/lib/i18n/client";

type Message = {
  id: string;
  role: "user" | "assistant";
  content: string;
  toolCalls?: Array<{
    id: string;
    name: string;
    arguments?: string;
    result?: string;
    success?: boolean;
  }>;
};

type MessageListProps = {
  messages: Message[];
  currentChunk: string;
  isStreaming: boolean;
  userName?: string;
};

const formatContent = (text: string | null | undefined) => {
  const safeText = `${text ?? ""}`;

  // First, split by code blocks to handle them separately
  const codeBlockRegex = /```[\s\S]*?```/g;
  const parts = safeText.split(codeBlockRegex);
  const codeBlocks = safeText.match(codeBlockRegex) || [];

  const result: ReactNode[] = [];

  parts.forEach((part, partIndex) => {
    // Process regular text
    if (part) {
      result.push(...formatRegularText(part, `part-${partIndex}`));
    }

    // Insert code block after this part (if exists)
    if (codeBlocks[partIndex]) {
      const codeContent = codeBlocks[partIndex]
        .replace(/^```\w*\n?/, "") // Remove opening ``` with optional language
        .replace(/\n?```$/, "");   // Remove closing ```

      result.push(
        <pre
          key={`code-${partIndex}`}
          className="my-2 px-3 py-2 bg-black/10 dark:bg-white/10 rounded-lg text-[13px] font-mono overflow-x-auto whitespace-pre show-scrollbar"
        >
          {codeContent}
        </pre>
      );
    }
  });

  return result;
};

const formatRegularText = (text: string, keyPrefix: string): ReactNode[] => {
  // Split by lines to handle headings
  const lines = text.split("\n");

  return lines.map((line, lineIndex) => {
    // Check if line is a heading (## text)
    const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);

    if (headingMatch) {
      const [, hashes, headingText] = headingMatch;
      const level = hashes.length;

      // Format the heading text (may contain bold)
      const formattedHeading = headingText.split(/(\*\*[^*]+?\*\*)/g).map((part, index) => {
        const isBold = part.startsWith("**") && part.endsWith("**") && part.length > 4;
        const content = isBold ? part.slice(2, -2) : part;

        return (
          <span
            key={`${keyPrefix}-${lineIndex}-${index}`}
            className={isBold ? "font-semibold text-current" : undefined}
          >
            {content}
          </span>
        );
      });

      // Render heading with appropriate styling
      if (level === 1) {
        return (
          <h1 key={`${keyPrefix}-${lineIndex}`} className="text-xl font-bold mb-2 mt-3">
            {formattedHeading}
          </h1>
        );
      } else if (level === 2) {
        return (
          <h2 key={`${keyPrefix}-${lineIndex}`} className="text-lg font-bold mb-1.5 mt-2.5">
            {formattedHeading}
          </h2>
        );
      } else if (level === 3) {
        return (
          <h3 key={`${keyPrefix}-${lineIndex}`} className="text-base font-semibold mb-1 mt-2">
            {formattedHeading}
          </h3>
        );
      } else {
        return (
          <h4 key={`${keyPrefix}-${lineIndex}`} className="text-sm font-semibold mb-1 mt-1.5">
            {formattedHeading}
          </h4>
        );
      }
    }

    // Not a heading, handle as regular line with bold support
    const parts = line.split(/(\*\*[^*]+?\*\*)/g).map((part, index) => {
      const isBold = part.startsWith("**") && part.endsWith("**") && part.length > 4;
      const content = isBold ? part.slice(2, -2) : part;

      return (
        <span
          key={`${keyPrefix}-${lineIndex}-${index}`}
          className={isBold ? "font-semibold text-current" : undefined}
        >
          {content}
        </span>
      );
    });

    return (
      <span key={`${keyPrefix}-${lineIndex}`}>
        {parts}
        {lineIndex < lines.length - 1 && "\n"}
      </span>
    );
  });
};

export function MessageList({
  messages,
  currentChunk,
  isStreaming,
  userName,
}: MessageListProps) {
  const { t } = useTranslations();

  if (messages.length === 0 && !currentChunk) {
    return (
      <div className="text-center text-text-muted pt-2">
        <p className="text-lg">👋 {t.pages.wagey.greeting}</p>
        <p className="text-sm mt-2">{t.pages.wagey.greetingSubtitle}</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {messages.map((message) => (
        <MessageBubble key={message.id} message={message} userName={userName} />
      ))}

      {/* Thinking indicator - show when streaming but no content yet */}
      {isStreaming && !currentChunk && (
        <ThinkingBubble />
      )}

      {/* Current streaming message */}
      {isStreaming && currentChunk && (
        <MessageBubble
          message={{
            id: "streaming",
            role: "assistant",
            content: currentChunk,
          }}
          isStreaming
        />
      )}
    </div>
  );
}

function MessageBubble({
  message,
  isStreaming,
  userName,
}: {
  message: Message;
  isStreaming?: boolean;
  userName?: string;
}) {
  const { t } = useTranslations();
  const isUser = message.role === "user";
  const isToolCall = message.toolCalls && message.toolCalls.length > 0;
  const toolCallSucceeded = isToolCall && message.toolCalls?.[0]?.success === true;
  const [showTooltip, setShowTooltip] = useState(false);
  const labelClass = isUser ? "text-white/90" : "text-text-muted/70";
  const userLabel = (() => {
    if (!userName) return t.pages.wagey.you;
    const parts = userName
      .split(" ")
      .map((part) => part.trim())
    .filter(Boolean);
    if (parts.length === 0) return t.pages.wagey.you;
    if (parts.length === 1) return parts[0];
    if (parts.length === 2) return parts[0];
    return `${parts[0]} ${parts[1]}`;
  })();

  const handleToolCallClick = () => {
    if (isToolCall && message.toolCalls?.[0]) {
      setShowTooltip(!showTooltip);
    }
  };

  // Format tool result for display
  const getToolResultDisplay = () => {
    if (!message.toolCalls?.[0]) return null;

    const toolCall = message.toolCalls[0];

    // Parse arguments
    let parsedArgs: unknown = null;
    try {
      parsedArgs = toolCall.arguments ? JSON.parse(toolCall.arguments) : null;
    } catch {
      parsedArgs = toolCall.arguments ?? "Invalid JSON";
    }

    // Parse result (only if defined)
    let parsedResult: unknown = null;
    if (toolCall.result !== undefined) {
      try {
        parsedResult = JSON.parse(toolCall.result);
      } catch {
        parsedResult = toolCall.result;
      }
    } else {
      parsedResult = "No result yet";
    }

    const display = {
      tool: toolCall.name,
      request: parsedArgs,
      response: parsedResult,
    };

    try {
      return JSON.stringify(display, null, 2);
    } catch (error) {
      // Handle circular references or other JSON.stringify errors
      console.error("Failed to stringify tool display:", error);
      return JSON.stringify({
        tool: toolCall.name,
        request: "Failed to serialize",
        response: "Failed to serialize",
      }, null, 2);
    }
  };

  return (
    <div className="flex flex-col gap-2">
      <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
        <Card
          className={`max-w-[94%] md:max-w-[75%] rounded-3xl shadow-app-sm ${
            isUser
              ? "bg-linear-to-br from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end text-white shadow-app"
              : isToolCall
                ? "bg-surface-secondary/90 text-text-muted cursor-pointer hover:bg-surface-primary transition-colors border border-border/60"
                : "bg-surface-secondary/90 text-text-primary border border-border/60"
          } backdrop-blur`}
          onClick={isToolCall ? handleToolCallClick : undefined}
        >
          <div className="p-3 md:p-4 flex flex-col gap-1">
            <div className={`text-[11px] font-semibold ${labelClass} whitespace-nowrap`}>
              {isUser ? userLabel : isToolCall ? (toolCallSucceeded ? `Wagey • ${t.pages.wagey.worked}` : `Wagey • ${t.pages.wagey.working}`) : "Wagey"}
            </div>
            <div className="whitespace-pre-wrap wrap-break-words text-sm md:text-base leading-relaxed">
              {formatContent(message.content)}
              {isStreaming && <span className="animate-pulse ml-0.5">▋</span>}
            </div>
          </div>
        </Card>
      </div>

      {/* Tool call details - inline in chat flow */}
      {showTooltip && isToolCall && (
        <div className="flex justify-start">
          <Card className="max-w-[94%] md:max-w-[85%] bg-surface-primary border border-border shadow-app-sm rounded-2xl">
            <div className="p-3 max-h-80 overflow-y-auto">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-semibold text-text-primary">
                  Tool Call Details
                </span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setShowTooltip(false);
                  }}
                  className="text-text-secondary hover:text-text-primary transition-colors px-2 py-1 rounded hover:bg-surface-secondary text-sm"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>
              <pre className="text-xs text-text-primary whitespace-pre font-mono bg-background p-2 rounded border border-border overflow-x-auto show-scrollbar">
                {getToolResultDisplay()}
              </pre>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}

/**
 * Thinking bubble with animated dots
 * Shown while waiting for the AI response to start streaming
 */
function ThinkingBubble() {
  return (
    <div className="flex justify-start">
      <div className="rounded-3xl bg-surface-secondary/90 text-text-muted border border-border/60 backdrop-blur shadow-app-sm">
        <div className="px-4 py-3 md:px-5 md:py-4">
          <span className="inline-flex gap-1">
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "0ms" }} />
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "150ms" }} />
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "300ms" }} />
          </span>
        </div>
      </div>
    </div>
  );
}
