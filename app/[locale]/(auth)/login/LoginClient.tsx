'use client';

import Link from 'next/link';
import dynamic from 'next/dynamic';
import { FormEvent, useState, use, useRef, useEffect } from 'react';
import { useTranslations } from '@/lib/i18n/client';

import { supabase } from '@/lib/supabase/browser';
import { translateError } from '@/lib/errors/translate';
import {
  detectInputType,
  normalizePhoneToE164,
  isValidNorwegianPhone,
  isValidEmail,
} from '@/lib/validation/phone';
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSeparator,
  InputOTPSlot,
} from '@/components/app/InputOTP';
import {
  Field,
  FieldLabel,
  FieldError,
  FieldGroup,
  FieldSeparator,
} from '@/components/app/Field';
import { Input } from '@/components/app/Input';
import { Button } from '@/components/app/Button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card';
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from '@/components/app/TurnstileCaptcha';

// Lazy load Google icon SVG
const GoogleIcon = dynamic(() => import('./GoogleIcon'), {
  ssr: false,
  loading: () => <div className="h-4 w-4" />
});

type MessageState = { type: 'error' | 'success'; text: string } | null;
type LoginStep = 'input' | 'otp';
type FieldErrors = {
  emailOrPhone?: string;
  password?: string;
  otp?: string;
};

export default function LoginClient({
  initialNext,
  params
}: {
  initialNext: string;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = use(params);
  const { t } = useTranslations();
  const getRedirectPath = () => initialNext;

  const [emailOrPhone, setEmailOrPhone] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [step, setStep] = useState<LoginStep>('input');
  const [, setLoginType] = useState<'email' | 'phone' | null>(null);
  const [phoneLoginMethod, setPhoneLoginMethod] = useState<'otp' | 'password'>('otp');
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isOAuthRedirecting, setIsOAuthRedirecting] = useState(false);
  const [showSignupPrompt, setShowSignupPrompt] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<'login' | 'oauth' | null>(null);
  const [isCaptchaValidating, setIsCaptchaValidating] = useState(false);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const resetMessage = () => {
    setMessage(null);
    setShowSignupPrompt(false);
  };

  const resetFieldErrors = () => {
    setFieldErrors({});
  };

  // When captcha token is received, automatically proceed with pending action
  useEffect(() => {
    if (captchaToken && pendingAction === 'login') {
      setPendingAction(null);
      // Re-submit the form programmatically
      formRef.current?.requestSubmit();
    } else if (captchaToken && pendingAction === 'oauth') {
      setPendingAction(null);
      // Directly call the OAuth flow
      performGoogleSignIn();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [captchaToken, pendingAction]);

  const performGoogleSignIn = async () => {
    setIsOAuthRedirecting(true);

    const redirectPath = getRedirectPath();
    const configuredBaseUrl = process.env.NEXT_PUBLIC_SITE_URL;
    const fallbackOrigin =
      typeof window !== 'undefined' ? window.location.origin : undefined;
    const baseUrl =
      configuredBaseUrl && configuredBaseUrl.startsWith('http')
        ? configuredBaseUrl
        : fallbackOrigin;

    if (!baseUrl) {
      setIsOAuthRedirecting(false);
      setMessage({
        type: 'error',
        text: t.pages.auth.login.errors.googleSignInFailed,
      });
      return;
    }

    const redirectUrl = new URL('/auth/callback', baseUrl);
    redirectUrl.searchParams.set('next', redirectPath);

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
      setIsOAuthRedirecting(false);
      setMessage({ type: 'error', text: translateError(error.message) });
      return;
    }

    setMessage({
      type: 'success',
      text: t.pages.auth.login.waitingForGoogle,
    });
  };

  const handleSignIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

    if (!emailOrPhone) {
      errors.emailOrPhone = t.pages.auth.login.errors.fillEmailOrPhone;
    }

    // If no captcha token yet, trigger captcha execution
    if (!captchaToken) {
      if (Object.keys(errors).length === 0) {
        setPendingAction('login');
        setIsCaptchaValidating(true);
        turnstileRef.current?.execute();
      } else {
        setFieldErrors(errors);
      }
      return;
    }

    // Reset pending action if we're proceeding
    setPendingAction(null);

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === 'unknown') {
      errors.emailOrPhone = t.pages.auth.login.errors.invalidEmailOrPhone;
    }

    if (inputType === 'email') {
      // Email login requires password
      if (!password) {
        errors.password = t.pages.auth.login.errors.fillPassword;
      }

      if (emailOrPhone && !isValidEmail(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.login.errors.invalidEmail;
      }

      if (Object.keys(errors).length > 0) {
        setFieldErrors(errors);
        return;
      }

      setIsSubmitting(true);
      setMessage(null);

      const { error } = await supabase.auth.signInWithPassword({
        email: emailOrPhone,
        password,
        options: {
          captchaToken,
        },
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: 'error', text: translateError(error.message) });
        return;
      }

      const destination = getRedirectPath();
      // Use full page navigation to ensure cookies are properly set
      window.location.href = destination;
    } else {
      // Phone login
      if (!isValidNorwegianPhone(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.login.errors.invalidPhone;
      }

      // Determine if user wants password login (has entered a password)
      const usePasswordLogin = password.trim().length > 0;

      if (Object.keys(errors).length > 0) {
        setFieldErrors(errors);
        return;
      }

      if (usePasswordLogin) {
        // Phone login with password
        setPhoneLoginMethod('password'); // Update state for UI consistency

        setIsSubmitting(true);
        setMessage(null);

        try {
          const phoneE164 = normalizePhoneToE164(emailOrPhone);
          const { error } = await supabase.auth.signInWithPassword({
            phone: phoneE164,
            password,
            options: {
              captchaToken,
            },
          });

          setIsSubmitting(false);

          if (error) {
            setMessage({ type: 'error', text: translateError(error.message) });
            return;
          }

          const destination = getRedirectPath();
          // Use full page navigation to ensure cookies are properly set
          window.location.href = destination;
        } catch (err) {
          setIsSubmitting(false);
          setMessage({
            type: 'error',
            text: err instanceof Error ? err.message : t.pages.auth.login.errors.genericError,
          });
        }
      } else {
        // Phone login with OTP
        setIsSubmitting(true);
        setMessage(null);

        try {
          const phoneE164 = normalizePhoneToE164(emailOrPhone);

          // First, check if the phone number exists in the system
          // We do this by attempting to send OTP with shouldCreateUser: false
          const { error } = await supabase.auth.signInWithOtp({
            phone: phoneE164,
            options: {
              shouldCreateUser: false, // Don't create user if doesn't exist
              captchaToken,
            },
          });

          setIsSubmitting(false);

          if (error) {
            // Check if error is because user doesn't exist
            if (
              error.message.includes('User not found') ||
              error.message.includes('not found') ||
              error.message.includes('No user') ||
              error.message.includes('Signups not allowed')
            ) {
              setMessage({
                type: 'error',
                text: t.pages.auth.login.mustRegister,
              });
              setShowSignupPrompt(true);
            } else {
              setMessage({
                type: 'error',
                text: translateError(error.message),
              });
            }
            return;
          }

          setLoginType('phone');
          setStep('otp');
          setMessage({
            type: 'success',
            text: t.pages.auth.login.success.smsSent,
          });
        } catch (err) {
          setIsSubmitting(false);
          setMessage({
            type: 'error',
            text: err instanceof Error ? err.message : t.pages.auth.login.errors.genericError,
          });
        }
      }
    }
  };

  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = t.pages.auth.login.errors.fillAllDigits;
    }

    if (!isValidNorwegianPhone(emailOrPhone)) {
      errors.otp = t.pages.auth.login.errors.invalidPhoneNumber;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const phoneE164 = normalizePhoneToE164(emailOrPhone);
      const { error } = await supabase.auth.verifyOtp({
        phone: phoneE164,
        token: otp,
        type: 'sms',
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: 'error', text: translateError(error.message) });
        return;
      }

      setMessage({ type: 'success', text: t.pages.auth.login.loggingIn });
      const destination = getRedirectPath();
      // Use full page navigation to ensure cookies are properly set
      window.location.href = destination;
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: 'error',
        text: err instanceof Error ? err.message : 'En feil oppstod',
      });
    }
  };

  const handleGoogleSignIn = async () => {
    setMessage(null);

    // If no captcha token yet, trigger captcha execution
    if (!captchaToken) {
      setPendingAction('oauth');
      setIsCaptchaValidating(true);
      turnstileRef.current?.execute();
      return;
    }

    // Reset pending action if we're proceeding
    setPendingAction(null);
    await performGoogleSignIn();
  };

  const detectedInputType = detectInputType(emailOrPhone);
  const isPhoneInput = detectedInputType === 'phone';
  const buttonDisabled = isSubmitting || isOAuthRedirecting || isCaptchaValidating;

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <Card className="max-w-sm shadow-lg">
            <CardContent className="pt-6">
              <div className="flex flex-col items-center gap-4">
                <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-primary"></div>
                <p className="text-lg font-semibold">{t.pages.auth.login.waitingForGoogle}</p>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.login.title}</CardTitle>
          {step === 'otp' && (
            <CardDescription>
              {t.pages.auth.login.otpDescription.replace('{phone}', emailOrPhone)}
            </CardDescription>
          )}
        </CardHeader>

        <CardContent>

        {/* Step 1: Email/Phone and Password Input */}
        {step === 'input' && (
          <form ref={formRef} className="space-y-6" noValidate onSubmit={handleSignIn}>
            <FieldGroup>
              <Field data-invalid={!!fieldErrors.emailOrPhone}>
                <FieldLabel htmlFor="emailOrPhone">{t.pages.auth.login.emailOrPhoneLabel}</FieldLabel>
                <Input
                  id="emailOrPhone"
                  name="emailOrPhone"
                  type="text"
                  placeholder={t.pages.auth.login.emailOrPhonePlaceholder}
                  // Microsoft Editor browser extension injects these attributes before hydration; set them eagerly to avoid mismatches.
                  spellCheck={false}
                  data-ms-editor="true"
                  suppressHydrationWarning
                  autoComplete="username"
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
                <FieldLabel htmlFor="password">
                  {t.pages.auth.login.passwordLabel}
                  {isPhoneInput && (
                    <span className="text-sm text-muted-foreground font-normal ml-2">{t.pages.auth.login.passwordOptional}</span>
                  )}
                </FieldLabel>
                <Input
                  id="password"
                  name="password"
                  type="password"
                  placeholder={t.pages.auth.login.passwordPlaceholder}
                  autoComplete="current-password"
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
            </FieldGroup>

            <Button
              type="submit"
              disabled={buttonDisabled}
              loading={isSubmitting || isCaptchaValidating}
              size="lg"
              className="w-full"
            >
              {isPhoneInput && !password.trim() && phoneLoginMethod === 'otp' ? t.pages.auth.login.submitButtonSendCode : t.pages.auth.login.submitButton}
            </Button>

            {/* Show "Engangskode" button for phone users with password */}
            {emailOrPhone &&
              isPhoneInput &&
              password.trim() && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setPhoneLoginMethod('otp');
                    setPassword('');
                    resetMessage();
                    resetFieldErrors();
                  }}
                  className="w-full"
                >
                  {t.pages.auth.login.useOtpInstead}
                </Button>
              )}
          </form>
        )}

        {/* Step 2: OTP Verification (for phone login) */}
        {step === 'otp' && (
          <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
            <Field data-invalid={!!fieldErrors.otp} className="items-center">
              <FieldLabel htmlFor="otp" className="sr-only">
                {t.pages.auth.login.otpLabel}
              </FieldLabel>
              <InputOTP
                maxLength={6}
                value={otp}
                onChange={(value) => {
                  resetMessage();
                  resetFieldErrors();
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
              disabled={buttonDisabled}
              loading={isSubmitting}
              size="lg"
              className="w-full"
            >
              {t.pages.auth.login.verifyButton}
            </Button>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                setStep('input');
                setOtp('');
                resetMessage();
                resetFieldErrors();
              }}
              className="w-full"
            >
              {t.pages.auth.login.backToLogin}
            </Button>
          </form>
        )}

        {message && (
          <div
            className={`mt-4 rounded-full px-5 py-3 text-sm font-medium ${
              message.type === 'error'
                ? 'bg-error-subtle text-error-foreground'
                : 'bg-success-subtle text-success-foreground'
            }`}
            role="status"
            aria-live="polite"
          >
            {message.text}
          </div>
        )}

        {/* Arrow pointing to signup button */}
        {showSignupPrompt && step === 'input' && (
          <div className="mt-2 flex justify-center animate-bounce">
            <svg
              className="h-6 w-6 text-error-foreground"
              fill="none"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path d="M19 14l-7 7m0 0l-7-7m7 7V3"></path>
            </svg>
          </div>
        )}

        {/* Only show signup and Google options on input step */}
        {step === 'input' && (
          <>
            <div className={showSignupPrompt ? 'mt-2 mb-6' : 'mt-6 mb-6'}>
              <FieldSeparator>{t.pages.auth.login.separator}</FieldSeparator>
            </div>

            <div className="space-y-3">
              <Button
                asChild
                variant={showSignupPrompt ? 'default' : 'outline'}
                size="lg"
                className={`w-full ${showSignupPrompt ? 'ring-2 ring-ring ring-offset-2' : ''}`}
              >
                <Link href={`/${locale}/signup`}>
                  {t.pages.auth.login.createAccount}
                </Link>
              </Button>

              <Button
                type="button"
                variant="outline"
                size="lg"
                onClick={handleGoogleSignIn}
                disabled={buttonDisabled}
                loading={isOAuthRedirecting || (isCaptchaValidating && pendingAction === 'oauth')}
                aria-label={t.pages.auth.login.continueWithGoogle}
                className="w-full"
              >
                <span className="flex h-5 w-5 items-center justify-center">
                  <GoogleIcon />
                </span>
                {t.pages.auth.login.continueWithGoogle}
              </Button>
            </div>

            <div className="mt-6 text-center">
              <Button
                asChild
                variant="link"
                size="sm"
              >
                <Link href={`/${locale}/reset-password`}>
                  {t.pages.auth.login.resetPassword}
                </Link>
              </Button>
            </div>
          </>
        )}
        </CardContent>
      </Card>

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
            setPendingAction(null);
            setIsCaptchaValidating(false);
            setMessage({ type: 'error', text: t.pages.auth.login.errors.captchaFailed });
          }}
        />
      </div>
    </div>
  );
}
