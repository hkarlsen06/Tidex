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

export default function Page({ searchParams }: { searchParams: LoginSearchParams }) {
  const initialNext = resolveInitialNext(searchParams);

  return <LoginClient initialNext={initialNext} />;
}
