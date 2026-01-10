"use server";

import { invalidateUserCache } from "@/data-access/cache";
import { verifySession } from "@/data-access/auth";

/**
 * Server action to invalidate subscription cache after Apple IAP verification.
 *
 * Apple IAP verification happens in an edge function which cannot call revalidateTag.
 * This server action is called from the client after successful IAP verification
 * to ensure the Next.js cache is invalidated before navigating to the success page.
 */
export async function invalidateSubscriptionCacheAction(): Promise<{ success: boolean }> {
  const { user } = await verifySession();
  invalidateUserCache(user.id);
  return { success: true };
}
