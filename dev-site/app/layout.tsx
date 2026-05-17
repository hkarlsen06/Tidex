import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { Inter, Manrope } from 'next/font/google';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  preload: true,
  variable: '--font-inter'
});
const manrope = Manrope({ subsets: ['latin'], display: 'swap', variable: '--font-display' });

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#0a0a0a' },
  ],
};

export const metadata: Metadata = {
  title: 'Hjalmar Karlsen — Full-Stack Developer',
  description:
    'Full-stack developer building beautiful websites with seamless integration. Specializing in React, Next.js, TypeScript, and modern web technologies.',
  metadataBase: new URL('https://kkarlsen.dev'),
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
    title: 'Hjalmar Karlsen — Full-Stack Developer',
    description:
      'Full-stack developer building beautiful websites with seamless integration. Check out my portfolio.',
    url: 'https://kkarlsen.dev',
    type: 'website',
    images: [
      {
        url: '/og/landing.png',
        width: 1200,
        height: 630,
        alt: 'Hjalmar Karlsen — Developer Portfolio',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Hjalmar Karlsen — Full-Stack Developer',
    description:
      'Full-stack developer building beautiful websites. View my portfolio and projects.',
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
      <head>
        {/* Preconnect to Google Fonts for faster font loading */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        {/* DNS prefetch for any external resources */}
        <link rel="dns-prefetch" href="https://fonts.googleapis.com" />
      </head>
      <body className={`${inter.className} ${manrope.variable} bg-background text-foreground antialiased`}>
        {children}
      </body>
    </html>
  );
}
