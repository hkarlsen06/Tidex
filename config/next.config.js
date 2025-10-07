/** @type {import('next').NextConfig} */
const nextConfig = {
  // Skip ESLint during production builds on Vercel so devDeps aren't required
  eslint: {
    ignoreDuringBuilds: true,
  },
};

export default nextConfig;
