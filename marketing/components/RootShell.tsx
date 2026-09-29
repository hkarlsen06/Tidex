import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { Poppins } from 'next/font/google';
import '@/app/globals.css';

// Poppins SemiBold is the display face of the App Store screenshots and the showcase film.
const poppins = Poppins({ subsets: ['latin'], weight: '600', display: 'swap', variable: '--font-display' });

// Shared by every root layout. Each segment has its own root layout so the
// server-rendered <html lang> matches the page locale.
export const rootMetadata: Metadata = {
  metadataBase: new URL('https://tidex.no'),
  icons: {
    icon: [
      { url: '/favicon.svg', type: 'image/svg+xml' },
      { url: '/favicon-32x32.png', sizes: '32x32', type: 'image/png' },
      { url: '/favicon-192x192.png', sizes: '192x192', type: 'image/png' },
      { url: '/android-chrome-512x512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: [{ url: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
    other: [{ rel: 'mask-icon', url: '/safari-pinned-tab.svg' }],
  },
  other: {
    'apple-itunes-app': 'app-id=6757129790',
  },
};

export const rootViewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#0a0f2e',
  colorScheme: 'dark',
};

export function RootShell({ lang, children }: { lang: string; children: ReactNode }) {
  return (
    <html lang={lang} className="dark">
      <body className={`${poppins.variable} bg-background text-foreground`}>
        {children}
      </body>
    </html>
  );
}
