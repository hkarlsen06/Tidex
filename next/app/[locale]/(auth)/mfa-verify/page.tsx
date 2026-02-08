import { Suspense } from 'react';
import { ShieldCheck } from 'lucide-react';
import MfaVerifyClient from './MfaVerifyClient';
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
    <div className="relative w-full max-w-md mx-auto">
      <div className="flex flex-col items-center gap-4 mb-10">
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-brand-gradient-start/10">
          <ShieldCheck className="h-9 w-9 text-brand-gradient-start animate-pulse" />
        </div>
        <h1 className="text-2xl font-bold text-foreground">{t.pages.auth.mfaVerify.title}</h1>
        <p className="text-sm text-text-secondary text-center">{t.pages.auth.mfaVerify.description}</p>
      </div>
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
        <div className="h-12 rounded-xl bg-surface-primary/50 animate-pulse" />
      </div>
      {/* Back to login link skeleton */}
      <div className="mt-10 flex justify-center">
        <div className="h-5 w-28 rounded bg-surface-primary/50 animate-pulse" />
      </div>
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
