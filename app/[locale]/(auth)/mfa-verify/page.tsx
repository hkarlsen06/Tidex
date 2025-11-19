"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { FormEvent, useState, use, useEffect } from "react";
import { useTranslations } from "@/lib/i18n/client";

import { supabase } from "@/lib/supabase/browser";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSeparator,
  InputOTPSlot,
} from "@/components/app/InputOTP";
import {
  Field,
  FieldLabel,
  FieldError,
} from "@/components/app/Field";
import { Button } from "@/components/app/Button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import type { Factor } from "@supabase/supabase-js";

type MessageState = { type: "error" | "success"; text: string } | null;

export default function MfaVerifyPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const searchParams = useSearchParams();
  const nextPath = searchParams.get("next") || `/${locale}`;

  const [factors, setFactors] = useState<Factor[]>([]);
  const [selectedFactor, setSelectedFactor] = useState<Factor | null>(null);
  const [code, setCode] = useState("");
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Load user's MFA factors on mount
  useEffect(() => {
    const loadFactors = async () => {
      try {
        // First check if user has a session
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();

        if (sessionError || !sessionData.session) {
          console.error("[MFA Verify] No session found:", sessionError);
          setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.noSession });
          setIsLoading(false);
          return;
        }

        const { data, error } = await supabase.auth.mfa.listFactors();

        if (error) {
          console.error("[MFA Verify] Failed to list factors:", error);
          setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.genericError });
          setIsLoading(false);
          return;
        }

        // Get verified TOTP factors only
        const verifiedFactors = (data.totp || []).filter(f => f.status === "verified");

        if (verifiedFactors.length === 0) {
          setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.noFactors });
          setIsLoading(false);
          return;
        }

        setFactors(verifiedFactors);

        // Auto-select if only one factor
        if (verifiedFactors.length === 1) {
          const factor = verifiedFactors[0];
          setSelectedFactor(factor);
          await createChallenge(factor);
        }

        setIsLoading(false);
      } catch (err) {
        console.error("[MFA Verify] Unexpected error:", err);
        setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.genericError });
        setIsLoading(false);
      }
    };

    loadFactors();
  }, [t]);

  const createChallenge = async (factor: Factor) => {
    try {
      const { data, error } = await supabase.auth.mfa.challenge({
        factorId: factor.id,
      });

      if (error) {
        setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.challengeFailed });
        return false;
      }

      setChallengeId(data.id);
      return true;
    } catch {
      setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.challengeFailed });
      return false;
    }
  };

  const handleSelectFactor = async (factor: Factor) => {
    setSelectedFactor(factor);
    setCode("");
    setFieldError(null);
    setMessage(null);
    setChallengeId(null);
    await createChallenge(factor);
  };

  const handleVerify = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFieldError(null);
    setMessage(null);

    if (code.length !== 6) {
      setFieldError(t.pages.auth.mfaVerify.errors.fillAllDigits);
      return;
    }

    if (!challengeId) {
      setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.challengeFailed });
      return;
    }

    setIsSubmitting(true);

    try {
      const { error } = await supabase.auth.mfa.verify({
        factorId: selectedFactor!.id,
        challengeId,
        code,
      });

      if (error) {
        setIsSubmitting(false);
        setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.invalidCode });
        return;
      }

      setMessage({ type: "success", text: t.pages.auth.mfaVerify.success.verified });

      // Redirect to intended destination
      setTimeout(() => {
        window.location.href = nextPath;
      }, 1000);
    } catch {
      setIsSubmitting(false);
      setMessage({ type: "error", text: t.pages.auth.mfaVerify.errors.verificationFailed });
    }
  };

  const getFactorLabel = (factor: Factor) => {
    return factor.friendly_name || t.pages.auth.mfaVerify.factorTypes.totp;
  };

  if (isLoading) {
    return (
      <div className="relative flex min-h-screen items-center justify-center py-16">
        <Card className="w-full max-w-md shadow-lg">
          <CardContent className="pt-6">
            <div className="flex flex-col items-center gap-4">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-border border-t-primary"></div>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.mfaVerify.title}</CardTitle>
          <CardDescription>
            {selectedFactor
              ? t.pages.auth.mfaVerify.description
              : t.pages.auth.mfaVerify.selectFactor}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Factor Selection */}
          {!selectedFactor && factors.length > 1 && (
            <div className="space-y-3">
              {factors.map((factor) => (
                <Button
                  key={factor.id}
                  variant="outline"
                  size="lg"
                  className="w-full justify-start"
                  onClick={() => handleSelectFactor(factor)}
                >
                  {getFactorLabel(factor)}
                </Button>
              ))}
            </div>
          )}

          {/* Code Entry */}
          {selectedFactor && challengeId && (
            <form className="space-y-6" noValidate onSubmit={handleVerify}>
              <Field data-invalid={!!fieldError} className="items-center">
                <FieldLabel htmlFor="code" className="sr-only">
                  {t.pages.auth.mfaVerify.codeLabel}
                </FieldLabel>
                <InputOTP
                  maxLength={6}
                  value={code}
                  onChange={(value) => {
                    setFieldError(null);
                    setMessage(null);
                    setCode(value);
                  }}
                >
                  <InputOTPGroup>
                    <InputOTPSlot index={0} />
                    <InputOTPSlot index={1} />
                    <InputOTPSlot index={2} />
                  </InputOTPGroup>
                  <InputOTPSeparator />
                  <InputOTPGroup>
                    <InputOTPSlot index={3} />
                    <InputOTPSlot index={4} />
                    <InputOTPSlot index={5} />
                  </InputOTPGroup>
                </InputOTP>
                {fieldError && (
                  <FieldError className="text-center">{fieldError}</FieldError>
                )}
              </Field>

              <Button
                type="submit"
                disabled={isSubmitting}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                {t.pages.auth.mfaVerify.verifyButton}
              </Button>

              {/* Back button for factor selection */}
              {factors.length > 1 && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setSelectedFactor(null);
                    setCode("");
                    setChallengeId(null);
                    setFieldError(null);
                    setMessage(null);
                  }}
                  className="w-full"
                >
                  {t.pages.auth.mfaVerify.selectFactor}
                </Button>
              )}
            </form>
          )}

          {/* Message Display */}
          {message && (
            <div
              className={`mt-4 rounded-md px-4 py-3 text-sm font-medium ${
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

          {/* Back to login link */}
          <div className="mt-6 text-center">
            <Button
              asChild
              variant="link"
              size="sm"
            >
              <Link href={`/${locale}/login`}>
                {t.pages.auth.mfaVerify.backToLogin}
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
