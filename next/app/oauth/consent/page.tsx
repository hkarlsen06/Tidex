import { Suspense } from "react";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { Shield, Check, ExternalLink, User, KeyRound, Mail, Phone, Link2 } from "lucide-react";

import { Button } from "@/components/app/Button";
import { AuthHeader } from "@/components/app/AuthHeader";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { LOCALE_COOKIE, defaultLocale, locales, type Locale } from "@/lib/i18n/config";
import { extractRedirectUrl, sanitizeUrl, sanitizeUserInput } from "@/lib/sanitize";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type ConsentSearchParams = {
  authorization_id?: string | string[];
  error?: string | string[];
  [key: string]: string | string[] | undefined;
};

type OAuthAuthorizationDetailsLike = {
  authorization_id: string;
  client: {
    name: string;
    uri: string;
    logo_uri: string;
  };
  user: {
    email: string;
  };
  scope: string;
};

const scopeIcons: Record<string, typeof Shield> = {
  openid: KeyRound,
  email: Mail,
  profile: User,
  phone: Phone,
};

function pickFirst(value?: string | string[]): string | undefined {
  if (Array.isArray(value)) {
    return value[0];
  }

  return value;
}

function serializeSearchParams(searchParams: ConsentSearchParams): string {
  const query = new URLSearchParams();

  for (const [key, value] of Object.entries(searchParams)) {
    if (Array.isArray(value)) {
      value.forEach((item) => {
        if (typeof item === "string") {
          query.append(key, item);
        }
      });
    } else if (typeof value === "string") {
      query.append(key, value);
    }
  }

  return query.toString();
}

function detectLocaleFromAcceptLanguage(acceptLanguage: string | null): Locale {
  if (!acceptLanguage) {
    return defaultLocale;
  }

  const ranked = acceptLanguage
    .split(",")
    .map((entry) => {
      const [languageTag, qualityPart] = entry.trim().split(";");
      const quality = qualityPart ? Number.parseFloat(qualityPart.split("=")[1] ?? "1") : 1;
      const languageCode = languageTag?.split("-")[0]?.toLowerCase() ?? "";

      return { languageCode, quality: Number.isNaN(quality) ? 1 : quality };
    })
    .sort((a, b) => b.quality - a.quality);

  for (const { languageCode } of ranked) {
    if (locales.includes(languageCode as Locale)) {
      return languageCode as Locale;
    }
  }

  return defaultLocale;
}

async function resolveLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  const cookieLocale = cookieStore.get(LOCALE_COOKIE)?.value;

  if (cookieLocale && locales.includes(cookieLocale as Locale)) {
    return cookieLocale as Locale;
  }

  const headerStore = await headers();
  return detectLocaleFromAcceptLanguage(headerStore.get("accept-language"));
}

function mapErrorKey(errorCode: string | undefined):
  | "invalid_request"
  | "auth_required"
  | "authorization_not_found"
  | "decision_failed"
  | "generic" {
  switch (errorCode) {
    case "invalid_request":
      return "invalid_request";
    case "auth_required":
      return "auth_required";
    case "authorization_not_found":
      return "authorization_not_found";
    case "decision_failed":
      return "decision_failed";
    default:
      return "generic";
  }
}

function isAuthorizationDetails(data: unknown): data is OAuthAuthorizationDetailsLike {
  if (!data || typeof data !== "object") {
    return false;
  }

  const record = data as Record<string, unknown>;
  const client = record.client as Record<string, unknown> | undefined;
  const user = record.user as Record<string, unknown> | undefined;

  return (
    typeof record.authorization_id === "string" &&
    typeof record.scope === "string" &&
    !!client &&
    typeof client.name === "string" &&
    typeof client.uri === "string" &&
    typeof client.logo_uri === "string" &&
    !!user &&
    typeof user.email === "string"
  );
}

function ConsentPageSkeleton() {
  return (
    <div className="relative w-full max-w-md mx-auto">
      <div className="flex flex-col items-center gap-4 mb-10">
        <div className="h-20 w-20 rounded-full bg-surface-primary/50 animate-pulse" />
        <div className="h-7 w-48 rounded bg-surface-primary/50 animate-pulse" />
        <div className="h-5 w-64 rounded bg-surface-primary/50 animate-pulse" />
      </div>

      <div className="space-y-4">
        <div className="h-16 w-full rounded-xl bg-surface-primary/50 animate-pulse" />
        <div className="h-24 w-full rounded-xl bg-surface-primary/50 animate-pulse" />
        <div className="h-12 w-full rounded-xl bg-surface-primary/50 animate-pulse" />
      </div>
    </div>
  );
}

function ErrorView({
  t,
  errorMessage,
}: {
  t: ReturnType<typeof getDictionary>["pages"]["auth"]["oauthConsent"];
  errorMessage: string;
}) {
  return (
    <div className="relative w-full max-w-md mx-auto">
      <AuthHeader
        variant="icon"
        icon={<Shield className="h-9 w-9 text-brand-gradient-start" />}
        title={t.title}
        subtitle={t.subtitle}
      />

      <div className="rounded-xl border border-error/20 bg-error-subtle px-5 py-4 text-sm text-error-foreground" role="alert">
        {errorMessage}
      </div>
    </div>
  );
}

function MissingAuthorizationView({
  t,
  searchErrorMessage,
}: {
  t: ReturnType<typeof getDictionary>["pages"]["auth"]["oauthConsent"];
  searchErrorMessage: string | null;
}) {
  return (
    <div className="relative w-full max-w-md mx-auto">
      <AuthHeader
        variant="icon"
        icon={<Link2 className="h-9 w-9 text-brand-gradient-start" />}
        title={t.endpointInfo.title}
        subtitle={t.endpointInfo.description}
      />

      <div className="space-y-5">
        <p className="text-sm text-text-secondary text-center">{t.endpointInfo.hint}</p>

        {searchErrorMessage ? (
          <div className="rounded-xl border border-error/20 bg-error-subtle px-5 py-4 text-sm text-error-foreground" role="alert">
            {searchErrorMessage}
          </div>
        ) : null}

        <div className="rounded-xl border border-border-subtle bg-surface-primary p-4">
          <p className="text-[11px] uppercase tracking-widest text-text-muted mb-2 font-medium">
            {t.endpointInfo.exampleLabel}
          </p>
          <p className="text-sm text-text-primary">
            {t.endpointInfo.exampleValue}
          </p>
        </div>

        <Button
          asChild
          size="lg"
          className="w-full h-12 bg-brand-gradient-start text-white hover:bg-brand-gradient-start/90"
        >
          <a href="/login">{t.endpointInfo.ctaLabel}</a>
        </Button>
      </div>
    </div>
  );
}

async function OAuthConsentContent({
  searchParams,
}: {
  searchParams: Promise<ConsentSearchParams>;
}) {
  const resolvedSearchParams = await searchParams;
  const locale = await resolveLocale();
  const dictionary = getDictionary(locale);
  const t = dictionary.pages.auth.oauthConsent;

  const authorizationId = pickFirst(resolvedSearchParams.authorization_id)?.trim();
  const queryString = serializeSearchParams(resolvedSearchParams);
  const loginReturnPath = `/oauth/consent${queryString ? `?${queryString}` : ""}`;

  const searchErrorCode = pickFirst(resolvedSearchParams.error);
  const searchErrorMessage = searchErrorCode
    ? t.errors[mapErrorKey(searchErrorCode)]
    : null;

  if (!authorizationId || authorizationId.length > 200) {
    return <MissingAuthorizationView t={t} searchErrorMessage={searchErrorMessage} />;
  }

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    const loginUrl = new URL("/login", "http://localhost");
    loginUrl.searchParams.set("next", loginReturnPath);
    redirect(`${loginUrl.pathname}${loginUrl.search}`);
  }

  const { data: authorizationData, error: authorizationError } =
    await supabase.auth.oauth.getAuthorizationDetails(authorizationId);

  if (authorizationError) {
    const status =
      typeof authorizationError === "object" && authorizationError && "status" in authorizationError
        ? Number((authorizationError as { status?: number }).status)
        : undefined;

    if (status === 401) {
      const loginUrl = new URL("/login", "http://localhost");
      loginUrl.searchParams.set("next", loginReturnPath);
      redirect(`${loginUrl.pathname}${loginUrl.search}`);
    }

    const errorKey = status === 404 ? "authorization_not_found" : "generic";
    return <ErrorView t={t} errorMessage={t.errors[errorKey]} />;
  }

  const autoRedirectUrl = extractRedirectUrl(authorizationData);
  if (autoRedirectUrl && !isAuthorizationDetails(authorizationData)) {
    redirect(autoRedirectUrl);
  }

  if (!isAuthorizationDetails(authorizationData)) {
    return <ErrorView t={t} errorMessage={t.errors.generic} />;
  }

  const clientName = sanitizeUserInput(authorizationData.client.name) || t.unknownClient;
  const clientUriText = sanitizeUserInput(authorizationData.client.uri);
  const clientUriHref = sanitizeUrl(authorizationData.client.uri);
  const clientLogoUrl = sanitizeUrl(authorizationData.client.logo_uri);
  const userEmail = sanitizeUserInput(authorizationData.user.email) || t.unknownAccount;

  const scopeLabels: Record<string, string> = {
    openid: t.scopes.openid,
    email: t.scopes.email,
    profile: t.scopes.profile,
    phone: t.scopes.phone,
  };

  const scopes = Array.from(
    new Set(
      authorizationData.scope
        .split(/\s+/)
        .map((scope) => scope.trim())
        .filter((scope) => scope.length > 0)
    )
  );

  return (
    <div className="relative w-full max-w-md mx-auto">
      <AuthHeader
        variant="icon"
        icon={<Shield className="h-9 w-9 text-brand-gradient-start" />}
        title={t.title}
      />

      <div className="space-y-5">
        {/* Client info card */}
        <div className="flex items-center gap-4 rounded-xl border border-border-subtle bg-surface-primary p-4">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-surface-secondary border border-border-subtle overflow-hidden">
            {clientLogoUrl ? (
              /* eslint-disable-next-line @next/next/no-img-element -- external OAuth client logo; next/image requires domain allowlisting */
              <img
                src={clientLogoUrl}
                alt=""
                className="h-full w-full object-cover"
              />
            ) : (
              <span className="text-lg font-bold text-text-primary">
                {clientName.charAt(0).toUpperCase()}
              </span>
            )}
          </div>

          <div className="min-w-0 flex-1">
            <p className="text-sm text-text-secondary">
              <span className="font-semibold text-text-primary">{clientName}</span>{" "}
              {t.appRequestingAccess}
            </p>
            {clientUriHref ? (
              <a
                href={clientUriHref}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1 text-xs text-brand-gradient-start hover:underline underline-offset-2"
              >
                {clientUriText || clientUriHref}
                <ExternalLink className="h-3 w-3" />
              </a>
            ) : null}
          </div>
        </div>

        {searchErrorMessage ? (
          <div className="rounded-xl border border-error/20 bg-error-subtle px-5 py-4 text-sm text-error-foreground" role="alert">
            {searchErrorMessage}
          </div>
        ) : null}

        {/* Signed-in account */}
        <div className="rounded-xl border border-border-subtle bg-surface-primary px-4 py-3">
          <p className="text-[11px] uppercase tracking-widest text-text-muted font-medium">
            {t.accountLabel}
          </p>
          <p className="text-sm font-medium text-text-primary break-all mt-1">{userEmail}</p>
        </div>

        {/* Permissions list */}
        <div className="space-y-3">
          <h2 className="text-[11px] uppercase tracking-widest text-text-muted font-medium px-1">
            {t.permissionsHeading}
          </h2>

          {scopes.length > 0 ? (
            <ul className="rounded-xl border border-border-subtle bg-surface-primary divide-y divide-border-subtle overflow-hidden">
              {scopes.map((scope) => {
                const fallbackScopeLabel = sanitizeUserInput(scope) || scope;
                const Icon = scopeIcons[scope] ?? Check;

                return (
                  <li
                    key={scope}
                    className="flex items-center gap-3 px-4 py-3 text-sm text-text-primary"
                  >
                    <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-brand-gradient-start/10">
                      <Icon className="h-3.5 w-3.5 text-brand-gradient-start" />
                    </div>
                    {scopeLabels[scope] ?? fallbackScopeLabel}
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className="text-sm text-text-secondary">{t.errors.invalid_request}</p>
          )}
        </div>

        <p className="text-xs text-text-muted text-center">{t.redirectNotice}</p>

        {/* Actions */}
        <div className="flex flex-col gap-3 pt-1">
          <form action="/api/oauth/decision" method="post" className="w-full">
            <input type="hidden" name="authorization_id" value={authorizationId} />
            <input type="hidden" name="action" value="approve" />
            <Button
              type="submit"
              size="lg"
              className="w-full h-12 bg-brand-gradient-start text-white hover:bg-brand-gradient-start/90"
            >
              {t.approveButton}
            </Button>
          </form>

          <form action="/api/oauth/decision" method="post" className="w-full">
            <input type="hidden" name="authorization_id" value={authorizationId} />
            <input type="hidden" name="action" value="deny" />
            <Button
              type="submit"
              variant="ghost"
              size="sm"
              className="w-full text-text-muted"
            >
              {t.denyButton}
            </Button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default async function OAuthConsentPage({
  searchParams,
}: {
  searchParams: Promise<ConsentSearchParams>;
}) {
  return (
    <Suspense fallback={<ConsentPageSkeleton />}>
      <OAuthConsentContent searchParams={searchParams} />
    </Suspense>
  );
}
