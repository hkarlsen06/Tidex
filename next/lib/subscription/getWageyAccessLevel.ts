/**
 * Wagey Access Level Helper
 *
 * Re-exports getUserTier for backward compatibility.
 * New code should import directly from @/lib/subscription/getUserTier.
 */

export { getUserTier as getWageyAccessLevel } from "./getUserTier";
