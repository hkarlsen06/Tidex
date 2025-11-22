"use client";

import { Turnstile, type TurnstileInstance } from "@marsidev/react-turnstile";
import { useRef, useImperativeHandle, forwardRef } from "react";
import { ENV } from "@/lib/env";

interface TurnstileCaptchaProps {
  onSuccess: (token: string) => void;
  onError?: () => void;
  onExpire?: () => void;
  className?: string;
  /**
   * Execution mode determines when verification runs:
   * - 'render' (default): Challenge runs immediately after widget renders
   * - 'execute': Challenge only runs when execute() is called programmatically
   */
  execution?: 'render' | 'execute';
  /**
   * Appearance mode determines when widget is visible:
   * - 'always' (default): Widget visible immediately
   * - 'execute': Widget appears when challenge begins
   * - 'interaction-only': Widget only appears if user interaction needed
   */
  appearance?: 'always' | 'execute' | 'interaction-only';
  /**
   * Size of the widget
   * - 'normal': 300px × 65px
   * - 'flexible': 100% width (min 300px) × 65px
   * - 'compact': 150px × 140px
   */
  size?: 'normal' | 'flexible' | 'compact';
}

export interface TurnstileCaptchaHandle {
  execute: () => void;
  reset: () => void;
}

/**
 * Wrapper component for Cloudflare Turnstile CAPTCHA (Managed Mode)
 * Integrates with Supabase auth to prevent automated abuse
 *
 * Managed mode automatically chooses the appropriate action based on risk level.
 * Most users will see a simple checkbox; suspected bots may face challenges.
 *
 * @param onSuccess - Callback fired when captcha is successfully solved, receives the token
 * @param onError - Optional callback fired when captcha fails
 * @param onExpire - Optional callback fired when token expires (300s lifetime)
 * @param className - Optional CSS classes for styling
 * @param execution - When verification runs: 'render' (immediate) or 'execute' (manual)
 * @param appearance - When widget is visible: 'always', 'execute', or 'interaction-only'
 * @param size - Widget size: 'normal', 'flexible' (responsive), or 'compact'
 */
export const TurnstileCaptcha = forwardRef<TurnstileCaptchaHandle, TurnstileCaptchaProps>(
  ({
    onSuccess,
    onError,
    onExpire,
    className,
    execution = 'render',
    appearance = 'always',
    size = 'flexible'
  }, ref) => {
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
        onExpire={onExpire}
        options={{
          theme: "auto", // Auto-detect light/dark mode from system
          size,
          execution,
          appearance,
          retry: "auto", // Auto-retry on failure
        }}
        className={className}
      />
    );
  }
);

TurnstileCaptcha.displayName = "TurnstileCaptcha";
