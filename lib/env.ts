// lib/env.ts
import { logger } from "./logger";

export const ENV = {
  URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  PUBLISHABLE: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
};
if (!ENV.URL || !ENV.PUBLISHABLE) {
  // logs exact cwd + dotenv file location for debugging
  logger.error("Missing environment variables. cwd:", process.cwd());
  throw new Error("ENV missing: NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}
