"use client";

/**
 * Message List Component
 *
 * Displays chat messages with markdown support and Framer Motion animations
 */

import type { ReactNode } from "react";
import { useRef, useEffect, useState, useSyncExternalStore, useCallback } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Card } from "@/components/app/Card";
import { useTranslations } from "@/lib/i18n/client";

// Animation variants for message bubbles with scroll-triggered animations
// Uses standard spring physics (stiffness: 300, damping: 30) per ANIMATION.md
const messageVariants = {
  hidden: (isUser: boolean) => ({
    opacity: 0,
    x: isUser ? 30 : -30,
    scale: 0.95,
  }),
  visible: {
    opacity: 1,
    x: 0,
    scale: 1,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
  exit: (isUser: boolean) => ({
    opacity: 0,
    x: isUser ? 30 : -30,
    scale: 0.95,
    transition: {
      duration: 0.2,
    },
  }),
};

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

/**
 * Check if a code block contains tabular data (tab or space-aligned).
 * Returns 'tab' if tab-separated, 'space' if space-aligned, or null if not tabular.
 */
const detectTabularFormat = (content: string): "tab" | "space" | null => {
  // Don't trim content - leading tabs are significant for table structure
  const lines = content.split("\n").filter((line) => line.trim());
  if (lines.length < 2) return null;

  // Check for tab-separated format first
  const linesWithTabs = lines.filter((line) => line.includes("\t"));
  if (linesWithTabs.length >= lines.length * 0.8) {
    const tabCounts = linesWithTabs.map((line) => (line.match(/\t/g) || []).length);
    const firstCount = tabCounts[0];
    const consistentTabs = tabCounts.filter((count) => count === firstCount).length;
    if (consistentTabs >= tabCounts.length * 0.8) {
      return "tab";
    }
  }

  // Check for space-aligned format (2+ spaces as delimiter)
  // This detects columns aligned with multiple spaces
  const linesWithMultiSpace = lines.filter((line) => /\s{2,}/.test(line));
  if (linesWithMultiSpace.length >= lines.length * 0.8) {
    // Check that each line has similar number of "columns" (split by 2+ spaces)
    const columnCounts = linesWithMultiSpace.map(
      (line) => line.split(/\s{2,}/).filter((c) => c.trim()).length
    );
    const firstColCount = columnCounts[0];
    // Allow some variance (±1 column) for space-aligned data
    const consistentCols = columnCounts.filter(
      (count) => Math.abs(count - firstColCount) <= 1
    ).length;
    if (consistentCols >= columnCounts.length * 0.7 && firstColCount >= 2) {
      return "space";
    }
  }

  return null;
};

/**
 * Parse tabular content into rows and cells.
 */
const parseTabularContent = (
  content: string,
  format: "tab" | "space"
): string[][] => {
  // Don't trim content - leading tabs are significant for table structure
  const lines = content.split("\n").filter((line) => line.trim());

  if (format === "tab") {
    return lines.map((line) => line.split("\t").map((cell) => cell.trim()));
  }

  // Space-aligned: split by 2+ spaces
  return lines.map((line) =>
    line
      .split(/\s{2,}/)
      .map((cell) => cell.trim())
      .filter((cell) => cell)
  );
};

/**
 * Render tabular content as a proper HTML table.
 */
const renderTabularData = (
  content: string,
  key: string,
  format: "tab" | "space"
): ReactNode => {
  const rows = parseTabularContent(content, format);

  // First row is header
  const [headerRow, ...dataRows] = rows;

  return (
    <div key={key} className="my-2 overflow-x-auto show-scrollbar">
      <table className="w-full text-[13px] font-mono border-collapse">
        <thead>
          <tr className="border-b border-border">
            {headerRow.map((cell, cellIndex) => (
              <th
                key={cellIndex}
                className="px-3 py-2 text-left font-semibold text-text-primary whitespace-nowrap"
              >
                {cell}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dataRows.map((row, rowIndex) => (
            <tr
              key={rowIndex}
              className="border-b border-border/50 last:border-b-0"
            >
              {row.map((cell, cellIndex) => (
                <td
                  key={cellIndex}
                  className={`px-3 py-2 whitespace-nowrap ${
                    cellIndex === 0 ? "text-text-primary" : "text-text-secondary"
                  }`}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

/**
 * Extract inline tabular data from regular text.
 * Looks for consecutive lines with tabs that form a table.
 * Returns array of {before, table, after} segments.
 */
const extractInlineTables = (
  text: string
): Array<{ type: "text"; content: string } | { type: "table"; content: string }> => {
  const lines = text.split("\n");
  const result: Array<{ type: "text"; content: string } | { type: "table"; content: string }> = [];

  let currentTextLines: string[] = [];
  let currentTableLines: string[] = [];
  let inTable = false;

  const flushText = () => {
    if (currentTextLines.length > 0) {
      result.push({ type: "text", content: currentTextLines.join("\n") });
      currentTextLines = [];
    }
  };

  const flushTable = () => {
    if (currentTableLines.length >= 2) {
      result.push({ type: "table", content: currentTableLines.join("\n") });
    } else if (currentTableLines.length > 0) {
      // Not enough lines for a table, treat as text
      currentTextLines.push(...currentTableLines);
    }
    currentTableLines = [];
  };

  for (const line of lines) {
    const hasTab = line.includes("\t");
    const isEmptyOrWhitespace = line.trim() === "";

    if (hasTab) {
      if (!inTable) {
        flushText();
        inTable = true;
      }
      currentTableLines.push(line);
    } else if (inTable) {
      // End of table section
      flushTable();
      inTable = false;
      if (!isEmptyOrWhitespace) {
        currentTextLines.push(line);
      } else {
        currentTextLines.push(line);
      }
    } else {
      currentTextLines.push(line);
    }
  }

  // Flush remaining content
  if (inTable) {
    flushTable();
  }
  flushText();

  return result;
};

const formatContent = (text: string | null | undefined) => {
  const safeText = `${text ?? ""}`;

  // First, split by code blocks to handle them separately
  const codeBlockRegex = /```[\s\S]*?```/g;
  const parts = safeText.split(codeBlockRegex);
  const codeBlocks = safeText.match(codeBlockRegex) || [];

  const result: ReactNode[] = [];

  parts.forEach((part, partIndex) => {
    // Process regular text - check for inline tables first
    if (part) {
      const segments = extractInlineTables(part);

      segments.forEach((segment, segIndex) => {
        if (segment.type === "table") {
          const tabularFormat = detectTabularFormat(segment.content);
          if (tabularFormat) {
            result.push(
              renderTabularData(segment.content, `inline-table-${partIndex}-${segIndex}`, tabularFormat)
            );
          } else {
            // Fallback to regular text if detection fails
            result.push(...formatRegularText(segment.content, `part-${partIndex}-${segIndex}`));
          }
        } else {
          result.push(...formatRegularText(segment.content, `part-${partIndex}-${segIndex}`));
        }
      });
    }

    // Insert code block after this part (if exists)
    if (codeBlocks[partIndex]) {
      const codeContent = codeBlocks[partIndex]
        .replace(/^```\w*\n?/, "") // Remove opening ``` with optional language
        .replace(/\n?```$/, "");   // Remove closing ```

      // Check if this is tabular data (tab or space-aligned)
      const tabularFormat = detectTabularFormat(codeContent);
      if (tabularFormat) {
        result.push(renderTabularData(codeContent, `table-${partIndex}`, tabularFormat));
      } else {
        result.push(
          <pre
            key={`code-${partIndex}`}
            className="my-2 px-3 py-2 bg-black/10 dark:bg-white/10 rounded-lg text-[13px] font-mono overflow-x-auto whitespace-pre show-scrollbar"
          >
            {codeContent}
          </pre>
        );
      }
    }
  });

  return result;
};

/**
 * Format inline text with bold (**text**) and italic (*text*) support.
 * Handles both formats, prioritizing bold (double asterisk) over italic (single asterisk).
 */
const formatInlineText = (text: string, keyPrefix: string): ReactNode[] => {
  // Match bold (**text**) or italic (*text*) - bold takes priority
  // Bold: ** followed by non-empty content (not starting with space) followed by **
  // Italic: * followed by non-empty content (not starting/ending with space, not another *) followed by *
  const inlineRegex = /(\*\*[^*]+?\*\*|\*(?!\s)([^*]+?)(?<!\s)\*)/g;

  const result: ReactNode[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = inlineRegex.exec(text)) !== null) {
    // Add text before this match
    if (match.index > lastIndex) {
      result.push(
        <span key={`${keyPrefix}-text-${lastIndex}`}>
          {text.slice(lastIndex, match.index)}
        </span>
      );
    }

    const matched = match[0];
    const isBold = matched.startsWith("**") && matched.endsWith("**");

    if (isBold) {
      // Bold: remove ** from both ends
      const content = matched.slice(2, -2);
      result.push(
        <strong key={`${keyPrefix}-bold-${match.index}`} className="font-semibold">
          {content}
        </strong>
      );
    } else {
      // Italic: remove * from both ends
      const content = matched.slice(1, -1);
      result.push(
        <em key={`${keyPrefix}-italic-${match.index}`} className="italic">
          {content}
        </em>
      );
    }

    lastIndex = match.index + matched.length;
  }

  // Add remaining text after last match
  if (lastIndex < text.length) {
    result.push(
      <span key={`${keyPrefix}-text-${lastIndex}`}>
        {text.slice(lastIndex)}
      </span>
    );
  }

  // If no matches, return the original text
  if (result.length === 0) {
    return [<span key={`${keyPrefix}-plain`}>{text}</span>];
  }

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

      // Format the heading text (may contain bold/italic)
      const formattedHeading = formatInlineText(headingText, `${keyPrefix}-${lineIndex}-h`);

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

    // Not a heading, handle as regular line with bold/italic support
    const formattedLine = formatInlineText(line, `${keyPrefix}-${lineIndex}`);

    return (
      <span key={`${keyPrefix}-${lineIndex}`}>
        {formattedLine}
        {lineIndex < lines.length - 1 && "\n"}
      </span>
    );
  });
};

// Module-level store for streamed message IDs to work with useSyncExternalStore
// This is outside the component to persist across re-renders and satisfy ESLint
const streamedMessageStore = {
  ids: new Set<string>(),
  listeners: new Set<() => void>(),

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  },

  getSnapshot() {
    return this.ids;
  },

  addId(id: string) {
    if (!this.ids.has(id)) {
      this.ids = new Set(this.ids).add(id);
      this.listeners.forEach(listener => listener());
    }
  }
};

// Custom hook to track which messages were streamed in
function useStreamedMessageTracker(isStreaming: boolean, messages: Message[]) {
  const wasStreamingRef = useRef(false);

  // Subscribe to the external store
  const streamedIds = useSyncExternalStore(
    useCallback((onStoreChange) => streamedMessageStore.subscribe(onStoreChange), []),
    () => streamedMessageStore.getSnapshot(),
    () => streamedMessageStore.getSnapshot()
  );

  // Update the store in an effect when streaming ends
  useEffect(() => {
    if (wasStreamingRef.current && !isStreaming && messages.length > 0) {
      const lastMessage = messages[messages.length - 1];
      if (lastMessage.role === "assistant") {
        streamedMessageStore.addId(lastMessage.id);
      }
    }
    wasStreamingRef.current = isStreaming;
  }, [isStreaming, messages]);

  return streamedIds;
}

export function MessageList({
  messages,
  currentChunk,
  isStreaming,
  userName,
}: MessageListProps) {
  const { t } = useTranslations();

  // Track IDs of messages that were streamed in - these skip entrance animation
  const streamedMessageIds = useStreamedMessageTracker(isStreaming, messages);

  if (messages.length === 0 && !currentChunk) {
    return (
      <motion.div
        className="text-center text-text-muted pt-2"
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 300, damping: 30 }}
      >
        <p className="text-lg">👋 {t.pages.wagey.greeting}</p>
        <p className="text-sm mt-2">{t.pages.wagey.greetingSubtitle}</p>
      </motion.div>
    );
  }

  return (
    <div className="space-y-4">
      <AnimatePresence mode="popLayout">
        {messages.map((message) => (
          <MessageBubble
            key={message.id}
            message={message}
            userName={userName}
            skipAnimation={streamedMessageIds.has(message.id)}
          />
        ))}

        {/* Thinking indicator - show when streaming but no content yet */}
        {isStreaming && !currentChunk && (
          <ThinkingBubble key="thinking" />
        )}

        {/* Current streaming message */}
        {isStreaming && currentChunk && (
          <MessageBubble
            key="streaming"
            message={{
              id: "streaming",
              role: "assistant",
              content: currentChunk,
            }}
            isStreaming
          />
        )}
      </AnimatePresence>
    </div>
  );
}

function MessageBubble({
  message,
  isStreaming,
  userName,
  skipAnimation,
}: {
  message: Message;
  isStreaming?: boolean;
  userName?: string;
  /** Skip entrance animation (for messages that just finished streaming) */
  skipAnimation?: boolean;
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

  // Skip animations for streaming messages to avoid jank during content updates
  if (isStreaming) {
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
              <div className="whitespace-pre-wrap wrap-break-word text-sm md:text-base leading-relaxed">
                {formatContent(message.content)}
                <span className="animate-pulse ml-0.5">▋</span>
              </div>
            </div>
          </Card>
        </div>
      </div>
    );
  }

  // For messages that just finished streaming, skip animation entirely
  // They're already visible from the streaming phase
  if (skipAnimation) {
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
              <div className="whitespace-pre-wrap wrap-break-word text-sm md:text-base leading-relaxed">
                {formatContent(message.content)}
              </div>
            </div>
          </Card>
        </div>

        {/* Tool call details - inline in chat flow */}
        <AnimatePresence>
          {showTooltip && isToolCall && (
            <motion.div
              className="flex justify-start"
              initial={{ opacity: 0, height: 0, y: -10 }}
              animate={{ opacity: 1, height: "auto", y: 0 }}
              exit={{ opacity: 0, height: 0, y: -10 }}
              transition={{ type: "spring", stiffness: 300, damping: 30 }}
            >
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
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    );
  }

  return (
    <motion.div
      className="flex flex-col gap-2"
      variants={messageVariants}
      initial="hidden"
      whileInView="visible"
      exit="exit"
      custom={isUser}
      viewport={{ once: false, amount: 0.3 }}
      layout
    >
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
            <div className="whitespace-pre-wrap wrap-break-word text-sm md:text-base leading-relaxed">
              {formatContent(message.content)}
            </div>
          </div>
        </Card>
      </div>

      {/* Tool call details - inline in chat flow */}
      <AnimatePresence>
        {showTooltip && isToolCall && (
          <motion.div
            className="flex justify-start"
            initial={{ opacity: 0, height: 0, y: -10 }}
            animate={{ opacity: 1, height: "auto", y: 0 }}
            exit={{ opacity: 0, height: 0, y: -10 }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
          >
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
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

/**
 * Thinking bubble with animated dots
 * Shown while waiting for the AI response to start streaming
 */
function ThinkingBubble() {
  return (
    <motion.div
      className="flex justify-start"
      variants={messageVariants}
      initial="hidden"
      whileInView="visible"
      exit="exit"
      custom={false}
      viewport={{ once: false, amount: 0.3 }}
      layout
    >
      <div className="rounded-3xl bg-surface-secondary/90 text-text-muted border border-border/60 backdrop-blur shadow-app-sm">
        <div className="px-4 py-3 md:px-5 md:py-4">
          <span className="inline-flex gap-1">
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "0ms" }} />
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "150ms" }} />
            <span className="w-2 h-2 rounded-full bg-text-muted/60 animate-bounce" style={{ animationDelay: "300ms" }} />
          </span>
        </div>
      </div>
    </motion.div>
  );
}
