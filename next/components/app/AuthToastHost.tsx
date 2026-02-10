"use client";

import { CheckCircle2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { AUTH_TOAST_EVENT } from "@/lib/ui/auth-toast";

type ToastState = {
  id: number;
  message: string;
};

type AuthToastEvent = CustomEvent<{
  message: string;
  durationMs?: number;
}>;

export function AuthToastHost() {
  const [toast, setToast] = useState<ToastState | null>(null);
  const timeoutRef = useRef<number | null>(null);

  useEffect(() => {
    const handleToast = (event: Event) => {
      const { message, durationMs } = (event as AuthToastEvent).detail ?? {};
      if (!message) {
        return;
      }

      setToast({ id: Date.now(), message });

      if (timeoutRef.current !== null) {
        window.clearTimeout(timeoutRef.current);
      }

      timeoutRef.current = window.setTimeout(() => {
        setToast(null);
      }, durationMs ?? 2400);
    };

    window.addEventListener(AUTH_TOAST_EVENT, handleToast);

    return () => {
      window.removeEventListener(AUTH_TOAST_EVENT, handleToast);
      if (timeoutRef.current !== null) {
        window.clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  if (!toast) {
    return null;
  }

  return (
    <div className="pointer-events-none fixed inset-x-0 top-4 z-[70] flex justify-center px-4">
      <div
        role="status"
        aria-live="polite"
        className="pointer-events-auto flex w-full max-w-md items-center gap-2 rounded-xl border border-success/25 bg-success-subtle px-4 py-3 text-sm font-medium text-success-foreground shadow-lg shadow-black/10"
      >
        <CheckCircle2 className="h-4 w-4 shrink-0" aria-hidden="true" />
        <span>{toast.message}</span>
      </div>
    </div>
  );
}
