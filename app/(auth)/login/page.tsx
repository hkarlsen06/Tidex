"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { translateError } from "@/lib/errors/translate";
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

type MessageState = { type: "error" | "success"; text: string } | null;
type LoginStep = "input" | "otp";

export default function LoginPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<LoginStep>("input");
  const [loginType, setLoginType] = useState<"email" | "phone" | null>(null);
  const [phoneLoginMethod, setPhoneLoginMethod] = useState<"otp" | "password">("otp");
  const [message, setMessage] = useState<MessageState>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isOAuthRedirecting, setIsOAuthRedirecting] = useState(false);
  const [showSignupPrompt, setShowSignupPrompt] = useState(false);

  const resetMessage = () => {
    setMessage(null);
    setShowSignupPrompt(false);
  };

  const handleSignIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!emailOrPhone) {
      setMessage({
        type: "error",
        text: "Fyll inn e-post eller telefonnummer.",
      });
      return;
    }

    const inputType = detectInputType(emailOrPhone);

    if (inputType === "unknown") {
      setMessage({
        type: "error",
        text: "Ugyldig e-post eller telefonnummer. Telefonnummer må være 8 siffer.",
      });
      return;
    }

    if (inputType === "email") {
      // Email login requires password
      if (!password) {
        setMessage({ type: "error", text: "Fyll inn passord." });
        return;
      }

      if (!isValidEmail(emailOrPhone)) {
        setMessage({ type: "error", text: "Ugyldig e-postformat." });
        return;
      }

      setIsSubmitting(true);
      setMessage(null);

      const { data, error } = await supabase.auth.signInWithPassword({
        email: emailOrPhone,
        password,
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: translateError(error.message) });
        return;
      }

      // Use full page navigation to ensure cookies are properly set
      window.location.href = "/";
    } else {
      // Phone login
      if (!isValidNorwegianPhone(emailOrPhone)) {
        setMessage({
          type: "error",
          text: "Telefonnummer må være 8 siffer.",
        });
        return;
      }

      if (phoneLoginMethod === "password") {
        // Phone login with password
        if (!password) {
          setMessage({ type: "error", text: "Fyll inn passord." });
          return;
        }

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
            setMessage({ type: "error", text: translateError(error.message) });
            return;
          }

          // Use full page navigation to ensure cookies are properly set
          window.location.href = "/";
        } catch (err) {
          setIsSubmitting(false);
          setMessage({
            type: "error",
            text: err instanceof Error ? err.message : "En feil oppstod",
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
              error.message.includes("User not found") ||
              error.message.includes("not found") ||
              error.message.includes("No user") ||
              error.message.includes("Signups not allowed")
            ) {
              setMessage({
                type: "error",
                text: "Du må registrere deg før du kan logge inn.",
              });
              setShowSignupPrompt(true);
            } else {
              setMessage({
                type: "error",
                text: translateError(error.message),
              });
            }
            return;
          }

          setLoginType("phone");
          setStep("otp");
          setMessage({
            type: "success",
            text: "SMS-kode sendt! Sjekk meldingene dine.",
          });
        } catch (err) {
          setIsSubmitting(false);
          setMessage({
            type: "error",
            text: err instanceof Error ? err.message : "En feil oppstod",
          });
        }
      }
    }
  };

  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (otp.length !== 6) {
      setMessage({ type: "error", text: "Fyll inn alle 6 sifrene." });
      return;
    }

    if (!isValidNorwegianPhone(emailOrPhone)) {
      setMessage({ type: "error", text: "Ugyldig telefonnummer." });
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
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

      setMessage({ type: "success", text: "Logger inn..." });
      // Use full page navigation to ensure cookies are properly set
      window.location.href = "/";
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "En feil oppstod",
      });
    }
  };

  const handleGoogleSignIn = async () => {
    setIsOAuthRedirecting(true);
    setMessage(null);

    // Build redirect URL dynamically based on current origin
    const redirectUrl = `${window.location.origin}/auth/callback`;

    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: redirectUrl,
        queryParams: {
          access_type: "offline",
          prompt: "consent",
        },
      },
    });

    if (error) {
      setIsOAuthRedirecting(false);
      setMessage({ type: "error", text: translateError(error.message) });
      return;
    }

    setMessage({
      type: "success",
      text: "Sender deg videre til Google...",
    });
  };

  const buttonDisabled = isSubmitting || isOAuthRedirecting;

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      {/* Full-screen loading overlay during OAuth redirect */}
      {isOAuthRedirecting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="rounded-3xl border border-border bg-surface-secondary p-8 shadow-app-lg">
            <div className="flex flex-col items-center gap-4">
              <div className="h-12 w-12 animate-spin rounded-full border-4 border-border border-t-brand-highlight"></div>
              <p className="text-lg font-semibold text-text-primary">Sender deg videre til Google...</p>
            </div>
          </div>
        </div>
      )}

      <section className="w-full max-w-md rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg backdrop-blur">
          <div className="mb-8 text-center">
            <h1 className="tracking-wide">Logg inn</h1>
            {step === "otp" && (
              <p className="mt-2 text-sm text-text-secondary">
                Skriv inn koden vi sendte til {emailOrPhone}
              </p>
            )}
          </div>

          {/* Step 1: Email/Phone and Password Input */}
          {step === "input" && (
            <form className="space-y-6" noValidate onSubmit={handleSignIn}>
              <div className="space-y-2">
                <label htmlFor="emailOrPhone">E-post eller telefonnummer</label>
                <input
                  id="emailOrPhone"
                  name="emailOrPhone"
                  type="text"
                  placeholder="E-post eller telefonnummer"
                  value={emailOrPhone}
                  onChange={(event) => {
                    resetMessage();
                    setEmailOrPhone(event.target.value);
                  }}
                  className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
                />
              </div>

              {/* Show password field for email OR phone with password option */}
              {emailOrPhone &&
                (detectInputType(emailOrPhone) === "email" ||
                  (detectInputType(emailOrPhone) === "phone" &&
                    phoneLoginMethod === "password")) && (
                  <div className="space-y-2">
                    <label htmlFor="password">Passord</label>
                    <input
                      id="password"
                      name="password"
                      type="password"
                      placeholder="Passord"
                      value={password}
                      onChange={(event) => {
                        resetMessage();
                        setPassword(event.target.value);
                      }}
                      className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
                    />
                  </div>
                )}

              <button
                type="submit"
                disabled={buttonDisabled}
                className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isSubmitting
                  ? detectInputType(emailOrPhone) === "phone" &&
                    phoneLoginMethod === "otp"
                    ? "Sender kode..."
                    : "Logger inn..."
                  : "Logg inn"}
              </button>

              {/* Show "Engangskode" button for phone users with password */}
              {emailOrPhone &&
                detectInputType(emailOrPhone) === "phone" &&
                phoneLoginMethod === "password" && (
                  <button
                    type="button"
                    onClick={() => {
                      setPhoneLoginMethod("otp");
                      setPassword("");
                      resetMessage();
                    }}
                    className="w-full text-sm text-text-secondary transition hover:text-text-primary"
                  >
                    Bruk engangskode i stedet →
                  </button>
                )}
            </form>
          )}

          {/* Step 2: OTP Verification (for phone login) */}
          {step === "otp" && (
            <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
              <div className="flex flex-col items-center space-y-4">
                <label htmlFor="otp" className="text-sm text-text-secondary">
                  6-sifret SMS-kode
                </label>
                <InputOTP
                  maxLength={6}
                  value={otp}
                  onChange={(value) => {
                    resetMessage();
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
              </div>

              <button
                type="submit"
                disabled={buttonDisabled}
                className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isSubmitting ? "Verifiserer..." : "Verifiser kode"}
              </button>

              <button
                type="button"
                onClick={() => {
                  setStep("input");
                  setOtp("");
                  resetMessage();
                }}
                className="w-full text-sm text-text-secondary transition hover:text-text-primary"
              >
                ← Tilbake til innlogging
              </button>
            </form>
          )}

          {message && (
            <div
              className={`mt-4 rounded-full px-5 py-3 text-sm font-medium ${
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

          {/* Arrow pointing to signup button */}
          {showSignupPrompt && step === "input" && (
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
          {step === "input" && (
            <>
              <div className={`space-y-3 ${showSignupPrompt ? "mt-2" : "mt-6"}`}>
                <Link
                  href="/signup"
                  className={`flex w-full items-center justify-center rounded-full px-5 py-3 text-sm font-semibold uppercase tracking-wide transition focus:outline-none focus:ring-4 focus:ring-offset-2 focus:ring-offset-surface-secondary ${
                    showSignupPrompt
                      ? "bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd text-text-inverse shadow-lg shadow-brand-gradientMid/40 hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:ring-brand-highlight/60 ring-4 ring-brand-highlight/40"
                      : "bg-surface-primary text-text-primary hover:bg-surface-primary/80 focus:ring-brand-highlight/40"
                  }`}
                >
                  Opprett ny konto
                </Link>
                <button
                  type="button"
                  onClick={handleGoogleSignIn}
                  disabled={buttonDisabled}
                  aria-label="Fortsett med Google"
                  className="flex w-full items-center justify-center gap-3 rounded-full bg-surface-primary px-5 py-3 text-sm font-semibold uppercase tracking-wide text-text-primary transition hover:bg-surface-primary/80 focus:outline-none focus:ring-4 focus:ring-brand-highlight/40 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <span className="flex h-6 w-6 items-center justify-center rounded-full bg-text-primary">
                    {googleIcon}
                  </span>
                  {isOAuthRedirecting ? "Videresender..." : "Fortsett med Google"}
                </button>
              </div>

              <div className="mt-8 text-center text-sm">
                <Link
                  href="/reset-password"
                  className="font-semibold text-brand-highlight transition hover:text-brand-highlight/80 focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
                >
                  Tilbakestill med kode
                </Link>
              </div>
            </>
          )}
      </section>
    </div>
  );
}
