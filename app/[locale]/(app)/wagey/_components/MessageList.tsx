"use client";

/**
 * Message List Component
 *
 * Displays chat messages with markdown support
 */

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

  return safeText.split(/(\*\*[^*]+?\*\*)/g).map((part, index) => {
    const isBold = part.startsWith("**") && part.endsWith("**") && part.length > 4;
    const content = isBold ? part.slice(2, -2) : part;

    return (
      <span
        key={`${part}-${index}`}
        className={isBold ? "font-semibold text-current" : undefined}
      >
        {content}
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
  if (messages.length === 0 && !currentChunk) {
    return (
      <div className="text-center text-text-muted pt-2">
        <p className="text-lg">👋 Hei! Jeg er Wagey.</p>
        <p className="text-sm mt-2">Spør meg om å legge til, endre eller slette skift.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {messages.map((message) => (
        <MessageBubble key={message.id} message={message} userName={userName} />
      ))}

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
    if (!userName) return "Deg";
    const parts = userName
      .split(" ")
      .map((part) => part.trim())
    .filter(Boolean);
    if (parts.length === 0) return "Deg";
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
    let parsedArgs = null;
    try {
      parsedArgs = toolCall.arguments ? JSON.parse(toolCall.arguments) : null;
    } catch {
      parsedArgs = toolCall.arguments;
    }

    // Parse result
    let parsedResult = null;
    try {
      parsedResult = toolCall.result ? JSON.parse(toolCall.result) : null;
    } catch {
      parsedResult = toolCall.result;
    }

    const display = {
      tool: toolCall.name,
      request: parsedArgs,
      response: parsedResult,
    };

    return JSON.stringify(display, null, 2);
  };

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div className="relative w-full">
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

        {/* Tooltip showing tool result - positioned absolutely with full width on mobile */}
        {showTooltip && isToolCall && (
          <div className="absolute z-50 mt-2 left-0 right-0 w-full md:max-w-md">
            <Card className="bg-surface-primary border border-border shadow-app-lg">
              <div className="p-3 max-h-96 overflow-y-auto">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold text-text-primary">
                    Tool Call Details
                  </span>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setShowTooltip(false);
                    }}
                    className="text-text-secondary hover:text-text-primary transition-colors px-2 py-1 rounded hover:bg-surface-secondary"
                    aria-label="Close"
                  >
                    ✕
                  </button>
                </div>
                <pre className="text-xs text-text-primary whitespace-pre-wrap font-mono bg-background p-2 rounded border border-border">
                  {getToolResultDisplay()}
                </pre>
              </div>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
}
