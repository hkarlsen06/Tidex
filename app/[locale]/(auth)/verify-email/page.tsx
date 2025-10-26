"use client";

import { useSearchParams } from "next/navigation";
import { useState, Suspense, use } from "react";
import Link from "next/link";
import { useTranslations } from "@/lib/i18n/client";

import { supabase } from "@/lib/supabase/browser";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";

type MessageState = { type: "error" | "success"; text: string } | null;

function VerifyEmailContent({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const searchParams = useSearchParams();
  const email = searchParams.get("email");

  const [message, setMessage] = useState<MessageState>(null);
  const [isResending, setIsResending] = useState(false);

  const handleResendEmail = async () => {
    if (!email) {
      setMessage({ type: "error", text: t.pages.auth.verifyEmail.errors.emailMissing });
      return;
    }

    setIsResending(true);
    setMessage(null);

    try {
      const { error } = await supabase.auth.resend({
        type: "signup",
        email,
        options: {
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/onboarding`,
        },
      });

      setIsResending(false);

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
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : t.pages.auth.verifyEmail.errors.genericError,
      });
    }
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-brand-primary/10">
            <svg
              className="h-8 w-8 text-brand-primary"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
              />
            </svg>
          </div>
          <CardTitle className="text-2xl">{t.pages.auth.verifyEmail.title}</CardTitle>
          <CardDescription>
            {email ? t.pages.auth.verifyEmail.description.replace('{email}', email) : t.pages.auth.verifyEmail.descriptionNoEmail}
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          <div className="rounded-lg bg-surface-primary/50 p-4 text-sm text-text-secondary space-y-2">
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
              disabled={isResending || !email}
              loading={isResending}
              variant="outline"
              size="lg"
              className="w-full"
            >
              {t.pages.auth.verifyEmail.resendButton}
            </Button>

            {message && (
              <div
                className={`rounded-md px-4 py-3 text-sm font-medium ${
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

          <div className="pt-4 border-t border-border">
            <div className="text-center text-sm text-text-secondary">
              {t.pages.auth.verifyEmail.wrongEmail}{" "}
              <Button
                asChild
                variant="link"
                size="sm"
                className="p-0 h-auto font-medium"
              >
                <Link href={`/${locale}/signup`}>{t.pages.auth.verifyEmail.backToSignup}</Link>
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export default function VerifyEmailPage({ params }: { params: Promise<{ locale: string }> }) {
  return (
    <Suspense
      fallback={<VerifyEmailSkeleton params={params} />}
    >
      <VerifyEmailContent params={params} />
    </Suspense>
  );
}

function VerifyEmailSkeleton({ params }: { params: Promise<{ locale: string }> }) {
  const { locale: _locale } = use(params);
  const { t } = useTranslations();

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-brand-primary/10">
            <svg
              className="h-8 w-8 text-brand-primary animate-pulse"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
              />
            </svg>
          </div>
          <CardTitle className="text-2xl">{t.pages.auth.verifyEmail.title}</CardTitle>
          <CardDescription>{t.pages.auth.verifyEmail.loading}</CardDescription>
        </CardHeader>
      </Card>
    </div>
  );
}
