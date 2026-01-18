import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import type { Friend, NotificationFrequency } from "@/data-access/sharing";

// Share limits per subscription tier
const SHARE_LIMITS = {
  free: 1,
  pro: 10,
  max: 20,
} as const;

/**
 * GET /api/sharing/friends
 *
 * Returns the unified friends list and share capacity for the authenticated user.
 * Used by the iOS app's sharing management modal.
 *
 * This endpoint bypasses the Effect layer to avoid session verification issues
 * when called with Bearer token auth from iOS.
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 *
 * Response:
 * {
 *   friends: Friend[],
 *   capacity: { canAdd: boolean, currentCount: number, limit: number }
 * }
 */
export async function GET(request: NextRequest) {
  // Try to get user ID from Authorization header first (iOS)
  // Fall back to cookie-based session (web)
  let userId: string | null = null;

  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const jwt = authHeader.slice(7);

    // Verify JWT and get user - uses server-side validation
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser(jwt);

    if (error || !user) {
      logger.warn("Auth error in /api/sharing/friends:", error?.message);
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    userId = user.id;
  } else {
    // Fall back to cookie-based session (web clients)
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    userId = session.user.id;
  }

  // Create admin client for fetching user data
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    logger.error("Missing Supabase URL or service role key");
    return NextResponse.json(
      { error: "Server configuration error" },
      { status: 500 }
    );
  }

  const adminClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    // Fetch sharers (people who share with me) - including blocked
    const { data: incomingShares, error: incomingError } = await adminClient
      .from("shift_shares")
      .select("owner_id, created_at, show_earnings, blocked, muted")
      .eq("viewer_id", userId)
      .order("created_at", { ascending: false });

    if (incomingError) {
      logger.error("Failed to fetch incoming shares:", incomingError);
      return NextResponse.json(
        { error: "Failed to fetch friends" },
        { status: 500 }
      );
    }

    // Fetch recipients (people I share with)
    const { data: outgoingShares, error: outgoingError } = await adminClient
      .from("shift_shares")
      .select("viewer_id, created_at, show_earnings")
      .eq("owner_id", userId)
      .order("created_at", { ascending: false });

    if (outgoingError) {
      logger.error("Failed to fetch outgoing shares:", outgoingError);
      return NextResponse.json(
        { error: "Failed to fetch friends" },
        { status: 500 }
      );
    }

    // Collect all unique user IDs
    const sharerIds = (incomingShares || []).map((s: any) => s.owner_id);
    const recipientIds = (outgoingShares || []).map((s: any) => s.viewer_id);
    const allUserIds = [...new Set([...sharerIds, ...recipientIds])];

    // Fetch user profiles for all friends
    let userProfiles: Map<
      string,
      {
        email: string | null;
        phone: string | null;
        firstName: string | null;
        profilePictureUrl: string | null;
        oauthAvatarUrl: string | null;
      }
    > = new Map();

    if (allUserIds.length > 0) {
      // Fetch from auth.users
      const { data: usersData, error: usersError } =
        await adminClient.auth.admin.listUsers();

      if (usersError) {
        logger.error("Failed to fetch user profiles:", usersError);
      } else {
        const usersMap = new Map(
          usersData.users.map((u) => [
            u.id,
            {
              email: u.email || null,
              phone: u.phone || null,
              firstName: u.user_metadata?.firstName || u.user_metadata?.full_name || null,
              oauthAvatarUrl: u.user_metadata?.avatar_url || null,
            },
          ])
        );

        // Fetch profile pictures from profiles table
        const { data: profilesData } = await adminClient
          .from("profiles")
          .select("id, profile_picture_url")
          .in("id", allUserIds);

        const profilePicturesMap = new Map(
          (profilesData || []).map((p: any) => [p.id, p.profile_picture_url])
        );

        // Combine data
        for (const id of allUserIds) {
          const userData = usersMap.get(id);
          if (userData) {
            userProfiles.set(id, {
              email: userData.email,
              phone: userData.phone,
              firstName: userData.firstName,
              profilePictureUrl: profilePicturesMap.get(id) || null,
              oauthAvatarUrl: userData.oauthAvatarUrl,
            });
          }
        }
      }
    }

    // Build maps for quick lookup
    const sharerMap = new Map(
      (incomingShares || []).map((s: any) => [
        s.owner_id,
        {
          blocked: s.blocked,
          showEarnings: s.show_earnings,
          sharedAt: s.created_at,
          notificationFrequency: (s.muted ? "muted" : "instant") as NotificationFrequency,
        },
      ])
    );

    const recipientMap = new Map(
      (outgoingShares || []).map((s: any) => [
        s.viewer_id,
        {
          showEarnings: s.show_earnings,
          sharedAt: s.created_at,
        },
      ])
    );

    // Build unified friends list
    const friends: Friend[] = [];

    for (const id of allUserIds) {
      const sharer = sharerMap.get(id);
      const recipient = recipientMap.get(id);
      const userInfo = userProfiles.get(id);

      friends.push({
        id,
        email: userInfo?.email || null,
        phone: userInfo?.phone || null,
        firstName: userInfo?.firstName || null,
        profilePictureUrl: userInfo?.profilePictureUrl || null,
        oauthAvatarUrl: userInfo?.oauthAvatarUrl || null,
        sharesWithMe: sharer
          ? {
              blocked: sharer.blocked,
              showEarningsToMe: sharer.showEarnings,
              sharedAt: sharer.sharedAt,
              notificationFrequency: sharer.notificationFrequency,
            }
          : null,
        iShareWith: recipient
          ? {
              showEarningsToThem: recipient.showEarnings,
              sharedAt: recipient.sharedAt,
            }
          : null,
      });
    }

    // Sort alphabetically by name using Norwegian locale
    friends.sort((a, b) => {
      const aName = (a.firstName || a.email || a.phone || "").toLowerCase();
      const bName = (b.firstName || b.email || b.phone || "").toLowerCase();
      return aName.localeCompare(bName, "nb");
    });

    // Calculate capacity
    const outgoingCount = outgoingShares?.length || 0;

    // Get user's tier from the user_entitlements view (single source of truth)
    const { data: entitlementData } = await adminClient
      .from("user_entitlements")
      .select("tier")
      .eq("user_id", userId)
      .maybeSingle();

    const tier = (entitlementData?.tier as "free" | "pro" | "max") || "free";

    const limit = SHARE_LIMITS[tier];
    const capacity = {
      canAdd: outgoingCount < limit,
      currentCount: outgoingCount,
      limit,
    };

    logger.info(
      `Fetched ${friends.length} friends for user (capacity: ${capacity.currentCount}/${capacity.limit})`
    );

    return NextResponse.json({
      friends,
      capacity,
    });
  } catch (error: any) {
    logger.error("Error in /api/sharing/friends:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
