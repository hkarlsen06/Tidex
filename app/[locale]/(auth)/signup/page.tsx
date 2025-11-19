"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState, use, useRef, useEffect } from "react";
import { useTranslations } from "@/lib/i18n/client";

import { supabase } from "@/lib/supabase/browser";
import {
  detectInputType,
  normalizePhoneToE164,
  isValidNorwegianPhone,
  isValidEmail,
} from "@/lib/validation/phone";
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
  FieldGroup,
} from "@/components/app/Field";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from "@/components/app/TurnstileCaptcha";
import { Checkbox } from "@/components/app/Checkbox";
import { LegalModal } from "@/components/legal";

type MessageState = { type: "error" | "success"; text: string } | null;
type SignupStep = "input" | "otp";
type FieldErrors = {
  fullName?: string;
  emailOrPhone?: string;
  password?: string;
  confirmPassword?: string;
  otp?: string;
};

export default function SignupPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const router = useRouter();

  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<SignupStep>("input");
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [legalModalOpen, setLegalModalOpen] = useState(false);
  const [isCaptchaValidating, setIsCaptchaValidating] = useState(false);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const resetMessage = () => setMessage(null);
  const resetFieldErrors = () => setFieldErrors({});
  const resetAll = () => {
    resetMessage();
    resetFieldErrors();
    setCaptchaToken(null);
  };

  // When captcha token is received, automatically re-submit the form
  useEffect(() => {
    if (captchaToken) {
      formRef.current?.requestSubmit();
    }
  }, [captchaToken]);

  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

    // Validate all inputs before triggering captcha
    if (!fullName) {
      errors.fullName = t.pages.auth.signup.errors.fillFullName;
    }

    if (!emailOrPhone) {
      errors.emailOrPhone = t.pages.auth.signup.errors.fillEmailOrPhone;
    }

    if (!agreedToTerms) {
      setMessage({ type: "error", text: t.pages.auth.signup.errors.acceptTerms });
      return;
    }

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === "unknown") {
      errors.emailOrPhone = t.pages.auth.signup.errors.invalidEmailOrPhone;
    }

    // Validate based on input type
    if (inputType === "email") {
      if (!password) {
        errors.password = t.pages.auth.signup.errors.fillPassword;
      }
      if (!confirmPassword) {
        errors.confirmPassword = t.pages.auth.signup.errors.fillConfirmPassword;
      }
      if (password && confirmPassword && password !== confirmPassword) {
        errors.confirmPassword = t.pages.auth.signup.errors.passwordMismatch;
      }
      if (password && password.length < 6) {
        errors.password = t.pages.auth.signup.errors.passwordTooShort;
      }
      if (emailOrPhone && !isValidEmail(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.signup.errors.invalidEmail;
      }
    } else if (inputType === "phone") {
      if (!isValidNorwegianPhone(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.signup.errors.invalidPhone;
      }
      if (!password) {
        errors.password = t.pages.auth.signup.errors.fillPassword;
      }
      if (!confirmPassword) {
        errors.confirmPassword = t.pages.auth.signup.errors.fillConfirmPassword;
      }
      if (password && confirmPassword && password !== confirmPassword) {
        errors.confirmPassword = t.pages.auth.signup.errors.passwordMismatch;
      }
      if (password && password.length < 6) {
        errors.password = t.pages.auth.signup.errors.passwordTooShort;
      }
    }

    // If there are validation errors, show them and don't trigger captcha
    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    // If no captcha token yet, trigger captcha execution
    if (!captchaToken) {
      setIsCaptchaValidating(true);
      turnstileRef.current?.execute();
      return;
    }

    if (inputType === "email") {

      setIsSubmitting(true);

      const { error } = await supabase.auth.signUp({
        email: emailOrPhone,
        password,
        options: {
          data: {
            first_name: fullName,
          },
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/onboarding`,
          captchaToken,
        },
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        return;
      }

      // Redirect to email verification page
      setMessage({
        type: "success",
        text: t.pages.auth.signup.success.emailSent,
      });

      setTimeout(() => {
        router.replace(`/${locale}/verify-email?email=${encodeURIComponent(emailOrPhone)}`);
      }, 1500);
    } else {
      // Phone signup with OTP verification
      setIsSubmitting(true);

      try {
        const phoneE164 = normalizePhoneToE164(emailOrPhone);

        const { error, data } = await supabase.auth.signUp({
          phone: phoneE164,
          password: password,
          options: {
            data: {
              first_name: fullName,
            },
            captchaToken,
          },
        });

        setIsSubmitting(false);

        if (error) {
          // Handle specific error for existing user
          if (error.message.includes("already registered") || error.message.includes("already exists") || error.message.includes("User already registered")) {
            setMessage({
              type: "error",
              text: t.pages.auth.signup.errors.phoneAlreadyExists
            });
          } else {
            setMessage({ type: "error", text: error.message });
          }
          return;
        }

        // Phone signup requires OTP verification to confirm phone ownership
        setStep("otp");
        setMessage({
          type: "success",
          text: t.pages.auth.signup.success.smsSent,
        });
      } catch (err) {
        setIsSubmitting(false);
        setMessage({
          type: "error",
          text: err instanceof Error ? err.message : t.pages.auth.signup.errors.genericError,
        });
      }
    }
  };

  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = t.pages.auth.signup.errors.fillAllDigits;
    }

    if (!isValidNorwegianPhone(emailOrPhone)) {
      errors.otp = t.pages.auth.signup.errors.invalidPhoneNumber;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    try {
      const phoneE164 = normalizePhoneToE164(emailOrPhone);
      const { error } = await supabase.auth.verifyOtp({
        phone: phoneE164,
        token: otp,
        type: "sms",
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        return;
      }

      setMessage({
        type: "success",
        text: t.pages.auth.signup.success.accountCreated,
      });

      // Redirect to onboarding
      setTimeout(() => {
        router.replace(`/${locale}/onboarding`);
        router.refresh();
      }, 1500);
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "En feil oppstod",
      });
    }
  };

  const detectedInputType = detectInputType(emailOrPhone);
  const isPhoneInput = detectedInputType === "phone";

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.signup.title}</CardTitle>
          <CardDescription>
            {step === "otp"
              ? t.pages.auth.signup.descriptionOtp.replace('{phone}', emailOrPhone)
              : t.pages.auth.signup.descriptionInput}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Step 1: Input Form */}
          {step === "input" && (
            <form ref={formRef} className="space-y-6" noValidate onSubmit={handleSignUp}>
              <FieldGroup>
                <Field data-invalid={!!fieldErrors.fullName}>
                  <FieldLabel htmlFor="fullName">{t.pages.auth.signup.fullNameLabel}</FieldLabel>
                  <Input
                    id="fullName"
                    name="fullName"
                    type="text"
                    placeholder={t.pages.auth.signup.fullNamePlaceholder}
                    value={fullName}
                    onChange={(event) => {
                      resetMessage();
                      resetFieldErrors();
                      setFullName(event.target.value);
                    }}
                    aria-invalid={!!fieldErrors.fullName}
                  />
                  <FieldError>{fieldErrors.fullName}</FieldError>
                </Field>

                <Field data-invalid={!!fieldErrors.emailOrPhone}>
                  <FieldLabel htmlFor="emailOrPhone">{t.pages.auth.signup.emailOrPhoneLabel}</FieldLabel>
                  <Input
                    id="emailOrPhone"
                    name="emailOrPhone"
                    type="text"
                    placeholder={t.pages.auth.signup.emailOrPhonePlaceholder}
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

                {/* Show password fields when email or phone is entered */}
                {emailOrPhone && (
                  <>
                    <Field data-invalid={!!fieldErrors.password}>
                      <FieldLabel htmlFor="password">{t.pages.auth.signup.passwordLabel}</FieldLabel>
                      <Input
                        id="password"
                        name="password"
                        type="password"
                        placeholder={t.pages.auth.signup.passwordPlaceholder}
                        value={password}
                        onChange={(event) => {
                          resetMessage();
                          resetFieldErrors();
                          setPassword(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.password}
                      />
                      <FieldError>{fieldErrors.password}</FieldError>
                    </Field>

                    <Field data-invalid={!!fieldErrors.confirmPassword}>
                      <FieldLabel htmlFor="confirmPassword">{t.pages.auth.signup.confirmPasswordLabel}</FieldLabel>
                      <Input
                        id="confirmPassword"
                        name="confirmPassword"
                        type="password"
                        placeholder={t.pages.auth.signup.confirmPasswordPlaceholder}
                        value={confirmPassword}
                        onChange={(event) => {
                          resetMessage();
                          resetFieldErrors();
                          setConfirmPassword(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.confirmPassword}
                      />
                      <FieldError>{fieldErrors.confirmPassword}</FieldError>
                    </Field>
                  </>
                )}
              </FieldGroup>

              <Card className="bg-surface-primary/50 rounded-lg">
                <CardContent className="flex items-center gap-3 p-4">
                  <Checkbox
                    id="terms"
                    checked={agreedToTerms}
                    onCheckedChange={(checked) => {
                      if (checked) {
                        // If checking, open modal to read terms
                        setLegalModalOpen(true);
                      } else {
                        // If unchecking, just untick
                        setAgreedToTerms(false);
                      }
                    }}
                    className="h-6 w-6"
                  />
                  <label
                    htmlFor="terms"
                    className="text-sm text-text-secondary leading-relaxed cursor-pointer select-none"
                  >
                    {t.pages.auth.signup.termsAgreement}{" "}
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        setLegalModalOpen(true);
                      }}
                      className="text-brand-primary hover:underline font-medium"
                    >
                      {t.pages.auth.signup.termsLink}
                    </button>
                  </label>
                </CardContent>
              </Card>

              <Button
                type="submit"
                disabled={isSubmitting || !agreedToTerms || isCaptchaValidating}
                loading={isSubmitting || isCaptchaValidating}
                size="lg"
                className="w-full"
              >
                {isPhoneInput ? t.pages.auth.signup.submitButtonPhone : t.pages.auth.signup.submitButtonEmail}
              </Button>
            </form>
          )}

          {/* Step 2: OTP Verification (for phone signup) */}
          {step === "otp" && (
            <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
              <Field data-invalid={!!fieldErrors.otp} className="items-center">
                <FieldLabel htmlFor="otp" className="sr-only">
                  {t.pages.auth.signup.otpLabel}
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
                {t.pages.auth.signup.verifyButton}
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
                {t.pages.auth.signup.backButton}
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

          {/* Back to login - only show on input step */}
          {step === "input" && (
            <div className="mt-6 text-center">
              <Button
                asChild
                variant="link"
                size="sm"
              >
                <Link href={`/${locale}/login`}>
                  {t.pages.auth.signup.backToLogin}
                </Link>
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      <LegalModal
        open={legalModalOpen}
        onOpenChange={setLegalModalOpen}
        showActions={true}
        onAccept={() => setAgreedToTerms(true)}
        onDecline={() => setAgreedToTerms(false)}
      />

      {/* Hidden Turnstile widget with execution mode */}
      <div className="sr-only">
        <TurnstileCaptcha
          ref={turnstileRef}
          execution="execute"
          onSuccess={(token) => {
            setCaptchaToken(token);
            setIsCaptchaValidating(false);
            resetMessage();
          }}
          onError={() => {
            setCaptchaToken(null);
            setIsCaptchaValidating(false);
            setMessage({ type: "error", text: t.pages.auth.signup.errors.captchaFailed });
          }}
        />
      </div>
    </div>
  );
}
