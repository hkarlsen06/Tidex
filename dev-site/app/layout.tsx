import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({ subsets: ['latin'], display: 'swap' });

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
        url: '/og/portfolio.png',
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
    images: ['/og/portfolio.png'],
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
