"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

/**
 * Extended user type that includes phone field from Supabase Auth
 * The SDK's User type may not include phone depending on version
 */
type AdminUser = {
  id: string;
  email?: string;
  phone?: string;
  user_metadata?: Record<string, unknown>;
  banned_until?: string | null;
};

export interface SubscriberData {
  userId: string;
  email: string | null;
  phone: string | null;
  name: string | null;
  provider: string | null;
  productId: string | null;
  priceId: string | null;
  status: string | null;
  currentPeriodEnd: string | null;
  isGrandfathered: boolean;
  // Subscription plan (separate from grandfathered status)
  plan: "pro" | "max" | "trial" | "free";
}

type FilterType = "all" | "pro" | "max" | "grandfathered" | "trial";

interface GetSubscribersResult {
  success: true;
  subscribers: SubscriberData[];
}

interface GetSubscribersError {
  success: false;
  message: string;
}

/**
 * Determine the subscription plan (separate from grandfathered status)
 */
function determinePlan(
  provider: string | null,
  productId: string | null,
  priceId: string | null,
  status: string | null
): SubscriberData["plan"] {
  // Admin trials
  if (provider === "admin_trial" && status === "active") {
    return "trial";
  }

  // Active subscriptions
  if (status === "active" || status === "trialing" || status === "grace") {
    // Check for Max tier
    const maxPriceId = process.env.NEXT_PUBLIC_MAX_PRICE_ID;
    if (priceId && maxPriceId && priceId === maxPriceId) {
      return "max";
    }
    if (productId === "max_monthly" || productId === "max_yearly") {
      return "max";
    }

    // Default to Pro for other active subscriptions
    return "pro";
  }

  return "free";
}

export async function getSubscribers(
  filter: FilterType = "all"
): Promise<GetSubscribersResult | GetSubscribersError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  // Call the SQL function to get subscribers from public tables
  const { data: subscriptionData, error: rpcError } = await supabase.rpc(
    "admin_get_subscribers"
  );

  if (rpcError) {
    return {
      success: false,
      message: `Kunne ikke hente abonnenter: ${rpcError.message}`,
    };
  }

  if (!subscriptionData || subscriptionData.length === 0) {
    return { success: true, subscribers: [] };
  }

  // Get user IDs to fetch user info
  const userIds = subscriptionData.map(
    (row: { user_id: string }) => row.user_id
  );

  // Fetch user info via auth.admin API
  // We need to fetch users individually since listUsers doesn't support filtering by IDs
  const userMap = new Map<
    string,
    { email: string | null; phone: string | null; name: string | null; banned: boolean }
  >();

  // Batch fetch users (Supabase auth admin doesn't have bulk get, so we iterate)
  // For reasonable subscriber counts this should be fine
  for (const userId of userIds) {
    const { data: userData } = await supabase.auth.admin.getUserById(userId);
    if (userData?.user) {
      // Cast to AdminUser to access phone field
      const user = userData.user as unknown as AdminUser;
      const bannedUntil = user.banned_until;
      // Phone can be in user.phone (phone auth) or user_metadata.phone (manual entry)
      // Use || instead of ?? to handle empty strings
      userMap.set(userId, {
        email: user.email || null,
        phone: user.phone || (user.user_metadata?.phone as string | undefined) || null,
        name: (user.user_metadata?.full_name as string) || null,
        banned: !!bannedUntil,
      });
    }
  }

  // Transform data
  const subscribers: SubscriberData[] = subscriptionData.map(
    (row: {
      user_id: string;
      provider: string | null;
      product_id: string | null;
      price_id: string | null;
      status: string | null;
      current_period_end: string | null;
      is_grandfathered: boolean;
    }) => {
      const userInfo = userMap.get(row.user_id) ?? {
        email: null,
        phone: null,
        name: null,
        banned: false,
      };

      return {
        userId: row.user_id,
        email: userInfo.email,
        phone: userInfo.phone,
        name: userInfo.name,
        provider: row.provider,
        productId: row.product_id,
        priceId: row.price_id,
        status: row.status,
        currentPeriodEnd: row.current_period_end,
        isGrandfathered: row.is_grandfathered,
        plan: determinePlan(
          row.provider,
          row.product_id,
          row.price_id,
          row.status
        ),
      };
    }
  );

  // Apply filter
  let filtered = subscribers;
  if (filter !== "all") {
    if (filter === "grandfathered") {
      filtered = subscribers.filter((s) => s.isGrandfathered);
    } else {
      filtered = subscribers.filter((s) => s.plan === filter);
    }
  }

  // Sort alphabetically by name (users without names go to end)
  filtered.sort((a, b) => {
    const nameA = a.name?.toLowerCase() ?? "";
    const nameB = b.name?.toLowerCase() ?? "";
    if (!nameA && !nameB) return 0;
    if (!nameA) return 1;
    if (!nameB) return -1;
    return nameA.localeCompare(nameB, "nb");
  });

  return { success: true, subscribers: filtered };
}
