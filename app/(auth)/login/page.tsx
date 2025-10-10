"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { translateError } from "@/lib/errors/translate";

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

export default function LoginPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState<MessageState>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isOAuthRedirecting, setIsOAuthRedirecting] = useState(false);

  const resetMessage = () => setMessage(null);

  const handleSignIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!email || !password) {
      setMessage({ type: "error", text: "Fyll inn e-post og passord." });
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    setIsSubmitting(false);

    if (error) {
      setMessage({ type: "error", text: translateError(error.message) });
      return;
    }

    // Use full page navigation to ensure cookies are properly set and visible
    // SupabaseListener will handle the auth state sync via its onAuthStateChange handler
    // Full navigation ensures server-side getUser() sees the cookies
    window.location.href = "/";
  };

  const handleGoogleSignIn = async () => {
    setIsOAuthRedirecting(true);
    setMessage(null);

    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo:
          process.env.NEXT_PUBLIC_SUPABASE_REDIRECT_URL ?? undefined,
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
          </div>

          <form className="space-y-6" noValidate onSubmit={handleSignIn}>
            <div className="space-y-2">
              <label htmlFor="email">
                E-post
              </label>
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
              <label htmlFor="password">
                Passord
              </label>
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

            <button
              type="submit"
              disabled={buttonDisabled}
              className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-5 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Logger inn..." : "Logg inn"}
            </button>
          </form>

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

          <div className="mt-6 space-y-3">
            <Link
              href="/signup"
              className="flex w-full items-center justify-center rounded-full bg-surface-primary px-5 py-3 text-sm font-semibold uppercase tracking-wide text-text-primary transition hover:bg-surface-primary/80 focus:outline-none focus:ring-4 focus:ring-brand-highlight/40 focus:ring-offset-2 focus:ring-offset-surface-secondary"
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
      </section>
    </div>
  );
}
