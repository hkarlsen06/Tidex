import type { ReactNode } from 'react';
import { RootShell, rootMetadata, rootViewport } from '@/components/RootShell';

export const metadata = rootMetadata;
export const viewport = rootViewport;

export default async function LocaleLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  return <RootShell lang={locale === 'no' ? 'no' : 'en'}>{children}</RootShell>;
}
