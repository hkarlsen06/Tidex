"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState, use, useRef, useEffect } from "react";
import { useTranslations } from "@/lib/i18n/client";

import {
  InputOTP,
  InputOTPGroup,
  InputOTPSeparator,
  InputOTPSlot,
} from "@/components/app/InputOTP";
import { supabase } from "@/lib/supabase/browser";
import {
  detectInputType,
  normalizePhoneToE164,
  isValidNorwegianPhone,
  isValidEmail,
} from "@/lib/validation/phone";
import { translateError } from "@/lib/errors/translate";
import {
  Field,
  FieldLabel,
  FieldError,
  FieldGroup,
} from "@/components/app/Field";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from "@/components/app/TurnstileCaptcha";

type MessageState = { type: "error" | "success"; text: string } | null;
type Step = "input" | "otp" | "password";
type FieldErrors = {
  emailOrPhone?: string;
  otp?: string;
  password?: string;
  confirmPassword?: string;
};

export default function ResetPasswordPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const router = useRouter();

  const [step, setStep] = useState<Step>("input");
  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [resetType, setResetType] = useState<"email" | "phone" | null>(null);
  const [otp, setOtp] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);

  const resetMessage = () => setMessage(null);
  const resetFieldErrors = () => setFieldErrors({});
  const resetAll = () => {
    resetMessage();
    resetFieldErrors();
    setCaptchaToken(null);
  };

  // Reset Turnstile widget on mount to prevent stale token issues
  useEffect(() => {
    turnstileRef.current?.reset();
  }, []);

  // Step 1: Send OTP to email or phone
  const handleSendOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

    if (!emailOrPhone) {
      errors.emailOrPhone = t.pages.auth.resetPassword.errors.fillEmailOrPhone;
    }

    // Show field errors if any
    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    // Require captcha token before submission
    if (!captchaToken) {
      setMessage({ type: "error", text: t.pages.auth.resetPassword.errors.completeCaptcha });
      return;
    }

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === "unknown") {
      errors.emailOrPhone = t.pages.auth.resetPassword.errors.invalidEmailOrPhone;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    try {
      if (inputType === "email") {
        if (!isValidEmail(emailOrPhone)) {
          setFieldErrors({ emailOrPhone: t.pages.auth.resetPassword.errors.invalidEmail });
          setIsSubmitting(false);
          return;
        }

        const { error } = await supabase.auth.resetPasswordForEmail(
          emailOrPhone,
          {
            redirectTo: undefined,
            captchaToken,
          }
        );

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: translateError(error.message) });
          return;
        }

        setResetType("email");
        setMessage({
          type: "success",
          text: t.pages.auth.resetPassword.success.emailCodeSent,
        });
      } else {
        // Phone reset
        if (!isValidNorwegianPhone(emailOrPhone)) {
          setFieldErrors({ emailOrPhone: t.pages.auth.resetPassword.errors.invalidPhone });
          setIsSubmitting(false);
          return;
        }

        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.signInWithOtp({
          phone: phoneE164,
          options: {
            captchaToken,
          },
        });

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: translateError(error.message) });
          return;
        }

        setResetType("phone");
        setMessage({
          type: "success",
          text: t.pages.auth.resetPassword.success.smsCodeSent,
        });
      }

      setStep("otp");
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : t.pages.auth.resetPassword.errors.genericError,
      });
    }
  };

  // Step 2: Verify OTP
  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = t.pages.auth.resetPassword.errors.fillAllDigits;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    try {
      if (resetType === "email") {
        const { error } = await supabase.auth.verifyOtp({
          email: emailOrPhone,
          token: otp,
          type: "recovery",
        });

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: translateError(error.message) });
          return;
        }
      } else {
        // Phone verification
        if (!isValidNorwegianPhone(emailOrPhone)) {
          setMessage({ type: "error", text: t.pages.auth.resetPassword.errors.invalidPhoneNumber });
          setIsSubmitting(false);
          return;
        }

        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.verifyOtp({
          phone: phoneE164,
          token: otp,
          type: "sms",
        });

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: translateError(error.message) });
          return;
        }
      }

      setMessage({ type: "success", text: t.pages.auth.resetPassword.success.codeVerified });
      setStep("password");
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : t.pages.auth.resetPassword.errors.genericError,
      });
    }
  };

  // Step 3: Update password
  const handleUpdatePassword = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (!password) {
      errors.password = t.pages.auth.resetPassword.errors.fillPassword;
    }

    if (!confirmPassword) {
      errors.confirmPassword = t.pages.auth.resetPassword.errors.fillConfirmPassword;
    }

    if (password && confirmPassword && password !== confirmPassword) {
      errors.confirmPassword = t.pages.auth.resetPassword.errors.passwordMismatch;
    }

    if (password && password.length < 6) {
      errors.password = t.pages.auth.resetPassword.errors.passwordTooShort;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    const { error } = await supabase.auth.updateUser({
      password: password,
    });

    setIsSubmitting(false);

    if (error) {
      setMessage({ type: "error", text: translateError(error.message) });
      return;
    }

    setMessage({
      type: "success",
      text: t.pages.auth.resetPassword.success.passwordUpdated,
    });

    // Auto-login and redirect
    setTimeout(() => {
      router.replace(`/${locale}`);
      router.refresh();
    }, 1500);
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.resetPassword.title}</CardTitle>
          <CardDescription>
            {step === "input" && t.pages.auth.resetPassword.descriptionInput}
            {step === "otp" && t.pages.auth.resetPassword.descriptionOtp}
            {step === "password" && t.pages.auth.resetPassword.descriptionPassword}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Step 1: Email or Phone Input */}
          {step === "input" && (
            <form className="space-y-6" noValidate onSubmit={handleSendOtp}>
              <Field data-invalid={!!fieldErrors.emailOrPhone}>
                <FieldLabel htmlFor="emailOrPhone">{t.pages.auth.resetPassword.emailOrPhoneLabel}</FieldLabel>
                <Input
                  id="emailOrPhone"
                  name="emailOrPhone"
                  type="text"
                  placeholder={t.pages.auth.resetPassword.emailOrPhonePlaceholder}
                  value={emailOrPhone}
                  onChange={(event) => {
                    resetMessage();
                    resetFieldErrors();
                    setEmailOrPhone(event.target.value);
                  }}
                  aria-invalid={!!fieldErrors.emailOrPhone}
                />
                <FieldError>{fieldErrors.emailOrPhone}</FieldError>
              </Field>

              {/* Turnstile CAPTCHA Widget */}
              <div className="flex justify-center">
                <TurnstileCaptcha
                  ref={turnstileRef}
                  execution="render"
                  appearance="always"
                  size="flexible"
                  onSuccess={(token) => {
                    setCaptchaToken(token);
                    resetMessage();
                  }}
                  onError={() => {
                    setCaptchaToken(null);
                    setMessage({ type: "error", text: t.pages.auth.resetPassword.errors.captchaFailed });
                  }}
                  onExpire={() => {
                    setCaptchaToken(null);
                    setMessage({ type: "error", text: t.pages.auth.resetPassword.errors.captchaExpired });
                  }}
                />
              </div>

              <Button
                type="submit"
                disabled={isSubmitting || !captchaToken}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                {t.pages.auth.resetPassword.sendCodeButton}
              </Button>
            </form>
          )}

          {/* Step 2: OTP */}
          {step === "otp" && (
            <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
              <Field data-invalid={!!fieldErrors.otp} className="items-center">
                <FieldLabel htmlFor="otp" className="sr-only">
                  {t.pages.auth.resetPassword.otpLabel}
                </FieldLabel>
                <InputOTP
                  maxLength={6}
                  value={otp}
                  onChange={(value) => {
                    resetAll();
                    setOtp(value);
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
                {fieldErrors.otp && (
                  <FieldError className="text-center">{fieldErrors.otp}</FieldError>
                )}
              </Field>

              <Button
                type="submit"
                disabled={isSubmitting}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                {t.pages.auth.resetPassword.verifyButton}
              </Button>

              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  setStep("input");
                  setOtp("");
                  resetAll();
                }}
                className="w-full"
              >
                {t.pages.auth.resetPassword.backButton}
              </Button>
            </form>
          )}

          {/* Step 3: New Password */}
          {step === "password" && (
            <form
              className="space-y-6"
              noValidate
              onSubmit={handleUpdatePassword}
            >
              <FieldGroup>
                <Field data-invalid={!!fieldErrors.password}>
                  <FieldLabel htmlFor="password">{t.pages.auth.resetPassword.newPasswordLabel}</FieldLabel>
                  <Input
                    id="password"
                    name="password"
                    type="password"
                    placeholder={t.pages.auth.resetPassword.newPasswordPlaceholder}
                    value={password}
                    onChange={(event) => {
                      resetAll();
                      setPassword(event.target.value);
                    }}
                    aria-invalid={!!fieldErrors.password}
                  />
                  <FieldError>{fieldErrors.password}</FieldError>
                </Field>

                <Field data-invalid={!!fieldErrors.confirmPassword}>
                  <FieldLabel htmlFor="confirmPassword">{t.pages.auth.resetPassword.confirmPasswordLabel}</FieldLabel>
                  <Input
                    id="confirmPassword"
                    name="confirmPassword"
                    type="password"
                    placeholder={t.pages.auth.resetPassword.confirmPasswordPlaceholder}
                    value={confirmPassword}
                    onChange={(event) => {
                      resetAll();
                      setConfirmPassword(event.target.value);
                    }}
                    aria-invalid={!!fieldErrors.confirmPassword}
                  />
                  <FieldError>{fieldErrors.confirmPassword}</FieldError>
                </Field>
              </FieldGroup>

              <Button
                type="submit"
                disabled={isSubmitting}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                {t.pages.auth.resetPassword.updateButton}
              </Button>
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

          {/* Back to login */}
          <div className="mt-6 text-center">
            <Button
              asChild
              variant="link"
              size="sm"
            >
              <Link href={`/${locale}/login`}>
                {t.pages.auth.resetPassword.backToLogin}
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
