import path from "node:path";
import { fileURLToPath } from "node:url";
import withPWA from "next-pwa";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** @type {import('next').NextConfig} */
const nextConfig = {
  allowedDevOrigins: ["192.168.68.50"],
  outputFileTracingRoot: path.join(__dirname, ".."),
  // Skip ESLint during production builds on Vercel so devDeps aren't required
  eslint: {
    ignoreDuringBuilds: true,
  },
  // Optimize icon library imports to reduce bundle size
  experimental: {
    optimizePackageImports: ['@tabler/icons-react'],
  },
};

export default withPWA({
  dest: "public",
  register: true,
  skipWaiting: true,
  disable: process.env.NODE_ENV === "development",
  runtimeCaching: [
    {
      // Bypass auth callback endpoint - must never be cached
      urlPattern: /^https?:\/\/[^/]+\/auth\/callback$/,
      handler: "NetworkOnly",
    },
    {
      // Cache top-level app pages to make reloads and back/forward instant
      // Serve cached immediately, update in background
      urlPattern: /^https?:\/\/[^/]+\/(?:\?.*)?$/,
      handler: "StaleWhileRevalidate",
      method: "GET",
      options: {
        cacheName: "page-root",
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60,
        },
      },
    },
    {
      urlPattern: /^https?:\/\/[^/]+\/shifts(?:\?.*)?$/,
      handler: "StaleWhileRevalidate",
      method: "GET",
      options: {
        cacheName: "page-shifts",
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60,
        },
      },
    },
    {
      urlPattern: /^https?:\/\/[^/]+\/stats(?:\?.*)?$/,
      handler: "StaleWhileRevalidate",
      method: "GET",
      options: {
        cacheName: "page-stats",
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60,
        },
      },
    },
    {
      urlPattern: /^https?:\/\/[^/]+\/settings(?:\?.*)?$/,
      handler: "StaleWhileRevalidate",
      method: "GET",
      options: {
        cacheName: "page-settings",
        expiration: {
          maxEntries: 10,
          maxAgeSeconds: 60,
        },
      },
    },
  ],
})(nextConfig);
