import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** @type {import('next').NextConfig} */
const nextConfig = {
  // You can read this yourself in proxy.ts or wherever you like.
  allowedDevOrigins: ["192.168.68.50"],

  outputFileTracingRoot: __dirname,

  // Next 16 feature replacing the old PPR path.
  // Temporarily disabled due to conflicts with route segment configs
  // cacheComponents: true,

  // Tell Next “yes, I know I’m on Turbopack”.
  turbopack: {},

  experimental: {
    // Keep this if you truly benefit from it.
    optimizePackageImports: ["@tabler/icons-react"],
  },

  // No `eslint` key (Next 16 doesn’t lint in build).
  // No `webpack` function (Turbopack ignores it, and it’s what caused the error).
};

export default nextConfig;