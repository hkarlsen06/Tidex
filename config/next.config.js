import withPWA from "next-pwa";

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Skip ESLint during production builds on Vercel so devDeps aren't required
  eslint: {
    ignoreDuringBuilds: true,
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
  ],
})(nextConfig);
