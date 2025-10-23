"use client";

import { useSearchParams } from "next/navigation";
import { useState, Suspense } from "react";
import Link from "next/link";

import { supabase } from "@/lib/supabase/browser";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";

type MessageState = { type: "error" | "success"; text: string } | null;

function VerifyEmailContent() {
  const searchParams = useSearchParams();
  const email = searchParams.get("email");

  const [message, setMessage] = useState<MessageState>(null);
  const [isResending, setIsResending] = useState(false);

  const handleResendEmail = async () => {
    if (!email) {
      setMessage({ type: "error", text: "E-postadresse mangler." });
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
        text: "Bekreftelseslenke sendt på nytt! Sjekk e-posten din.",
      });
    } catch (err) {
      setIsResending(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "En feil oppstod",
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
          <CardTitle className="text-2xl">Bekreft e-postadressen din</CardTitle>
          <CardDescription>
            Vi har sendt en bekreftelseslenke til {email ? <strong className="text-text-primary">{email}</strong> : "din e-post"}
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          <div className="rounded-lg bg-surface-primary/50 p-4 text-sm text-text-secondary space-y-2">
            <p className="font-medium text-text-primary">Neste steg:</p>
            <ol className="list-decimal list-inside space-y-1 ml-2">
              <li>Sjekk innboksen din (og spam-mappen)</li>
              <li>Klikk på bekreftelseslenken i e-posten</li>
              <li>Du vil automatisk bli logget inn og sendt til onboarding</li>
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
              Send bekreftelseslenke på nytt
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
              Feil e-postadresse?{" "}
              <Button
                asChild
                variant="link"
                size="sm"
                className="p-0 h-auto font-medium"
              >
                <Link href="/signup">Gå tilbake til registrering</Link>
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export default function VerifyEmailPage() {
  return (
    <Suspense
      fallback={
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
              <CardTitle className="text-2xl">Bekreft e-postadressen din</CardTitle>
              <CardDescription>Laster...</CardDescription>
            </CardHeader>
          </Card>
        </div>
      }
    >
      <VerifyEmailContent />
    </Suspense>
  );
}
