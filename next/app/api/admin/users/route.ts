import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import {
  verifyAdminFromRequest,
  isNextInternalError,
  SUPERADMIN_USER_ID,
} from '../_lib/verify-admin';

/**
 * GET /api/admin/users
 *
 * List and search users with pagination support.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Query Parameters:
 * - page: number - Page number (1-indexed, default: 1)
 * - perPage: number - Items per page (default: 20)
 * - search: string - Search term for email, phone, or name
 *
 * Response:
 * - 200: { users: UserListItem[], totalCount: number, page: number, perPage: number, resultsArePartial: boolean }
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not an admin
 * - 500: { error: string } - Server error
 */

/**
 * Extended user type from Supabase Auth
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
 * User list item returned to the client
 */
interface UserListItem {
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
  plan: 'pro' | 'max' | 'trial' | 'free';
}

const DEFAULT_PER_PAGE = 20;
const MAX_SEARCH_ITERATIONS = 5;
const SEARCH_BATCH_SIZE = 100;

// Apple product IDs (must match App Store Connect configuration)
const APPLE_MAX_IDS = ['no.tidex.max', 'no.tidex.max.year'];
const APPLE_PRO_IDS = ['no.tidex.pro', 'no.tidex.pro.year'];

export async function GET(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const page = Math.max(1, parseInt(searchParams.get('page') ?? '1', 10));
    const perPage = parseInt(
      searchParams.get('perPage') ?? String(DEFAULT_PER_PAGE),
      10
    );
    const search = searchParams.get('search')?.trim().toLowerCase() ?? '';

    // Fetch subscription and profile data for tier determination
    const { data: subscriptionsData } = await supabase
      .from('subscriptions')
      .select(
        'user_id, provider, product_id, price_id, status, current_period_end'
      );

    const { data: profilesData } = await supabase
      .from('profiles')
      .select('id, before_paywall');

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

    // Determine plan for a user
    const determinePlan = (userId: string): UserListItem['plan'] => {
      const sub = subscriptionMap.get(userId);
      if (!sub) return 'free';

      const isActive =
        (sub.status === 'active' ||
          sub.status === 'trialing' ||
          sub.status === 'grace') &&
        (!sub.currentPeriodEnd ||
          new Date(sub.currentPeriodEnd) > new Date());

      if (!isActive) return 'free';

      if (sub.provider === 'admin_trial') return 'trial';

      // Check for Max tier
      const maxPriceId = process.env.NEXT_PUBLIC_MAX_PRICE_ID;
      const maxYearlyId = process.env.NEXT_PUBLIC_MAX_YEARLY_ID;
      if (
        sub.priceId === maxPriceId ||
        sub.priceId === maxYearlyId ||
        sub.productId === 'max_monthly' ||
        sub.productId === 'max_yearly' ||
        APPLE_MAX_IDS.includes(sub.priceId ?? '') ||
        APPLE_MAX_IDS.includes(sub.productId ?? '')
      ) {
        return 'max';
      }

      // Check for Pro tier
      const proPriceId = process.env.NEXT_PUBLIC_PRO_PRICE_ID;
      const proYearlyId = process.env.NEXT_PUBLIC_PRO_YEARLY_ID;
      if (
        sub.priceId === proPriceId ||
        sub.priceId === proYearlyId ||
        sub.productId === 'pro_monthly' ||
        sub.productId === 'pro_yearly' ||
        APPLE_PRO_IDS.includes(sub.priceId ?? '') ||
        APPLE_PRO_IDS.includes(sub.productId ?? '')
      ) {
        return 'pro';
      }

      // Default to pro for any other active subscription
      return 'pro';
    };

    // Transform auth user to UserListItem
    const transformUser = (authUser: AdminUser): UserListItem => {
      const role = authUser.app_metadata?.role as string | undefined;
      const isAdmin = role === 'admin';
      const isSuperAdmin = authUser.id === SUPERADMIN_USER_ID;
      const bannedUntil = authUser.banned_until ?? null;
      const phone =
        authUser.phone ||
        (authUser.user_metadata?.phone as string | undefined) ||
        null;
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
        console.error('[admin/users] List users error:', error);
        return NextResponse.json(
          { error: 'Failed to fetch users' },
          { status: 500 }
        );
      }

      const users = (data.users as unknown as AdminUser[]).map(transformUser);

      // Sort alphabetically by name (users without names go to end)
      users.sort((a, b) => {
        const nameA = a.name?.toLowerCase() ?? '';
        const nameB = b.name?.toLowerCase() ?? '';
        if (!nameA && !nameB) return 0;
        if (!nameA) return 1;
        if (!nameB) return -1;
        return nameA.localeCompare(nameB, 'nb');
      });

      const hasMore = data.users.length === perPage;
      const estimatedTotal = hasMore
        ? page * perPage + 1
        : (page - 1) * perPage + data.users.length;

      return NextResponse.json({
        users,
        totalCount: estimatedTotal,
        page,
        perPage,
        resultsArePartial: false,
      });
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
        console.error('[admin/users] Search users error:', error);
        return NextResponse.json(
          { error: 'Failed to search users' },
          { status: 500 }
        );
      }

      // No more users to fetch
      if (data.users.length === 0) {
        break;
      }

      const adminUsers = data.users as unknown as AdminUser[];

      // Filter by search term (email, phone, or name)
      for (const authUser of adminUsers) {
        const email = (authUser.email || '').toLowerCase();
        const phone = (
          authUser.phone ||
          (authUser.user_metadata?.phone as string | undefined) ||
          ''
        ).toLowerCase();
        const name = (
          (authUser.user_metadata?.full_name as string) || ''
        ).toLowerCase();

        if (
          email.includes(search) ||
          phone.includes(search) ||
          name.includes(search)
        ) {
          matchingUsers.push(transformUser(authUser));
        }

        if (matchingUsers.length >= perPage) {
          break;
        }
      }

      if (data.users.length < SEARCH_BATCH_SIZE) {
        break;
      }

      currentPage++;
    }

    if (iterations >= MAX_SEARCH_ITERATIONS && matchingUsers.length >= perPage) {
      resultsArePartial = true;
    }

    return NextResponse.json({
      users: matchingUsers.slice(0, perPage),
      totalCount: matchingUsers.length,
      page: 1,
      perPage,
      resultsArePartial,
    });
  } catch (error) {
    // Re-throw Next.js internal errors (prerender bailout, etc.)
    if (isNextInternalError(error)) throw error;
    console.error('[admin/users] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
