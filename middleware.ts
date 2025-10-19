import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Define routes that don't need authentication
  const isPublicRoute =
    pathname.startsWith('/login') ||
    pathname.startsWith('/signup') ||
    pathname.startsWith('/auth/') ||
    pathname.startsWith('/reset-password');

  // Always create a response object so we can modify cookies later
  const res = NextResponse.next();

  // Skip auth checks on public routes
  if (isPublicRoute) return res;

  // Create Supabase server client for the middleware
const supabase = createServerClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  {
    cookies: {
      getAll() {
        return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
      },
      setAll(cookies) {
        cookies.forEach(({ name, value, options }) => {
          res.cookies.set({ name, value, ...options });
        });
      },
    },
  }
);

  // Try to get the current user (refreshes tokens if needed)
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  // If refresh token is invalid or expired, clear cookies and redirect to login
  if (error?.status === 400 || /refresh token/i.test(error?.message ?? '')) {
    res.cookies.set({ name: 'sb-access-token', value: '', path: '/', maxAge: 0 });
    res.cookies.set({ name: 'sb-refresh-token', value: '', path: '/', maxAge: 0 });

    const loginUrl = new URL('/login', request.url);
    return NextResponse.redirect(loginUrl);
  }

  // If no user found, redirect to login
  if (!user) {
    const loginUrl = new URL('/login', request.url);
    return NextResponse.redirect(loginUrl);
  }

  // Auth OK — continue
  return res;
}

export const config = {
  matcher: [
    // Match all routes except static assets and public files
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};