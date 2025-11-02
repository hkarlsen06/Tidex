"use client";

import { Turnstile, type TurnstileInstance } from "@marsidev/react-turnstile";
import { useRef, useImperativeHandle, forwardRef } from "react";
import { ENV } from "@/lib/env";

interface TurnstileCaptchaProps {
  onSuccess: (token: string) => void;
  onError?: () => void;
  className?: string;
  /**
   * Use execution mode - widget only renders/validates when execute() is called.
   * Note: For truly invisible widgets, configure the widget as "Invisible" mode
   * in your Cloudflare Turnstile dashboard settings.
   */
  execution?: 'render' | 'execute';
}

export interface TurnstileCaptchaHandle {
  execute: () => void;
  reset: () => void;
}

/**
 * Wrapper component for Cloudflare Turnstile CAPTCHA
 * Integrates with Supabase auth to prevent automated abuse
 *
 * @param onSuccess - Callback fired when captcha is successfully solved, receives the token
 * @param onError - Optional callback fired when captcha fails
 * @param className - Optional CSS classes for styling
 * @param execution - Control when widget validates: 'render' (default) or 'execute' (manual)
 */
export const TurnstileCaptcha = forwardRef<TurnstileCaptchaHandle, TurnstileCaptchaProps>(
  ({ onSuccess, onError, className, execution = 'render' }, ref) => {
    const turnstileRef = useRef<TurnstileInstance>(null);

    useImperativeHandle(ref, () => ({
      execute: () => {
        turnstileRef.current?.execute();
      },
      reset: () => {
        turnstileRef.current?.reset();
      },
    }));

    return (
      <Turnstile
        ref={turnstileRef}
        siteKey={ENV.TURNSTILE_SITE_KEY!}
        onSuccess={onSuccess}
        onError={onError}
        options={{
          theme: "dark",
          size: "flexible",
          execution,
        }}
        className={className}
      />
    );
  }
);

TurnstileCaptcha.displayName = "TurnstileCaptcha";
