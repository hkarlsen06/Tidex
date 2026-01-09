"use client";

import { Turnstile, type TurnstileInstance } from "@marsidev/react-turnstile";
import { useRef, useImperativeHandle, forwardRef } from "react";
import { ENV } from "@/lib/env";

/**
 * Cloudflare Turnstile test sitekeys for development
 * @see https://developers.cloudflare.com/turnstile/troubleshooting/testing/
 */
const TURNSTILE_TEST_SITEKEYS = {
  /** Always passes - visible widget */
  ALWAYS_PASS: "1x00000000000000000000AA",
  /** Always fails - visible widget */
  ALWAYS_FAIL: "2x00000000000000000000AB",
  /** Always passes - invisible widget */
  INVISIBLE_PASS: "1x00000000000000000000BB",
  /** Always fails - invisible widget */
  INVISIBLE_FAIL: "2x00000000000000000000BB",
  /** Forces interactive challenge - visible widget */
  FORCE_INTERACTIVE: "3x00000000000000000000FF",
} as const;

/**
 * Get the appropriate Turnstile sitekey based on environment
 * In development, uses a test sitekey that always passes
 */
function getTurnstileSiteKey(): string {
  const isDev = process.env.NODE_ENV === "development";

  if (isDev) {
    return TURNSTILE_TEST_SITEKEYS.ALWAYS_PASS;
  }

  return ENV.TURNSTILE_SITE_KEY!;
}

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
  /**
   * Language for the widget UI
   * - 'auto' (default): Auto-detect from browser
   * - Or any supported language code: 'en', 'no', 'de', 'fr', etc.
   * @see https://developers.cloudflare.com/turnstile/reference/supported-languages/
   */
  language?: string;
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
    size = 'flexible',
    language = 'auto'
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
        siteKey={getTurnstileSiteKey()}
        onSuccess={onSuccess}
        onError={onError}
        onExpire={onExpire}
        options={{
          theme: "auto", // Auto-detect light/dark mode from system
          size,
          execution,
          appearance,
          retry: "auto", // Auto-retry on failure
          language,
        }}
        className={className}
      />
    );
  }
);

TurnstileCaptcha.displayName = "TurnstileCaptcha";
