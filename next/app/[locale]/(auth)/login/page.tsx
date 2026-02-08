import Image from 'next/image';
import { Suspense } from 'react';
import LoginClient from './LoginClient';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

type LoginSearchParams = {
  next?: string | string[];
  redirect?: string | string[];
};

function pickFirst(value?: string | string[]) {
  if (Array.isArray(value)) {
    return value[0];
  }

  return value;
}

function resolveInitialNext(searchParams: LoginSearchParams, locale: string): string {
  const defaultRedirect = `/${locale}/dashboard`;
  const raw =
    pickFirst(searchParams?.next) ??
    pickFirst(searchParams?.redirect) ??
    defaultRedirect;

  if (typeof raw !== 'string') {
    return defaultRedirect;
  }

  if (!raw.startsWith('/') || raw.startsWith('//')) {
    return defaultRedirect;
  }

  if (raw === '/') {
    return defaultRedirect;
  }

  return raw;
}

// Loading skeleton for instant paint
async function LoginSkeleton({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.auth']);

  return (
    <div className="relative w-full max-w-md mx-auto">
      <div className="flex flex-col items-center mb-10">
        <Image
          src="/icons/wordmark-transparent.webp"
          alt="Tidex"
          width={160}
          height={48}
          priority
          className="h-12 w-auto"
        />
        <p className="mt-4 text-sm text-text-secondary">{t.pages.auth.login.skeletonTitle}</p>
      </div>
      <div className="space-y-6">
        <div className="space-y-3">
          <div className="h-12.5 rounded-xl bg-surface-primary/50 animate-pulse"></div>
          <div className="h-12.5 rounded-xl bg-surface-primary/50 animate-pulse"></div>
        </div>
        <div className="h-12 rounded-xl bg-surface-primary/50 animate-pulse"></div>
      </div>
    </div>
  );
}

export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<LoginSearchParams>;
}) {
  const resolvedSearchParams = await searchParams;
  const paramsPromise = params;
  const { locale } = await paramsPromise;
  const initialNext = resolveInitialNext(resolvedSearchParams, locale);

  return (
    <Suspense fallback={<LoginSkeleton params={paramsPromise} />}>
      <LoginClient initialNext={initialNext} params={paramsPromise} />
    </Suspense>
  );
}
