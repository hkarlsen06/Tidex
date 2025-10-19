import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

function getProjectRefFromUrl(url: string) {
  try {
    const u = new URL(url);
    // e.g. https://kkarlsen-dev.supabase.co -> kkarlsen-dev
    const host = u.hostname; // kkarlsen-dev.supabase.co
    const [ref] = host.split('.');
    return ref || '';
  } catch {
    return '';
  }
}

function clearSupabaseCookies(res: NextResponse, req: NextRequest, projectRef: string) {
  // Clear new-style names (some setups use these)
  res.cookies.set({ name: 'sb-access-token', value: '', path: '/', maxAge: 0 });
  res.cookies.set({ name: 'sb-refresh-token', value: '', path: '/', maxAge: 0 });

  // Clear project-scoped cookie names: sb-<project-ref>-auth-token.*
  const prefix = projectRef ? `sb-${projectRef}-auth-token` : 'sb-';
  for (const { name } of req.cookies.getAll()) {
    if (name === 'sb-access-token' || name === 'sb-refresh-token') continue;
    if (name.startsWith(prefix)) {
      res.cookies.set({ name, value: '', path: '/', maxAge: 0 });
    }
  }
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublicRoute =
    pathname.startsWith('/login') ||
    pathname.startsWith('/signup') ||
    pathname.startsWith('/auth/') ||
    pathname.startsWith('/reset-password');

  // We’ll mutate cookies on this response if Supabase updates them.
  const res = NextResponse.next();

  if (isPublicRoute) return res;

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

  // Quick guard: if envs aren’t loaded, you’ll always look logged out.
  if (!supabaseUrl || !supabaseKey) {
    // Don’t loop; just send to login.
    return NextResponse.redirect(new URL('/login', request.url));
  }

  const projectRef = getProjectRefFromUrl(supabaseUrl);

  // Use the cookie adapter that matches older & newer ssr versions (get/set/remove).
  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      get: (name: string) => request.cookies.get(name)?.value,
      set: (name: string, value: string, options?: any) => {
        res.cookies.set({ name, value, ...options });
      },
      remove: (name: string, options?: any) => {
        res.cookies.set({ name, value: '', ...options, maxAge: 0 });
      },
    },
  });

  const { data: { user }, error } = await supabase.auth.getUser();

  // If refresh token is invalid/missing, purge all possible SB cookie variants and bounce to /login
  if (error?.status === 400 || /refresh token/i.test(error?.message ?? '')) {
    clearSupabaseCookies(res, request, projectRef);
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (!user) {
    // Not authenticated: redirect once.
    return NextResponse.redirect(new URL('/login', request.url));
  }

  // Auth OK
  return res;
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};