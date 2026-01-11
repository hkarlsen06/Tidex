import { Suspense } from 'react';
import LoginClient from './LoginClient';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/app/Card';
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
    <div className="relative w-full">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">{t.pages.auth.login.skeletonTitle}</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-6">
            <div className="space-y-4">
              <div className="h-10 rounded-md bg-surface-primary/50 animate-pulse"></div>
              <div className="h-10 rounded-md bg-surface-primary/50 animate-pulse"></div>
            </div>
            <div className="h-16.25 rounded-lg bg-surface-primary/50 animate-pulse"></div>
            <div className="h-10 rounded-md bg-surface-primary/50 animate-pulse"></div>
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
