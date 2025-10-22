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

  // Silence build-time ESLint requirement on CI (or install eslint as a devDep)
  eslint: { ignoreDuringBuilds: true },

  // Monorepo/workspace hint so Next traces correctly on Netlify
  outputFileTracingRoot: path.join(__dirname, '..'),
};

module.exports = nextConfig;