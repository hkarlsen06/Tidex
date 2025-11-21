"use client";

/**
 * Chat Input Component
 *
 * Textarea with send button for chat messages
 */

import { useState, useRef, KeyboardEvent } from "react";
import { Button } from "@/components/app/Button";
import { SendIcon } from "lucide-react";

type ChatInputProps = {
  onSend: (message: string) => void;
  disabled?: boolean;
  placeholder?: string;
};

export function ChatInput({
  onSend,
  disabled = false,
  placeholder = "Skriv en melding...",
}: ChatInputProps) {
  const [value, setValue] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const handleSend = () => {
    if (!value.trim() || disabled) return;

    onSend(value);
    setValue("");

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
    }
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleInput = () => {
    // Auto-resize textarea
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`;
    }
  };

  return (
    <div className="flex items-center gap-3 rounded-2xl border border-border/70 bg-surface-primary/90 p-3 shadow-app-lg backdrop-blur-md">
      <textarea
        ref={textareaRef}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={handleKeyDown}
        onInput={handleInput}
        placeholder={placeholder}
        disabled={disabled}
        rows={1}
        className="flex-1 resize-none rounded-xl border border-border/40 bg-surface-secondary/60 px-3 py-2.5 text-base leading-6 text-text-primary placeholder-text-muted/80 shadow-inner outline-none focus:border-brand-gradient-mid focus:ring-2 focus:ring-brand-gradient-mid/40 disabled:opacity-60 min-h-10 max-h-[200px]"
        aria-label="Chat input"
      />
      <Button
        onClick={handleSend}
        disabled={disabled || !value.trim()}
        size="icon"
        className="shrink-0 shadow-app bg-linear-to-br from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end text-white hover:brightness-110 h-11 w-11"
      >
        <SendIcon className="h-4 w-4" />
      </Button>
    </div>
  );
}
