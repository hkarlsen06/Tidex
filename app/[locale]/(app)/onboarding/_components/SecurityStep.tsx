"use client";

import { useState, FormEvent } from "react";
import { Button } from "@/components/app/Button";
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
import { Shield, ChevronRight } from "lucide-react";
import { useTranslations } from "@/lib/i18n/client";

interface SecurityStepProps {
  onNext: () => void;
  onBack: () => void;
}

type EnrollmentState = {
  step: "prompt" | "qr" | "verify";
  factorId: string | null;
  qrCode: string | null;
  secret: string | null;
  uri: string | null;
};

export function SecurityStep({ onNext, onBack }: SecurityStepProps) {
  const { t } = useTranslations();

  const [enrollment, setEnrollment] = useState<EnrollmentState>({
    step: "prompt",
    factorId: null,
    qrCode: null,
    secret: null,
    uri: null,
  });
  const [verifyCode, setVerifyCode] = useState("");
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [isEnrolling, setIsEnrolling] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleStartEnrollment = async () => {
    setIsEnrolling(true);
    setError(null);

    try {
      const friendlyName = `${t.onboarding.securityStep.factorName} ${Date.now()}`;

      const { data, error } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName,
      });

      if (error) {
        setError(t.onboarding.securityStep.enrollFailed);
        setIsEnrolling(false);
        return;
      }

      setEnrollment({
        step: "qr",
        factorId: data.id,
        qrCode: data.totp.qr_code,
        secret: data.totp.secret,
        uri: data.totp.uri,
      });
      setIsEnrolling(false);
    } catch {
      setError(t.onboarding.securityStep.enrollFailed);
      setIsEnrolling(false);
    }
  };

  const handleVerify = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFieldError(null);
    setError(null);

    if (verifyCode.length !== 6) {
      setFieldError(t.onboarding.securityStep.fillAllDigits);
      return;
    }

    if (!enrollment.factorId) {
      setError(t.onboarding.securityStep.genericError);
      return;
    }

    setIsVerifying(true);

    try {
      const { data: challengeData, error: challengeError } =
        await supabase.auth.mfa.challenge({
          factorId: enrollment.factorId,
        });

      if (challengeError) {
        setError(t.onboarding.securityStep.verifyFailed);
        setIsVerifying(false);
        return;
      }

      const { error: verifyError } = await supabase.auth.mfa.verify({
        factorId: enrollment.factorId,
        challengeId: challengeData.id,
        code: verifyCode,
      });

      if (verifyError) {
        setError(t.onboarding.securityStep.invalidCode);
        setIsVerifying(false);
        return;
      }

      // Success - continue to next step
      onNext();
    } catch {
      setError(t.onboarding.securityStep.verifyFailed);
      setIsVerifying(false);
    }
  };

  const handleCancel = async () => {
    if (enrollment.factorId) {
      try {
        await supabase.auth.mfa.unenroll({ factorId: enrollment.factorId });
      } catch {
        // Ignore errors
      }
    }
    setEnrollment({
      step: "prompt",
      factorId: null,
      qrCode: null,
      secret: null,
      uri: null,
    });
    setVerifyCode("");
    setFieldError(null);
    setError(null);
  };

  // Initial prompt view
  if (enrollment.step === "prompt") {
    return (
      <div className="space-y-6">
        <div className="space-y-2">
          <h2 className="text-2xl font-bold">{t.onboarding.securityStep.title}</h2>
          <p className="text-text-secondary">{t.onboarding.securityStep.description}</p>
        </div>

        <div className="rounded-xl border border-border bg-surface-secondary/50 p-6 space-y-4">
          <div className="flex items-start gap-4">
            <div className="p-3 rounded-lg bg-surface-secondary">
              <Shield className="h-6 w-6 text-text-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-text-primary">
                {t.onboarding.securityStep.mfaTitle}
              </h3>
              <p className="text-sm text-text-secondary mt-1">
                {t.onboarding.securityStep.mfaDescription}
              </p>
            </div>
          </div>

          {error && (
            <p className="text-sm text-error-foreground">{error}</p>
          )}

          <Button
            onClick={handleStartEnrollment}
            disabled={isEnrolling}
            loading={isEnrolling}
            className="w-full"
          >
            {t.onboarding.securityStep.enableMfa}
          </Button>
        </div>

        <div className="flex gap-3">
          <Button onClick={onBack} variant="outline" className="flex-1">
            {t.common.back}
          </Button>
          <Button onClick={onNext} variant="ghost" className="flex-1">
            {t.onboarding.securityStep.skipForNow}
            <ChevronRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      </div>
    );
  }

  // QR code and verification view
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">{t.onboarding.securityStep.setupTitle}</h2>
        <p className="text-text-secondary">{t.onboarding.securityStep.setupDescription}</p>
      </div>

      <div className="flex flex-col items-center gap-4">
        {enrollment.qrCode && (
          <div className="p-4 bg-white rounded-lg">
            <img
              src={enrollment.qrCode}
              alt="QR Code for authenticator app"
              width={180}
              height={180}
            />
          </div>
        )}

        {enrollment.uri && (
          <div className="text-center">
            <p className="text-sm text-text-secondary mb-2">
              {t.onboarding.securityStep.cantScan}
            </p>
            <a
              href={enrollment.uri}
              className="inline-flex items-center justify-center gap-2 rounded-md bg-brand-gradient-start px-4 py-2 text-sm font-medium text-white hover:opacity-90 transition-opacity"
            >
              {t.onboarding.securityStep.addAutomatically}
            </a>
          </div>
        )}

        {enrollment.secret && (
          <div className="text-center">
            <p className="text-sm text-text-secondary mb-1">
              {t.onboarding.securityStep.manualEntry}
            </p>
            <code className="text-xs bg-surface-secondary px-2 py-1 rounded font-mono break-all">
              {enrollment.secret}
            </code>
          </div>
        )}
      </div>

      <form onSubmit={handleVerify} className="space-y-4">
        <Field data-invalid={!!fieldError} className="items-center">
          <FieldLabel htmlFor="verify-code" className="text-center mb-2">
            {t.onboarding.securityStep.enterCode}
          </FieldLabel>
          <InputOTP
            maxLength={6}
            value={verifyCode}
            onChange={(value) => {
              setFieldError(null);
              setError(null);
              setVerifyCode(value);
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

        {error && (
          <p className="text-sm text-error-foreground text-center">{error}</p>
        )}

        <div className="flex gap-3">
          <Button type="button" onClick={handleCancel} variant="outline" className="flex-1">
            {t.common.cancel}
          </Button>
          <Button type="submit" disabled={isVerifying} loading={isVerifying} className="flex-1">
            {t.onboarding.securityStep.verify}
          </Button>
        </div>
      </form>
    </div>
  );
}
