// next.config.js
const path = require('path');

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Export a fully static site into /out
  output: 'export',

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
};

module.exports = nextConfig;
