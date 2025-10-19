"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

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

type MessageState = { type: "error" | "success"; text: string } | null;
type SignupStep = "input" | "otp";

export default function SignupPage() {
  const router = useRouter();

  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<SignupStep>("input");
  const [signupType, setSignupType] = useState<"email" | "phone" | null>(null);
  const [message, setMessage] = useState<MessageState>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const resetMessage = () => setMessage(null);

  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!emailOrPhone || !fullName) {
      setMessage({
        type: "error",
        text: "Fyll inn alle feltene.",
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
      // Email signup requires password
      if (!password || !confirmPassword) {
        setMessage({
          type: "error",
          text: "Fyll inn passord.",
        });
        return;
      }

      if (password !== confirmPassword) {
        setMessage({
          type: "error",
          text: "Passordene stemmer ikke overens.",
        });
        return;
      }

      if (password.length < 6) {
        setMessage({
          type: "error",
          text: "Passordet må være minst 6 tegn langt.",
        });
        return;
      }

      if (!isValidEmail(emailOrPhone)) {
        setMessage({ type: "error", text: "Ugyldig e-postformat." });
        return;
      }

      setIsSubmitting(true);
      setMessage(null);

      const { error } = await supabase.auth.signUp({
        email: emailOrPhone,
        password,
        options: {
          data: {
            first_name: fullName,
          },
          emailRedirectTo: `${window.location.origin}/auth/callback`,
        },
      });

      setIsSubmitting(false);

      if (error) {
        setMessage({ type: "error", text: error.message });
        return;
      }

      // User is now logged in automatically
      setMessage({
        type: "success",
        text: "Konto opprettet! Omdirigerer...",
      });

      // Redirect to onboarding
      setTimeout(() => {
        router.replace("/onboarding");
        router.refresh();
      }, 1500);
    } else {
      // Phone signup with OTP
      if (!isValidNorwegianPhone(emailOrPhone)) {
        setMessage({
          type: "error",
          text: "Telefonnummer må være 8 siffer.",
        });
        return;
      }

      // Validate password if provided (optional for phone)
      if (password || confirmPassword) {
        if (!password || !confirmPassword) {
          setMessage({
            type: "error",
            text: "Fyll inn begge passordfeltene hvis du vil sette passord.",
          });
          return;
        }

        if (password !== confirmPassword) {
          setMessage({
            type: "error",
            text: "Passordene stemmer ikke overens.",
          });
          return;
        }

        if (password.length < 6) {
          setMessage({
            type: "error",
            text: "Passordet må være minst 6 tegn langt.",
          });
          return;
        }
      }

      setIsSubmitting(true);
      setMessage(null);

      try {
        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.signInWithOtp({
          phone: phoneE164,
          options: {
            data: {
              first_name: fullName,
            },
          },
        });

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: error.message });
          return;
        }

        setSignupType("phone");
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
        setMessage({ type: "error", text: error.message });
        return;
      }

      // If user provided a password during signup, set it now
      if (password && password.length >= 6) {
        const { error: passwordError } = await supabase.auth.updateUser({
          password: password,
        });

        if (passwordError) {
          console.error("Failed to set password:", passwordError);
          // Don't block signup if password setting fails
          // User can set it later in profile
        }
      }

      setMessage({
        type: "success",
        text: "Konto opprettet! Omdirigerer...",
      });

      // Redirect to onboarding
      setTimeout(() => {
        router.replace("/onboarding");
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

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <section className="w-full max-w-md rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg backdrop-blur">
        <div className="mb-8 text-center">
          <h1 className="tracking-wide">Opprett konto</h1>
          <p className="mt-2 text-sm text-text-secondary">
            {step === "otp"
              ? `Skriv inn koden vi sendte til ${emailOrPhone}`
              : "Fyll inn dine opplysninger"}
          </p>
        </div>

        {/* Step 1: Input Form */}
        {step === "input" && (
          <form className="space-y-6" noValidate onSubmit={handleSignUp}>
            <div className="space-y-2">
              <label htmlFor="fullName">Fullt navn</label>
              <input
                id="fullName"
                name="fullName"
                type="text"
                placeholder="Fullt navn"
                value={fullName}
                onChange={(event) => {
                  resetMessage();
                  setFullName(event.target.value);
                }}
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
              />
            </div>

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

            {/* Show password fields for email (required) or phone (optional) */}
            {emailOrPhone && (
              <>
                <div className="space-y-2">
                  <label htmlFor="password">
                    Passord
                    {detectInputType(emailOrPhone) === "phone" && (
                      <span className="ml-2 text-xs text-text-secondary font-normal">
                        (valgfritt)
                      </span>
                    )}
                  </label>
                  <input
                    id="password"
                    name="password"
                    type="password"
                    placeholder={
                      detectInputType(emailOrPhone) === "phone"
                        ? "Sett passord (eller bruk kun SMS-kode)"
                        : "Passord"
                    }
                    value={password}
                    onChange={(event) => {
                      resetMessage();
                      setPassword(event.target.value);
                    }}
                    className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
                  />
                  {detectInputType(emailOrPhone) === "phone" && (
                    <p className="text-xs text-text-secondary">
                      Hvis du setter passord kan du logge inn med enten SMS-kode
                      eller passord
                    </p>
                  )}
                </div>

                {(password || detectInputType(emailOrPhone) === "email") && (
                  <div className="space-y-2">
                    <label htmlFor="confirmPassword">Bekreft passord</label>
                    <input
                      id="confirmPassword"
                      name="confirmPassword"
                      type="password"
                      placeholder="Bekreft passord"
                      value={confirmPassword}
                      onChange={(event) => {
                        resetMessage();
                        setConfirmPassword(event.target.value);
                      }}
                      className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
                    />
                  </div>
                )}
              </>
            )}

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting
                ? detectInputType(emailOrPhone) === "phone"
                  ? "Sender kode..."
                  : "Oppretter konto..."
                : "Opprett konto"}
            </button>
          </form>
        )}

        {/* Step 2: OTP Verification (for phone signup) */}
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
              disabled={isSubmitting}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Verifiserer..." : "Verifiser og opprett konto"}
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
              ← Tilbake
            </button>
          </form>
        )}

        {/* Message Display */}
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

        {/* Back to login - only show on input step */}
        {step === "input" && (
          <div className="mt-8 text-center text-sm">
            <Link
              href="/login"
              className="font-semibold text-brand-highlight transition hover:text-brand-highlight/80 focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
            >
              ← Tilbake til innlogging
            </Link>
          </div>
        )}
      </section>
    </div>
  );
}
