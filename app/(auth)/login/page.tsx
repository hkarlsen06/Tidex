export const dynamic = 'force-dynamic';

import { Suspense } from 'react';
import LoginClient from './LoginClient';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/app/Card';

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

// Loading skeleton for instant paint
function LoginSkeleton() {
  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Hei, du!</CardTitle>
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
  searchParams,
}: {
  searchParams: Promise<LoginSearchParams>;
}) {
  const resolvedSearchParams = await searchParams;
  const initialNext = resolveInitialNext(resolvedSearchParams);

  return (
    <Suspense fallback={<LoginSkeleton />}>
      <LoginClient initialNext={initialNext} />
    </Suspense>
  );
}
