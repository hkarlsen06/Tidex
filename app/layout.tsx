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
                // Primary: Check for Capacitor bridge (most reliable)
                // Fallback: Check user agent for iOS without Safari
                function checkNativeIOS() {
                  // Check Capacitor bridge first (injected by native shell)
                  if (window.Capacitor && window.Capacitor.getPlatform) {
                    return window.Capacitor.getPlatform() === 'ios';
                  }
                  // Fallback: iOS device without Safari in UA (WebView)
                  var ua = navigator.userAgent || '';
                  return /iPhone|iPad|iPod/.test(ua) && !/Safari/.test(ua);
                }

                var isIOSNative = checkNativeIOS();

                // Mark native iOS immediately so CSS can hide web NavBar on first paint
                if (isIOSNative) {
                  document.documentElement.classList.add('native-ios');
                }

                // If Capacitor bridge wasn't ready, check again shortly
                // This handles race condition where bridge loads after this script
                if (!window.Capacitor) {
                  var checkCount = 0;
                  var maxChecks = 20; // ~200ms max wait
                  function recheckCapacitor() {
                    checkCount++;
                    if (window.Capacitor && window.Capacitor.getPlatform) {
                      if (window.Capacitor.getPlatform() === 'ios') {
                        document.documentElement.classList.add('native-ios');
                      }
                    } else if (checkCount < maxChecks) {
                      setTimeout(recheckCapacitor, 10);
                    }
                  }
                  setTimeout(recheckCapacitor, 10);
                }

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
