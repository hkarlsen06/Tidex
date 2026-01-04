import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { Inter } from "next/font/google";

import { Analytics } from "@vercel/analytics/next";

import SWRegister from "./sw-register";
import { CapacitorUrlListener } from "./capacitor-url-listener";
import { ChunkErrorRecovery } from "./chunk-error-recovery";
import { DynamicThemeColor } from "@/components/app/DynamicThemeColor";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "600", "700"], // Reduced to only critical weights
  display: "optional", // Prevents layout shift, allows system font during load
  variable: "--font-inter",
  preload: true,
  fallback: ["system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"],
  adjustFontFallback: true, // Size-adjust fallback font to match Inter metrics
});

export const metadata: Metadata = {
  title: "Tidex",
  description: "App for å regne ut lønn basert på skiftene dine med tillegg!",
  manifest: "/manifest.json",
  applicationName: "Tidex",
  icons: {
    icon: [
      {
        url: "/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        url: "/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
    apple: [
      {
        url: "/apple-touch-icon.png",
      },
    ],
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Tidex",
    startupImage: [
      // iPhone 14 Pro / 13 Pro / 12 Pro (390x844)
      {
        media: "(device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3)",
        url: "/splash/apple-splash-1170-2532.svg",
      },
      {
        media: "(device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: landscape)",
        url: "/splash/apple-splash-2532-1170.svg",
      },
      // iPhone 14 Plus / 13 Pro Max / 12 Pro Max (428x926)
      {
        media: "(device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3)",
        url: "/splash/apple-splash-1284-2778.svg",
      },
      {
        media: "(device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: landscape)",
        url: "/splash/apple-splash-2778-1284.svg",
      },
      // iPhone 14 / 13 / 12 (390x844)
      {
        media: "(device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3)",
        url: "/splash/apple-splash-1125-2436.svg",
      },
      {
        media: "(device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: landscape)",
        url: "/splash/apple-splash-2436-1125.svg",
      },
      // iPhone 8 Plus / 7 Plus / 6s Plus (414x736)
      {
        media: "(device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3)",
        url: "/splash/apple-splash-1242-2208.svg",
      },
      {
        media: "(device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3) and (orientation: landscape)",
        url: "/splash/apple-splash-2208-1242.svg",
      },
      // iPhone 8 / 7 / 6s (375x667)
      {
        media: "(device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2)",
        url: "/splash/apple-splash-750-1334.svg",
      },
      {
        media: "(device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
        url: "/splash/apple-splash-1334-750.svg",
      },
      // iPad Pro 12.9" (1024x1366)
      {
        media: "(device-width: 1024px) and (device-height: 1366px) and (-webkit-device-pixel-ratio: 2)",
        url: "/splash/apple-splash-2048-2732.svg",
      },
      {
        media: "(device-width: 1024px) and (device-height: 1366px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
        url: "/splash/apple-splash-2732-2048.svg",
      },
      // iPad Pro 11" (834x1194)
      {
        media: "(device-width: 834px) and (device-height: 1194px) and (-webkit-device-pixel-ratio: 2)",
        url: "/splash/apple-splash-1668-2388.svg",
      },
      {
        media: "(device-width: 834px) and (device-height: 1194px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
        url: "/splash/apple-splash-2388-1668.svg",
      },
      // iPad Air / iPad Mini (820x1180)
      {
        media: "(device-width: 820px) and (device-height: 1180px) and (-webkit-device-pixel-ratio: 2)",
        url: "/splash/apple-splash-1640-2360.svg",
      },
      {
        media: "(device-width: 820px) and (device-height: 1180px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
        url: "/splash/apple-splash-2360-1640.svg",
      },
      // iPad 10.2" (810x1080)
      {
        media: "(device-width: 810px) and (device-height: 1080px) and (-webkit-device-pixel-ratio: 2)",
        url: "/splash/apple-splash-1620-2160.svg",
      },
      {
        media: "(device-width: 810px) and (device-height: 1080px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
        url: "/splash/apple-splash-2160-1620.svg",
      },
    ],
  },
  // Critical iOS meta tag workaround for Next.js 16 bug
  // See: https://github.com/vercel/next.js/issues/74524
  other: {
    'apple-mobile-web-app-capable': 'yes',
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#0e172a",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="no" className="safe-area-loading" suppressHydrationWarning>
      <head>
        <meta name="mobile-web-app-capable" content="yes" />
        {/* Critical resource hints for faster loading */}
        <link rel="preconnect" href="https://identity.tidex.no" crossOrigin="anonymous" />
        <link rel="dns-prefetch" href="https://identity.tidex.no" />
        {/* Defer non-critical third-party connections */}
        <link rel="preconnect" href="https://vercel.live" crossOrigin="anonymous" />
        <link rel="dns-prefetch" href="https://vercel.live" />
        {/* Inline critical scripts for instant paint without layout shift */}
        <script
          dangerouslySetInnerHTML={{
            __html: `
              try {
                // Detect if running in iOS native app (Capacitor WebView)
                // iOS WKWebView doesn't have Safari in user agent when embedded
                var ua = navigator.userAgent || '';
                var isIOSNative = /iPhone|iPad|iPod/.test(ua) && !/Safari/.test(ua);

                // Initialize theme from localStorage or system preference
                // ThemeProvider will sync with DB preference on authenticated pages
                // On native iOS, always start dark to match the launch screen
                var savedTheme = localStorage.getItem('theme');
                var theme;
                if (isIOSNative) {
                  // Native iOS: force dark to match launch screen, then system will take over
                  theme = 'dark';
                } else {
                  theme = savedTheme || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
                }
                document.documentElement.classList.toggle('dark', theme === 'dark');

                // Wait for safe-area-insets to be available before showing content
                // On iOS PWA/Capacitor, env() values are not immediately available
                // This prevents the layout shift when the header/navbar snap into position
                (function waitForSafeArea() {
                  // Create a test element to measure safe-area-inset-top
                  var test = document.createElement('div');
                  test.style.cssText = 'position:fixed;top:env(safe-area-inset-top,0px);left:0;width:1px;height:1px;pointer-events:none;visibility:hidden';
                  document.documentElement.appendChild(test);

                  function check() {
                    var rect = test.getBoundingClientRect();
                    // If top > 0, safe-area-insets are resolved (notched device)
                    // If top === 0, either no notch or values not yet available
                    // We use a short timeout to ensure the CSS has been applied
                    if (rect.top > 0) {
                      // Safe area is available and non-zero
                      document.documentElement.classList.remove('safe-area-loading');
                      test.remove();
                    } else {
                      // Check if we're on a device that should have safe-area
                      // Use CSS.supports to check if env() is understood by the browser
                      var supportsEnv = CSS.supports && CSS.supports('top', 'env(safe-area-inset-top)');
                      if (!supportsEnv) {
                        // Browser doesn't support env(), no need to wait
                        document.documentElement.classList.remove('safe-area-loading');
                        test.remove();
                      } else {
                        // Wait a frame and check again (max ~100ms total)
                        requestAnimationFrame(function() {
                          setTimeout(function() {
                            // After waiting, remove regardless (fallback)
                            document.documentElement.classList.remove('safe-area-loading');
                            test.remove();
                          }, 50);
                        });
                      }
                    }
                  }

                  // Use rAF to ensure layout is computed
                  requestAnimationFrame(check);
                })();
              } catch (e) {
                // If anything fails, make sure we show the content
                document.documentElement.classList.remove('safe-area-loading');
              }
            `,
          }}
        />
      </head>
      <body className={`${inter.className} text-foreground antialiased`}>
        <ChunkErrorRecovery />
        <DynamicThemeColor />
        <CapacitorUrlListener />
        {children}
        <SWRegister />
        <Analytics />
      </body>
    </html>
  );
}
