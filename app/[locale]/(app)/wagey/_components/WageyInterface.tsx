"use client";

/**
 * Wagey Chat Interface
 *
 * Main chat UI component with streaming support
 */

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { createRiverClient } from "@/lib/river";
import type { ChatRouter, ChatChunk } from "@/lib/chat/router";
import type { WageyAccessResult } from "@/lib/wagey/types";
import { useTranslations } from "@/lib/i18n/client";
import { MessageList } from "./MessageList";
import { ChatInput } from "./ChatInput";
import { Button } from "@/components/app/Button";
import Link from "next/link";
import { PlusIcon, AlertCircle, ArrowRight } from "lucide-react";

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

type WageyInterfaceProps = {
  userId: string;
  userName?: string;
  wageyAccess: WageyAccessResult;
};

const client = createRiverClient<ChatRouter>("/api/chat");

const STORAGE_KEY = "wagey-conversation";

export function WageyInterface({ userId, userName, wageyAccess }: WageyInterfaceProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [messages, setMessages] = useState<Message[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [currentChunk, setCurrentChunk] = useState("");
  const [resumptionToken, setResumptionToken] = useState<string | null>(null);
  const [isHydrated, setIsHydrated] = useState(false);
  const [limitReached, setLimitReached] = useState(false);
  const [_limitResetDays, setLimitResetDays] = useState(0);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesContainerRef = useRef<HTMLDivElement>(null);
  const processedChunksRef = useRef<Set<string>>(new Set());
  const toolMessageMapRef = useRef<Map<string, string>>(new Map());
  const chunkSequenceRef = useRef(0);
  const hasSuccessfulToolCallsRef = useRef(false);

  // Track remaining messages for UI (decrements client-side after successful sends)
  const [remainingMessages, setRemainingMessages] = useState<number | null>(
    wageyAccess.remaining
  );

  // Load conversation from sessionStorage on client-side only (after hydration)
  useEffect(() => {
    try {
      const stored = sessionStorage.getItem(STORAGE_KEY);
      if (stored) {
        setMessages(JSON.parse(stored) as Message[]);
      }
    } catch (error) {
      console.error("Failed to load conversation from sessionStorage:", error);
    }
    setIsHydrated(true);
  }, []);

  // Save conversation to sessionStorage whenever messages change (but only after hydration)
  useEffect(() => {
    if (!isHydrated) return;

    try {
      if (messages.length > 0) {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(messages));
      }
    } catch (error) {
      console.error("Failed to save conversation to sessionStorage:", error);
    }
  }, [messages, isHydrated]);

  // Auto-scroll to bottom of messages container
  useEffect(() => {
    if (!messages.length && !currentChunk) return;

    requestAnimationFrame(() => {
      messagesEndRef.current?.scrollIntoView({
        behavior: "smooth",
        block: "end",
      });
    });
  }, [messages, currentChunk]);

  // Note: Auto-resume removed - streams expire in Redis
  // Users should start a new chat instead of trying to resume old sessions

  const nextMessageId = (prefix: string) => {
    const random =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : Math.random().toString(36).slice(2);

    return `${prefix}-${random}`;
  };

  // River stream caller
  const streamCaller = client.wagey.useStream({
    onStart: ({ encodedResumptionToken }) => {
      setResumptionToken(encodedResumptionToken);
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();
      chunkSequenceRef.current = 0;
      hasSuccessfulToolCallsRef.current = false;
    },

    onChunk: (chunk: ChatChunk) => {
      // Create unique signature for each chunk
      // For text chunks, use sequence number to avoid dropping duplicate content
      const signature =
        chunk.type === "text"
          ? `text:${chunkSequenceRef.current++}`
          : chunk.type === "tool_start"
            ? `tool_start:${chunk.toolCallId}`
            : chunk.type === "tool_result"
              ? `tool_result:${chunk.toolCallId}:${chunk.result}:${chunk.success}`
              : chunk.type;

      if (processedChunksRef.current.has(signature)) return;
      processedChunksRef.current.add(signature);

      if (chunk.type === "text") {
        setCurrentChunk((prev) => prev + chunk.content);
      } else if (chunk.type === "tool_start") {
        // Finalize current streaming text first
        setCurrentChunk((prev) => {
          // Store current text for batch update
          const currentText = prev;

          if (currentText) {
            const textMessage: Message = {
              id: nextMessageId("assistant"),
              role: "assistant",
              content: currentText,
            };

            const toolMessage: Message = {
              id: nextMessageId("tool"),
              role: "assistant",
              content: `🔧 ${getToolDisplayName(chunk.toolName)}`,
              toolCalls: [
                {
                  id: chunk.toolCallId,
                  name: chunk.toolName,
                  arguments: chunk.toolArguments,
                },
              ],
            };

            // Batch update to avoid race condition
            setMessages((messages) => {
              if (toolMessageMapRef.current.has(chunk.toolCallId)) {
                return messages;
              }

              toolMessageMapRef.current.set(chunk.toolCallId, toolMessage.id);
              return [...messages, textMessage, toolMessage];
            });
          } else {
            const toolMessage: Message = {
              id: nextMessageId("tool"),
              role: "assistant",
              content: `🔧 ${getToolDisplayName(chunk.toolName)}`,
              toolCalls: [
                {
                  id: chunk.toolCallId,
                  name: chunk.toolName,
                  arguments: chunk.toolArguments,
                },
              ],
            };

            setMessages((messages) => {
              if (toolMessageMapRef.current.has(chunk.toolCallId)) {
                return messages;
              }

              toolMessageMapRef.current.set(chunk.toolCallId, toolMessage.id);
              return [...messages, toolMessage];
            });
          }

          // Return empty string to clear current chunk
          return "";
        });
      } else if (chunk.type === "tool_result") {
        // Track successful tool calls for cache invalidation
        if (chunk.success) {
          hasSuccessfulToolCallsRef.current = true;
        }

        // Update tool call with result
        setMessages((prev) =>
          prev.map((msg) => {
            const toolCall = msg.toolCalls?.find((tc) => tc.id === chunk.toolCallId);
            if (toolCall) {
              // Extract message from result (result is now full JSON with message + data)
              let displayMessage = chunk.result;
              try {
                const parsed = JSON.parse(chunk.result);
                displayMessage = parsed.message || chunk.result;
              } catch {
                // If not JSON, use as-is
              }

              // Only update content if success - failures are handled by AI follow-up
              const updatedContent = chunk.success
                ? `✓ ${displayMessage}`
                : msg.content; // Keep "working" indicator for failures

              return {
                ...msg,
                content: updatedContent,
                toolCalls: msg.toolCalls?.map((tc) =>
                  tc.id === chunk.toolCallId
                    ? { ...tc, result: chunk.result, success: chunk.success }
                    : tc
                ),
              };
            }
            return msg;
          })
        );
      } else if (chunk.type === "wagey_limit") {
        // User hit their monthly limit
        setLimitReached(true);
        setLimitResetDays(chunk.resetDays);
        setMessages((prev) => [
          ...prev,
          {
            id: nextMessageId("limit"),
            role: "assistant",
            content: t.pages.wagey.limitReached.message
              .replace("{limit}", String(wageyAccess.limit ?? 0))
              .replace("{days}", String(chunk.resetDays)),
          },
        ]);
        processedChunksRef.current.clear();
        setIsStreaming(false);
        setCurrentChunk("");
      } else if (chunk.type === "wagey_no_access") {
        // User doesn't have access (shouldn't happen if page guards work)
        setMessages((prev) => [
          ...prev,
          {
            id: nextMessageId("no-access"),
            role: "assistant",
            content: t.pages.wagey.noAccess,
          },
        ]);
        processedChunksRef.current.clear();
        setIsStreaming(false);
        setCurrentChunk("");
      } else if (chunk.type === "done") {
        // Finalize any remaining text
        setCurrentChunk((currentText) => {
          if (currentText) {
            setMessages((messages) => {
              const lastMessage = messages[messages.length - 1];
              if (lastMessage?.role === "assistant" && lastMessage.content === currentText) {
                return messages;
              }

              return [
                ...messages,
                {
                  id: nextMessageId("assistant"),
                  role: "assistant",
                  content: currentText,
                },
              ];
            });
          }
          return ""; // Clear current chunk
        });
        processedChunksRef.current.clear();
        setIsStreaming(false);

        // Decrement remaining messages on successful completion (for UI only)
        if (remainingMessages !== null && remainingMessages > 0) {
          setRemainingMessages(remainingMessages - 1);
        }

        // Refresh router cache if there were successful tool calls
        // This ensures data is fresh when user navigates away
        if (hasSuccessfulToolCallsRef.current) {
          router.refresh();
          hasSuccessfulToolCallsRef.current = false;
        }
      }
    },

    onSuccess: () => {
      // Stream completed successfully - done chunk already handled finalization
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();
      setIsStreaming(false);
    },

    onError: (error) => {
      console.error("Stream error:", error);
      setMessages((prev) => [
        ...prev,
        {
          id: nextMessageId("error"),
          role: "assistant",
          content: `❌ Feil: ${error.message}`,
        },
      ]);
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();
      setIsStreaming(false);
      setCurrentChunk("");

      // Save error state to sessionStorage
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify([...messages, {
          id: nextMessageId("error"),
          role: "assistant",
          content: `❌ Feil: ${error.message}`,
        }]));
      } catch (storageError) {
        console.error("Failed to save error to sessionStorage:", storageError);
      }
    },

    onFatalError: (error) => {
      console.error("Fatal stream error:", error);
      setMessages((prev) => [
        ...prev,
        {
          id: nextMessageId("fatal-error"),
          role: "assistant",
          content: `❌ ${t.pages.wagey.errors.streamFailed}`,
        },
      ]);
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();
      setIsStreaming(false);
      setCurrentChunk("");

      // Save fatal error state to sessionStorage
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify([...messages, {
          id: nextMessageId("fatal-error"),
          role: "assistant",
          content: `❌ ${t.pages.wagey.errors.streamFailed}`,
        }]));
      } catch (storageError) {
        console.error("Failed to save fatal error to sessionStorage:", storageError);
      }
    },

    onInfo: ({ encodedResumptionToken }) => {
      // Store resumption token for cleanup
      // Note: Not updating URL as resume functionality is disabled
      // (streams expire in Redis)
      setResumptionToken(encodedResumptionToken);
    },

    onAbort: () => {
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();
      setIsStreaming(false);
      setCurrentChunk("");
    },
  });

  const handleSend = (content: string) => {
    if (!content.trim() || isStreaming) return;

    // Abort any existing stream before starting a new one
    streamCaller.abort();

    // Add user message
    const userMessage: Message = {
      id: nextMessageId("user"),
      role: "user",
      content,
    };

    processedChunksRef.current.clear();
    toolMessageMapRef.current.clear();
    setMessages((prev) => [...prev, userMessage]);
    setIsStreaming(true);
    setCurrentChunk("");

    // Build messages for AI
    type AIMessage = {
      role: "user" | "assistant" | "system" | "tool";
      content: string | null;
      tool_calls?: Array<{
        id: string;
        type: "function";
        function: {
          name: string;
          arguments: string;
        };
      }>;
      tool_call_id?: string;
      name?: string;
    };

    const aiMessages: AIMessage[] = messages.flatMap((msg): AIMessage[] => {
      const baseMessage: AIMessage = {
        role: msg.role as "user" | "assistant",
        content: msg.content,
      };

      if (!msg.toolCalls?.length) {
        return [baseMessage];
      }

      // Only include tool calls that have results (completed tool calls)
      const completedToolCalls = msg.toolCalls.filter((tc) => tc.result !== undefined);

      // If no completed tool calls, just return the text message
      if (completedToolCalls.length === 0) {
        return [baseMessage];
      }

      const assistantWithTools: AIMessage = {
        role: "assistant" as const,
        content: msg.content,
        tool_calls: completedToolCalls.map((tc) => ({
          id: tc.id,
          type: "function" as const,
          function: {
            name: tc.name,
            arguments: tc.arguments ?? "{}",
          },
        })),
      };

      const toolResponses: AIMessage[] = completedToolCalls.map((tc) => {
        try {
          return {
            role: "tool" as const,
            content: JSON.stringify({
              success: tc.success ?? true,
              message: tc.result ?? "",
            }),
            tool_call_id: tc.id,
            name: tc.name,
          };
        } catch (error) {
          // Handle JSON.stringify errors (circular references, etc.)
          console.error("Failed to stringify tool result:", error);
          return {
            role: "tool" as const,
            content: JSON.stringify({
              success: false,
              message: "Failed to serialize tool result",
            }),
            tool_call_id: tc.id,
            name: tc.name,
          };
        }
      });

      return [assistantWithTools, ...toolResponses];
    });

    // Start stream
    streamCaller.start({
      messages: [
        ...aiMessages,
        {
          role: "user" as const,
          content,
        },
      ],
      userId,
      userName,
    });
  };

  const handleNewChat = async () => {
    try {
      // Cleanup Redis stream
      if (resumptionToken) {
        try {
          await fetch("/api/chat/cleanup", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ streamRunId: resumptionToken }),
          });
        } catch (error) {
          console.error("Cleanup error:", error);
          // Continue with cleanup even if fetch fails
        }
      }
    } finally {
      // Always clear sessionStorage and reset state, even if cleanup fails
      try {
        sessionStorage.removeItem(STORAGE_KEY);
      } catch (error) {
        console.error("Failed to clear sessionStorage:", error);
      }

      // Reset state
      setMessages([]);
      setCurrentChunk("");
      setResumptionToken(null);
      setIsStreaming(false);
      processedChunksRef.current.clear();
      toolMessageMapRef.current.clear();

      // Clear URL
      router.replace(`/${locale}/wagey`);
    }
  };

  const getToolDisplayName = (toolName: string): string => {
    const normalizedToolName =
      (["add_shift", "update_shift", "delete_shift", "bulk_delete_shifts", "query_shifts", "calculate_wages"] as const).find(
        (name) => toolName.includes(name)
      ) || toolName;

    switch (normalizedToolName) {
      case "add_shift":
        return t.pages.wagey.toolFeedback.addingShift;
      case "update_shift":
        return t.pages.wagey.toolFeedback.updatingShift;
      case "delete_shift":
      case "bulk_delete_shifts":
        return t.pages.wagey.toolFeedback.deletingShift;
      case "query_shifts":
        return t.pages.wagey.toolFeedback.queryingShifts;
      case "calculate_wages":
        return "Beregner lønn";
      default:
        return t.pages.wagey.executing;
    }
  };

  return (
    <div className="flex flex-col h-full md:relative md:top-0 md:inset-auto md:max-w-3xl md:mx-auto md:mt-6 md:h-[calc(100vh-6rem)] md:min-h-[calc(100vh-6rem)] md:max-h-[calc(100vh-6rem)] md:rounded-card md:border md:border-border/60 md:shadow-app-lg overflow-hidden bg-background">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,hsla(var(--brand-gradientStart)/0.08),transparent_45%),radial-gradient(circle_at_80%_10%,hsla(var(--brand-gradientEnd)/0.06),transparent_35%)] pointer-events-none" />

      {/* Fixed Header */}
      <header className="relative z-10 shrink-0 px-4 py-4 md:py-5 border-b border-border/60 bg-surface-primary/95 backdrop-blur-lg flex items-center justify-between shadow-app-sm">
        <div className="flex-1 min-w-0 mr-3">
          <h1 className="text-xl md:text-2xl font-bold text-text-primary tracking-tight">
            {t.pages.wagey.title}
          </h1>
          <p className="text-sm text-text-secondary mt-1 leading-tight">
            {t.pages.wagey.subtitle}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {/* Remaining messages badge - show when 1-3 left, clickable for Pro users */}
          {remainingMessages !== null && remainingMessages > 0 && remainingMessages <= 3 && !limitReached && (
            wageyAccess.level === "pro" ? (
              <Link
                href={`/${locale}/settings/subscription`}
                className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 border border-amber-500/20 px-2 py-0.5 text-xs font-medium text-amber-600 dark:text-amber-400 hover:bg-amber-500/20 transition-colors"
              >
                <AlertCircle className="h-3 w-3" />
                {t.pages.wagey.messagesRemaining.replace("{count}", String(remainingMessages))}
              </Link>
            ) : (
              <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 border border-amber-500/20 px-2 py-0.5 text-xs font-medium text-amber-600 dark:text-amber-400">
                <AlertCircle className="h-3 w-3" />
                {t.pages.wagey.messagesRemaining.replace("{count}", String(remainingMessages))}
              </span>
            )
          )}
          {/* Limit reached badge - shows upgrade prompt for Pro/free, limit reached for Max/grandfathered */}
          {(limitReached || (remainingMessages !== null && remainingMessages === 0)) && (
            (wageyAccess.level === "pro" || wageyAccess.level === "free") ? (
              <Link
                href={`/${locale}/settings/subscription`}
                className="inline-flex items-center gap-1 rounded-full bg-linear-to-r from-brand-gradient-start/10 via-brand-gradient-mid/10 to-brand-gradient-end/10 border border-brand-gradient-mid/30 px-2 py-0.5 text-xs font-medium text-brand-gradient-mid hover:border-brand-gradient-mid/50 transition-colors"
              >
                <ArrowRight className="h-3 w-3" />
                {t.pages.wagey.upgradePrompt.button}
              </Link>
            ) : (
              <span className="inline-flex items-center gap-1 rounded-full bg-red-500/10 border border-red-500/20 px-2 py-0.5 text-xs font-medium text-red-600 dark:text-red-400">
                <AlertCircle className="h-3 w-3" />
                {t.pages.wagey.limitReached.badge}
              </span>
            )
          )}
          {messages.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={handleNewChat}
              disabled={isStreaming}
              className="shrink-0 backdrop-blur h-9 px-3 md:px-4 text-sm font-medium"
            >
              <PlusIcon className="h-4 w-4 mr-1.5 md:mr-2" />
              <span className="hidden xs:inline">Ny chat</span>
              <span className="xs:hidden">Ny</span>
            </Button>
          )}
        </div>
      </header>

      {/* Scrollable Messages Area */}
      <div
        ref={messagesContainerRef}
        className="relative z-10 flex-1 min-h-0 overflow-y-auto overscroll-contain px-3 pb-2 pt-8 md:px-5 md:pb-6 md:pt-10"
      >
        <div className="flex flex-col gap-3 md:gap-4 py-2 max-w-3xl mx-auto">
          <MessageList
            messages={messages}
            currentChunk={currentChunk}
            isStreaming={isStreaming}
            userName={userName}
          />
          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* Upgrade prompt for Pro and free users when limit reached */}
      {limitReached && (wageyAccess.level === "pro" || wageyAccess.level === "free") && (
        <div className="relative z-15 shrink-0 px-4 pt-3">
          <div className="max-w-3xl mx-auto">
            <Link
              href={`/${locale}/settings/subscription`}
              className="flex items-center justify-between gap-3 rounded-2xl bg-linear-to-r from-brand-gradient-start/10 via-brand-gradient-mid/10 to-brand-gradient-end/10 border border-brand-gradient-mid/30 px-4 py-3 hover:border-brand-gradient-mid/50 transition-colors group"
            >
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-text-primary">
                  {wageyAccess.level === "free"
                    ? t.pages.wagey.upgradePrompt.free.title
                    : t.pages.wagey.upgradePrompt.pro.title}
                </p>
                <p className="text-xs text-text-secondary mt-0.5">
                  {wageyAccess.level === "free"
                    ? t.pages.wagey.upgradePrompt.free.description
                    : t.pages.wagey.upgradePrompt.pro.description}
                </p>
              </div>
              <div className="flex items-center gap-1 text-sm font-medium text-brand-gradient-mid group-hover:translate-x-0.5 transition-transform">
                {wageyAccess.level === "free"
                  ? t.pages.wagey.upgradePrompt.free.button
                  : t.pages.wagey.upgradePrompt.pro.button}
                <ArrowRight className="h-4 w-4" />
              </div>
            </Link>
          </div>
        </div>
      )}

      {/* Fixed Input - stays at bottom, above navbar when closed */}
      <div className="relative z-20 shrink-0 px-4 pt-3 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-4 md:pt-4 bg-linear-to-t from-background via-background/95 to-transparent md:bg-none">
        <div className="max-w-3xl mx-auto">
          <ChatInput
            onSend={handleSend}
            disabled={isStreaming || limitReached}
            placeholder={limitReached ? t.pages.wagey.limitReached.inputPlaceholder : t.pages.wagey.placeholder}
          />
        </div>
      </div>
    </div>
  );
}
