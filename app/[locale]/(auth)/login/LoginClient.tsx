'use client';

import Link from 'next/link';
import Image from 'next/image';
import dynamic from 'next/dynamic';
import { FormEvent, useState, use, useRef, useEffect } from 'react';
import { motion, AnimatePresence, useReducedMotion } from 'motion/react';
import { useTranslations } from '@/lib/i18n/client';
import { isNativePlatform } from '@/lib/capacitor/platform';
import { turnstileLanguages, locales, LOCALE_COOKIE, type Locale } from '@/lib/i18n/config';

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

// Reduced motion variant (no y-transform)
const reducedMotionVariants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
};

import { supabase } from '@/lib/supabase/browser';
import { translateError } from '@/lib/errors/translate';
import { performOAuthSignIn } from '@/lib/capacitor/oauth';
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
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/app/Card';
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from '@/components/app/TurnstileCaptcha';
import { InputOTP, InputOTPGroup, InputOTPSlot, InputOTPSeparator } from '@/components/app/InputOTP';
import { LocaleSwitcher } from '@/components/app/LocaleSwitcher';

// Lazy load OAuth icon SVGs
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
  const shouldReduceMotion = useReducedMotion();
  const getRedirectPath = () => initialNext;

  const [emailOrPhone, setEmailOrPhone] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [step, setStep] = useState<LoginStep>('input');
  const [_loginType, setLoginType] = useState<'email' | 'phone' | null>(null);
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [oauthProvider, setOauthProvider] = useState<'google' | 'apple' | null>(null);
  const [showSignupPrompt, setShowSignupPrompt] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [showEmailLogin, setShowEmailLogin] = useState(false);

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

  // Listen for Capacitor Browser close events to reset OAuth state
  // This handles when user cancels Apple/Google sign-in (e.g., fails Face ID)
  useEffect(() => {
    if (!isNativePlatform()) return;

    let cleanup: (() => void) | undefined;

    const setupListener = async () => {
      const { Browser } = await import('@capacitor/browser');
      const handle = await Browser.addListener('browserFinished', () => {
        // Browser was closed - reset OAuth state so user can try again
        setOauthProvider(null);
        setMessage(null);
      });
      cleanup = () => handle.remove();
    };

    setupListener();

    return () => {
      cleanup?.();
    };
  }, []);

  // Apply user's locale preference from metadata by setting the locale cookie
  // If user doesn't have a locale preference saved, save the current locale to their metadata
  const applyUserLocalePreference = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    const userLocale = user?.user_metadata?.locale;

    console.log('[LOCALE] applyUserLocalePreference:', {
      userMetadata: user?.user_metadata,
      userLocale,
      currentPageLocale: locale,
    });

    if (userLocale && locales.includes(userLocale as Locale)) {
      // User has a saved locale preference - apply it
      document.cookie = `${LOCALE_COOKIE}=${userLocale}; path=/; max-age=${60 * 60 * 24 * 365}; samesite=lax`;
      return userLocale as Locale;
    }

    // User doesn't have a locale preference - save the current locale to their metadata
    // This handles existing users who signed up before locale tracking was added
    if (user) {
      supabase.auth.updateUser({
        data: { locale }
      }).catch((error) => {
        console.error('Failed to save user locale metadata:', error);
      });
    }

    return null;
  };

  // Check if user needs MFA verification and redirect accordingly
  const checkMfaAndRedirect = async (destination: string) => {
    // Apply user's locale preference before redirecting
    const userLocale = await applyUserLocalePreference();

    const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    // Determine which locale to use in the redirect URL
    const targetLocale = userLocale || locale;

    // Build the final destination with proper locale prefix
    const localePattern = new RegExp(`^/(${locales.join('|')})(/|$)`);
    const hasLocalePrefix = localePattern.test(destination);
    let finalDestination: string;

    if (hasLocalePrefix) {
      // Replace existing locale prefix with user's preferred locale
      finalDestination = destination.replace(
        new RegExp(`^/(${locales.join('|')})`),
        `/${targetLocale}`
      );
    } else {
      // No locale prefix - prepend user's preferred locale
      finalDestination = `/${targetLocale}${destination}`;
    }

    if (aalData && aalData.currentLevel === 'aal1' && aalData.nextLevel === 'aal2') {
      // User has MFA enrolled but hasn't verified - redirect to MFA verify
      const mfaUrl = `/${targetLocale}/mfa-verify?next=${encodeURIComponent(finalDestination)}`;
      window.location.href = mfaUrl;
    } else {
      // No MFA required or already verified
      window.location.href = finalDestination;
    }
  };

  const performGoogleSignIn = async () => {
    setOauthProvider('google');

    const redirectPath = getRedirectPath();

    const result = await performOAuthSignIn(supabase, 'google', {
      redirectPath,
      queryParams: { access_type: 'offline' },
    });

    if (!result.success) {
      setOauthProvider(null);
      setMessage({
        type: 'error',
        text: result.error
          ? translateError(result.error.message)
          : t.pages.auth.login.errors.googleSignInFailed,
      });
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
      // Password is optional for phone - will use OTP if not provided
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
      // Phone login - use password if provided, otherwise OTP
      if (password) {
        // Phone login with password
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
      } else {
        // Phone login with OTP
        setIsSubmitting(true);
        setMessage(null);

        try {
          const phoneE164 = normalizePhoneToE164(emailOrPhone);

          // Send OTP with shouldCreateUser: false (don't create user if doesn't exist)
          const { error } = await supabase.auth.signInWithOtp({
            phone: phoneE164,
            options: {
              shouldCreateUser: false,
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
            // Reset captcha token so user can retry with fresh token
            setCaptchaToken(null);
            turnstileRef.current?.reset();
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
          // Reset captcha token so user can retry with fresh token
          setCaptchaToken(null);
          turnstileRef.current?.reset();
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
      // Check MFA and redirect appropriately
      await checkMfaAndRedirect(destination);
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
    await performGoogleSignIn();
  };

  const performAppleSignIn = async () => {
    setOauthProvider('apple');

    const redirectPath = getRedirectPath();

    const result = await performOAuthSignIn(supabase, 'apple', {
      redirectPath,
    });

    if (!result.success) {
      setOauthProvider(null);
      setMessage({
        type: 'error',
        text: result.error
          ? translateError(result.error.message)
          : t.pages.auth.login.errors.appleSignInFailed,
      });
      return;
    }

    setMessage({
      type: 'success',
      text: t.pages.auth.login.waitingForApple,
    });
  };

  const handleAppleSignIn = async () => {
    setMessage(null);
    await performAppleSignIn();
  };

  const isOAuthRedirecting = oauthProvider !== null;
  const oauthButtonDisabled = isSubmitting || isOAuthRedirecting;
  const formButtonDisabled = isSubmitting || isOAuthRedirecting || !captchaToken;

  return (
    <motion.div
      className="relative w-full"
      variants={shouldReduceMotion ? reducedMotionVariants : cardVariants}
      initial="hidden"
      animate="visible"
    >
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-xs"
          role="button"
          tabIndex={0}
          onClick={() => {
            setOauthProvider(null);
            setMessage(null);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') {
              setOauthProvider(null);
              setMessage(null);
            }
          }}
        >
          <Card className="max-w-sm shadow-lg" onClick={(e) => e.stopPropagation()}>
            <CardContent className="pt-6">
              <div className="flex flex-col items-center gap-4">
                <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-primary"></div>
                <p className="text-lg font-semibold">
                  {oauthProvider === 'apple'
                    ? t.pages.auth.login.waitingForApple
                    : t.pages.auth.login.waitingForGoogle}
                </p>
                <button
                  type="button"
                  onClick={() => {
                    setOauthProvider(null);
                    setMessage(null);
                  }}
                  className="text-sm text-text-muted hover:text-text-primary transition-colors"
                >
                  {t.common.cancel}
                </button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card className="w-full max-w-md shadow-lg">
        <CardHeader>
          {/* Title and Logo inline */}
          <div className="flex items-center justify-between mb-1">
            <CardTitle className="text-2xl font-bold">{t.pages.auth.login.title}</CardTitle>
            <Image
              src="/icons/short-logo-gradient.svg"
              alt="Tidex"
              width={32}
              height={32}
              priority
            />
          </div>
          {step === 'otp' ? (
            <CardDescription>
              {t.pages.auth.login.otpDescription.replace('{phone}', emailOrPhone)}
            </CardDescription>
          ) : (
            <CardDescription>{t.pages.auth.login.subtitle}</CardDescription>
          )}
        </CardHeader>

        <CardContent>
          {/* Step 1: Email/Phone and Password Input */}
          {step === 'input' && (
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
                  <Image
                    src="/icons/apple.svg"
                    alt=""
                    width={20}
                    height={20}
                    className="dark:invert"
                  />
                  Apple
                </Button>
              </div>

              <FieldSeparator>{t.pages.auth.login.separator}</FieldSeparator>

              <AnimatePresence mode="wait">
                {!showEmailLogin ? (
                  <motion.div
                    key="reveal-button"
                    initial={{ opacity: 0, y: -10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -10 }}
                    transition={{ duration: 0.2 }}
                    className="mt-6"
                  >
                    <Button
                      type="button"
                      variant="outline"
                      size="lg"
                      onClick={() => setShowEmailLogin(true)}
                      className="w-full"
                    >
                      {t.pages.auth.login.emailOrPhoneReveal}
                    </Button>
                  </motion.div>
                ) : (
                  <motion.form
                    key="login-form"
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 10 }}
                    transition={{ duration: 0.2 }}
                    className="space-y-4 mt-6"
                    noValidate
                    onSubmit={handleSignIn}
                  >
                    <FieldGroup>
                      <Field data-invalid={!!fieldErrors.emailOrPhone}>
                        <FieldLabel htmlFor="emailOrPhone">{t.pages.auth.login.usernameLabel}</FieldLabel>
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
                        <div className="flex items-center justify-between">
                          <FieldLabel htmlFor="password">
                            {t.pages.auth.login.passwordLabel}
                          </FieldLabel>
                          <Link
                            href={`/${locale}/reset-password`}
                            className="text-sm text-text-muted hover:text-text-primary transition-colors"
                          >
                            {t.pages.auth.login.forgotPassword}
                          </Link>
                        </div>
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
                        language={turnstileLanguages[locale as Locale]}
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

                    {message && (
                      <div
                        className={`rounded-lg px-4 py-3 text-sm font-medium ${
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
                    {showSignupPrompt && (
                      <div className="flex justify-center animate-bounce">
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

                    <Button
                      type="submit"
                      disabled={formButtonDisabled}
                      loading={isSubmitting}
                      size="lg"
                      className="w-full"
                    >
                      {t.pages.auth.login.submitButton}
                    </Button>
                  </motion.form>
                )}
              </AnimatePresence>
            </>
          )}

          {/* OTP Verification step for phone login */}
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

              {message && (
                <div
                  className={`rounded-lg px-4 py-3 text-sm font-medium ${
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

              <Button
                type="submit"
                disabled={isSubmitting || isOAuthRedirecting}
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
        </CardContent>

        {/* Footer with create account link */}
        {step === 'input' && (
          <CardFooter className="flex-col border-t bg-surface-secondary rounded-b-3xl pt-6">
            <p className="text-sm text-text-secondary">
              {t.pages.auth.login.noAccount}{' '}
              <Link
                href={`/${locale}/signup${emailOrPhone ? `?email=${encodeURIComponent(emailOrPhone)}` : ''}`}
                className="font-semibold text-text-primary hover:underline"
              >
                {t.pages.auth.login.createAccount}
              </Link>
            </p>
          </CardFooter>
        )}
      </Card>

      <div className="mt-6 flex justify-center">
        <LocaleSwitcher />
      </div>
    </motion.div>
  );
}
