import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { SUPABASE_AUTH_COOKIE_NAME } from '@/lib/supabase/constants';

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Define public routes that don't need auth
  const isPublicRoute =
    pathname.startsWith('/login') ||
    pathname.startsWith('/signup') ||
    pathname.startsWith('/auth/') ||
    pathname.startsWith('/reset-password');

  // Only check auth for protected routes
  if (!isPublicRoute) {
    const hasSupabaseCookie = request.cookies
      .getAll()
      .some((cookie) => cookie.name.startsWith(SUPABASE_AUTH_COOKIE_NAME));

    if (!hasSupabaseCookie) {
      const loginUrl = new URL('/login', request.url);
      return NextResponse.redirect(loginUrl);
    }
  }

  return NextResponse.next();
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
