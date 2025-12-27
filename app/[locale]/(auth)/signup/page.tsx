"use client";

import Link from "next/link";
import Image from "next/image";
import dynamic from "next/dynamic";
import { useRouter, useSearchParams } from "next/navigation";
import { FormEvent, useState, use, useRef, useEffect } from "react";
import { motion } from "framer-motion";
import { useTranslations } from "@/lib/i18n/client";

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
  FieldSeparator,
} from "@/components/app/Field";
import { Input } from "@/components/app/Input";
import { PasswordInput } from "@/components/app/PasswordInput";
import { Button } from "@/components/app/Button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/app/Card";
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from "@/components/app/TurnstileCaptcha";
import { Checkbox } from "@/components/app/Checkbox";
import { LegalModal } from "@/components/legal";
import { translateError } from "@/lib/errors/translate";

// Lazy load OAuth icon SVGs
const GoogleIcon = dynamic(() => import("../login/GoogleIcon"), {
  ssr: false,
  loading: () => <div className="h-4 w-4" />
});

const AppleIcon = dynamic(() => import("../login/AppleIcon"), {
  ssr: false,
  loading: () => <div className="h-4 w-4" />
});

type MessageState = { type: "error" | "success"; text: string } | null;
type SignupStep = "input" | "otp";
type FieldErrors = {
  firstName?: string;
  lastName?: string;
  emailOrPhone?: string;
  password?: string;
  otp?: string;
};

export default function SignupPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();

  // Pre-populate email from login page if user came from there
  const initialEmail = searchParams.get('email') || '';

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [emailOrPhone, setEmailOrPhone] = useState(initialEmail);
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<SignupStep>("input");
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [oauthProvider, setOauthProvider] = useState<'google' | 'apple' | null>(null);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [legalModalOpen, setLegalModalOpen] = useState(false);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);
  const formRef = useRef<HTMLFormElement>(null);

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

  const performGoogleSignIn = async () => {
    setOauthProvider('google');

    const configuredBaseUrl = process.env.NEXT_PUBLIC_SITE_URL;
    const fallbackOrigin =
      typeof window !== 'undefined' ? window.location.origin : undefined;
    const baseUrl =
      configuredBaseUrl && configuredBaseUrl.startsWith('http')
        ? configuredBaseUrl
        : fallbackOrigin;

    if (!baseUrl) {
      setOauthProvider(null);
      setMessage({
        type: 'error',
        text: t.pages.auth.login.errors.googleSignInFailed,
      });
      return;
    }

    const redirectUrl = new URL('/auth/callback', baseUrl);
    redirectUrl.searchParams.set('next', '/onboarding');

    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: redirectUrl.toString(),
        queryParams: {
          access_type: 'offline',
        },
      },
    });

    if (error) {
      setOauthProvider(null);
      setMessage({ type: 'error', text: translateError(error.message) });
      setCaptchaToken(null);
      turnstileRef.current?.reset();
      return;
    }

    setMessage({
      type: 'success',
      text: t.pages.auth.login.waitingForGoogle,
    });
  };

  const handleGoogleSignIn = async () => {
    setMessage(null);

    if (!captchaToken) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.completeCaptcha });
      return;
    }

    if (!agreedToTerms) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.acceptTerms });
      return;
    }

    setCaptchaToken(null);
    await performGoogleSignIn();
  };

  const performAppleSignIn = async () => {
    setOauthProvider('apple');

    const configuredBaseUrl = process.env.NEXT_PUBLIC_SITE_URL;
    const fallbackOrigin =
      typeof window !== 'undefined' ? window.location.origin : undefined;
    const baseUrl =
      configuredBaseUrl && configuredBaseUrl.startsWith('http')
        ? configuredBaseUrl
        : fallbackOrigin;

    if (!baseUrl) {
      setOauthProvider(null);
      setMessage({
        type: 'error',
        text: t.pages.auth.login.errors.appleSignInFailed,
      });
      return;
    }

    const redirectUrl = new URL('/auth/callback', baseUrl);
    redirectUrl.searchParams.set('next', '/onboarding');

    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'apple',
      options: {
        redirectTo: redirectUrl.toString(),
      },
    });

    if (error) {
      setOauthProvider(null);
      setMessage({ type: 'error', text: translateError(error.message) });
      setCaptchaToken(null);
      turnstileRef.current?.reset();
      return;
    }

    setMessage({
      type: 'success',
      text: t.pages.auth.login.waitingForApple,
    });
  };

  const handleAppleSignIn = async () => {
    setMessage(null);

    if (!captchaToken) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.completeCaptcha });
      return;
    }

    if (!agreedToTerms) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.acceptTerms });
      return;
    }

    setCaptchaToken(null);
    await performAppleSignIn();
  };

  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

    // Validate all inputs before triggering captcha
    if (!firstName) {
      errors.firstName = t.pages.auth.signup.errors.fillFirstName;
    }

    if (!lastName) {
      errors.lastName = t.pages.auth.signup.errors.fillLastName;
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
      if (password && password.length < 6) {
        errors.password = t.pages.auth.signup.errors.passwordTooShort;
      }
    }

    // If there are validation errors, show them and don't trigger captcha
    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    // Require captcha token before submission
    if (!captchaToken) {
      setMessage({ type: "error", text: t.pages.auth.signup.errors.completeCaptcha });
      return;
    }

    const fullName = `${firstName} ${lastName}`.trim();

    if (inputType === "email") {

      setIsSubmitting(true);

      const { error } = await supabase.auth.signUp({
        email: emailOrPhone,
        password,
        options: {
          data: {
            full_name: fullName,
          },
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/onboarding`,
          captchaToken,
        },
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        // Reset captcha token so user can retry with fresh token
        setCaptchaToken(null);
        turnstileRef.current?.reset();
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

        const { error } = await supabase.auth.signUp({
          phone: phoneE164,
          password: password,
          options: {
            data: {
              full_name: fullName,
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
          // Reset captcha token so user can retry with fresh token
          setCaptchaToken(null);
          turnstileRef.current?.reset();
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
        // Reset captcha token so user can retry with fresh token
        setCaptchaToken(null);
        turnstileRef.current?.reset();
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

  const isOAuthRedirecting = oauthProvider !== null;
  const oauthButtonDisabled = isSubmitting || isOAuthRedirecting || !captchaToken;
  const submitButtonDisabled = isSubmitting || isOAuthRedirecting || !captchaToken || !agreedToTerms;

  return (
    <motion.div
      className="relative w-full"
      variants={cardVariants}
      initial="hidden"
      animate="visible"
    >
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-xs">
          <Card className="max-w-sm shadow-lg">
            <CardContent className="pt-6">
              <div className="flex flex-col items-center gap-4">
                <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-primary"></div>
                <p className="text-lg font-semibold">
                  {oauthProvider === 'apple'
                    ? t.pages.auth.login.waitingForApple
                    : t.pages.auth.login.waitingForGoogle}
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card className="w-full max-w-md shadow-lg">
        <CardHeader>
          {/* Title and Logo inline */}
          <div className="flex items-center justify-between mb-1">
            <CardTitle className="text-2xl font-bold">{t.pages.auth.signup.title}</CardTitle>
            <Image
              src="/icons/tidex-logo.webp"
              alt="Tidex"
              width={32}
              height={32}
              priority
            />
          </div>
          <CardDescription>
            {step === "otp"
              ? t.pages.auth.signup.descriptionOtp.replace('{phone}', emailOrPhone)
              : t.pages.auth.signup.subtitle}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Step 1: Input Form */}
          {step === "input" && (
            <>
              {/* OAuth Buttons */}
              <div className="flex flex-col gap-3 mb-6">
                <Button
                  type="button"
                  variant="outline"
                  size="lg"
                  onClick={handleGoogleSignIn}
                  disabled={oauthButtonDisabled}
                  loading={isOAuthRedirecting}
                  aria-label={t.pages.auth.login.continueWithGoogle}
                  className="w-full"
                >
                  <span className="flex h-5 w-5 items-center justify-center">
                    <GoogleIcon />
                  </span>
                  Google
                </Button>

                <Button
                  type="button"
                  variant="outline"
                  size="lg"
                  onClick={handleAppleSignIn}
                  disabled={oauthButtonDisabled}
                  loading={isOAuthRedirecting}
                  aria-label={t.pages.auth.login.continueWithApple}
                  className="w-full"
                >
                  <span className="flex h-5 w-5 items-center justify-center">
                    <AppleIcon />
                  </span>
                  Apple
                </Button>
              </div>

              <FieldSeparator>{t.pages.auth.login.separator}</FieldSeparator>

              <form ref={formRef} className="space-y-4 mt-6" noValidate onSubmit={handleSignUp}>
                <FieldGroup>
                  {/* First name and Last name side by side */}
                  <div className="grid grid-cols-2 gap-3">
                    <Field data-invalid={!!fieldErrors.firstName}>
                      <FieldLabel htmlFor="firstName">{t.pages.auth.signup.firstNameLabel}</FieldLabel>
                      <Input
                        id="firstName"
                        name="firstName"
                        type="text"
                        value={firstName}
                        onChange={(event) => {
                          resetMessage();
                          resetFieldErrors();
                          setFirstName(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.firstName}
                      />
                      <FieldError>{fieldErrors.firstName}</FieldError>
                    </Field>

                    <Field data-invalid={!!fieldErrors.lastName}>
                      <FieldLabel htmlFor="lastName">{t.pages.auth.signup.lastNameLabel}</FieldLabel>
                      <Input
                        id="lastName"
                        name="lastName"
                        type="text"
                        value={lastName}
                        onChange={(event) => {
                          resetMessage();
                          resetFieldErrors();
                          setLastName(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.lastName}
                      />
                      <FieldError>{fieldErrors.lastName}</FieldError>
                    </Field>
                  </div>

                  <Field data-invalid={!!fieldErrors.emailOrPhone}>
                    <FieldLabel htmlFor="emailOrPhone">{t.pages.auth.signup.usernameLabel}</FieldLabel>
                    <Input
                      id="emailOrPhone"
                      name="emailOrPhone"
                      type="text"
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

                  <Field data-invalid={!!fieldErrors.password}>
                    <FieldLabel htmlFor="password">{t.pages.auth.signup.passwordLabel}</FieldLabel>
                    <PasswordInput
                      id="password"
                      name="password"
                      value={password}
                      onChange={(event) => {
                        resetMessage();
                        resetFieldErrors();
                        setPassword(event.target.value);
                      }}
                      invalid={!!fieldErrors.password}
                    />
                    <FieldError>{fieldErrors.password}</FieldError>
                  </Field>
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
                      setMessage({ type: "error", text: t.pages.auth.signup.errors.captchaFailed });
                    }}
                    onExpire={() => {
                      setCaptchaToken(null);
                      setMessage({ type: "error", text: t.pages.auth.signup.errors.captchaExpired });
                    }}
                  />
                </div>

                {/* Message Display */}
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

                <Button
                  type="submit"
                  disabled={submitButtonDisabled}
                  loading={isSubmitting}
                  size="lg"
                  className="w-full"
                >
                  {t.pages.auth.signup.continueButton}
                </Button>
              </form>
            </>
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

              {/* Message Display */}
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
        </CardContent>

        {/* Footer with sign in link */}
        {step === "input" && (
          <CardFooter className="flex-col border-t bg-surface-secondary rounded-b-3xl pt-6">
            <p className="text-sm text-text-secondary">
              {t.pages.auth.signup.haveAccount}{' '}
              <Link
                href={`/${locale}/login`}
                className="font-semibold text-text-primary hover:underline"
              >
                {t.pages.auth.signup.signIn}
              </Link>
            </p>
          </CardFooter>
        )}
      </Card>

      <LegalModal
        open={legalModalOpen}
        onOpenChange={setLegalModalOpen}
        showActions={true}
        onAccept={() => setAgreedToTerms(true)}
        onDecline={() => setAgreedToTerms(false)}
      />
    </motion.div>
  );
}
