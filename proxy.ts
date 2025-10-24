import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createServerClient, type CookieOptions } from "@supabase/ssr";

import { getProjectRefFromUrl } from "@/lib/supabase/utils";

const PUBLIC_PATH_PREFIXES = ["/login", "/signup", "/auth/", "/reset-password", "/verify-email"];

function isLoopbackHost(hostname: string) {
  const lower = hostname.toLowerCase();
  return (
    lower === "localhost" ||
    lower.startsWith("localhost:") ||
    lower === "127.0.0.1" ||
    lower.startsWith("127.0.0.1:") ||
    lower === "[::1]" ||
    lower.startsWith("[::1]:")
  );
}

function shouldUseSecureCookies(protocol: string, hostname: string) {
  if (protocol === "https:") return true;
  if (protocol === "http:") {
    if (isLoopbackHost(hostname)) {
      return false;
    }
    return false;
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (siteUrl) {
    return siteUrl.startsWith("https");
  }

  return process.env.NODE_ENV === "production";
}

function buildCookieBase(request: NextRequest): Partial<CookieOptions> {
  return {
    httpOnly: true,
    secure: shouldUseSecureCookies(request.nextUrl.protocol, request.nextUrl.hostname),
    sameSite: "lax",
    path: "/",
  };
}

function buildLoginUrl(request: NextRequest) {
  const loginUrl = new URL("/login", request.url);
  loginUrl.searchParams.set("redirect", request.nextUrl.pathname + request.nextUrl.search);
  return loginUrl;
}

function applySupabaseCookie(
  base: Partial<CookieOptions>,
  response: NextResponse,
  name: string,
  value: string,
  overrides?: Partial<CookieOptions>
) {
  response.cookies.set({
    name,
    value,
    ...base,
    ...(overrides ?? {}),
  });
}

function clearSupabaseCookies(
  base: Partial<CookieOptions>,
  response: NextResponse,
  request: NextRequest,
  projectRef: string | null
) {
  const expireOverrides: Partial<CookieOptions> = {
    maxAge: 0,
    expires: new Date(0),
  };

  applySupabaseCookie(base, response, "sb-access-token", "", expireOverrides);
  applySupabaseCookie(base, response, "sb-refresh-token", "", expireOverrides);

  const scopedPrefix = projectRef ? `sb-${projectRef}-auth-token` : null;

  for (const { name } of request.cookies.getAll()) {
    if (name === "sb-access-token" || name === "sb-refresh-token") continue;
    if (name.startsWith("sb-") || (scopedPrefix && name.startsWith(scopedPrefix))) {
      applySupabaseCookie(base, response, name, "", expireOverrides);
    }
  }
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (PUBLIC_PATH_PREFIXES.some((prefix) => pathname.startsWith(prefix))) {
    return NextResponse.next();
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return NextResponse.redirect(buildLoginUrl(request));
  }

  const projectRef = getProjectRefFromUrl(supabaseUrl);
  const cookieBase = buildCookieBase(request);

  const response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => {
          applySupabaseCookie(cookieBase, response, name, value, options ?? undefined);
        });
      },
    },
    cookieOptions: cookieBase,
  });

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error?.status === 400 || error?.status === 401 || error?.status === 403) {
    const redirectResponse = NextResponse.redirect(buildLoginUrl(request));
    clearSupabaseCookies(cookieBase, redirectResponse, request, projectRef);
    return redirectResponse;
  }

  if (!user) {
    const redirectResponse = NextResponse.redirect(buildLoginUrl(request));
    clearSupabaseCookies(cookieBase, redirectResponse, request, projectRef);
    return redirectResponse;
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
