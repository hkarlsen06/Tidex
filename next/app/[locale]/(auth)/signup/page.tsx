"use client";

import Link from "next/link";
import Image from "next/image";
import dynamic from "next/dynamic";
import { useRouter, useSearchParams } from "next/navigation";
import { FormEvent, useState, use, useRef, useEffect } from "react";
import { motion, useReducedMotion } from "motion/react";
import { useTranslations } from "@/lib/i18n/client";
import { turnstileLanguages, type Locale } from "@/lib/i18n/config";

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

import { supabase } from "@/lib/supabase/browser";
import { performOAuthSignIn } from "@/lib/auth/oauth";
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
} from "@/components/app/Field";
import { Input } from "@/components/app/Input";
import { PasswordInput } from "@/components/app/PasswordInput";
import { Button } from "@/components/app/Button";
import { TurnstileCaptcha, type TurnstileCaptchaHandle } from "@/components/app/TurnstileCaptcha";
import { Checkbox } from "@/components/app/Checkbox";
import { LegalModal } from "@/components/legal";
import { translateError } from "@/lib/errors/translate";
import { LocaleSwitcher } from "@/components/app/LocaleSwitcher";
import { AuthHeader } from "@/components/app/AuthHeader";
import { GroupedInput, GroupedInputDivider, groupedInputClassName } from "@/components/app/GroupedInput";
import { showAuthSuccessToast } from "@/lib/ui/auth-toast";

// Lazy load OAuth icon SVGs
const GoogleIcon = dynamic(() => import("../login/GoogleIcon"), {
  ssr: false,
  loading: () => <div className="h-4 w-4" />
});

type MessageState = { type: "error"; text: string } | null;
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
  const shouldReduceMotion = useReducedMotion();

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

    const result = await performOAuthSignIn(supabase, 'google', {
      redirectPath: '/onboarding',
      queryParams: { access_type: 'offline' },
    });

    if (!result.success) {
      setOauthProvider(null);
      const errorMessage = result.error?.message || '';
      if (errorMessage.includes('cancel') || errorMessage.includes('Cancel')) {
        return;
      }
      setMessage({
        type: 'error',
        text: result.error
          ? translateError(result.error.message)
          : t.pages.auth.login.errors.googleSignInFailed,
      });
      setCaptchaToken(null);
      turnstileRef.current?.reset();
      return;
    }

    showAuthSuccessToast(t.pages.auth.login.waitingForGoogle);
  };

  const handleGoogleSignIn = async () => {
    setMessage(null);
    if (!agreedToTerms) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.acceptTerms });
      return;
    }
    await performGoogleSignIn();
  };

  const performAppleSignIn = async () => {
    setOauthProvider('apple');

    const result = await performOAuthSignIn(supabase, 'apple', {
      redirectPath: '/onboarding',
    });

    if (!result.success) {
      setOauthProvider(null);
      const errorMessage = result.error?.message || '';
      if (errorMessage.includes('cancel') || errorMessage.includes('Cancel')) {
        return;
      }
      setMessage({
        type: 'error',
        text: result.error
          ? translateError(result.error.message)
          : t.pages.auth.login.errors.appleSignInFailed,
      });
      setCaptchaToken(null);
      turnstileRef.current?.reset();
      return;
    }

    showAuthSuccessToast(t.pages.auth.login.waitingForApple);
  };

  const handleAppleSignIn = async () => {
    setMessage(null);
    if (!agreedToTerms) {
      setMessage({ type: 'error', text: t.pages.auth.signup.errors.acceptTerms });
      return;
    }
    await performAppleSignIn();
  };

  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetMessage();
    resetFieldErrors();

    const errors: FieldErrors = {};

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

    if (inputType === "email") {
      if (!password) errors.password = t.pages.auth.signup.errors.fillPassword;
      if (password && password.length < 6) errors.password = t.pages.auth.signup.errors.passwordTooShort;
      if (emailOrPhone && !isValidEmail(emailOrPhone)) errors.emailOrPhone = t.pages.auth.signup.errors.invalidEmail;
    } else if (inputType === "phone") {
      if (!isValidNorwegianPhone(emailOrPhone)) errors.emailOrPhone = t.pages.auth.signup.errors.invalidPhone;
      if (!password) errors.password = t.pages.auth.signup.errors.fillPassword;
      if (password && password.length < 6) errors.password = t.pages.auth.signup.errors.passwordTooShort;
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

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
          data: { full_name: fullName, locale, terms_accepted_at: new Date().toISOString() },
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/onboarding`,
          captchaToken,
        },
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        setCaptchaToken(null);
        turnstileRef.current?.reset();
        return;
      }

      setMessage(null);
      showAuthSuccessToast(t.pages.auth.signup.success.accountCreated);

      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: emailOrPhone,
        password,
      });

      if (signInError) {
        setMessage({ type: "error", text: signInError.message });
        setCaptchaToken(null);
        turnstileRef.current?.reset();
        return;
      }

      setTimeout(() => {
        router.replace(`/${locale}/onboarding`);
        router.refresh();
      }, 1000);
    } else {
      setIsSubmitting(true);

      try {
        const phoneE164 = normalizePhoneToE164(emailOrPhone);

        const { error } = await supabase.auth.signUp({
          phone: phoneE164,
          password,
          options: {
            data: { full_name: fullName, locale, terms_accepted_at: new Date().toISOString() },
            captchaToken,
          },
        });

        setIsSubmitting(false);

        if (error) {
          if (error.message.includes("already registered") || error.message.includes("already exists") || error.message.includes("User already registered")) {
            setMessage({ type: "error", text: t.pages.auth.signup.errors.phoneAlreadyExists });
          } else {
            setMessage({ type: "error", text: error.message });
          }
          setCaptchaToken(null);
          turnstileRef.current?.reset();
          return;
        }

        setStep("otp");
        setMessage(null);
        showAuthSuccessToast(t.pages.auth.signup.success.smsSent);
      } catch (err) {
        setIsSubmitting(false);
        setMessage({
          type: "error",
          text: err instanceof Error ? err.message : t.pages.auth.signup.errors.genericError,
        });
        setCaptchaToken(null);
        turnstileRef.current?.reset();
      }
    }
  };

  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};
    if (otp.length !== 6) errors.otp = t.pages.auth.signup.errors.fillAllDigits;
    if (!isValidNorwegianPhone(emailOrPhone)) errors.otp = t.pages.auth.signup.errors.invalidPhoneNumber;

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    try {
      const phoneE164 = normalizePhoneToE164(emailOrPhone);
      const { error } = await supabase.auth.verifyOtp({ phone: phoneE164, token: otp, type: "sms" });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        return;
      }

      setMessage(null);
      showAuthSuccessToast(t.pages.auth.signup.success.accountCreated);

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
  const oauthButtonDisabled = isSubmitting || isOAuthRedirecting;
  const submitButtonDisabled = isSubmitting || isOAuthRedirecting || !captchaToken || !agreedToTerms;

  return (
    <motion.div
      className="relative w-full max-w-md mx-auto"
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
          onClick={() => { setOauthProvider(null); setMessage(null); }}
          onKeyDown={(e) => {
            if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') { setOauthProvider(null); setMessage(null); }
          }}
        >
          <div role="presentation" className="bg-surface-primary rounded-xl shadow-lg max-w-sm p-6" onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
            <div className="flex flex-col items-center gap-4">
              <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-brand-gradient-start"></div>
              <p className="text-lg font-semibold">
                {oauthProvider === 'apple' ? t.pages.auth.login.waitingForApple : t.pages.auth.login.waitingForGoogle}
              </p>
              <button
                type="button"
                onClick={() => { setOauthProvider(null); setMessage(null); }}
                className="text-sm text-text-muted hover:text-text-primary transition-colors"
              >
                {t.common.cancel}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Header */}
      <AuthHeader
        variant="wordmark"
        subtitle={step === "otp"
          ? t.pages.auth.signup.descriptionOtp.replace('{phone}', emailOrPhone)
          : t.pages.auth.signup.subtitle}
      />

      <div className="space-y-6">
        {step === "input" && (
          <>
            {/* OAuth Buttons */}
            <div className="flex flex-col gap-3">
              <button
                type="button"
                onClick={handleAppleSignIn}
                disabled={oauthButtonDisabled}
                aria-label={t.pages.auth.login.continueWithApple}
                className="w-full h-12.5 rounded-xl bg-white text-black font-medium flex items-center justify-center gap-3 border border-border dark:border-transparent hover:bg-white/90 active:scale-[0.98] transition-all disabled:opacity-60"
              >
                <Image src="/icons/apple.svg" alt="" width={20} height={20} />
                Apple
              </button>
              <button
                type="button"
                onClick={handleGoogleSignIn}
                disabled={oauthButtonDisabled}
                aria-label={t.pages.auth.login.continueWithGoogle}
                className="w-full h-12.5 rounded-xl bg-white text-black font-medium flex items-center justify-center gap-3 border border-border dark:border-transparent hover:bg-white/90 active:scale-[0.98] transition-all disabled:opacity-60"
              >
                <span className="flex h-5 w-5 items-center justify-center"><GoogleIcon /></span>
                Google
              </button>
            </div>

            {/* "or" divider */}
            <div className="flex items-center gap-4 my-2">
              <div className="h-px flex-1 bg-border-subtle" />
              <span className="text-sm text-text-muted">{t.pages.auth.login.separator}</span>
              <div className="h-px flex-1 bg-border-subtle" />
            </div>

            <form ref={formRef} className="space-y-4" noValidate onSubmit={handleSignUp}>
              {/* Name fields side by side */}
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-surface-primary rounded-xl overflow-hidden">
                  <Input
                    id="firstName"
                    name="firstName"
                    type="text"
                    placeholder={t.pages.auth.signup.firstNameLabel}
                    value={firstName}
                    onChange={(e) => { resetMessage(); resetFieldErrors(); setFirstName(e.target.value); }}
                    aria-invalid={!!fieldErrors.firstName}
                    className={groupedInputClassName}
                  />
                </div>
                <div className="bg-surface-primary rounded-xl overflow-hidden">
                  <Input
                    id="lastName"
                    name="lastName"
                    type="text"
                    placeholder={t.pages.auth.signup.lastNameLabel}
                    value={lastName}
                    onChange={(e) => { resetMessage(); resetFieldErrors(); setLastName(e.target.value); }}
                    aria-invalid={!!fieldErrors.lastName}
                    className={groupedInputClassName}
                  />
                </div>
              </div>
              {fieldErrors.firstName && <p className="text-xs text-error px-1">{fieldErrors.firstName}</p>}
              {fieldErrors.lastName && <p className="text-xs text-error px-1">{fieldErrors.lastName}</p>}

              {/* Grouped email + password */}
              <GroupedInput>
                <Input
                  id="emailOrPhone"
                  name="emailOrPhone"
                  type="text"
                  placeholder={t.pages.auth.signup.usernameLabel}
                  value={emailOrPhone}
                  onChange={(e) => { resetMessage(); resetFieldErrors(); setEmailOrPhone(e.target.value); }}
                  aria-invalid={!!fieldErrors.emailOrPhone}
                  className={groupedInputClassName}
                />
                <GroupedInputDivider />
                <PasswordInput
                  id="password"
                  name="password"
                  placeholder={t.pages.auth.signup.passwordLabel}
                  value={password}
                  onChange={(e) => { resetMessage(); resetFieldErrors(); setPassword(e.target.value); }}
                  invalid={!!fieldErrors.password}
                  className={groupedInputClassName}
                />
              </GroupedInput>
              {fieldErrors.emailOrPhone && <p className="text-xs text-error px-1">{fieldErrors.emailOrPhone}</p>}
              {fieldErrors.password && <p className="text-xs text-error px-1">{fieldErrors.password}</p>}

              {/* Terms checkbox */}
              <div className="bg-surface-primary/50 rounded-xl p-4 flex items-center gap-3">
                <Checkbox
                  id="terms"
                  checked={agreedToTerms}
                  onCheckedChange={(checked) => {
                    if (checked) { setLegalModalOpen(true); } else { setAgreedToTerms(false); }
                  }}
                  className="h-6 w-6"
                />
                <label htmlFor="terms" className="text-sm text-text-secondary leading-relaxed cursor-pointer select-none">
                  {t.pages.auth.signup.termsAgreement}{" "}
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); setLegalModalOpen(true); }}
                    className="text-brand-gradient-start hover:underline font-medium"
                  >
                    {t.pages.auth.signup.termsLink}
                  </button>
                </label>
              </div>

              {/* Turnstile CAPTCHA */}
              <div className="flex justify-center">
                <TurnstileCaptcha
                  ref={turnstileRef}
                  execution="render"
                  appearance="always"
                  size="flexible"
                  language={turnstileLanguages[locale as Locale]}
                  onSuccess={(token) => { setCaptchaToken(token); resetMessage(); }}
                  onError={() => { setCaptchaToken(null); setMessage({ type: "error", text: t.pages.auth.signup.errors.captchaFailed }); }}
                  onExpire={() => { setCaptchaToken(null); setMessage({ type: "error", text: t.pages.auth.signup.errors.captchaExpired }); }}
                />
              </div>

              {message?.type === "error" && (
                <div
                  className="rounded-lg px-4 py-3 text-sm font-medium bg-error-subtle text-error-foreground"
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
                className="w-full h-12 bg-brand-gradient-start text-white hover:bg-brand-gradient-start/90"
              >
                {t.pages.auth.signup.continueButton}
              </Button>
            </form>
          </>
        )}

        {/* OTP step */}
        {step === "otp" && (
          <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
            <Field data-invalid={!!fieldErrors.otp} className="items-center">
              <FieldLabel htmlFor="otp" className="sr-only">{t.pages.auth.signup.otpLabel}</FieldLabel>
              <InputOTP maxLength={6} value={otp} onChange={(value) => { resetAll(); setOtp(value); }}>
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
              {fieldErrors.otp && <FieldError className="text-center">{fieldErrors.otp}</FieldError>}
            </Field>

            {message?.type === "error" && (
              <div
                className="rounded-lg px-4 py-3 text-sm font-medium bg-error-subtle text-error-foreground"
                role="status"
                aria-live="polite"
              >
                {message.text}
              </div>
            )}

            <Button type="submit" disabled={isSubmitting} loading={isSubmitting} size="lg" className="w-full h-12 bg-brand-gradient-start text-white hover:bg-brand-gradient-start/90">
              {t.pages.auth.signup.verifyButton}
            </Button>
            <Button type="button" variant="ghost" size="sm" onClick={() => { setStep("input"); setOtp(""); resetAll(); }} className="w-full">
              {t.pages.auth.signup.backButton}
            </Button>
          </form>
        )}
      </div>

      {/* Footer */}
      {step === "input" && (
        <div className="mt-10 text-center">
          <p className="text-sm text-text-secondary">
            {t.pages.auth.signup.haveAccount}{' '}
            <Link href={`/${locale}/login`} className="font-semibold text-brand-gradient-start hover:underline">
              {t.pages.auth.signup.signIn}
            </Link>
          </p>
        </div>
      )}

      <div className="mt-6 flex justify-center">
        <LocaleSwitcher />
      </div>

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
