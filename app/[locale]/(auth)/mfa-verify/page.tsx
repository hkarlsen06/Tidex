import { Suspense } from 'react';
import MfaVerifyClient from './MfaVerifyClient';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/app/Card';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

type MfaVerifySearchParams = {
  next?: string | string[];
};

const DEFAULT_REDIRECT = '/';

function pickFirst(value?: string | string[]) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}

function resolveNextPath(searchParams: MfaVerifySearchParams, locale: string): string {
  const raw = pickFirst(searchParams?.next) ?? DEFAULT_REDIRECT;

  if (typeof raw !== 'string') {
    return `/${locale}`;
  }

  if (!raw.startsWith('/') || raw.startsWith('//')) {
    return `/${locale}`;
  }

  return raw;
}

// Server-rendered skeleton for immediate FCP
async function MfaVerifySkeleton({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.auth']);

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
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
    <Suspense fallback={<MfaVerifySkeleton params={params} />}>
      <MfaVerifyClient locale={locale} nextPath={nextPath} />
    </Suspense>
  );
}
