import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { Inter } from 'next/font/google';
import Script from 'next/script';
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

export default function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <html lang="no" className="dark">
      <body className={`${inter.className} bg-background text-foreground`}>
        <Script
          async
          src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-6148969948097858"
          crossOrigin="anonymous"
          strategy="afterInteractive"
        />
        {children}
      </body>
    </html>
  );
}
