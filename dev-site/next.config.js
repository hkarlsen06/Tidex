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

  // Monorepo/workspace hint so Next traces correctly
  outputFileTracingRoot: path.join(__dirname, '..'),

  // Turbopack needs the workspace root to resolve packages in a pnpm monorepo
  turbopack: {
    root: path.join(__dirname, '..'),
  },
};

module.exports = nextConfig;