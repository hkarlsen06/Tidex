import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { Inter } from 'next/font/google';
import { headers } from 'next/headers';
import { defaultLocale, type Locale } from '@/lib/i18n/config';
import { StructuredData } from '../components/StructuredData';
import './globals.css';

const inter = Inter({ subsets: ['latin'], display: 'swap' });

export const metadata: Metadata = {
  title: 'Tidex — Regn ut lønna di - gratis!',
  description:
    'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som hjelper deg og teamet ditt å holde kontroll.',
  metadataBase: new URL('https://tidex.no'),
  manifest: '/site.webmanifest',
  icons: {
    icon: [
      { url: '/favicon-32x32.png', sizes: '32x32', type: 'image/png' },
      { url: '/favicon-192x192.png', sizes: '192x192', type: 'image/png' },
      { url: '/android-chrome-512x512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: [{ url: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
  },
  openGraph: {
    title: 'Tidex — Regn ut lønna di - gratis!',
    description:
      'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    url: 'https://tidex.no',
    type: 'website',
    images: [
      {
        url: '/og/landing.png',
        width: 1200,
        height: 630,
        alt: 'Tidex — Kontroll på lønnen din',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Tidex — Regn ut lønna di - gratis!',
    description:
      'Planlegg vakter, beregn tillegg og få kontroll på lønnen din med Tidex.',
    images: ['/og/landing.png'],
  },
};

export default async function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  // Get locale from proxy-injected header for proper lang attribute
  const headersList = await headers();
  const locale = (headersList.get('x-tidex-locale') as Locale) || defaultLocale;

  return (
    <html lang={locale} className="dark">
      <head>
        <StructuredData />
      </head>
      <body className={`${inter.className} bg-background text-foreground`}>
        {children}
      </body>
    </html>
  );
}
