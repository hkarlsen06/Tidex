/**
 * Locale API Route
 *
 * Handles locale switching from client components
 */

import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { locales, LOCALE_COOKIE, type Locale } from '@/lib/i18n/config';
import { APP_NAMESPACES, getAppDictionary, type AppNamespace } from '@/lib/i18n/dictionaries';

export async function POST(request: NextRequest) {
  try {
    const { locale, namespaces } = await request.json();

    // Validate locale
    if (!locale || !locales.includes(locale as Locale)) {
      return NextResponse.json(
        { error: 'Invalid locale' },
        { status: 400 }
      );
    }

    // Set cookie
    const cookieStore = await cookies();
    cookieStore.set(LOCALE_COOKIE, locale, {
      path: '/',
      sameSite: 'lax',
      maxAge: 60 * 60 * 24 * 365, // 1 year
    });

    const requestedNamespaces: AppNamespace[] = Array.isArray(namespaces)
      ? namespaces.filter((ns): ns is AppNamespace => typeof ns === 'string' && APP_NAMESPACES.includes(ns as AppNamespace))
      : [];

    const appDictionary = getAppDictionary(locale as Locale, requestedNamespaces);

    return NextResponse.json({
      success: true,
      locale,
      dictionary: appDictionary
    });
  } catch (error) {
    console.error('Failed to update locale:', error);
    return NextResponse.json(
      { error: 'Failed to update locale' },
      { status: 500 }
    );
  }
}
