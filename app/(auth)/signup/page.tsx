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
import {
  Field,
  FieldLabel,
  FieldError,
  FieldGroup,
} from "@/components/app/Field";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/app/Card";
import { TurnstileCaptcha } from "@/components/app/TurnstileCaptcha";

type MessageState = { type: "error" | "success"; text: string } | null;
type SignupStep = "input" | "otp";
type FieldErrors = {
  fullName?: string;
  emailOrPhone?: string;
  password?: string;
  confirmPassword?: string;
  otp?: string;
};

export default function SignupPage() {
  const router = useRouter();

  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<SignupStep>("input");
  const [message, setMessage] = useState<MessageState>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);

  const resetMessage = () => setMessage(null);
  const resetFieldErrors = () => setFieldErrors({});
  const resetAll = () => {
    resetMessage();
    resetFieldErrors();
    setCaptchaToken(null);
  };

  const handleSignUp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

    if (!fullName) {
      errors.fullName = "Fyll inn fullt navn.";
    }

    if (!emailOrPhone) {
      errors.emailOrPhone = "Fyll inn e-post eller telefonnummer.";
    }

    if (!captchaToken) {
      setMessage({ type: "error", text: "Vennligst fullfør captcha-verifiseringen." });
      return;
    }

    const inputType = detectInputType(emailOrPhone);

    if (emailOrPhone && inputType === "unknown") {
      errors.emailOrPhone = "Ugyldig e-post eller telefonnummer. Telefonnummer må være 8 siffer.";
    }

    if (inputType === "email") {
      // Email signup requires password
      if (!password) {
        errors.password = "Fyll inn passord.";
      }

      if (!confirmPassword) {
        errors.confirmPassword = "Fyll inn bekreftelse av passord.";
      }

      if (password && confirmPassword && password !== confirmPassword) {
        errors.confirmPassword = "Passordene stemmer ikke overens.";
      }

      if (password && password.length < 6) {
        errors.password = "Passordet må være minst 6 tegn langt.";
      }

      if (emailOrPhone && !isValidEmail(emailOrPhone)) {
        errors.emailOrPhone = "Ugyldig e-postformat.";
      }

      if (Object.keys(errors).length > 0) {
        setFieldErrors(errors);
        return;
      }

      setIsSubmitting(true);

      const { error } = await supabase.auth.signUp({
        email: emailOrPhone,
        password,
        options: {
          data: {
            first_name: fullName,
          },
          emailRedirectTo: `${window.location.origin}/auth/callback`,
          captchaToken,
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
        errors.emailOrPhone = "Telefonnummer må være 8 siffer.";
      }

      // Password is required for phone signup
      if (!password) {
        errors.password = "Fyll inn passord.";
      }

      if (!confirmPassword) {
        errors.confirmPassword = "Fyll inn bekreftelse av passord.";
      }

      if (password && confirmPassword && password !== confirmPassword) {
        errors.confirmPassword = "Passordene stemmer ikke overens.";
      }

      if (password && password.length < 6) {
        errors.password = "Passordet må være minst 6 tegn langt.";
      }

      if (Object.keys(errors).length > 0) {
        setFieldErrors(errors);
        return;
      }

      setIsSubmitting(true);

      try {
        const phoneE164 = normalizePhoneToE164(emailOrPhone);

        const { error } = await supabase.auth.signUp({
          phone: phoneE164,
          password: password,
          options: {
            data: {
              first_name: fullName,
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
              text: "Dette telefonnummeret er allerede registrert. Gå til innlogging."
            });
          } else {
            setMessage({ type: "error", text: error.message });
          }
          return;
        }

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
    resetAll();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = "Fyll inn alle 6 sifrene.";
    }

    if (!isValidNorwegianPhone(emailOrPhone)) {
      errors.otp = "Ugyldig telefonnummer.";
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

  const detectedInputType = detectInputType(emailOrPhone);
  const isPhoneInput = detectedInputType === "phone";

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Opprett konto</CardTitle>
          <CardDescription>
            {step === "otp"
              ? `Skriv inn koden vi sendte til ${emailOrPhone}`
              : "Fyll inn dine opplysninger"}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Step 1: Input Form */}
          {step === "input" && (
            <form className="space-y-6" noValidate onSubmit={handleSignUp}>
              <FieldGroup>
                <Field data-invalid={!!fieldErrors.fullName}>
                  <FieldLabel htmlFor="fullName">Fullt navn</FieldLabel>
                  <Input
                    id="fullName"
                    name="fullName"
                    type="text"
                    placeholder="Fullt navn"
                    value={fullName}
                    onChange={(event) => {
                      resetAll();
                      setFullName(event.target.value);
                    }}
                    aria-invalid={!!fieldErrors.fullName}
                  />
                  <FieldError>{fieldErrors.fullName}</FieldError>
                </Field>

                <Field data-invalid={!!fieldErrors.emailOrPhone}>
                  <FieldLabel htmlFor="emailOrPhone">E-post eller telefonnummer</FieldLabel>
                  <Input
                    id="emailOrPhone"
                    name="emailOrPhone"
                    type="text"
                    placeholder="E-post eller telefonnummer"
                    value={emailOrPhone}
                    onChange={(event) => {
                      resetAll();
                      setEmailOrPhone(event.target.value);
                    }}
                    aria-invalid={!!fieldErrors.emailOrPhone}
                  />
                  <FieldError>{fieldErrors.emailOrPhone}</FieldError>
                </Field>

                {/* Show password fields when email or phone is entered */}
                {emailOrPhone && (
                  <>
                    <Field data-invalid={!!fieldErrors.password}>
                      <FieldLabel htmlFor="password">Passord</FieldLabel>
                      <Input
                        id="password"
                        name="password"
                        type="password"
                        placeholder="Passord"
                        value={password}
                        onChange={(event) => {
                          resetAll();
                          setPassword(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.password}
                      />
                      <FieldError>{fieldErrors.password}</FieldError>
                    </Field>

                    <Field data-invalid={!!fieldErrors.confirmPassword}>
                      <FieldLabel htmlFor="confirmPassword">Bekreft passord</FieldLabel>
                      <Input
                        id="confirmPassword"
                        name="confirmPassword"
                        type="password"
                        placeholder="Bekreft passord"
                        value={confirmPassword}
                        onChange={(event) => {
                          resetAll();
                          setConfirmPassword(event.target.value);
                        }}
                        aria-invalid={!!fieldErrors.confirmPassword}
                      />
                      <FieldError>{fieldErrors.confirmPassword}</FieldError>
                    </Field>
                  </>
                )}
              </FieldGroup>

              <div className="flex justify-center">
                <TurnstileCaptcha
                  onSuccess={(token) => {
                    setCaptchaToken(token);
                    resetMessage();
                  }}
                  onError={() => {
                    setCaptchaToken(null);
                    setMessage({ type: "error", text: "Captcha-verifisering feilet. Prøv igjen." });
                  }}
                />
              </div>

              <Button
                type="submit"
                disabled={isSubmitting || !captchaToken}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                {isPhoneInput ? "Send kode" : "Opprett konto"}
              </Button>
            </form>
          )}

          {/* Step 2: OTP Verification (for phone signup) */}
          {step === "otp" && (
            <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
              <Field data-invalid={!!fieldErrors.otp} className="items-center">
                <FieldLabel htmlFor="otp" className="sr-only">
                  6-sifret SMS-kode
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
                disabled={isSubmitting}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                Verifiser og opprett konto
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
                ← Tilbake
              </Button>
            </form>
          )}

          {/* Message Display */}
          {message && (
            <div
              className={`mt-4 rounded-md px-4 py-3 text-sm font-medium ${
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
            <div className="mt-6 text-center">
              <Button
                asChild
                variant="link"
                size="sm"
              >
                <Link href="/login">
                  ← Tilbake til innlogging
                </Link>
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
