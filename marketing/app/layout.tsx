import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({ subsets: ['latin'], display: 'swap' });

export const metadata: Metadata = {
  title: 'kkarlsen.dev — Regn ut lønna di - gratis!',
  description:
    'Få oversikt over lønn, tillegg og overtid med kkarlsen.dev. En moderne lønnskalkulator som hjelper deg og teamet ditt å holde kontroll.',
  metadataBase: new URL('https://kkarlsen.dev'),
  openGraph: {
    title: 'kkarlsen.dev — Regn ut lønna di - gratis!',
    description:
      'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med kkarlsen.dev.',
    url: 'https://kkarlsen.dev',
    type: 'website',
    images: [
      {
        url: '/og/landing.png',
        width: 1200,
        height: 630,
        alt: 'kkarlsen.dev — Kontroll på lønnen din',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'kkarlsen.dev — Regn ut lønna di - gratis!',
    description:
      'Planlegg vakter, beregn tillegg og få kontroll på lønnen din med kkarlsen.dev.',
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
        {children}
      </body>
    </html>
  );
}
