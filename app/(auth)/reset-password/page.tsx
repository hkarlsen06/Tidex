"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

import {
  InputOTP,
  InputOTPGroup,
  InputOTPSeparator,
  InputOTPSlot,
} from "@/components/app/InputOTP";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import {
  detectInputType,
  normalizePhoneToE164,
  isValidNorwegianPhone,
  isValidEmail,
} from "@/lib/validation/phone";
import { translateError } from "@/lib/errors/translate";

type MessageState = { type: "error" | "success"; text: string } | null;
type Step = "input" | "otp" | "password";

export default function ResetPasswordPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [step, setStep] = useState<Step>("input");
  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [resetType, setResetType] = useState<"email" | "phone" | null>(null);
  const [otp, setOtp] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [message, setMessage] = useState<MessageState>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const resetMessage = () => setMessage(null);

  // Step 1: Send OTP to email or phone
  const handleSendOtp = async (event: FormEvent<HTMLFormElement>) => {
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

    setIsSubmitting(true);
    setMessage(null);

    try {
      if (inputType === "email") {
        if (!isValidEmail(emailOrPhone)) {
          setMessage({ type: "error", text: "Ugyldig e-postformat." });
          setIsSubmitting(false);
          return;
        }

        const { error } = await supabase.auth.resetPasswordForEmail(
          emailOrPhone,
          {
            redirectTo: undefined,
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
          text: "En kode er sendt til din e-post. Sjekk innboksen din.",
        });
      } else {
        // Phone reset
        if (!isValidNorwegianPhone(emailOrPhone)) {
          setMessage({
            type: "error",
            text: "Telefonnummer må være 8 siffer.",
          });
          setIsSubmitting(false);
          return;
        }

        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.signInWithOtp({
          phone: phoneE164,
        });

        setIsSubmitting(false);

        if (error) {
          setMessage({ type: "error", text: translateError(error.message) });
          return;
        }

        setResetType("phone");
        setMessage({
          type: "success",
          text: "SMS-kode sendt! Sjekk meldingene dine.",
        });
      }

      setStep("otp");
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "En feil oppstod",
      });
    }
  };

  // Step 2: Verify OTP
  const handleVerifyOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (otp.length !== 6) {
      setMessage({ type: "error", text: "Fyll inn alle 6 sifrene." });
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

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
          setMessage({ type: "error", text: "Ugyldig telefonnummer." });
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

      setMessage({ type: "success", text: "Koden er verifisert!" });
      setStep("password");
    } catch (err) {
      setIsSubmitting(false);
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "En feil oppstod",
      });
    }
  };

  // Step 3: Update password
  const handleUpdatePassword = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!password || !confirmPassword) {
      setMessage({ type: "error", text: "Fyll inn begge passordfeltene." });
      return;
    }

    if (password !== confirmPassword) {
      setMessage({ type: "error", text: "Passordene stemmer ikke overens." });
      return;
    }

    if (password.length < 6) {
      setMessage({
        type: "error",
        text: "Passordet må være minst 6 tegn langt.",
      });
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

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
      text: "Passord oppdatert! Logger inn...",
    });

    // Auto-login and redirect
    setTimeout(() => {
      router.replace("/");
      router.refresh();
    }, 1500);
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <section className="w-full max-w-md rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg backdrop-blur">
        <div className="mb-8 text-center">
          <h1 className="tracking-wide">Tilbakestill passord</h1>
          <p className="mt-2 text-sm text-text-secondary">
            {step === "input" &&
              "Vi sender deg en kode på e-post eller SMS"}
            {step === "otp" && "Skriv inn koden vi sendte deg"}
            {step === "password" && "Velg et nytt passord"}
          </p>
        </div>

        {/* Step 1: Email or Phone Input */}
        {step === "input" && (
          <form className="space-y-6" noValidate onSubmit={handleSendOtp}>
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

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Sender..." : "Send kode"}
            </button>
          </form>
        )}

        {/* Step 2: OTP */}
        {step === "otp" && (
          <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
            <div className="flex flex-col items-center space-y-4">
              <label htmlFor="otp" className="text-sm text-text-secondary">
                6-sifret kode
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
              ← Tilbake
            </button>
          </form>
        )}

        {/* Step 3: New Password */}
        {step === "password" && (
          <form
            className="space-y-6"
            noValidate
            onSubmit={handleUpdatePassword}
          >
            <div className="space-y-2">
              <label htmlFor="password">Nytt passord</label>
              <input
                id="password"
                name="password"
                type="password"
                placeholder="Nytt passord"
                value={password}
                onChange={(event) => {
                  resetMessage();
                  setPassword(event.target.value);
                }}
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-base text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
              />
            </div>

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

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Oppdaterer..." : "Oppdater passord"}
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

        {/* Back to login */}
        <div className="mt-8 text-center text-sm">
          <Link
            href="/login"
            className="font-semibold text-brand-highlight transition hover:text-brand-highlight/80 focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
          >
            ← Tilbake til innlogging
          </Link>
        </div>
      </section>
    </div>
  );
}
