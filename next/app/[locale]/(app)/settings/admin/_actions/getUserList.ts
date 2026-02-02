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
  created_at?: string;
  last_sign_in_at?: string | null;
  app_metadata?: Record<string, unknown>;
  user_metadata?: Record<string, unknown>;
  banned_until?: string | null;
};

/**
 * Superadmin user ID - only this user can grant/revoke admin privileges
 * This is Hjalmar's account (primary developer)
 */
const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

export interface UserListItem {
  id: string;
  email: string | null;
  phone: string | null;
  name: string | null;
  lastSignInAt: string | null;
  createdAt: string;
  isBanned: boolean;
  bannedUntil: string | null;
  isAdmin: boolean;
  isSuperAdmin: boolean;
  isGrandfathered: boolean;
  // Subscription plan (separate from admin status)
  plan: "pro" | "max" | "trial" | "free";
}

interface GetUserListInput {
  page: number;
  perPage?: number;
  search?: string;
}

interface GetUserListResult {
  success: true;
  users: UserListItem[];
  totalCount: number;
  page: number;
  perPage: number;
  resultsArePartial: boolean;
}

interface GetUserListError {
  success: false;
  message: string;
}

const DEFAULT_PER_PAGE = 20;
const MAX_SEARCH_ITERATIONS = 5;
const SEARCH_BATCH_SIZE = 100;

export async function getUserList(
  input: GetUserListInput
): Promise<GetUserListResult | GetUserListError> {
  await verifyAdmin();
  const supabase = createSupabaseServiceClient();

  const page = Math.max(1, input.page);
  const perPage = input.perPage ?? DEFAULT_PER_PAGE;
  const search = input.search?.trim().toLowerCase() ?? "";

  // Fetch subscription and profile data for tier determination
  const { data: subscriptionsData } = await supabase
    .from("subscriptions")
    .select("user_id, provider, product_id, price_id, status, current_period_end");

  const { data: profilesData } = await supabase
    .from("profiles")
    .select("id, before_paywall");

  // Build lookup maps
  const subscriptionMap = new Map<
    string,
    {
      provider: string;
      productId: string | null;
      priceId: string | null;
      status: string;
      currentPeriodEnd: string | null;
    }
  >();
  for (const sub of subscriptionsData ?? []) {
    subscriptionMap.set(sub.user_id, {
      provider: sub.provider,
      productId: sub.product_id,
      priceId: sub.price_id,
      status: sub.status,
      currentPeriodEnd: sub.current_period_end,
    });
  }

  const grandfatheredSet = new Set<string>();
  for (const profile of profilesData ?? []) {
    if (profile.before_paywall) {
      grandfatheredSet.add(profile.id);
    }
  }

  // Apple product IDs (must match App Store Connect configuration)
  const APPLE_MAX_IDS = ["no.tidex.max", "no.tidex.max.year"];
  const APPLE_PRO_IDS = ["no.tidex.pro", "no.tidex.pro.year"];

  // Determine plan for a user (separate from admin status)
  const determinePlan = (userId: string): UserListItem["plan"] => {
    const sub = subscriptionMap.get(userId);
    if (!sub) return "free";

    const isActive =
      (sub.status === "active" ||
        sub.status === "trialing" ||
        sub.status === "grace") &&
      (!sub.currentPeriodEnd ||
        new Date(sub.currentPeriodEnd) > new Date());

    if (!isActive) return "free";

    if (sub.provider === "admin_trial") return "trial";

    // Check for Max tier (Stripe price IDs, internal product IDs, and Apple product IDs)
    const maxPriceId = process.env.NEXT_PUBLIC_MAX_PRICE_ID;
    const maxYearlyId = process.env.NEXT_PUBLIC_MAX_YEARLY_ID;
    if (
      sub.priceId === maxPriceId ||
      sub.priceId === maxYearlyId ||
      sub.productId === "max_monthly" ||
      sub.productId === "max_yearly" ||
      APPLE_MAX_IDS.includes(sub.priceId ?? "") ||
      APPLE_MAX_IDS.includes(sub.productId ?? "")
    ) {
      return "max";
    }

    // Check for Pro tier (Stripe price IDs, internal product IDs, and Apple product IDs)
    const proPriceId = process.env.NEXT_PUBLIC_PRO_PRICE_ID;
    const proYearlyId = process.env.NEXT_PUBLIC_PRO_YEARLY_ID;
    if (
      sub.priceId === proPriceId ||
      sub.priceId === proYearlyId ||
      sub.productId === "pro_monthly" ||
      sub.productId === "pro_yearly" ||
      APPLE_PRO_IDS.includes(sub.priceId ?? "") ||
      APPLE_PRO_IDS.includes(sub.productId ?? "")
    ) {
      return "pro";
    }

    // Default to pro for any other active subscription
    return "pro";
  };

  // Transform auth user to UserListItem
  const transformUser = (authUser: AdminUser): UserListItem => {
    const role = authUser.app_metadata?.role as string | undefined;
    const isAdmin = role === "admin";
    const isSuperAdmin = authUser.id === SUPERADMIN_USER_ID;
    const bannedUntil = authUser.banned_until ?? null;
    // Phone can be in authUser.phone (phone auth) or user_metadata.phone (manual entry)
    // Use || instead of ?? to handle empty strings
    const phone = authUser.phone || (authUser.user_metadata?.phone as string | undefined) || null;
    // Email can also be empty string, normalize to null
    const email = authUser.email || null;

    return {
      id: authUser.id,
      email,
      phone,
      name: (authUser.user_metadata?.full_name as string) ?? null,
      lastSignInAt: authUser.last_sign_in_at ?? null,
      createdAt: authUser.created_at ?? new Date().toISOString(),
      isBanned: !!bannedUntil,
      bannedUntil,
      isAdmin,
      isSuperAdmin,
      isGrandfathered: grandfatheredSet.has(authUser.id),
      plan: determinePlan(authUser.id),
    };
  };

  // When no search, use direct pagination
  if (!search) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) {
      return {
        success: false,
        message: `Kunne ikke hente brukere: ${error.message}`,
      };
    }

    // Cast to AdminUser[] to access phone field
    const users = (data.users as unknown as AdminUser[]).map(transformUser);

    // Sort alphabetically by name (users without names go to end)
    users.sort((a, b) => {
      const nameA = a.name?.toLowerCase() ?? "";
      const nameB = b.name?.toLowerCase() ?? "";
      if (!nameA && !nameB) return 0;
      if (!nameA) return 1;
      if (!nameB) return -1;
      return nameA.localeCompare(nameB, "nb");
    });

    // Get total count from first page if needed
    // Supabase listUsers doesn't return total, so we estimate
    // If we got a full page, there are likely more
    const hasMore = data.users.length === perPage;
    const estimatedTotal = hasMore
      ? page * perPage + 1
      : (page - 1) * perPage + data.users.length;

    return {
      success: true,
      users,
      totalCount: estimatedTotal,
      page,
      perPage,
      resultsArePartial: false,
    };
  }

  // When search is present, fetch larger batches and filter server-side
  const matchingUsers: UserListItem[] = [];
  let currentPage = 1;
  let iterations = 0;
  let resultsArePartial = false;

  while (
    matchingUsers.length < perPage &&
    iterations < MAX_SEARCH_ITERATIONS
  ) {
    iterations++;

    const { data, error } = await supabase.auth.admin.listUsers({
      page: currentPage,
      perPage: SEARCH_BATCH_SIZE,
    });

    if (error) {
      return {
        success: false,
        message: `Kunne ikke søke brukere: ${error.message}`,
      };
    }

    // No more users to fetch
    if (data.users.length === 0) {
      break;
    }

    // Cast to AdminUser[] to access phone field
    const adminUsers = data.users as unknown as AdminUser[];

    // Filter by search term (email, phone, or name)
    for (const authUser of adminUsers) {
      const email = (authUser.email || "").toLowerCase();
      // Phone can be in authUser.phone (phone auth) or user_metadata.phone (manual entry)
      const phone = (
        authUser.phone ||
        (authUser.user_metadata?.phone as string | undefined) ||
        ""
      ).toLowerCase();
      const name =
        ((authUser.user_metadata?.full_name as string) || "").toLowerCase();

      if (email.includes(search) || phone.includes(search) || name.includes(search)) {
        matchingUsers.push(transformUser(authUser));
      }

      // Stop if we have enough results
      if (matchingUsers.length >= perPage) {
        break;
      }
    }

    // If we didn't get a full batch, no more users exist
    if (data.users.length < SEARCH_BATCH_SIZE) {
      break;
    }

    currentPage++;
  }

  // If we hit the iteration limit but there might be more matches
  if (iterations >= MAX_SEARCH_ITERATIONS && matchingUsers.length >= perPage) {
    resultsArePartial = true;
  }

  return {
    success: true,
    users: matchingUsers.slice(0, perPage),
    totalCount: matchingUsers.length,
    page: 1, // Search always returns from start
    perPage,
    resultsArePartial,
  };
}
