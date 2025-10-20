export const dynamic = 'force-dynamic';

import LoginClient from './LoginClient';

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

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<LoginSearchParams>;
}) {
  const resolvedSearchParams = await searchParams;
  const initialNext = resolveInitialNext(resolvedSearchParams);

  return <LoginClient initialNext={initialNext} />;
}
