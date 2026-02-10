import { NextResponse, type NextRequest } from "next/server";

import { extractRedirectUrl } from "@/lib/sanitize";
import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

type ConsentAction = "approve" | "deny";

function copyCookies(source: NextResponse, target: NextResponse): NextResponse {
  source.cookies.getAll().forEach((cookie) => {
    target.cookies.set(cookie.name, cookie.value, {
      ...cookie,
    });
  });

  return target;
}

function buildConsentPath(options: {
  authorizationId?: string;
  error: "invalid_request" | "auth_required" | "authorization_not_found" | "decision_failed";
}): string {
  const url = new URL("/oauth/consent", "http://localhost");

  if (options.authorizationId) {
    url.searchParams.set("authorization_id", options.authorizationId);
  }

  url.searchParams.set("error", options.error);
  return `${url.pathname}${url.search}`;
}

function getFormValue(formData: FormData, key: string): string | null {
  const value = formData.get(key);

  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function parseAction(value: string | null): ConsentAction | null {
  if (value === "approve" || value === "deny") {
    return value;
  }

  return null;
}

function mapDecisionError(error: unknown): "authorization_not_found" | "decision_failed" {
  if (!error || typeof error !== "object") {
    return "decision_failed";
  }

  const status = "status" in error ? Number((error as { status?: number }).status) : undefined;
  const message = "message" in error ? String((error as { message?: string }).message ?? "") : "";

  if (status === 404 || message.toLowerCase().includes("not found")) {
    return "authorization_not_found";
  }

  return "decision_failed";
}

export async function POST(request: NextRequest) {
  const formData = await request.formData();

  const authorizationId = getFormValue(formData, "authorization_id");
  const action = parseAction(getFormValue(formData, "action"));

  if (!authorizationId || authorizationId.length > 200 || !action) {
    const invalidUrl = new URL(
      buildConsentPath({ authorizationId: authorizationId ?? undefined, error: "invalid_request" }),
      request.url
    );
    return NextResponse.redirect(invalidUrl, 303);
  }

  const response = NextResponse.next();
  const supabase = createSupabaseRouteHandlerClient(request, response);

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", `/oauth/consent?authorization_id=${encodeURIComponent(authorizationId)}`);

    return copyCookies(response, NextResponse.redirect(loginUrl, 303));
  }

  const decisionResult =
    action === "approve"
      ? await supabase.auth.oauth.approveAuthorization(authorizationId, { skipBrowserRedirect: true })
      : await supabase.auth.oauth.denyAuthorization(authorizationId, { skipBrowserRedirect: true });

  if (decisionResult.error) {
    const errorCode = mapDecisionError(decisionResult.error);
    const consentUrl = new URL(
      buildConsentPath({ authorizationId, error: errorCode }),
      request.url
    );

    return copyCookies(response, NextResponse.redirect(consentUrl, 303));
  }

  const redirectUrl = extractRedirectUrl(decisionResult.data);
  if (!redirectUrl) {
    const consentUrl = new URL(
      buildConsentPath({ authorizationId, error: "decision_failed" }),
      request.url
    );

    return copyCookies(response, NextResponse.redirect(consentUrl, 303));
  }

  return copyCookies(response, NextResponse.redirect(redirectUrl, 303));
}
