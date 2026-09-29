// next.config.js
const path = require('path');

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Export a fully static site into /out
  output: 'export',

  // `next dev` only: let phones on the local network load the dev server's scripts, so the page can be tested on a
  // real iPhone at http://<this Mac's IP>:3001. Without it the 3D hero phone never loads there.
  allowedDevOrigins: ['192.168.*.*', '10.*.*.*', '*.local'],

  // Make next/image work on static hosting
  images: { unoptimized: true },

  // Optional: keeps URLs consistent on static hosts
  trailingSlash: true,

  // Monorepo/workspace hint so Next traces correctly on Cloudflare Pages
  outputFileTracingRoot: path.join(__dirname, '..'),

  // Set turbopack root for monorepo builds
  turbopack: {
    root: path.join(__dirname, '..'),
  },

  // Each segment has its own root layout (for a per-locale <html lang>), so the
  // 404 page is app/global-not-found.tsx.
  experimental: {
    globalNotFound: true,
    // The stylesheet is about 9 KB, so it goes into the HTML instead of blocking the first paint.
    inlineCss: true,
  },
};

module.exports = nextConfig;
