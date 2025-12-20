import { Suspense } from 'react';
import MfaVerifyClient from './MfaVerifyClient';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

type MfaVerifySearchParams = {
  next?: string | string[];
};

function pickFirst(value?: string | string[]) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}

function resolveNextPath(searchParams: MfaVerifySearchParams, locale: string): string {
  const raw = pickFirst(searchParams?.next);

  // No next param or invalid type - redirect to locale root
  if (typeof raw !== 'string') {
    return `/${locale}`;
  }

  // Security: reject absolute URLs or protocol-relative URLs
  if (!raw.startsWith('/') || raw.startsWith('//')) {
    return `/${locale}`;
  }

  return raw;
}

// Server-rendered skeleton for immediate FCP (must be synchronous for Suspense fallback)
function MfaVerifySkeleton({ locale }: { locale: string }) {
  const t = getTranslations(locale as Locale, ['pages.auth']);

  return (
    <div className="relative w-full">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.mfaVerify.title}</CardTitle>
          <CardDescription>{t.pages.auth.mfaVerify.description}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-6">
            {/* OTP input skeleton */}
            <div className="flex justify-center gap-3 sm:gap-4 px-4 sm:px-0">
              <div className="flex gap-1">
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
              </div>
              <div className="flex items-center text-text-muted">-</div>
              <div className="flex gap-1">
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
                <div className="h-11 w-11 sm:h-14 sm:w-14 rounded-md sm:rounded-lg bg-surface-primary/50 animate-pulse" />
              </div>
            </div>
            {/* Verify button skeleton */}
            <div className="h-11 rounded-md bg-surface-primary/50 animate-pulse" />
          </div>
          {/* Back to login link skeleton */}
          <div className="mt-6 flex justify-center">
            <div className="h-5 w-28 rounded bg-surface-primary/50 animate-pulse" />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<MfaVerifySearchParams>;
}) {
  const { locale } = await params;
  const resolvedSearchParams = await searchParams;
  const nextPath = resolveNextPath(resolvedSearchParams, locale);

  return (
    <Suspense fallback={<MfaVerifySkeleton locale={locale} />}>
      <MfaVerifyClient locale={locale} nextPath={nextPath} />
    </Suspense>
  );
}