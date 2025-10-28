// lib/env.ts
import { logger } from "./logger";

export const ENV = {
  URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  PUBLISHABLE: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  PRO_PRICE_ID: process.env.NEXT_PUBLIC_PRO_PRICE_ID,
  MAX_PRICE_ID: process.env.NEXT_PUBLIC_MAX_PRICE_ID,
  PRO_YEARLY_PRICE_ID: process.env.NEXT_PUBLIC_PRO_YEARLY_ID,
  MAX_YEARLY_PRICE_ID: process.env.NEXT_PUBLIC_MAX_YEARLY_ID,
  TURNSTILE_SITE_KEY: process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY,
};
if (!ENV.URL || !ENV.PUBLISHABLE) {
  // logs exact cwd + dotenv file location for debugging
  logger.error("Missing environment variables. cwd:", process.cwd());
  throw new Error("ENV missing: NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}
if (!ENV.PRO_PRICE_ID || !ENV.MAX_PRICE_ID) {
  logger.error("Missing subscription price IDs. cwd:", process.cwd());
  throw new Error("ENV missing: NEXT_PUBLIC_PRO_PRICE_ID or NEXT_PUBLIC_MAX_PRICE_ID");
}
if (!ENV.PRO_YEARLY_PRICE_ID || !ENV.MAX_YEARLY_PRICE_ID) {
  logger.error("Missing yearly subscription price IDs. cwd:", process.cwd());
  throw new Error("ENV missing: NEXT_PUBLIC_PRO_YEARLY_ID or NEXT_PUBLIC_MAX_YEARLY_ID");
}
if (!ENV.TURNSTILE_SITE_KEY) {
  logger.error("Missing Turnstile site key. cwd:", process.cwd());
  throw new Error("ENV missing: NEXT_PUBLIC_TURNSTILE_SITE_KEY");
}
