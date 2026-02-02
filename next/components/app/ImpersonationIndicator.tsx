"use client";

import { useState, useEffect, useRef } from "react";
import { UserCog, X, Loader2, ChevronDown } from "lucide-react";
import { useImpersonation } from "@/components/providers/ImpersonationProvider";
import { useTranslations } from "@/lib/i18n/client";

/**
 * Format remaining time as "Xh Ym" or "Ym" or "< 1m"
 */
function formatTimeRemaining(expiresAt: string): string {
  const now = new Date();
  const expires = new Date(expiresAt);
  const remainingMs = expires.getTime() - now.getTime();

  if (remainingMs <= 0) {
    return "Expired";
  }

  const totalMinutes = Math.floor(remainingMs / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m`;
  }
  return "< 1m";
}

/**
 * Impersonation indicator dropdown that replaces the logo in the header.
 * Shows a compact badge that expands to show time remaining and stop button.
 */
export function ImpersonationIndicator() {
  const { isImpersonating, expiresAt, targetUserName } = useImpersonation();
  const { locale } = useTranslations();
  const [stopping, setStopping] = useState(false);
  const [open, setOpen] = useState(false);
  const [timeRemaining, setTimeRemaining] = useState<string>("");
  const btnRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  // Update time remaining every minute
  useEffect(() => {
    if (!expiresAt) return;

    const updateTime = () => {
      setTimeRemaining(formatTimeRemaining(expiresAt));
    };

    updateTime();
    const interval = setInterval(updateTime, 60000);

    return () => clearInterval(interval);
  }, [expiresAt]);

  // Close dropdown when clicking outside
  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (!open) return;
      const t = e.target as Node;
      if (menuRef.current?.contains(t) || btnRef.current?.contains(t)) return;
      setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [open]);

  if (!isImpersonating) {
    return null;
  }

  const handleStop = async () => {
    setStopping(true);

    try {
      const response = await fetch("/api/admin/impersonation/stop", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        if (data.redirectHint) {
          window.location.href = data.redirectHint;
          return;
        }
        setStopping(false);
        return;
      }

      // Use window.location for a full page navigation to ensure query params are preserved
      window.location.href = `/${locale}/settings/admin?tab=users`;
    } catch {
      setStopping(false);
    }
  };

  return (
    <div className="relative">
      {/* Trigger button */}
      <button
        ref={btnRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={(e) => {
          if (e.key === "Escape") setOpen(false);
        }}
        className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-amber-500/20 border border-amber-500/50 text-amber-600 dark:text-amber-400 hover:bg-amber-500/30 transition-colors"
      >
        <UserCog className="h-4 w-4 shrink-0" />
        <span className="font-medium text-sm">Impersonating</span>
        <ChevronDown className={`h-3.5 w-3.5 transition-transform ${open ? "rotate-180" : ""}`} />
      </button>

      {/* Dropdown menu */}
      {open && (
        <div
          ref={menuRef}
          role="menu"
          className="absolute left-0 mt-2 w-56 overflow-hidden rounded-xl border border-border/40 bg-background shadow-app-lg z-50"
        >
          {/* User info */}
          <div className="px-4 py-3 border-b border-border/40">
            <p className="text-sm text-text-secondary">Viewing as</p>
            <p className="text-sm font-medium text-text-primary truncate">
              {targetUserName || "User"}
            </p>
          </div>

          {/* Time remaining */}
          <div className="px-4 py-3 border-b border-border/40">
            <p className="text-sm text-text-secondary">Time remaining</p>
            <p className="text-sm font-medium text-amber-600 dark:text-amber-400">
              {timeRemaining}
            </p>
          </div>

          {/* Stop button */}
          <div className="p-2">
            <button
              onClick={handleStop}
              disabled={stopping}
              className="flex items-center justify-center gap-2 w-full px-4 py-2 text-sm font-medium text-error bg-error/10 hover:bg-error/20 rounded-lg transition-colors disabled:opacity-50"
            >
              {stopping ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <X className="h-4 w-4" />
              )}
              Stop Impersonation
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
