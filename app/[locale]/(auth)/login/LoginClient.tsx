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
  Field,
  FieldLabel,
  FieldError,
  FieldGroup,
  FieldSeparator,
} from '@/components/app/Field';
import { Input } from '@/components/app/Input';
import { PasswordInput } from '@/components/app/PasswordInput';
import { Button } from '@/components/app/Button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card';
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from '@/components/app/TurnstileCaptcha';

// Lazy load Google icon SVG
const GoogleIcon = dynamic(() => import('./GoogleIcon'), {
  ssr: false,
  loading: () => <div className="h-4 w-4" />
});

type MessageState = { type: 'error' | 'success'; text: string } | null;
// NOTE: 'otp' step preserved for future MFA implementation
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
  const [otp, _setOtp] = useState('');
  // NOTE: step state preserved for future MFA implementation
  const [step, _setStep] = useState<LoginStep>('input');
  const [, _setLoginType] = useState<'email' | 'phone' | null>(null);
  // NOTE: phoneLoginMethod preserved for future MFA implementation
  const [, _setPhoneLoginMethod] = useState<'otp' | 'password'>('password');
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isOAuthRedirecting, setIsOAuthRedirecting] = useState(false);
  const [showSignupPrompt, setShowSignupPrompt] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);

  const turnstileRef = useRef<TurnstileCaptchaHandle>(null);

  const resetMessage = () => {
    setMessage(null);
    setShowSignupPrompt(false);
  };

  const resetFieldErrors = () => {
    setFieldErrors({});
  };

  // Reset Turnstile widget on mount to prevent stale token issues
  useEffect(() => {
    turnstileRef.current?.reset();
  }, []);

  // Check if user needs MFA verification and redirect accordingly
  const checkMfaAndRedirect = async (destination: string) => {
    const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    if (aalData && aalData.currentLevel === 'aal1' && aalData.nextLevel === 'aal2') {
      // User has MFA enrolled but hasn't verified - redirect to MFA verify
      const mfaUrl = `/${locale}/mfa-verify?next=${encodeURIComponent(destination)}`;
      window.location.href = mfaUrl;
    } else {
      // No MFA required or already verified
      window.location.href = destination;
    }
  };

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
      // Reset captcha token so user can retry with fresh token
      setCaptchaToken(null);
      turnstileRef.current?.reset();
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

    // Validate all inputs before triggering captcha
    if (!emailOrPhone) {
      errors.emailOrPhone = t.pages.auth.login.errors.fillEmailOrPhone;
    }

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === 'unknown') {
      errors.emailOrPhone = t.pages.auth.login.errors.invalidEmailOrPhone;
    }

    if (inputType === 'email') {
      if (!password) {
        errors.password = t.pages.auth.login.errors.fillPassword;
      }
      if (emailOrPhone && !isValidEmail(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.login.errors.invalidEmail;
      }
    } else if (inputType === 'phone') {
      if (!isValidNorwegianPhone(emailOrPhone)) {
        errors.emailOrPhone = t.pages.auth.login.errors.invalidPhone;
      }
      if (!password) {
        errors.password = t.pages.auth.login.errors.fillPassword;
      }
    }

    // If there are validation errors, show them
    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    // Require captcha token before submission
    if (!captchaToken) {
      setMessage({ type: 'error', text: t.pages.auth.login.errors.completeCaptcha });
      return;
    }

    // Use and consume the captcha token
    const usedCaptchaToken = captchaToken;
    setCaptchaToken(null);

    if (inputType === 'email') {

      setIsSubmitting(true);
      setMessage(null);

      const { error } = await supabase.auth.signInWithPassword({
        email: emailOrPhone,
        password,
        options: {
          captchaToken: usedCaptchaToken,
        },
      });

      if (error) {
        setIsSubmitting(false);
        setMessage({ type: 'error', text: translateError(error.message) });
        // Reset captcha token so user can retry with fresh token
        setCaptchaToken(null);
        turnstileRef.current?.reset();
        return;
      }

      const destination = getRedirectPath();
      // Check MFA and redirect appropriately
      await checkMfaAndRedirect(destination);
      setIsSubmitting(false);
    } else {
      // Phone login with password
      _setPhoneLoginMethod('password');

      setIsSubmitting(true);
      setMessage(null);

      try {
        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.signInWithPassword({
          phone: phoneE164,
          password,
          options: {
            captchaToken: usedCaptchaToken,
          },
        });

        if (error) {
          setIsSubmitting(false);
          setMessage({ type: 'error', text: translateError(error.message) });
          // Reset captcha token so user can retry with fresh token
          setCaptchaToken(null);
          turnstileRef.current?.reset();
          return;
        }

        const destination = getRedirectPath();
        // Check MFA and redirect appropriately
        await checkMfaAndRedirect(destination);
        setIsSubmitting(false);
      } catch (err) {
        setIsSubmitting(false);
        setMessage({
          type: 'error',
          text: err instanceof Error ? err.message : t.pages.auth.login.errors.genericError,
        });
        // Reset captcha token so user can retry with fresh token
        setCaptchaToken(null);
        turnstileRef.current?.reset();
      }

      /* NOTE: OTP login path preserved for future MFA implementation
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
            captchaToken: usedCaptchaToken,
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

        _setLoginType('phone');
        _setStep('otp');
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
      */
    }
  };

  const _handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
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

    // Require captcha token before OAuth
    if (!captchaToken) {
      setMessage({ type: 'error', text: t.pages.auth.login.errors.completeCaptcha });
      return;
    }

    // Consume the captcha token (verification happened, now proceed with OAuth)
    setCaptchaToken(null);
    await performGoogleSignIn();
  };

  const buttonDisabled = isSubmitting || isOAuthRedirecting || !captchaToken;

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-xs">
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
          <form className="space-y-6" noValidate onSubmit={handleSignIn}>
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
                </FieldLabel>
                <PasswordInput
                  id="password"
                  name="password"
                  placeholder={t.pages.auth.login.passwordPlaceholder}
                  autoComplete="current-password"
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
                  setMessage({ type: 'error', text: t.pages.auth.login.errors.captchaFailed });
                }}
                onExpire={() => {
                  setCaptchaToken(null);
                  setMessage({ type: 'error', text: t.pages.auth.login.errors.captchaExpired });
                }}
              />
            </div>

            <Button
              type="submit"
              disabled={buttonDisabled}
              loading={isSubmitting}
              size="lg"
              className="w-full"
            >
              {t.pages.auth.login.submitButton}
            </Button>
          </form>
        )}

        {/* NOTE: OTP Verification step preserved for future MFA implementation
        {step === 'otp' && (
          <form className="space-y-6" noValidate onSubmit={_handleVerifyOtp}>
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
                  _setOtp(value);
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
                _setStep('input');
                _setOtp('');
                resetMessage();
                resetFieldErrors();
              }}
              className="w-full"
            >
              {t.pages.auth.login.backToLogin}
            </Button>
          </form>
        )}
        */}

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
                loading={isOAuthRedirecting}
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
    </div>
  );
}
