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
import { supabase } from "@/lib/supabase/browser";
import {
  detectInputType,
  normalizePhoneToE164,
  isValidNorwegianPhone,
  isValidEmail,
} from "@/lib/validation/phone";
import { translateError } from "@/lib/errors/translate";
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
type Step = "input" | "otp" | "password";
type FieldErrors = {
  emailOrPhone?: string;
  otp?: string;
  password?: string;
  confirmPassword?: string;
};

export default function ResetPasswordPage() {
  const router = useRouter();

  const [step, setStep] = useState<Step>("input");
  const [emailOrPhone, setEmailOrPhone] = useState("");
  const [resetType, setResetType] = useState<"email" | "phone" | null>(null);
  const [otp, setOtp] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
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

  // Step 1: Send OTP to email or phone
  const handleSendOtp = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    resetAll();

    const errors: FieldErrors = {};

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

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

    try {
      if (inputType === "email") {
        if (!isValidEmail(emailOrPhone)) {
          setFieldErrors({ emailOrPhone: "Ugyldig e-postformat." });
          setIsSubmitting(false);
          return;
        }

        const { error } = await supabase.auth.resetPasswordForEmail(
          emailOrPhone,
          {
            redirectTo: undefined,
            captchaToken,
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
          setFieldErrors({ emailOrPhone: "Telefonnummer må være 8 siffer." });
          setIsSubmitting(false);
          return;
        }

        const phoneE164 = normalizePhoneToE164(emailOrPhone);
        const { error } = await supabase.auth.signInWithOtp({
          phone: phoneE164,
          options: {
            captchaToken,
          },
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
    resetAll();

    const errors: FieldErrors = {};

    if (otp.length !== 6) {
      errors.otp = "Fyll inn alle 6 sifrene.";
    }

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      return;
    }

    setIsSubmitting(true);

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
    resetAll();

    const errors: FieldErrors = {};

    if (!password) {
      errors.password = "Fyll inn nytt passord.";
    }

    if (!confirmPassword) {
      errors.confirmPassword = "Bekreft passordet.";
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
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Tilbakestill passord</CardTitle>
          <CardDescription>
            {step === "input" && "Vi sender deg en kode på e-post eller SMS"}
            {step === "otp" && "Skriv inn koden vi sendte deg"}
            {step === "password" && "Velg et nytt passord"}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {/* Step 1: Email or Phone Input */}
          {step === "input" && (
            <form className="space-y-6" noValidate onSubmit={handleSendOtp}>
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

              <div className="flex justify-center overflow-hidden rounded-lg bg-surface-primary/50">
                <TurnstileCaptcha
                  onSuccess={(token) => {
                    setCaptchaToken(token);
                    resetMessage();
                  }}
                  onError={() => {
                    setCaptchaToken(null);
                    setMessage({ type: "error", text: "Captcha-verifisering feilet. Prøv igjen." });
                  }}
                  className="scale-[1.01] -my-[1px] brightness-90 contrast-110"
                />
              </div>

              <Button
                type="submit"
                disabled={isSubmitting || !captchaToken}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                Send kode
              </Button>
            </form>
          )}

          {/* Step 2: OTP */}
          {step === "otp" && (
            <form className="space-y-6" noValidate onSubmit={handleVerifyOtp}>
              <Field data-invalid={!!fieldErrors.otp} className="items-center">
                <FieldLabel htmlFor="otp" className="sr-only">
                  6-sifret kode
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
                Verifiser kode
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

          {/* Step 3: New Password */}
          {step === "password" && (
            <form
              className="space-y-6"
              noValidate
              onSubmit={handleUpdatePassword}
            >
              <FieldGroup>
                <Field data-invalid={!!fieldErrors.password}>
                  <FieldLabel htmlFor="password">Nytt passord</FieldLabel>
                  <Input
                    id="password"
                    name="password"
                    type="password"
                    placeholder="Nytt passord"
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
              </FieldGroup>

              <Button
                type="submit"
                disabled={isSubmitting}
                loading={isSubmitting}
                size="lg"
                className="w-full"
              >
                Oppdater passord
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

          {/* Back to login */}
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
        </CardContent>
      </Card>
    </div>
  );
}
