import { Suspense } from 'react';
import type { Metadata } from 'next';
import LoginClient from './LoginClient';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/app/Card';
import { getTranslations } from '@/lib/i18n/server';
import { locales, type Locale } from '@/lib/i18n/config';

type LoginSearchParams = {
  next?: string | string[];
  redirect?: string | string[];
};

const DEFAULT_REDIRECT = '/';

function pickFirst(value?: string | string[]) {
  if (Array.isArray(value)) {
    return value[0];
  }

  return value;
}

function resolveInitialNext(searchParams: LoginSearchParams): string {
  const raw =
    pickFirst(searchParams?.next) ??
    pickFirst(searchParams?.redirect) ??
    DEFAULT_REDIRECT;

  if (typeof raw !== 'string') {
    return DEFAULT_REDIRECT;
  }

  if (!raw.startsWith('/') || raw.startsWith('//')) {
    return DEFAULT_REDIRECT;
  }

  return raw;
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  // Build language alternates for hreflang tags
  const languages: Record<string, string> = {};
  locales.forEach((loc) => {
    languages[loc] = `https://app.tidex.no/${loc}/login`;
  });

  return {
    title: t.pages.auth.login.skeletonTitle,
    description: 'Logg inn på Tidex for å administrere dine vakter og lønnsberegninger.',
    alternates: {
      canonical: `https://app.tidex.no/${locale}/login`,
      languages,
    },
    robots: {
      index: true,
      follow: true,
    },
  };
}

// Loading skeleton for instant paint
async function LoginSkeleton({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
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
            <div className="h-[65px] rounded-lg bg-surface-primary/50 animate-pulse"></div>
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
  const initialNext = resolveInitialNext(resolvedSearchParams);

  return (
    <Suspense fallback={<LoginSkeleton params={params} />}>
      <LoginClient initialNext={initialNext} params={params} />
    </Suspense>
  );
}
