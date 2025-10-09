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

type MessageState = { type: "error" | "success"; text: string } | null;
type Step = "details" | "otp";

export default function SignupPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [step, setStep] = useState<Step>("details");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [otp, setOtp] = useState("");
  const [message, setMessage] = useState<MessageState>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const resetMessage = () => setMessage(null);

  // Step 1: Create account and send OTP
  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!email || !password || !confirmPassword || !fullName) {
      setMessage({
        type: "error",
        text: "Fyll inn alle feltene.",
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

    setIsSubmitting(true);
    setMessage(null);

    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          name: fullName,
        },
        emailRedirectTo: undefined,
      },
    });

    setIsSubmitting(false);

    if (error) {
      setMessage({ type: "error", text: error.message });
      return;
    }

    setMessage({
      type: "success",
      text: "En kode er sendt til din e-post. Sjekk innboksen din.",
    });
    setStep("otp");
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

    const { error } = await supabase.auth.verifyOtp({
      email,
      token: otp,
      type: "signup",
    });

    setIsSubmitting(false);

    if (error) {
      setMessage({ type: "error", text: error.message });
      return;
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
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <section className="w-full max-w-md rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg backdrop-blur">
        <div className="mb-8 text-center">
          <h1 className="tracking-wide">Opprett konto</h1>
          <p className="mt-2 text-sm text-text-secondary">
            {step === "details" && "Fyll inn dine opplysninger"}
            {step === "otp" && "Skriv inn koden vi sendte deg"}
          </p>
        </div>

        {/* Step 1: Account Details */}
        {step === "details" && (
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
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
              />
            </div>

            <div className="space-y-2">
              <label htmlFor="email">E-post</label>
              <input
                id="email"
                name="email"
                type="email"
                placeholder="E-post"
                value={email}
                onChange={(event) => {
                  resetMessage();
                  setEmail(event.target.value);
                }}
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
              />
            </div>

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
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
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
                className="w-full rounded-full border border-border-subtle bg-background-primary px-5 py-3 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-highlight focus:outline-none focus:ring-2 focus:ring-brand-highlight/60"
              />
            </div>

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Sender kode..." : "Send kode"}
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
              onClick={() => setStep("details")}
              className="w-full text-sm text-text-secondary transition hover:text-text-primary"
            >
              ← Tilbake til opplysninger
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
