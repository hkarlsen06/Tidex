import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';
import { ENV } from '@/lib/env';
import { SUPABASE_AUTH_COOKIE_NAME } from '@/lib/supabase/constants';

const COOKIE_SECURITY_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  maxAge: 60 * 60 * 24 * 7,
  path: '/',
};

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Define public routes that don't need auth
  const isPublicRoute =
    pathname.startsWith('/login') ||
    pathname.startsWith('/signup') ||
    pathname.startsWith('/auth/') ||
    pathname.startsWith('/reset-password');

  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  // Only check auth for protected routes
  if (!isPublicRoute) {
    const supabase = createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
      cookieOptions: {
        name: SUPABASE_AUTH_COOKIE_NAME,
        ...COOKIE_SECURITY_OPTIONS,
      },
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options) {
          response.cookies.set(name, value, options);
        },
        remove(name: string, options) {
          response.cookies.set(name, '', {
            ...options,
            expires: new Date(0),
            maxAge: 0,
          });
        },
      },
    });

    // Try to get the user
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser();

    // Check for stale token errors
    const isStaleTokenError =
      error?.message?.includes('refresh_token_not_found') ||
      error?.message?.includes('Invalid Refresh Token') ||
      error?.status === 400;

    if (isStaleTokenError) {
      console.info('[MIDDLEWARE] Detected stale tokens, clearing cookies and redirecting');

      // Clear all auth cookies
      const cookiesToDelete = [
        SUPABASE_AUTH_COOKIE_NAME,
        `${SUPABASE_AUTH_COOKIE_NAME}.0`,
        `${SUPABASE_AUTH_COOKIE_NAME}.1`,
        `${SUPABASE_AUTH_COOKIE_NAME}.2`,
        `${SUPABASE_AUTH_COOKIE_NAME}.3`,
      ];

      const loginUrl = new URL('/login', request.url);
      const redirectResponse = NextResponse.redirect(loginUrl);

      for (const cookieName of cookiesToDelete) {
        redirectResponse.cookies.set(cookieName, '', {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'lax',
          path: '/',
          expires: new Date(0),
          maxAge: 0,
        });
      }

      return redirectResponse;
    }

    // If no user on protected route, redirect to login
    if (!user) {
      const loginUrl = new URL('/login', request.url);
      return NextResponse.redirect(loginUrl);
    }
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - public files (public folder)
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
