import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { Inter, Manrope } from 'next/font/google';
import './globals.css';

const inter = Inter({ subsets: ['latin'], display: 'swap' });
const manrope = Manrope({ subsets: ['latin'], display: 'swap', variable: '--font-display' });

export const metadata: Metadata = {
  title: 'Lønnskalkulator | Tidex',
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
    title: 'Lønnskalkulator | Tidex',
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
    title: 'Lønnskalkulator | Tidex',
    description:
      'Planlegg vakter, beregn tillegg og få kontroll på lønnen din med Tidex.',
    images: ['/og/landing.png'],
  },
  other: {
    'apple-itunes-app': 'app-id=6757129790',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#09192b',
  colorScheme: 'dark',
};

export default function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <html lang="no" className="dark">
      <body className={`${inter.className} ${manrope.variable} bg-background text-foreground`}>
        {children}
      </body>
    </html>
  );
}
