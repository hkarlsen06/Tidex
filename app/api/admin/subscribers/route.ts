import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isNextInternalError } from '../_lib/verify-admin';

/**
 * GET /api/admin/subscribers
 *
 * Lists all subscribers with optional filtering by plan type.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Query Parameters:
 * - filter: "all" | "pro" | "max" | "grandfathered" | "trial" (default: "all")
 *
 * Response:
 * - 200: { success: true, subscribers: SubscriberData[] }
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not an admin
 * - 500: { error: string } - Server error
 */

/**
 * Extended user type that includes phone field from Supabase Auth
 */
type AdminUser = {
  id: string;
  email?: string;
  phone?: string;
  user_metadata?: Record<string, unknown>;
  banned_until?: string | null;
};

/**
 * Subscriber data returned to the client
 */
interface SubscriberData {
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
  plan: 'pro' | 'max' | 'trial' | 'free';
}

type FilterType = 'all' | 'pro' | 'max' | 'grandfathered' | 'trial';

// Apple product IDs (must match App Store Connect configuration)
const APPLE_MAX_IDS = ['no.tidex.max', 'no.tidex.max.year'];
const APPLE_PRO_IDS = ['no.tidex.pro', 'no.tidex.pro.year'];

/**
 * Determine the subscription plan (separate from grandfathered status)
 * Supports both Stripe price IDs and Apple product IDs
 */
function determinePlan(
  provider: string | null,
  productId: string | null,
  priceId: string | null,
  status: string | null
): SubscriberData['plan'] {
  // Admin trials
  if (provider === 'admin_trial' && status === 'active') {
    return 'trial';
  }

  // Active subscriptions
  if (status === 'active' || status === 'trialing' || status === 'grace') {
    // Check for Max tier (Stripe price IDs, internal product IDs, and Apple product IDs)
    const maxPriceId = process.env.NEXT_PUBLIC_MAX_PRICE_ID;
    const maxYearlyId = process.env.NEXT_PUBLIC_MAX_YEARLY_ID;
    if (
      (priceId && maxPriceId && priceId === maxPriceId) ||
      (priceId && maxYearlyId && priceId === maxYearlyId) ||
      productId === 'max_monthly' ||
      productId === 'max_yearly' ||
      APPLE_MAX_IDS.includes(priceId ?? '') ||
      APPLE_MAX_IDS.includes(productId ?? '')
    ) {
      return 'max';
    }

    // Check for Pro tier (Stripe price IDs, internal product IDs, and Apple product IDs)
    const proPriceId = process.env.NEXT_PUBLIC_PRO_PRICE_ID;
    const proYearlyId = process.env.NEXT_PUBLIC_PRO_YEARLY_ID;
    if (
      (priceId && proPriceId && priceId === proPriceId) ||
      (priceId && proYearlyId && priceId === proYearlyId) ||
      productId === 'pro_monthly' ||
      productId === 'pro_yearly' ||
      APPLE_PRO_IDS.includes(priceId ?? '') ||
      APPLE_PRO_IDS.includes(productId ?? '')
    ) {
      return 'pro';
    }

    // Default to Pro for other active subscriptions
    return 'pro';
  }

  return 'free';
}

export async function GET(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const filterParam = searchParams.get('filter') ?? 'all';
    const filter: FilterType = ['all', 'pro', 'max', 'grandfathered', 'trial'].includes(filterParam)
      ? (filterParam as FilterType)
      : 'all';

    // Call the SQL function to get subscribers from public tables
    const { data: subscriptionData, error: rpcError } = await supabase.rpc(
      'admin_get_subscribers'
    );

    if (rpcError) {
      console.error('[admin/subscribers] RPC error:', rpcError);
      return NextResponse.json(
        { success: false, message: `Failed to fetch subscribers: ${rpcError.message}` },
        { status: 500 }
      );
    }

    if (!subscriptionData || subscriptionData.length === 0) {
      return NextResponse.json({ success: true, subscribers: [] });
    }

    // Get user IDs to fetch user info
    const userIds = subscriptionData.map(
      (row: { user_id: string }) => row.user_id
    );

    // Fetch user info via auth.admin API
    const userMap = new Map<
      string,
      { email: string | null; phone: string | null; name: string | null }
    >();

    // Batch fetch users (Supabase auth admin doesn't have bulk get, so we iterate)
    for (const userId of userIds) {
      const { data: userData } = await supabase.auth.admin.getUserById(userId);
      if (userData?.user) {
        // Cast to AdminUser to access phone field
        const user = userData.user as unknown as AdminUser;
        // Phone can be in user.phone (phone auth) or user_metadata.phone (manual entry)
        userMap.set(userId, {
          email: user.email || null,
          phone: user.phone || (user.user_metadata?.phone as string | undefined) || null,
          name: (user.user_metadata?.full_name as string) || null,
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
    if (filter !== 'all') {
      if (filter === 'grandfathered') {
        filtered = subscribers.filter((s) => s.isGrandfathered);
      } else {
        filtered = subscribers.filter((s) => s.plan === filter);
      }
    }

    // Sort alphabetically by name (users without names go to end)
    filtered.sort((a, b) => {
      const nameA = a.name?.toLowerCase() ?? '';
      const nameB = b.name?.toLowerCase() ?? '';
      if (!nameA && !nameB) return 0;
      if (!nameA) return 1;
      if (!nameB) return -1;
      return nameA.localeCompare(nameB, 'nb');
    });

    return NextResponse.json({ success: true, subscribers: filtered });
  } catch (error) {
    // Re-throw Next.js internal errors (prerender bailout, etc.)
    if (isNextInternalError(error)) throw error;
    console.error('[admin/subscribers] Exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
