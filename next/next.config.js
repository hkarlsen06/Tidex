import path from "node:path";
import { fileURLToPath } from "node:url";
import bundleAnalyzer from "@next/bundle-analyzer";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === "true",
});

// Detect tunnel mode (set by local-ios script)
const isTunnelMode = process.env.TUNNEL_MODE === "true";

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Expose TUNNEL_MODE to client-side code
  env: {
    NEXT_PUBLIC_TUNNEL_MODE: isTunnelMode ? "true" : "",
  },
  // You can read this yourself in proxy.ts or wherever you like.
  allowedDevOrigins: ["192.168.68.50", "192.168.68.62", "dev.tidex.no", "172.20.10.5"],

  // Move dev indicator to top-left to avoid overlap with native tab bar on iOS
  devIndicators: {
    position: "top-left",
  },

  // In tunnel mode, disable automatic page reload on chunk load errors
  // This prevents infinite reload loops when HMR WebSocket fails through Cloudflare tunnel
  ...(isTunnelMode && {
    onDemandEntries: {
      // Keep pages in memory longer to reduce chunk loading
      maxInactiveAge: 60 * 60 * 1000, // 1 hour
      pagesBufferLength: 10,
    },
  }),

  // Configure allowed external image hosts
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "lh3.googleusercontent.com",
        pathname: "/**",
      },
      {
        protocol: "https",
        hostname: "*.supabase.co",
        pathname: "/storage/v1/object/public/**",
      },
      {
        protocol: "https",
        hostname: "identity.tidex.no",
        pathname: "/storage/v1/object/public/**",
      },
    ],
  },

  outputFileTracingRoot: path.join(__dirname, ".."),
  // Tell Next "yes, I know I'm on Turbopack".
  turbopack: {
    root: path.join(__dirname, ".."),
  },

  cacheComponents: true,

  // Enable React 19 Compiler for automatic optimization
  // Reduces need for manual useMemo/useCallback/memo
  reactCompiler: true,

  // Enable compression for smaller file sizes
  compress: true,

  experimental: {
    // Optimize package imports to reduce bundle size
    // optimizePackageImports handles tree-shaking for these packages
    optimizePackageImports: [
      "recharts",
      "lucide-react",
      "@vercel/analytics",
      "@vercel/speed-insights",
    ],

    // Enable router cache for prefetched and dynamic pages
    // Required for 'use cache: private' to persist across navigations
    // In development: use minimum cache times (30s) for faster iteration
    // In production: longer cache times for performance
    staleTimes: {
      dynamic: process.env.NODE_ENV === "development" ? 30 : 300,
      static: process.env.NODE_ENV === "development" ? 30 : 180,
    },
  },

  // Configure headers for service worker and PWA assets
  async headers() {
    const headers = [
      // In tunnel mode, add CORS headers for _next/static to prevent chunk load failures
      ...(isTunnelMode
        ? [
            {
              source: "/_next/static/:path*",
              headers: [
                { key: "Access-Control-Allow-Origin", value: "*" },
                { key: "Access-Control-Allow-Methods", value: "GET, OPTIONS" },
              ],
            },
          ]
        : []),
      {
        source: '/sw.js',
        headers: [
          {
            key: 'Cache-Control',
            value: 'no-cache, no-store, must-revalidate',
          },
          {
            key: 'Service-Worker-Allowed',
            value: '/',
          },
        ],
      },
      {
        source: '/offline.html',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=86400, stale-while-revalidate',
          },
        ],
      },
      {
        source: '/manifest.json',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=86400, stale-while-revalidate',
          },
        ],
      },
      // Cache static assets aggressively
      {
        source: '/:path(icon-.*\\.png)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      {
        source: '/apple-touch-icon.png',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      // Apple App Site Association for iOS Universal Links
      {
        source: '/.well-known/apple-app-site-association',
        headers: [
          {
            key: 'Content-Type',
            value: 'application/json',
          },
          {
            key: 'Cache-Control',
            value: 'public, max-age=86400',
          },
        ],
      },
    ];
    return headers;
  },

  // No `eslint` key (Next 16 doesn't lint in build).
  // No `webpack` function (Turbopack ignores it, and it's what caused the error).
};

export default withBundleAnalyzer(nextConfig);
