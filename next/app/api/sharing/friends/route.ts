import { NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
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
 * Authentication:
 * - Bearer token in Authorization header (native iOS app) - handled by getSession
 * - Cookie-based session (web app) - handled by getSession
 *
 * Response:
 * {
 *   friends: Friend[],
 *   blockedFriends: Friend[],
 *   capacity: { canAdd: boolean, currentCount: number, limit: number }
 * }
 */
export async function GET() {
  // getSession handles both Bearer tokens (iOS) and cookies (web)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session.user.id;

  // Service client for fetching user data
  const adminClient = createSupabaseServiceClient();

  try {
    // Fetch sharers (people who share with me) - including hidden-from-list rows
    const { data: incomingShares, error: incomingError } = await adminClient
      .from("shift_shares")
      .select("owner_id, created_at, show_earnings, hidden, muted, blocked_by_user_id")
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
      .select("viewer_id, created_at, show_earnings, owner_muted, blocked_by_user_id")
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

    // Fetch user profiles for all friends using direct RPC query
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
      // Fetch user data via RPC (no pagination issues)
      const { data: usersData, error: usersError } = await adminClient.rpc(
        "get_users_by_ids",
        { user_ids: allUserIds }
      );

      if (usersError) {
        logger.error("Failed to fetch user profiles:", usersError);
      } else {
        const usersMap = new Map<
          string,
          {
            email: string | null;
            phone: string | null;
            firstName: string | null;
            oauthAvatarUrl: string | null;
          }
        >(
          (usersData || []).map((u: any) => [
            u.id,
            {
              email: u.email || null,
              phone: u.phone || null,
              firstName: u.first_name || null,
              oauthAvatarUrl: u.oauth_avatar_url || null,
            },
          ])
        );

        // Fetch profile pictures from user_settings table
        const { data: settingsData } = await adminClient
          .from("user_settings")
          .select("user_id, profile_picture_url")
          .in("user_id", allUserIds);

        const profilePicturesMap = new Map(
          (settingsData || []).map((s: any) => [s.user_id, s.profile_picture_url])
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
          blocked: s.hidden,
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
          ownerMuted: s.owner_muted ?? false,
        },
      ])
    );

    // Build unified friends list
    const friends: Friend[] = [];
    const blockedFriends: Friend[] = [];

    const blockedPairIds = new Set<string>();
    const blockedByCurrentUserIds = new Set<string>();

    for (const share of incomingShares || []) {
      if (!share.blocked_by_user_id) continue;
      blockedPairIds.add(share.owner_id);
      if (share.blocked_by_user_id === userId) {
        blockedByCurrentUserIds.add(share.owner_id);
      }
    }

    for (const share of outgoingShares || []) {
      if (!share.blocked_by_user_id) continue;
      blockedPairIds.add(share.viewer_id);
      if (share.blocked_by_user_id === userId) {
        blockedByCurrentUserIds.add(share.viewer_id);
      }
    }

    for (const id of allUserIds) {
      const sharer = sharerMap.get(id);
      const recipient = recipientMap.get(id);
      const userInfo = userProfiles.get(id);

      const friend: Friend = {
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
              ownerMuted: recipient.ownerMuted,
            }
          : null,
      };

      if (blockedPairIds.has(id)) {
        if (blockedByCurrentUserIds.has(id)) {
          blockedFriends.push(friend);
        }
        continue;
      }

      friends.push(friend);
    }

    // Sort alphabetically by name using Norwegian locale
    friends.sort((a, b) => {
      const aName = (a.firstName || a.email || a.phone || "").toLowerCase();
      const bName = (b.firstName || b.email || b.phone || "").toLowerCase();
      return aName.localeCompare(bName, "nb");
    });

    blockedFriends.sort((a, b) => {
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
      blockedFriends,
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
