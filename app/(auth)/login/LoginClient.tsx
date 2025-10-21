'use client';

import Link from 'next/link';
import { FormEvent, useState } from 'react';

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

const googleIcon = (
  <svg
    className="h-4 w-4"
    viewBox="0 0 533.5 544.3"
    aria-hidden
    focusable="false"
  >
    <path
      d="M533.5 278.4c0-18.5-1.5-37-4.7-55H272.1v104h146.9c-6.3 33.9-25.5 62.6-54.3 81.9v68.2h87.8c51.4-47.4 81-117.5 81-199.1z"
      fill="#4285f4"
    />
    <path
      d="M272.1 544.3c73.5 0 135.3-24.3 180.4-66.1l-87.8-68.2c-24.3 16.3-55.4 25.8-92.6 25.8-71 0-131.2-47.9-152.6-112.2H28.7v70.5c45.4 90.1 138.5 150.2 243.4 150.2z"
      fill="#34a853"
    />
    <path
      d="M119.5 323.6c-10.7-31.8-10.7-66.4 0-98.2V154.9H28.7c-41.4 82.6-41.4 180.7 0 263.3l90.8-70.6z"
      fill="#fbbc04"
    />
    <path
      d="M272.1 107.7c38.9-.6 76.2 14.7 104.2 42.4l77.6-77.6C406.7 27.4 344.4.1 272.1 0 167.2 0 74.1 60.1 28.7 150.1l90.8 70.5c21.4-64.2 81.6-112.2 152.6-112.2z"
      fill="#ea4335"
    />
  </svg>
);

type MessageState = { type: 'error' | 'success'; text: string } | null;
type LoginStep = 'input' | 'otp';
type FieldErrors = {
  emailOrPhone?: string;
  password?: string;
  otp?: string;
};

export default function LoginClient({ initialNext }: { initialNext: string }) {
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

  const resetMessage = () => {
    setMessage(null);
    setShowSignupPrompt(false);
  };

  const resetFieldErrors = () => {
    setFieldErrors({});
  };

  const resetAll = () => {
    resetMessage();
    resetFieldErrors();
  };

  const handleSignIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (!emailOrPhone) {
      errors.emailOrPhone = 'Fyll inn e-post eller telefonnummer.';
    }

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === 'unknown') {
      errors.emailOrPhone = 'Ugyldig e-post eller telefonnummer. Telefonnummer må være 8 siffer.';
    }

    if (inputType === 'email') {
      // Email login requires password
      if (!password) {
        errors.password = 'Fyll inn passord.';
      }

      if (emailOrPhone && !isValidEmail(emailOrPhone)) {
        errors.emailOrPhone = 'Ugyldig e-postformat.';
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
        errors.emailOrPhone = 'Telefonnummer må være 8 siffer.';
      }

      if (phoneLoginMethod === 'password' && !password) {
        errors.password = 'Fyll inn passord.';
      }

      if (Object.keys(errors).length > 0) {
        setFieldErrors(errors);
        return;
      }

      if (phoneLoginMethod === 'password') {
        // Phone login with password

        setIsSubmitting(true);
        setMessage(null);

        try {
          const phoneE164 = normalizePhoneToE164(emailOrPhone);
          const { error } = await supabase.auth.signInWithPassword({
            phone: phoneE164,
            password,
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
            text: err instanceof Error ? err.message : 'En feil oppstod',
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
                text: 'Du må registrere deg før du kan logge inn.',
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
            text: 'SMS-kode sendt! Sjekk meldingene dine.',
          });
        } catch (err) {
          setIsSubmitting(false);
          setMessage({
            type: 'error',
            text: err instanceof Error ? err.message : 'En feil oppstod',
          });
        }
      }
    }
  };

  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = 'Fyll inn alle 6 sifrene.';
    }

    if (!isValidNorwegianPhone(emailOrPhone)) {
      errors.otp = 'Ugyldig telefonnummer.';
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

      setMessage({ type: 'success', text: 'Logger inn...' });
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
    setIsOAuthRedirecting(true);
    setMessage(null);

    const redirectPath = getRedirectPath();
    // Build redirect URL dynamically based on configured site URL, but tolerate misconfiguration.
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
        text: 'Kunne ikke starte Google-innlogging. Prøv igjen senere.',
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
      text: 'Venter på Google...',
    });
  };

  const detectedInputType = detectInputType(emailOrPhone);
  const isPhoneInput = detectedInputType === 'phone';
  const buttonDisabled = isSubmitting || isOAuthRedirecting;

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <Card className="max-w-sm shadow-lg">
            <CardContent className="pt-6">
              <div className="flex flex-col items-center gap-4">
                <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-primary"></div>
                <p className="text-lg font-semibold">Venter på Google...</p>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Hei, du!</CardTitle>
          {step === 'otp' && (
            <CardDescription>
              Skriv inn koden vi sendte til {emailOrPhone}
            </CardDescription>
          )}
        </CardHeader>

        <CardContent>

        {/* Step 1: Email/Phone and Password Input */}
        {step === 'input' && (
          <form className="space-y-6" noValidate onSubmit={handleSignIn}>
            <FieldGroup>
              <Field data-invalid={!!fieldErrors.emailOrPhone}>
                <FieldLabel htmlFor="emailOrPhone">E-post eller telefonnummer</FieldLabel>
                <Input
                  id="emailOrPhone"
                  name="emailOrPhone"
                  type="text"
                  placeholder="E-post eller telefonnummer"
                  // Microsoft Editor browser extension injects these attributes before hydration; set them eagerly to avoid mismatches.
                  spellCheck={false}
                  data-ms-editor="true"
                  suppressHydrationWarning
                  autoComplete="username"
                  value={emailOrPhone}
                  onChange={(event) => {
                    resetAll();
                    setEmailOrPhone(event.target.value);
                  }}
                  aria-invalid={!!fieldErrors.emailOrPhone}
                />
                <FieldError>{fieldErrors.emailOrPhone}</FieldError>
              </Field>

              <Field data-invalid={!!fieldErrors.password}>
                <FieldLabel htmlFor="password">
                  Passord
                  {isPhoneInput && (
                    <span className="text-sm text-muted-foreground font-normal ml-2">(valgfritt)</span>
                  )}
                </FieldLabel>
                <Input
                  id="password"
                  name="password"
                  type="password"
                  placeholder="Passord"
                  autoComplete="current-password"
                  value={password}
                  onChange={(event) => {
                    resetAll();
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
              loading={isSubmitting}
              size="lg"
              className="w-full"
            >
              {isPhoneInput && phoneLoginMethod === 'otp' ? 'Send kode' : 'Logg inn'}
            </Button>

            {/* Show "Engangskode" button for phone users with password */}
            {emailOrPhone &&
              isPhoneInput &&
              phoneLoginMethod === 'password' && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setPhoneLoginMethod('otp');
                    setPassword('');
                    resetAll();
                  }}
                  className="w-full"
                >
                  Bruk engangskode i stedet →
                </Button>
              )}
          </form>
        )}

        {/* Step 2: OTP Verification (for phone login) */}
        {step === 'otp' && (
          <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
            <Field data-invalid={!!fieldErrors.otp} className="items-center">
              <FieldLabel htmlFor="otp" className="sr-only">
                Engangskode mottatt via SMS
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
              disabled={buttonDisabled}
              loading={isSubmitting}
              size="lg"
              className="w-full"
            >
              Verifiser kode
            </Button>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                setStep('input');
                setOtp('');
                resetAll();
              }}
              className="w-full"
            >
              ← Tilbake til innlogging
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
              <FieldSeparator>Eller</FieldSeparator>
            </div>

            <div className="space-y-3">
              <Button
                asChild
                variant={showSignupPrompt ? 'default' : 'outline'}
                size="lg"
                className={`w-full ${showSignupPrompt ? 'ring-2 ring-ring ring-offset-2' : ''}`}
              >
                <Link href="/signup">
                  Opprett ny konto
                </Link>
              </Button>

              <Button
                type="button"
                variant="outline"
                size="lg"
                onClick={handleGoogleSignIn}
                disabled={buttonDisabled}
                loading={isOAuthRedirecting}
                aria-label="Fortsett med Google"
                className="w-full"
              >
                <span className="flex h-5 w-5 items-center justify-center">
                  {googleIcon}
                </span>
                Fortsett med Google
              </Button>
            </div>

            <div className="mt-6 text-center">
              <Button
                asChild
                variant="link"
                size="sm"
              >
                <Link href="/reset-password">
                  Tilbakestill passord
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
