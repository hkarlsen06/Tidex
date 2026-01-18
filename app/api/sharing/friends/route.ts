import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { Effect } from "effect";
import { SharingService } from "@/lib/services/sharing";
import { SharingLive } from "@/lib/layers/app";
import { getSession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import type { Friend } from "@/data-access/sharing";

/**
 * GET /api/sharing/friends
 *
 * Returns the unified friends list and share capacity for the authenticated user.
 * Used by the iOS app's sharing management modal.
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
  try {
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

    // Fetch friends and capacity in parallel using Effect
    const friendsProgram = Effect.gen(function* () {
      const sharing = yield* SharingService;
      const [allSharers, recipients] = yield* Effect.all([
        sharing.getAllSharersIncludingBlocked(userId),
        sharing.getMyShareRecipients(userId),
      ]);

      // Create maps for quick lookup
      const sharerMap = new Map(allSharers.map((s) => [s.id, s]));
      const recipientMap = new Map(recipients.map((r) => [r.id, r]));

      // Collect all unique user IDs
      const allUserIds = new Set([
        ...allSharers.map((s) => s.id),
        ...recipients.map((r) => r.id),
      ]);

      // Build unified friends list
      const friends: Friend[] = [];

      for (const id of allUserIds) {
        const sharer = sharerMap.get(id);
        const recipient = recipientMap.get(id);

        // Use whichever has the user info (prefer sharer since it has blocked info)
        const userInfo = sharer ?? recipient;
        if (!userInfo) continue;

        friends.push({
          id,
          email: userInfo.email,
          phone: userInfo.phone,
          firstName: userInfo.firstName,
          profilePictureUrl: userInfo.profilePictureUrl,
          oauthAvatarUrl: userInfo.oauthAvatarUrl,
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

      return friends;
    }).pipe(Effect.provide(SharingLive), Effect.scoped);

    const capacityProgram = Effect.gen(function* () {
      const sharing = yield* SharingService;
      return yield* sharing.canAddMoreRecipients(userId);
    }).pipe(Effect.provide(SharingLive), Effect.scoped);

    const [friends, capacity] = await Promise.all([
      Effect.runPromise(friendsProgram),
      Effect.runPromise(capacityProgram),
    ]);

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
