"use client";

import { Turnstile, type TurnstileInstance } from "@marsidev/react-turnstile";
import { useRef } from "react";
import { ENV } from "@/lib/env";

interface TurnstileCaptchaProps {
  onSuccess: (token: string) => void;
  onError?: () => void;
  className?: string;
}

/**
 * Wrapper component for Cloudflare Turnstile CAPTCHA
 * Integrates with Supabase auth to prevent automated abuse
 *
 * @param onSuccess - Callback fired when captcha is successfully solved, receives the token
 * @param onError - Optional callback fired when captcha fails
 * @param className - Optional CSS classes for styling
 */
export function TurnstileCaptcha({ onSuccess, onError, className }: TurnstileCaptchaProps) {
  const turnstileRef = useRef<TurnstileInstance>(null);

  return (
    <Turnstile
      ref={turnstileRef}
      siteKey={ENV.TURNSTILE_SITE_KEY!}
      onSuccess={onSuccess}
      onError={onError}
      options={{
        theme: "dark",
        size: "flexible",
      }}
      className={className}
    />
  );
}
