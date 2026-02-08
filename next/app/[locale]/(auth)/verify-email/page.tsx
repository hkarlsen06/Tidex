"use client";

import { useSearchParams } from "next/navigation";
import { useState, Suspense, use, useRef, useEffect } from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "motion/react";
import { Mail } from "lucide-react";
import { useTranslations } from "@/lib/i18n/client";
import { turnstileLanguages, type Locale } from "@/lib/i18n/config";

import { supabase } from "@/lib/supabase/browser";

// Animation variants for entrance animation
const cardVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

// Reduced motion variant (no y-transform)
const reducedMotionVariants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
};
import { Button } from "@/components/app/Button";
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from "@/components/app/TurnstileCaptcha";
import { LocaleSwitcher } from "@/components/app/LocaleSwitcher";
import { AuthHeader } from "@/components/app/AuthHeader";

type MessageState = { type: "error" | "success"; text: string } | null;

function VerifyEmailContent({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const searchParams = useSearchParams();
  const email = searchParams.get("email");
  const shouldReduceMotion = useReducedMotion();

  const [message, setMessage] = useState<MessageState>(null);
  const [isResending, setIsResending] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [isCaptchaValidating, setIsCaptchaValidating] = useState(false);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);

  // When captcha token is received, perform the resend
  useEffect(() => {
    if (captchaToken) {
      performResend(captchaToken);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [captchaToken]);

  const performResend = async (token: string) => {
    try {
      const { error } = await supabase.auth.resend({
        type: "signup",
        email: email!,
        options: {
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/onboarding`,
          captchaToken: token,
        },
      });

      setIsResending(false);
      setIsCaptchaValidating(false);
      setCaptchaToken(null);
      turnstileRef.current?.reset();

      if (error) {
        setMessage({ type: "error", text: error.message });
        return;
      }

      setMessage({
        type: "success",
        text: t.pages.auth.verifyEmail.success.resent,
      });
    } catch (err) {
      setIsResending(false);
      setIsCaptchaValidating(false);
      setCaptchaToken(null);
      turnstileRef.current?.reset();
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : t.pages.auth.verifyEmail.errors.genericError,
      });
    }
  };

  const handleResendEmail = () => {
    if (!email) {
      setMessage({ type: "error", text: t.pages.auth.verifyEmail.errors.emailMissing });
      return;
    }

    setIsResending(true);
    setMessage(null);
    setIsCaptchaValidating(true);
    turnstileRef.current?.execute();
  };

  return (
    <motion.div
      className="relative w-full max-w-md mx-auto"
      variants={shouldReduceMotion ? reducedMotionVariants : cardVariants}
      initial="hidden"
      animate="visible"
    >
      {/* Header: Envelope icon in blue circle */}
      <AuthHeader
        variant="icon"
        icon={<Mail className="h-9 w-9 text-brand-gradient-start" />}
        title={t.pages.auth.verifyEmail.title}
        subtitle={email ? t.pages.auth.verifyEmail.description.replace('{email}', email) : t.pages.auth.verifyEmail.descriptionNoEmail}
      />

      {/* Main content */}
      <div className="space-y-6">
        <div className="rounded-xl bg-surface-primary p-4 text-sm text-text-secondary space-y-2">
          <p className="font-medium text-text-primary">{t.pages.auth.verifyEmail.nextStepsTitle}</p>
          <ol className="list-decimal list-inside space-y-1 ml-2">
            <li>{t.pages.auth.verifyEmail.step1}</li>
            <li>{t.pages.auth.verifyEmail.step2}</li>
            <li>{t.pages.auth.verifyEmail.step3}</li>
          </ol>
        </div>

        <div className="space-y-3">
          <Button
            onClick={handleResendEmail}
            disabled={isResending || !email || isCaptchaValidating}
            loading={isResending || isCaptchaValidating}
            size="lg"
            className="w-full h-12 bg-brand-gradient-start text-white hover:bg-brand-gradient-start/90"
          >
            {t.pages.auth.verifyEmail.resendButton}
          </Button>

          <TurnstileCaptcha
            ref={turnstileRef}
            onSuccess={setCaptchaToken}
            onError={() => {
              setIsResending(false);
              setIsCaptchaValidating(false);
              setMessage({ type: "error", text: t.pages.auth.verifyEmail.errors.captchaFailed });
            }}
            execution="execute"
            language={turnstileLanguages[locale as Locale]}
            className="hidden"
          />

          {message && (
            <div
              className={`rounded-lg px-4 py-3 text-sm font-medium ${
                message.type === "error"
                  ? "bg-error-subtle text-error-foreground"
                  : "bg-success-subtle text-success-foreground"
              }`}
              role="status"
              aria-live="polite"
            >
              {message.text}
            </div>
          )}
        </div>
      </div>

      {/* Footer */}
      <div className="mt-10 text-center">
        <p className="text-sm text-text-secondary">
          {t.pages.auth.verifyEmail.wrongEmail}{" "}
          <Link
            href={`/${locale}/signup`}
            className="font-semibold text-brand-gradient-start hover:underline"
          >
            {t.pages.auth.verifyEmail.backToSignup}
          </Link>
        </p>
      </div>

      <div className="mt-6 flex justify-center">
        <LocaleSwitcher />
      </div>
    </motion.div>
  );
}

export default function VerifyEmailPage({ params }: { params: Promise<{ locale: string }> }) {
  return (
    <Suspense
      fallback={<VerifyEmailSkeleton />}
    >
      <VerifyEmailContent params={params} />
    </Suspense>
  );
}

function VerifyEmailSkeleton() {
  return (
    <div className="relative w-full max-w-md mx-auto">
      <div className="flex flex-col items-center gap-4 mb-10">
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-brand-gradient-start/10">
          <Mail className="h-9 w-9 text-brand-gradient-start animate-pulse" />
        </div>
        <div className="h-7 w-48 rounded bg-surface-primary/50 animate-pulse" />
        <div className="h-4 w-64 rounded bg-surface-primary/50 animate-pulse" />
      </div>
      <div className="space-y-6">
        <div className="rounded-xl bg-surface-primary/50 h-32 animate-pulse" />
        <div className="h-12 rounded-xl bg-surface-primary/50 animate-pulse" />
      </div>
    </div>
  );
}
