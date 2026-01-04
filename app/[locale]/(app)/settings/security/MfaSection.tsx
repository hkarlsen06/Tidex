"use client";

import { useState, useEffect, FormEvent } from "react";
import { useTranslations } from "@/lib/i18n/client";
import { supabase } from "@/lib/supabase/browser";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/app/Dialog";
import { Smartphone, Trash2, Plus, Loader2, AlertTriangle } from "lucide-react";
import { useImpersonation } from "@/components/providers/ImpersonationProvider";
import type { Factor } from "@supabase/supabase-js";

type MessageState = { type: "error" | "success"; text: string } | null;

type EnrollmentState = {
  step: "idle" | "qr" | "verify";
  factorId: string | null;
  qrCode: string | null;
  secret: string | null;
  uri: string | null;
};

export function MfaSection() {
  const { t } = useTranslations();
  const { isImpersonating } = useImpersonation();

  const [factors, setFactors] = useState<Factor[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [message, setMessage] = useState<MessageState>(null);

  // Enrollment state
  const [enrollment, setEnrollment] = useState<EnrollmentState>({
    step: "idle",
    factorId: null,
    qrCode: null,
    secret: null,
    uri: null,
  });
  const [verifyCode, setVerifyCode] = useState("");
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [isEnrolling, setIsEnrolling] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);

  // Unenrollment state
  const [unenrollDialog, setUnenrollDialog] = useState<{
    open: boolean;
    factor: Factor | null;
  }>({ open: false, factor: null });
  const [isUnenrolling, setIsUnenrolling] = useState(false);

  const loadFactors = async () => {
    try {
      const { data, error } = await supabase.auth.mfa.listFactors();

      if (error) {
        setMessage({ type: "error", text: t.pages.settings.security.errors.loadFailed });
        setIsLoading(false);
        return;
      }

      // Get verified TOTP factors only
      const verifiedFactors = (data.totp || []).filter(f => f.status === "verified");
      setFactors(verifiedFactors);
      setIsLoading(false);
    } catch {
      setMessage({ type: "error", text: t.pages.settings.security.errors.genericError });
      setIsLoading(false);
    }
  };

  // Load enrolled factors
  useEffect(() => {
    loadFactors();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleStartEnrollment = async () => {
    // Block MFA enrollment while impersonating
    if (isImpersonating) {
      setMessage({ type: "error", text: "MFA changes are not allowed while impersonating another user" });
      return;
    }

    setIsEnrolling(true);
    setMessage(null);
    setFieldError(null);

    try {
      // Use full timestamp to ensure unique name and avoid conflicts with abandoned enrollments
      const friendlyName = `${t.pages.settings.security.defaultFactorName} ${Date.now()}`;

      const { data, error } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName,
      });

      if (error) {
        setMessage({ type: "error", text: t.pages.settings.security.errors.enrollFailed });
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
      setMessage({ type: "error", text: t.pages.settings.security.errors.enrollFailed });
      setIsEnrolling(false);
    }
  };

  const handleVerifyEnrollment = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFieldError(null);
    setMessage(null);

    if (verifyCode.length !== 6) {
      setFieldError(t.pages.settings.security.errors.fillAllDigits);
      return;
    }

    if (!enrollment.factorId) {
      setMessage({ type: "error", text: t.pages.settings.security.errors.genericError });
      return;
    }

    setIsVerifying(true);

    try {
      // First create a challenge
      const { data: challengeData, error: challengeError } = await supabase.auth.mfa.challenge({
        factorId: enrollment.factorId,
      });

      if (challengeError) {
        setMessage({ type: "error", text: t.pages.settings.security.errors.verifyFailed });
        setIsVerifying(false);
        return;
      }

      // Then verify with the code
      const { error: verifyError } = await supabase.auth.mfa.verify({
        factorId: enrollment.factorId,
        challengeId: challengeData.id,
        code: verifyCode,
      });

      if (verifyError) {
        setMessage({ type: "error", text: t.pages.settings.security.errors.invalidCode });
        setIsVerifying(false);
        return;
      }

      // Success - reload factors and reset state
      setMessage({ type: "success", text: t.pages.settings.security.success.enrolled });
      setEnrollment({ step: "idle", factorId: null, qrCode: null, secret: null, uri: null });
      setVerifyCode("");
      await loadFactors();
      setIsVerifying(false);
    } catch {
      setMessage({ type: "error", text: t.pages.settings.security.errors.verifyFailed });
      setIsVerifying(false);
    }
  };

  const handleCancelEnrollment = async () => {
    // If we have an unverified factor, unenroll it
    if (enrollment.factorId) {
      try {
        await supabase.auth.mfa.unenroll({ factorId: enrollment.factorId });
      } catch {
        // Ignore errors when canceling
      }
    }

    setEnrollment({ step: "idle", factorId: null, qrCode: null, secret: null, uri: null });
    setVerifyCode("");
    setFieldError(null);
    setMessage(null);
  };

  const handleUnenroll = async () => {
    if (!unenrollDialog.factor) return;

    // Block MFA unenrollment while impersonating
    if (isImpersonating) {
      setMessage({ type: "error", text: "MFA changes are not allowed while impersonating another user" });
      setUnenrollDialog({ open: false, factor: null });
      return;
    }

    setIsUnenrolling(true);

    try {
      const { error } = await supabase.auth.mfa.unenroll({
        factorId: unenrollDialog.factor.id,
      });

      if (error) {
        setMessage({ type: "error", text: t.pages.settings.security.errors.unenrollFailed });
        setIsUnenrolling(false);
        return;
      }

      setMessage({ type: "success", text: t.pages.settings.security.success.unenrolled });
      setUnenrollDialog({ open: false, factor: null });
      await loadFactors();
      setIsUnenrolling(false);
    } catch {
      setMessage({ type: "error", text: t.pages.settings.security.errors.unenrollFailed });
      setIsUnenrolling(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-6 w-6 animate-spin text-text-secondary" />
      </div>
    );
  }

  return (
    <>
      {/* Message display */}
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

      {/* Enrolled factors */}
      <Card>
        <CardHeader>
          <CardTitle>{t.pages.settings.security.factorsTitle}</CardTitle>
          <CardDescription>
            {t.pages.settings.security.factorsDescription}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {factors.length === 0 ? (
            <p className="text-text-secondary text-sm">
              {t.pages.settings.security.noFactors}
            </p>
          ) : (
            <div className="space-y-3">
              {factors.map((factor) => (
                <div
                  key={factor.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-surface-secondary"
                >
                  <div className="flex items-center gap-3">
                    <Smartphone className="h-5 w-5 text-text-secondary" />
                    <div>
                      <p className="font-medium text-sm">
                        {factor.friendly_name || t.pages.settings.security.authenticatorApp}
                      </p>
                      <p className="text-xs text-text-muted">
                        {t.pages.settings.security.addedOn.replace(
                          "{date}",
                          new Date(factor.created_at).toLocaleDateString()
                        )}
                      </p>
                    </div>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setUnenrollDialog({ open: true, factor })}
                    disabled={isImpersonating}
                    title={isImpersonating ? "MFA changes not allowed while impersonating" : undefined}
                  >
                    <Trash2 className="h-4 w-4 text-error-foreground" />
                  </Button>
                </div>
              ))}
            </div>
          )}

          {/* Add new factor button */}
          {enrollment.step === "idle" && (
            <Button
              onClick={handleStartEnrollment}
              disabled={isEnrolling || isImpersonating}
              loading={isEnrolling}
              className="mt-4 w-full"
              variant="outline"
              title={isImpersonating ? "MFA changes not allowed while impersonating" : undefined}
            >
              <Plus className="h-4 w-4 mr-2" />
              {t.pages.settings.security.addFactor}
            </Button>
          )}

          {/* Warning when impersonating */}
          {isImpersonating && (
            <div className="mt-4 flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400">
              <AlertTriangle className="h-4 w-4" />
              <span>MFA changes are disabled while impersonating</span>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Enrollment flow */}
      {enrollment.step === "qr" && (
        <Card>
          <CardHeader>
            <CardTitle>{t.pages.settings.security.enrollTitle}</CardTitle>
            <CardDescription>
              {t.pages.settings.security.enrollDescription}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-6">
              {/* QR Code */}
              <div className="flex flex-col items-center gap-4">
                {enrollment.qrCode && (
                  <div className="p-4 bg-white rounded-lg">
                    {/* Using img tag because Next.js Image doesn't support inline SVG data URIs */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={enrollment.qrCode}
                      alt="QR Code for authenticator app"
                      width={200}
                      height={200}
                    />
                  </div>
                )}

                {/* Open in authenticator app button */}
                {enrollment.uri && (
                  <div className="text-center">
                    <p className="text-sm text-text-secondary mb-2">
                      {t.pages.settings.security.cantScanQr}
                    </p>
                    <a
                      href={enrollment.uri}
                      className="inline-flex items-center justify-center gap-2 rounded-md bg-brand-gradient-start px-4 py-2 text-sm font-medium text-white hover:opacity-90 transition-opacity"
                    >
                      {t.pages.settings.security.openInApp}
                    </a>
                  </div>
                )}

                {/* Manual entry secret */}
                {enrollment.secret && (
                  <div className="text-center">
                    <p className="text-sm text-text-secondary mb-1">
                      {t.pages.settings.security.manualEntry}
                    </p>
                    <code className="text-xs bg-surface-secondary px-2 py-1 rounded font-mono break-all">
                      {enrollment.secret}
                    </code>
                  </div>
                )}
              </div>

              {/* Verification form */}
              <form onSubmit={handleVerifyEnrollment} className="space-y-4">
                <Field data-invalid={!!fieldError} className="items-center">
                  <FieldLabel htmlFor="verify-code" className="text-center mb-2">
                    {t.pages.settings.security.verifyLabel}
                  </FieldLabel>
                  <InputOTP
                    maxLength={6}
                    value={verifyCode}
                    onChange={(value) => {
                      setFieldError(null);
                      setMessage(null);
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

                <div className="flex gap-3">
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleCancelEnrollment}
                    className="flex-1"
                  >
                    {t.pages.settings.security.cancel}
                  </Button>
                  <Button
                    type="submit"
                    disabled={isVerifying}
                    loading={isVerifying}
                    className="flex-1"
                  >
                    {t.pages.settings.security.verify}
                  </Button>
                </div>
              </form>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Unenroll confirmation dialog */}
      <Dialog
        open={unenrollDialog.open}
        onOpenChange={(open) => {
          if (!open) {
            setUnenrollDialog({ open: false, factor: null });
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t.pages.settings.security.unenrollDialog.title}</DialogTitle>
            <DialogDescription>
              {t.pages.settings.security.unenrollDialog.description}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setUnenrollDialog({ open: false, factor: null })}
            >
              {t.pages.settings.security.cancel}
            </Button>
            <Button
              variant="destructive"
              onClick={handleUnenroll}
              disabled={isUnenrolling}
              loading={isUnenrolling}
            >
              {t.pages.settings.security.unenrollDialog.confirm}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
