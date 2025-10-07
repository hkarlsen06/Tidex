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
})(nextConfig);
