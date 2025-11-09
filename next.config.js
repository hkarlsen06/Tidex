import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** @type {import('next').NextConfig} */
const nextConfig = {
  // You can read this yourself in proxy.ts or wherever you like.
  allowedDevOrigins: ["192.168.68.50"],

  outputFileTracingRoot: __dirname,
  // Tell Next "yes, I know I'm on Turbopack".
  turbopack: {},

  cacheComponents: true,

  experimental: {
    // Optimize package imports to reduce bundle size
    // optimizePackageImports handles tree-shaking for these packages
    optimizePackageImports: [
      "recharts",
      "lucide-react",
    ],
  },

  // Configure headers for service worker and PWA assets
  async headers() {
    return [
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
    ];
  },

  // No `eslint` key (Next 16 doesn't lint in build).
  // No `webpack` function (Turbopack ignores it, and it's what caused the error).
};

export default nextConfig;
